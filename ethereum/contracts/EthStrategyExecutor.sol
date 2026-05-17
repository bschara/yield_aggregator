// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./VaultOFT.sol";

/**
 * EthStrategyExecutor: receives cross-chain instructions from the Aptos vault,
 * executes DeFi strategy actions (Aave deposit/withdraw/harvest), and sends
 * results back to Aptos via LayerZero.
 *
 * Action codes (match Aptos side):
 *   0x01 = DEPLOY  — deposit wAPT into strategy
 *   0x02 = RECALL  — withdraw from strategy, bridge principal back to Aptos
 *   0x03 = HARVEST — collect yield, bridge yield back to Aptos
 *   0x04 = COMPLETE — sent back to Aptos (not received here)
 *
 * Payload format (57 bytes, must match oft_bridge.move):
 *   [0]      action    uint8
 *   [1..8]   amount    uint64 big-endian
 *   [9..16]  strategy  uint64 big-endian
 *   [17..24] nonce     uint64 big-endian
 *   [25..56] vaultAddr bytes32 (Aptos address)
 */
contract EthStrategyExecutor is Ownable, ReentrancyGuard {
    VaultOFT public immutable oft;

    // Replay protection: nonce → executed
    mapping(uint64 => bool) public executedNonces;

    // strategy_id → amount deployed (in wAPT octas)
    mapping(uint64 => uint256) public deployedAmounts;

    // Aptos bridge address packed as 32 bytes (used as LZ destination)
    bytes public aptosBridgeAddress;

    // Minimum gas delivered to Aptos on send-back messages
    uint256 public constant MIN_GAS_LIMIT = 300_000;

    uint16 private constant APTOS_CHAIN_ID = 108;

    uint8 public constant ACTION_DEPLOY   = 0x01;
    uint8 public constant ACTION_RECALL   = 0x02;
    uint8 public constant ACTION_HARVEST  = 0x03;
    uint8 public constant ACTION_COMPLETE = 0x04;

    event Deploy(uint64 indexed strategyId, uint256 amount, uint64 nonce);
    event Recall(uint64 indexed strategyId, uint256 amount, uint64 nonce);
    event Harvest(uint64 indexed strategyId, uint256 yieldAmount, uint64 nonce);
    event SentBackToAptos(uint64 indexed strategyId, uint256 amount, uint8 action, uint64 nonce);

    constructor(address _oft, address initialOwner) Ownable(initialOwner) {
        oft = VaultOFT(payable(_oft));
    }

    // ── Admin ────────────────────────────────────────────────────────────────

    /**
     * Set the Aptos bridge contract address (32-byte Aptos address).
     * This is packed into the LZ destination for send-back messages.
     */
    function setAptosBridgeAddress(bytes32 _aptosAddr) external onlyOwner {
        aptosBridgeAddress = abi.encodePacked(_aptosAddr);
    }

    // ── Entry point (called by VaultOFT._nonblockingLzReceive) ───────────────

    /**
     * Receives cross-chain instructions from Aptos.
     * VaultOFT has already minted wAPT to this contract (for DEPLOY).
     */
    function executeIncoming(
        uint256 amount,
        bytes calldata payload
    ) external nonReentrant {
        require(msg.sender == address(oft), "Executor: only OFT");

        (, uint64 aptAmount, uint64 strategyId, uint64 nonce, bytes32 vaultAddr) =
            oft.decodePayload(payload);
        uint8 action = uint8(payload[0]);

        require(!executedNonces[nonce], "Executor: nonce replay");
        executedNonces[nonce] = true;

        if (action == ACTION_DEPLOY) {
            _deploy(strategyId, amount, nonce);
        } else if (action == ACTION_RECALL) {
            _recall(strategyId, uint256(aptAmount), vaultAddr, nonce);
        } else if (action == ACTION_HARVEST) {
            _harvest(strategyId, vaultAddr, nonce);
        } else {
            revert("Executor: unknown action");
        }
    }

    // ── Strategy actions ─────────────────────────────────────────────────────

    function _deploy(uint64 strategyId, uint256 amount, uint64 nonce) internal {
        // TODO: swap wAPT → USDC via DEX, deposit USDC into Aave v3
        // For now: track accounting only
        deployedAmounts[strategyId] += amount;
        emit Deploy(strategyId, amount, nonce);
    }

    function _recall(
        uint64 strategyId,
        uint256 amount,
        bytes32 vaultAddr,
        uint64 nonce
    ) internal {
        require(deployedAmounts[strategyId] >= amount, "Executor: insufficient deployed");
        // TODO: withdraw from Aave, swap USDC → wAPT
        deployedAmounts[strategyId] -= amount;

        // Mint wAPT representing the recalled principal so we can burn it on send-back
        oft.mintBridge(address(this), amount);

        emit Recall(strategyId, amount, nonce);
        _sendBackToAptos(amount, vaultAddr, strategyId, nonce + 1);
    }

    function _harvest(uint64 strategyId, bytes32 vaultAddr, uint64 nonce) internal {
        // TODO: claim Aave rewards, convert to wAPT equivalent
        uint256 yieldAmount = 0; // stub — real impl queries Aave aToken balance delta
        emit Harvest(strategyId, yieldAmount, nonce);

        if (yieldAmount > 0) {
            oft.mintBridge(address(this), yieldAmount);
            _sendBackToAptos(yieldAmount, vaultAddr, strategyId, nonce + 1);
        }
    }

    // ── Bridge back to Aptos ─────────────────────────────────────────────────

    /**
     * Burns wAPT from this contract and sends a COMPLETE message back to Aptos
     * via the LayerZero endpoint. Aptos will unlock the equivalent APT and credit
     * the vault.
     *
     * adapterParams encodes the gas limit for the Aptos executor:
     *   abi.encodePacked(uint16(1), uint256(MIN_GAS_LIMIT))
     */
    function _sendBackToAptos(
        uint256 amount,
        bytes32 vaultAddr,
        uint64 strategyId,
        uint64 nonce
    ) internal {
        // Burn wAPT — the corresponding APT is already locked on Aptos side
        oft.burnBridge(address(this), amount);

        bytes memory payload = oft.encodePayload(
            ACTION_COMPLETE,
            uint64(amount),
            strategyId,
            nonce,
            vaultAddr
        );

        bytes memory adapterParams = abi.encodePacked(uint16(1), MIN_GAS_LIMIT);

        // destination is the Aptos bridge contract address (32 bytes)
        // LZ V1 destination format: abi.encodePacked(remoteAddress, localAddress)
        bytes memory destination = abi.encodePacked(aptosBridgeAddress, address(oft));

        (uint256 lzFee,) = oft.estimateLzFee(
            APTOS_CHAIN_ID,
            payload,
            adapterParams
        );

        oft.lzSend{value: lzFee}(
            APTOS_CHAIN_ID,
            destination,
            payload,
            payable(address(this)),
            adapterParams
        );

        emit SentBackToAptos(strategyId, amount, ACTION_COMPLETE, nonce);
    }

    // ── Fee helpers ──────────────────────────────────────────────────────────

    function estimateSendBackFee(
        uint64 strategyId,
        uint64 amount,
        bytes32 vaultAddr,
        uint64 nonce
    ) external view returns (uint256 nativeFee) {
        bytes memory payload = oft.encodePayload(ACTION_COMPLETE, amount, strategyId, nonce, vaultAddr);
        bytes memory adapterParams = abi.encodePacked(uint16(1), MIN_GAS_LIMIT);
        (nativeFee,) = oft.estimateLzFee(APTOS_CHAIN_ID, payload, adapterParams);
    }

    // Allow receiving ETH for LayerZero fees
    receive() external payable {}
}

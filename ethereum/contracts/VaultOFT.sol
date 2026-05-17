// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// ── LayerZero V1 interfaces (inline — no package dependency) ──────────────────

interface ILayerZeroEndpoint {
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external view returns (uint256 nativeFee, uint256 zroFee);

    function getChainId() external view returns (uint16);
    function retryPayload(uint16 _srcChainId, bytes calldata _srcAddress, bytes calldata _payload) external;
    function hasStoredPayload(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool);
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external;
    function setConfig(uint16 _version, uint16 _chainId, uint _configType, bytes calldata _config) external;
    function setSendVersion(uint16 _version) external;
    function setReceiveVersion(uint16 _version) external;
}

interface ILayerZeroReceiver {
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external;
}

/**
 * VaultOFT: ERC-20 wAPT token + LayerZero V1 messaging on Ethereum.
 *
 * Receives raw LZ messages from Aptos carrying our 57-byte custom payload:
 *   [0]      action    uint8  — 1=DEPLOY 2=RECALL 3=HARVEST 4=COMPLETE
 *   [1..8]   amount    uint64 (big-endian) — APT octas
 *   [9..16]  strategy  uint64 (big-endian)
 *   [17..24] nonce     uint64 (big-endian)
 *   [25..56] vaultAddr bytes32 — Aptos vault address
 *
 * We use raw LZ endpoint messaging (not OFT sendFrom/lzReceive) because the
 * standard OFT wire format only carries [receiver(32)][amount_sd(8)] and cannot
 * carry our custom payload. APT is locked on Aptos; we mint wAPT here to give
 * the EthStrategyExecutor a transferable representation of that locked value.
 */
contract VaultOFT is ERC20, Ownable, ILayerZeroReceiver {
    ILayerZeroEndpoint public immutable lzEndpoint;

    address public strategyExecutor;

    // LayerZero chain ID for Aptos
    uint16 public constant APTOS_CHAIN_ID = 108;

    // chain ID → trusted remote path: abi.encodePacked(remoteAddress, localAddress)
    // This is the standard LZ V1 "trusted remote" format.
    mapping(uint16 => bytes) public trustedRemotes;

    uint8 public constant ACTION_DEPLOY   = 0x01;
    uint8 public constant ACTION_RECALL   = 0x02;
    uint8 public constant ACTION_HARVEST  = 0x03;
    uint8 public constant ACTION_COMPLETE = 0x04;

    event StrategyExecutorSet(address indexed executor);
    event TrustedRemoteSet(uint16 indexed chainId, bytes path);
    event CrossChainReceive(uint16 indexed srcChainId, uint8 action, uint256 amount, uint64 nonce);
    event CrossChainSent(uint16 indexed dstChainId, uint8 action, uint256 amount, uint64 nonce);

    constructor(address _lzEndpoint, address initialOwner)
        ERC20("Wrapped APT", "wAPT")
        Ownable(initialOwner)
    {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
    }

    // ── Admin ────────────────────────────────────────────────────────────────

    function setStrategyExecutor(address _executor) external onlyOwner {
        strategyExecutor = _executor;
        emit StrategyExecutorSet(_executor);
    }

    /**
     * Set the trusted remote for a source chain.
     * path = abi.encodePacked(remoteContractAddress, address(this))
     * For Aptos, remoteContractAddress is the 32-byte Aptos bridge address.
     */
    function setTrustedRemote(uint16 _chainId, bytes calldata _path) external onlyOwner {
        trustedRemotes[_chainId] = _path;
        emit TrustedRemoteSet(_chainId, _path);
    }

    // ── LayerZero receive ─────────────────────────────────────────────────────

    /**
     * Called by the LayerZero endpoint when a message arrives from a remote chain.
     * Verifies the message comes from the trusted remote, then processes it.
     */
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external override {
        require(msg.sender == address(lzEndpoint), "VaultOFT: not endpoint");
        bytes memory trusted = trustedRemotes[_srcChainId];
        require(
            trusted.length > 0 && keccak256(_srcAddress) == keccak256(trusted),
            "VaultOFT: untrusted remote"
        );
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes calldata, /* _srcAddress */
        uint64, /* _nonce */
        bytes calldata _payload
    ) internal {
        (uint8 action, uint64 amount, uint64 strategyId, uint64 nonce, bytes32 vaultAddr) =
            decodePayload(_payload);

        if (action == ACTION_DEPLOY) {
            // Aptos locked APT and sent a DEPLOY message. Mint wAPT to the
            // executor so it can deposit into the strategy.
            _mint(strategyExecutor, uint256(amount));
            IEthStrategyExecutor(strategyExecutor).executeIncoming(uint256(amount), _payload);
        }
        // RECALL and HARVEST arrive as separate signal messages (amount=0 or amount=requested).
        // The executor handles them via executeIncoming as well.
        else {
            IEthStrategyExecutor(strategyExecutor).executeIncoming(uint256(amount), _payload);
        }

        emit CrossChainReceive(_srcChainId, action, uint256(amount), nonce);
        // suppress unused warning
        (strategyId, vaultAddr);
    }

    // ── LayerZero send ────────────────────────────────────────────────────────

    /**
     * Called by EthStrategyExecutor to send a message back to Aptos.
     * Burns wAPT before calling this when returning principal (COMPLETE action).
     *
     * _destination: ABI-encoded 32-byte Aptos bridge address.
     * _adapterParams: LZ adapter params, e.g. abi.encodePacked(uint16(1), uint256(gasLimit)).
     */
    function lzSend(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        bytes calldata _adapterParams
    ) external payable {
        require(msg.sender == strategyExecutor, "VaultOFT: not executor");
        lzEndpoint.send{value: msg.value}(
            _dstChainId,
            _destination,
            _payload,
            _refundAddress,
            address(0),   // no ZRO payment
            _adapterParams
        );
        uint8 action = uint8(_payload[0]);
        uint64 amount = uint64(bytes8(_payload[1:9]));
        uint64 nonce  = uint64(bytes8(_payload[17:25]));
        emit CrossChainSent(_dstChainId, action, uint256(amount), nonce);
    }

    // ── Fee estimation ────────────────────────────────────────────────────────

    function estimateLzFee(
        uint16 _dstChainId,
        bytes calldata _payload,
        bytes calldata _adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        return lzEndpoint.estimateFees(_dstChainId, address(this), _payload, false, _adapterParams);
    }

    // ── Payload encoding / decoding ───────────────────────────────────────────
    //
    // Must match oft_bridge.move exactly:
    //   [0]     action    uint8  (1 byte)
    //   [1..8]  amount    uint64 big-endian (8 bytes)
    //   [9..16] strategy  uint64 big-endian (8 bytes)
    //   [17..24] nonce    uint64 big-endian (8 bytes)
    //   [25..56] vaultAddr bytes32           (32 bytes)
    //   Total: 57 bytes

    function encodePayload(
        uint8 action,
        uint64 amount,
        uint64 strategyId,
        uint64 nonce,
        bytes32 vaultAddr
    ) public pure returns (bytes memory) {
        return abi.encodePacked(action, amount, strategyId, nonce, vaultAddr);
    }

    function decodePayload(bytes calldata payload)
        public
        pure
        returns (uint8 action, uint64 amount, uint64 strategyId, uint64 nonce, bytes32 vaultAddr)
    {
        require(payload.length >= 57, "VaultOFT: bad payload");
        action     = uint8(payload[0]);
        amount     = uint64(bytes8(payload[1:9]));
        strategyId = uint64(bytes8(payload[9:17]));
        nonce      = uint64(bytes8(payload[17:25]));
        vaultAddr  = bytes32(payload[25:57]);
    }

    // ── Mint / Burn (restricted to executor) ─────────────────────────────────

    function mintBridge(address to, uint256 amount) external {
        require(msg.sender == strategyExecutor, "VaultOFT: not executor");
        _mint(to, amount);
    }

    function burnBridge(address from, uint256 amount) external {
        require(msg.sender == strategyExecutor, "VaultOFT: not executor");
        _burn(from, amount);
    }

    // Allow receiving ETH for LZ fee forwarding
    receive() external payable {}
}

// Forward declaration so VaultOFT can call executor
interface IEthStrategyExecutor {
    function executeIncoming(uint256 amount, bytes calldata payload) external;
}

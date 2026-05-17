// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Standalone LZ V1 endpoint mock. No external dependencies.
// Implements the same ILayerZeroEndpoint interface used by VaultOFT.
//
// Key features vs a simple stub:
//   - Real fee math (BASE_FEE + FEE_PER_BYTE * payload.length)
//   - Inbound + outbound nonce tracking per (chainId, path)
//   - setRoute() wires two endpoints for auto-delivery via callReceive
//   - blockNextMsg() + forceResumeReceive() tests retry / blocking scenarios
//   - receivePayload() lets tests simulate an incoming message directly

interface ILayerZeroReceiverLocal {
    function lzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce, bytes calldata payload) external;
}

contract LZEndpointMock {
    uint16 public immutable chainId;

    struct Route { address destEndpoint; address destUA; }
    mapping(address => Route) public routes;

    // inboundNonce[srcChainId][srcPath]
    mapping(uint16 => mapping(bytes => uint64)) public inboundNonce;
    // outboundNonce[dstChainId][srcUA]
    mapping(uint16 => mapping(address => uint64)) public outboundNonce;

    bool public callReceiveEnabled;

    struct BlockedMsg { uint16 srcChainId; bytes srcPath; address dstUA; uint64 nonce; bytes payload; }
    BlockedMsg private _blocked;
    bool public hasBlocked;
    bool private _nextBlocked;

    // 0.001 ETH base + 1000 wei per payload byte — realistic non-zero fees
    uint256 public constant BASE_FEE    = 0.001 ether;
    uint256 public constant FEE_PER_BYTE = 1000 wei;

    event PacketSent(uint16 dstChainId, bytes destination, bytes payload, uint64 nonce);
    event PacketReceived(uint16 srcChainId, bytes srcPath, address dstUA, uint64 nonce);
    event MessageBlocked(uint16 srcChainId, bytes srcPath, address dstUA, uint64 nonce);

    constructor(uint16 _chainId) {
        chainId = _chainId;
    }

    // ── Configuration ────────────────────────────────────────────────────────

    // Wire outbound routing: when srcUA sends a message, deliver through
    // destEndpoint to destUA. Call this on the sending-side endpoint.
    function setRoute(address srcUA, address destEndpoint, address destUA) external {
        routes[srcUA] = Route(destEndpoint, destUA);
    }

    // When true, send() immediately delivers to the destination in the same tx.
    function setCallReceive(bool enabled) external {
        callReceiveEnabled = enabled;
    }

    // Block the next outbound message (stores it; use forceResumeReceive to deliver).
    function blockNextMsg() external {
        _nextBlocked = true;
    }

    // ── ILayerZeroEndpoint ───────────────────────────────────────────────────

    // Called by VaultOFT.lzSend. Enforces fee, tracks outbound nonce,
    // and auto-delivers to the destination endpoint when callReceiveEnabled.
    function send(
        uint16 dstChainId,
        bytes calldata destination,
        bytes calldata payload,
        address payable refundAddress,
        address, /* zroPaymentAddress */
        bytes calldata /* adapterParams */
    ) external payable {
        (uint256 fee, ) = estimateFees(dstChainId, msg.sender, payload, false, hex"");
        require(msg.value >= fee, "LayerZeroMock: not enough native for fees");

        uint256 excess = msg.value - fee;
        if (excess > 0) {
            (bool ok, ) = refundAddress.call{value: excess}("");
            require(ok, "LZMock: refund failed");
        }

        uint64 nonce = ++outboundNonce[dstChainId][msg.sender];
        emit PacketSent(dstChainId, destination, payload, nonce);

        if (!callReceiveEnabled) return;

        Route memory r = routes[msg.sender];
        if (r.destEndpoint == address(0)) return;

        bytes memory srcPath = abi.encodePacked(msg.sender);

        if (_nextBlocked) {
            _nextBlocked = false;
            _blocked = BlockedMsg(chainId, srcPath, r.destUA, nonce, payload);
            hasBlocked = true;
            emit MessageBlocked(chainId, srcPath, r.destUA, nonce);
            return;
        }

        LZEndpointMock(payable(r.destEndpoint)).deliver(chainId, srcPath, r.destUA, nonce, payload);
    }

    // Called by a remote endpoint to deliver a packet here. Increments inbound
    // nonce and calls lzReceive on the destination UA.
    function deliver(
        uint16 srcChainId,
        bytes calldata srcPath,
        address dstUA,
        uint64 nonce,
        bytes calldata payload
    ) external {
        inboundNonce[srcChainId][srcPath]++;
        emit PacketReceived(srcChainId, srcPath, dstUA, nonce);
        ILayerZeroReceiverLocal(dstUA).lzReceive(srcChainId, srcPath, nonce, payload);
    }

    // Called by tests to simulate an incoming message from any chain.
    // Increments inbound nonce and calls lzReceive on dstUA.
    function receivePayload(
        uint16 srcChainId,
        bytes calldata srcPath,
        address dstUA,
        uint64 nonce,
        bytes calldata payload
    ) external {
        inboundNonce[srcChainId][srcPath]++;
        emit PacketReceived(srcChainId, srcPath, dstUA, nonce);
        ILayerZeroReceiverLocal(dstUA).lzReceive(srcChainId, srcPath, nonce, payload);
    }

    // Delivers a previously blocked message.
    function forceResumeReceive(uint16 srcChainId, bytes calldata srcPath) external {
        require(hasBlocked, "LZMock: nothing blocked");
        BlockedMsg memory b = _blocked;
        hasBlocked = false;
        inboundNonce[b.srcChainId][b.srcPath]++;
        ILayerZeroReceiverLocal(b.dstUA).lzReceive(b.srcChainId, b.srcPath, b.nonce, b.payload);
        // suppress unused params (srcChainId/srcPath identify which blocked msg to resume;
        // since we only store one at a time, they are informational only)
        (srcChainId, srcPath);
    }

    // ── Fee estimation ───────────────────────────────────────────────────────

    function estimateFees(
        uint16, /* dstChainId */
        address, /* userApplication */
        bytes calldata payload,
        bool, /* payInZRO */
        bytes calldata /* adapterParams */
    ) public pure returns (uint256 nativeFee, uint256 zroFee) {
        nativeFee = BASE_FEE + payload.length * FEE_PER_BYTE;
        zroFee = 0;
    }

    // ── Getters ──────────────────────────────────────────────────────────────

    function getChainId() external view returns (uint16) { return chainId; }

    function getInboundNonce(uint16 srcChainId, bytes calldata srcPath)
        external view returns (uint64) {
        return inboundNonce[srcChainId][srcPath];
    }

    function getOutboundNonce(uint16 dstChainId, address srcUA)
        external view returns (uint64) {
        return outboundNonce[dstChainId][srcUA];
    }

    // ── ILayerZeroEndpoint stubs ─────────────────────────────────────────────

    function retryPayload(uint16, bytes calldata, bytes calldata) external {}
    function hasStoredPayload(uint16, bytes calldata) external view returns (bool) { return hasBlocked; }
    function setConfig(uint16, uint16, uint, bytes calldata) external {}
    function setSendVersion(uint16) external {}
    function setReceiveVersion(uint16) external {}

    receive() external payable {}
}

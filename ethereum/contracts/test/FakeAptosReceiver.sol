// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// EVM stand-in for the Aptos oft_bridge.move contract.
// Used only in Hardhat tests to capture ETH→Aptos messages sent by the executor.
contract FakeAptosReceiver {
    struct Message {
        uint16  srcChainId;
        bytes   srcAddress;
        uint64  nonce;
        bytes   payload;
    }

    Message[] public received;
    address public immutable lzEndpoint;

    event MessageReceived(uint16 srcChainId, uint64 nonce, bytes payload);

    constructor(address _endpoint) {
        lzEndpoint = _endpoint;
    }

    function lzReceive(
        uint16  _srcChainId,
        bytes calldata _srcAddress,
        uint64  _nonce,
        bytes calldata _payload
    ) external {
        require(msg.sender == lzEndpoint, "FakeAptosReceiver: only endpoint");
        received.push(Message(_srcChainId, _srcAddress, _nonce, _payload));
        emit MessageReceived(_srcChainId, _nonce, _payload);
    }

    function receivedCount() external view returns (uint256) {
        return received.length;
    }

    function lastMessage() external view returns (Message memory) {
        require(received.length > 0, "FakeAptosReceiver: no messages");
        return received[received.length - 1];
    }
}

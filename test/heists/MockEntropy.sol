// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IEntropyV2} from "../../src/utils/pyth/IEntropyV2.sol";

interface IEntropyConsumerExternal {
    function _entropyCallback(uint64 sequence, address provider, bytes32 randomNumber) external;
}

/**
 * @dev Test double for Pyth Entropy. Records requests and lets a test fire the async
 *      callback (as the entropy contract, so the consumer's msg.sender check passes).
 */
contract MockEntropy is IEntropyV2 {
    uint64 public nextSeq = 1;
    uint128 public fee;
    address public provider = address(0xBEEF);

    mapping(uint64 => address) public requesterOf;

    function setFee(uint128 f) external {
        fee = f;
    }

    function getFeeV2() external view returns (uint128) {
        return fee;
    }

    function getDefaultProvider() external view returns (address) {
        return provider;
    }

    function requestV2() external payable returns (uint64 seq) {
        require(msg.value >= fee, "MockEntropy: fee");
        seq = nextSeq++;
        requesterOf[seq] = msg.sender;
    }

    /// @dev Simulates the keeper invoking the consumer callback.
    function fireCallback(address consumer, uint64 seq, bytes32 randomNumber) external {
        IEntropyConsumerExternal(consumer)._entropyCallback(seq, provider, randomNumber);
    }

    /// @dev Fire against the last requester of `seq`.
    function fire(uint64 seq, bytes32 randomNumber) external {
        IEntropyConsumerExternal(requesterOf[seq])._entropyCallback(seq, provider, randomNumber);
    }
}

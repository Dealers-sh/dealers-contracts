// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @title IEntropyV2 (minimal)
 * @dev Minimal subset of Pyth's IEntropyV2 used by the Dealers contracts —
 *      only the request + fee + provider-lookup methods this repo calls.
 *      Full interface:
 *      https://github.com/pyth-network/pyth-crosschain/blob/main/target_chains/ethereum/entropy_sdk/solidity/IEntropyV2.sol
 *
 *      Consumers implement {IEntropyConsumer} to receive the async callback.
 *      Deployed Entropy addresses (read the provider on-chain via getDefaultProvider):
 *        Abstract mainnet (2741):  0x5a4a369F4db5df2054994AF031b7b23949b98c0e
 *        Abstract testnet (11124): 0x858687fD592112f7046E394A3Bf10D0C11fF9e63
 */
interface IEntropyV2 {
    /// @notice Request a random number from the default provider with the default gas limit.
    /// @dev Pay exactly {getFeeV2} as msg.value. Returns the request's sequence number.
    function requestV2() external payable returns (uint64 assignedSequenceNumber);

    /// @notice The fee (in wei) required for a {requestV2} call at the default gas limit.
    function getFeeV2() external view returns (uint128 feeAmount);

    /// @notice The default entropy provider address.
    function getDefaultProvider() external view returns (address provider);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealersRandomness - Interface for the commit-reveal randomness coordinator
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @author Berny0x
 */
interface IDealersRandomness {
    /**
     * @notice Reserve a sequence number whose entropy will come from a future blockhash
     */
    function commit() external returns (uint64 seq);

    /**
     * @notice Read entropy for a previously committed sequence number
     */
    /**
     * @dev Reverts UnknownSeq, TooEarly, or Expired. Mixes msg.sender into the digest so
     */
    /**
     * different consumer modules cannot collide on the same seq.
     */
    function reveal(uint64 seq) external view returns (uint256 rand);

    /**
     * @notice Whether a committed sequence number is past its blockhash window
     */
    function isExpired(uint64 seq) external view returns (bool);

    /**
     * @notice Whether a contract may call commit()
     */
    function isAuthorizedResolver(address resolver) external view returns (bool);
}

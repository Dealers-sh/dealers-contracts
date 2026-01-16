// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDERandomness - Interface for centralized randomness provider
 */
interface IDERandomness {
    /**
     * @notice Get randomness using prevrandao and additional entropy
     * @param seed Context-specific seed for additional entropy
     * @return Deterministic randomness value
     */
    function getRandomness(bytes32 seed) external returns (uint256);
}

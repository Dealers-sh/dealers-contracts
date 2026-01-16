// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDERandomness - Interface for Randomness Provider
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Interface for centralized randomness provider
 * @author Dealers.Exe Team
 */
interface IDERandomness {
    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Get a random number based on a seed
    function getRandomness(bytes32 seed) external returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /// @notice Check if a contract is authorized to request randomness
    /// @param resolver Address to check
    /// @return True if authorized
    function isAuthorizedResolver(address resolver) external view returns (bool);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealersRandomness - Interface for Randomness Provider
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Interface for centralized randomness provider
 * @author Berny0x
 */
interface IDealersRandomness {
    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Get a random number based on a seed
    function getRandomness(bytes32 seed) external returns (uint256);

    /// @notice Get multiple independent random values from a single seed
    function getRandomValues(bytes32 seed, uint8 count) external returns (uint256[] memory);

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /// @notice Check if a contract is authorized to request randomness
    /// @param resolver Address to check
    /// @return True if authorized
    function isAuthorizedResolver(address resolver) external view returns (bool);
}

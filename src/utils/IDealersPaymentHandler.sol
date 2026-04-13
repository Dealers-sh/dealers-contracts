// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealersPaymentHandler - Interface for Payment Handler
 *
 * @dev Interface for ETH management and fee distribution
 * @author Berny0x
 */
interface IDealersPaymentHandler {
    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Process area movement fee
    function processMovementFee(address player, uint256 amount) external payable;

    /// @notice Process marketplace/boost fee
    function processMarketplaceFee(address player, uint256 amount) external payable;

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /// @notice Calculate fees for a given amount based on current split
    function calculateFees(uint256 amount) external view returns (uint256 bankFee, uint256 devFee);
}

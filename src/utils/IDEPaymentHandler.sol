// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDEPaymentHandler - Interface for Payment Handler
 *
 * @dev Interface for ETH management and fee distribution
 * @author Dealers.Exe Team
 */
interface IDEPaymentHandler {
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

    /// @notice Calculate fees for a given amount (20% bank, 80% dev)
    function calculateFees(uint256 amount) external pure returns (uint256 bankFee, uint256 devFee);
}

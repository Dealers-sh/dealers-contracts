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
    //                            TYPES
    // =============================================================

    enum Outcome { WIN, TIE, LOSS }

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Process staked bet payment and split fees
    /// @param player The player address placing the bet
    /// @param amount Bet amount in wei
    function processStakedBet(address player, uint256 amount) external payable;

    /// @notice Process game payout based on outcome
    /// @param player Player address to receive payout
    /// @param outcome Game outcome (WIN, TIE, or LOSS)
    /// @param stakeAmount Original stake amount
    function processGamePayout(address player, Outcome outcome, uint256 stakeAmount) external;

    /// @notice Process area movement fee
    /// @param player The player address making the movement
    /// @param amount Movement fee amount
    function processMovementFee(address player, uint256 amount) external payable;

    /// @notice Process marketplace transaction fee
    /// @param player The player address involved in the transaction
    /// @param amount Marketplace fee amount
    function processMarketplaceFee(address player, uint256 amount) external payable;

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /// @notice Calculate fees for a given amount
    function calculateFees(uint256 amount) external pure returns (
        uint256 devFee,
        uint256 bankFee,
        uint256 totalFee,
        uint256 netAmount
    );

    /// @notice Calculate payout for a stake and outcome
    function calculatePayout(uint256 stakeAmount, Outcome outcome) external pure returns (uint256 payout);
}

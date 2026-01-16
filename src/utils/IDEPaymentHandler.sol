// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDEPaymentHandler - Interface for Payment Handler
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Interface for ETH management and fee distribution
 * @author Dealers.Exe Team
 */
interface IDEPaymentHandler {
    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Process a game fee payment
    function processGameFee(uint256 amount) external payable;

    /// @notice Process a marketplace fee payment
    function processMarketplaceFee(uint256 amount) external payable;
}

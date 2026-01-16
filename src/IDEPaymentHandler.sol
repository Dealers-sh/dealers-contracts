// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDEPaymentHandler {
    function processGameFee(uint256 amount) external payable;
    function processMarketplaceFee(uint256 amount) external payable;
}

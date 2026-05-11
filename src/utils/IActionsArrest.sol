// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Minimal arrest interface — lets PVE / PVP delegate jail policy
///         to DealersActions without importing the concrete contract.
interface IActionsArrest {
    function arrest(uint256 tokenId, uint256 confiscRng) external returns (uint256, uint256);
}

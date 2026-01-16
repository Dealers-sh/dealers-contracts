// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC721Minimal - Minimal ERC721 Interface
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Minimal ERC721 interface for ownership checks
 * @author Dealers.Exe Team
 */
interface IERC721Minimal {
    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Get the owner of a token
    function ownerOf(uint256 tokenId) external view returns (address);
}

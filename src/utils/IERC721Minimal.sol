// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IERC721Minimal - Minimal ERC721 Interface
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Minimal ERC721 interface for ownership checks
 * @author Berny0x
 */
interface IERC721Minimal {
    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /** @notice Get the owner of a token */
    function ownerOf(uint256 tokenId) external view returns (address);
}

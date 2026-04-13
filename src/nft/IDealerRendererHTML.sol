// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealerRendererHTML - Interface for HTML Rendering
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Interface for HTML wrapper generation around dealer SVGs
 * @author Berny0x
 */
interface IDealerRendererHTML {
    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Generate HTML wrapper for an SVG
    function getHTML(uint256 tokenId, string memory svg) external view returns (string memory);
}

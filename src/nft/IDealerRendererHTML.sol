// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IDealerRendererHTML - Interface for HTML Rendering
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Interface for HTML wrapper generation around dealer SVGs
 * @author Dealers.Exe Team
 */
interface IDealerRendererHTML {
    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Generate HTML wrapper for an SVG
    function getHTML(string memory svg) external view returns (string memory);
}

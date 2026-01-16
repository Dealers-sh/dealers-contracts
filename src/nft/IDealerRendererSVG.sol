// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDealerRendererSVG - Interface for SVG Rendering
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Interface for SVG generation and trait metadata for dealer NFTs
 * @author Dealers.Exe Team
 */
interface IDealerRendererSVG {
    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Generate the SVG artwork for a dealer
    function getSVG(uint256 tokenId, uint256 seed) external view returns (string memory);

    /// @notice Get traits metadata JSON for a given seed
    function getTraitsMetadata(uint256 seed) external view returns (string memory);

    /// @notice Get traits metadata JSON for a specific token
    function getTraitsMetadataForToken(uint256 tokenId, uint256 seed) external view returns (string memory);

    /// @notice Get the character type for a token
    function getCharacterType(uint256 tokenId) external view returns (uint8);

    /// @notice Check if the distribution has been initialized
    function distributionInitialized() external view returns (bool);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Initialize the character type distribution
    function initializeDistribution(uint256 seed) external;
}

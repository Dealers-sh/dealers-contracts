// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDealerRendererSVG {
    // SVG rendering
    function getSVG(uint256 tokenId, uint256 seed) external view returns (string memory);

    // Metadata - compatible with NFT contract expectations
    function getTraitsMetadata(uint256 seed) external view returns (string memory);
    
    // Token-specific metadata (additional method for enhanced functionality)
    function getTraitsMetadataForToken(uint256 tokenId, uint256 seed) external view returns (string memory);
    
    // Distribution management
    function getCharacterType(uint256 tokenId) external view returns (uint8);
    function initializeDistribution(uint256 seed) external;
    function distributionInitialized() external view returns (bool);
}
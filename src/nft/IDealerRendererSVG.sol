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
    //                            EVENTS
    // =============================================================

    event IncompatibilityRuleAdded(uint8 categoryA, uint8 traitIndexA, uint8 categoryB, uint8 traitIndexB);
    event IncompatibilityRuleRemoved(uint8 categoryA, uint8 traitIndexA, uint8 categoryB, uint8 traitIndexB);
    event AllIncompatibilityRulesCleared(uint256 count);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error RulesLocked();
    error MaxRulesExceeded();
    error InvalidRule();
    error DuplicateRule();
    error RuleNotFound();

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

    /// @notice Get the number of incompatibility rules
    function getIncompatibilityRuleCount() external view returns (uint256);

    /// @notice Get an incompatibility rule by index
    function getIncompatibilityRule(uint256 index)
        external
        view
        returns (uint8 categoryA, uint8 traitIndexA, uint8 categoryB, uint8 traitIndexB);

    /// @notice Check if two traits are incompatible
    function areTraitsIncompatible(
        uint8 categoryA,
        uint8 traitIndexA,
        uint8 categoryB,
        uint8 traitIndexB
    ) external view returns (bool);

    /// @notice Get all traits incompatible with a given trait
    function getIncompatibleTraits(uint8 category, uint8 traitIndex)
        external
        view
        returns (uint8[] memory categories, uint8[] memory indices);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Initialize the character type distribution
    function initializeDistribution(uint256 seed) external;

    /// @notice Add an incompatibility rule between two traits
    function addIncompatibilityRule(
        uint8 categoryA,
        uint8 traitIndexA,
        uint8 categoryB,
        uint8 traitIndexB
    ) external;

    /// @notice Add multiple incompatibility rules in batch
    function batchAddIncompatibilityRules(
        uint8[] calldata categoriesA,
        uint8[] calldata traitIndicesA,
        uint8[] calldata categoriesB,
        uint8[] calldata traitIndicesB
    ) external;

    /// @notice Remove an incompatibility rule
    function removeIncompatibilityRule(
        uint8 categoryA,
        uint8 traitIndexA,
        uint8 categoryB,
        uint8 traitIndexB
    ) external;

    /// @notice Clear all incompatibility rules
    function clearAllIncompatibilityRules() external;
}

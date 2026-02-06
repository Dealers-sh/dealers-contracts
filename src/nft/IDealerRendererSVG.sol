// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
    //                            ENUMS
    // =============================================================

    enum CharacterType {
        NORMAL,
        SPECIAL,
        ONE_OF_ONE
    }

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
    error InvalidPointer();
    error PoolEmpty();
    error InsufficientPoolSize();
    error TooManyReservedOneOfOnes();

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Generate the SVG artwork for a dealer
    function getSVG(uint256 tokenId, uint256 seed) external view returns (string memory);

    /// @notice Get traits metadata JSON for a specific token
    function getTraitsMetadataForToken(uint256 tokenId, uint256 seed) external view returns (string memory);

    /// @notice Get the character type for a token
    function getCharacterType(uint256 tokenId) external view returns (uint8);

    /// @notice Check if the distribution has been initialized
    function distributionInitialized() external view returns (bool);

    /// @notice Get the placeholder SVG pointer
    function placeholderSvgPointer() external view returns (address);

    /// @notice Get the size of the one-of-one SVG pool
    function getOneOfOneSVGPoolSize() external view returns (uint256);

    /// @notice Get the number of reserved one-of-one token IDs
    function getReservedOneOfOneCount() external view returns (uint256);

    /// @notice Get the pool index assigned to a token (1-indexed, 0 means not assigned)
    function tokenPoolIndex(uint256 tokenId) external view returns (uint256);

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

    /// @notice Get token IDs by character type with pagination
    function getTokenIdsByType(CharacterType charType, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory tokenIds);

    /// @notice Get one-of-one configuration for a token
    function getOneOfOneInfo(uint256 tokenId)
        external
        view
        returns (string memory characterName, address svgContract, bool exists);

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

    // =============================================================
    //                      TRAIT MANAGEMENT
    // =============================================================

    /// @notice Add a new trait using a FileStore pointer
    function addTrait(
        uint8 characterType,
        uint8 category,
        string calldata name,
        uint16 probability,
        address fileStorePointer
    ) external;

    /// @notice Add multiple traits using FileStore pointers
    function batchAddTraits(
        uint8[] calldata characterTypes,
        uint8[] calldata categories,
        string[] calldata names,
        uint16[] calldata probabilities,
        address[] calldata fileStorePointers
    ) external;

    /// @notice Set a one-of-one token using a FileStore pointer
    function setOneOfOne(
        uint256 tokenId,
        string calldata characterName,
        address fileStorePointer
    ) external;

    /// @notice Set multiple one-of-one tokens using FileStore pointers
    function batchSetOneOfOnes(
        uint256[] calldata tokenIds,
        string[] calldata characterNames,
        address[] calldata fileStorePointers
    ) external;

    // =============================================================
    //                    PLACEHOLDER & POOL MANAGEMENT
    // =============================================================

    /// @notice Set the placeholder SVG shown before reveal
    function setPlaceholderSvg(address pointer) external;

    /// @notice Add a one-of-one SVG to the pool for random assignment
    function addOneOfOneToPool(string calldata name, address pointer) external;

    /// @notice Add multiple one-of-one SVGs to the pool
    function batchAddOneOfOnesToPool(
        string[] calldata names,
        address[] calldata pointers
    ) external;
}

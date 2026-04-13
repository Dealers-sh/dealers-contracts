// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealerRendererSVG - Interface for SVG Rendering
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Interface for SVG generation and trait metadata for dealer NFTs
 * @author Berny0x
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

    event TraitsStored(uint256 indexed tokenId);
    event TraitUpdated(uint256 indexed tokenId, uint8 indexed category, uint8 traitIndex);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidPointer();
    error TraitsNotStored();

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function getSVG(uint256 tokenId) external view returns (string memory);

    function getTraitsMetadataForToken(uint256 tokenId) external view returns (string memory);

    function getCharacterType(uint256 tokenId) external view returns (uint8);

    function revealed() external view returns (bool);

    function placeholderSvgPointer() external view returns (address);

    function getOneOfOneInfo(uint256 tokenId)
        external
        view
        returns (string memory characterName, address svgContract, bool exists);

    function getStoredTraits(uint256 tokenId) external view returns (uint8[12] memory);

    function isTraitStored(uint256 tokenId) external view returns (bool);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    function batchSetTraits(uint256[] calldata tokenIds, bytes32[] calldata packedTraits) external;

    function setTraitForToken(uint256 tokenId, uint8 category, uint8 traitIndex) external;

    // =============================================================
    //                      TRAIT MANAGEMENT
    // =============================================================

    function addTrait(
        uint8 characterType,
        uint8 category,
        string calldata name,
        uint16 probability,
        address fileStorePointer
    ) external;

    function batchAddTraits(
        uint8[] calldata characterTypes,
        uint8[] calldata categories,
        string[] calldata names,
        uint16[] calldata probabilities,
        address[] calldata fileStorePointers
    ) external;

    function setOneOfOne(
        uint256 tokenId,
        string calldata characterName,
        address fileStorePointer
    ) external;

    function batchSetOneOfOnes(
        uint256[] calldata tokenIds,
        string[] calldata characterNames,
        address[] calldata fileStorePointers
    ) external;

    // =============================================================
    //                    PLACEHOLDER MANAGEMENT
    // =============================================================

    function setPlaceholderSvg(address pointer) external;

    // =============================================================
    //                      REVEAL MANAGEMENT
    // =============================================================

    function reveal() external;
}

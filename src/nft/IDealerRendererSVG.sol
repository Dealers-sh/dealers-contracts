// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealerRendererSVG - Interface for SVG Rendering
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Interface for SVG generation and trait metadata for dealer NFTs. Artwork is
 *      stored by pool index; the token-facing views resolve a tokenId to its pool index
 *      via DealersNFT.tokenToPool.
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

    event TraitsStored(uint256 indexed poolIndex);
    event TraitUpdated(uint256 indexed poolIndex, uint8 indexed category, uint8 traitIndex);

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

    function placeholderSvgPointer() external view returns (address);

    function dealersNFT() external view returns (address);

    function getOneOfOneInfo(uint256 poolIndex)
        external
        view
        returns (string memory characterName, address svgContract, bool exists);

    function getStoredTraits(uint256 poolIndex) external view returns (uint8[12] memory);

    function isTraitStored(uint256 poolIndex) external view returns (bool);

    function traitCount(uint8 characterType, uint8 category) external view returns (uint256);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    function batchSetTraits(uint256[] calldata poolIndices, bytes32[] calldata packedTraits) external;

    function setTraitForToken(uint256 poolIndex, uint8 category, uint8 traitIndex) external;

    // =============================================================
    //                      TRAIT MANAGEMENT
    // =============================================================

    function addTrait(uint8 characterType, uint8 category, string calldata name, address fileStorePointer) external;

    function batchAddTraits(
        uint8[] calldata characterTypes,
        uint8[] calldata categories,
        string[] calldata names,
        address[] calldata fileStorePointers
    ) external;

    function updateTraitPointer(uint8 characterType, uint8 category, uint256 traitIndex, address newFileStorePointer)
        external;

    function setOneOfOne(uint256 poolIndex, string calldata characterName, address fileStorePointer) external;

    function batchSetOneOfOnes(
        uint256[] calldata poolIndices,
        string[] calldata characterNames,
        address[] calldata fileStorePointers
    ) external;

    // =============================================================
    //                    PLACEHOLDER MANAGEMENT
    // =============================================================

    function setPlaceholderSvg(address pointer) external;

    // =============================================================
    //                       NFT INTEGRATION
    // =============================================================

    function setDealersNFT(address _dealersNFT) external;
}

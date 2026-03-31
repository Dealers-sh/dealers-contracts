// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDealerRendererSVG} from "./IDealerRendererSVG.sol";
import {File} from "./File.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {SSTORE2} from "solady/src/utils/SSTORE2.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

/**
 * @title DealerRendererSVG - On-Chain SVG Generator
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Renders dynamic SVG art for dealers from stored trait indices.
 *      Traits are generated off-chain and uploaded via batchSetTraits.
 *      Character type is packed in byte 13 (bits 96-103) of storedTraits.
 *      One-of-ones have their own complete SVG via oneOfOnes mapping.
 *      Uses SSTORE2 for gas-efficient on-chain SVG storage.
 * @author HeadmasterBerny
 */
contract DealerRendererSVG is IDealerRendererSVG, Ownable {
    using LibString for uint256;

    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 public constant MAX_SUPPLY = 8888;
    uint8 public constant CATEGORY_COUNT = 12;

    // =============================================================
    //                            STRUCTS
    // =============================================================

    struct CharacterData {
        uint8 backdrop;
        uint8 head;
        uint8 expression;
        uint8 eyes;
        uint8 nose;
        uint8 eartip;
        uint8 earAccessory;
        uint8 facialHair;
        uint8 mouth;
        uint8 chin;
        uint8 neck;
        uint8 accessory;
    }

    struct TraitConfig {
        string name;
        uint16 probability;
        address svgContract;
    }

    struct OneOfOneData {
        string characterName;
        address completeSvgContract;
        bool exists;
    }

    // =============================================================
    //                            STORAGE
    // =============================================================

    mapping(uint8 => mapping(uint8 => TraitConfig[])) public traits;

    mapping(uint256 => OneOfOneData) public oneOfOnes;

    address public placeholderSvgPointer;
    bool public revealed;

    string[12] public categoryNames = [
        "Backdrop", "Head", "Expression", "Eyes", "Nose", "Eartip",
        "Ear Accessory", "Facial Hair", "Mouth", "Chin", "Neck", "Accessory"
    ];

    // Packed: 12 trait uint8s (bytes 0-11) + charType uint8 (byte 12) = 13 bytes in one slot.
    // bytes32(0) = not stored.
    mapping(uint256 => bytes32) public storedTraits;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event TraitAdded(uint8 indexed characterType, uint8 indexed category, uint256 traitIndex, string name, uint16 probability);
    event OneOfOneSet(uint256 indexed tokenId, string characterName);
    event PlaceholderSvgSet(address indexed pointer);
    event Revealed();

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidTokenId();
    error InvalidCharacterType();
    error InvalidCategory();
    error InvalidTraitIndex();
    error InvalidProbability();
    error ArrayLengthMismatch();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor() {
        _initializeOwner(msg.sender);
    }

    // =============================================================
    //                      CHARACTER TYPE
    // =============================================================

    function getCharacterType(uint256 tokenId) public view returns (uint8) {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        if (oneOfOnes[tokenId].exists) return uint8(CharacterType.ONE_OF_ONE);
        return uint8(uint256(storedTraits[tokenId]) >> 96);
    }

    // =============================================================
    //                        STORED TRAITS
    // =============================================================

    function batchSetTraits(
        uint256[] calldata tokenIds,
        bytes32[] calldata packedTraits
    ) external onlyOwner {
        uint256 len = tokenIds.length;
        if (len != packedTraits.length) revert ArrayLengthMismatch();

        for (uint256 i; i < len; ) {
            uint256 tokenId = tokenIds[i];
            if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();

            storedTraits[tokenId] = packedTraits[i];
            emit TraitsStored(tokenId);
            unchecked { ++i; }
        }
    }

    function setTraitForToken(
        uint256 tokenId,
        uint8 category,
        uint8 traitIndex
    ) external onlyOwner {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        if (category >= CATEGORY_COUNT) revert InvalidCategory();

        bytes32 packed = storedTraits[tokenId];
        uint256 shift = uint256(category) * 8;
        uint256 mask = ~(uint256(0xFF) << shift);
        packed = bytes32((uint256(packed) & mask) | (uint256(traitIndex) << shift));

        storedTraits[tokenId] = packed;
        emit TraitUpdated(tokenId, category, traitIndex);
    }

    function getStoredTraits(uint256 tokenId) external view returns (uint8[12] memory result) {
        CharacterData memory d = _unpackCharacterData(storedTraits[tokenId]);
        result[0] = d.backdrop;
        result[1] = d.head;
        result[2] = d.expression;
        result[3] = d.eyes;
        result[4] = d.nose;
        result[5] = d.eartip;
        result[6] = d.earAccessory;
        result[7] = d.facialHair;
        result[8] = d.mouth;
        result[9] = d.chin;
        result[10] = d.neck;
        result[11] = d.accessory;
    }

    function isTraitStored(uint256 tokenId) external view returns (bool) {
        return storedTraits[tokenId] != bytes32(0);
    }

    // =============================================================
    //                           RENDERING
    // =============================================================

    function getSVG(uint256 tokenId) external view returns (string memory) {
        bytes memory inner;

        if (!revealed) {
            if (placeholderSvgPointer == address(0)) revert TraitsNotStored();
            inner = _readFileStorePointer(placeholderSvgPointer);
        } else if (oneOfOnes[tokenId].exists) {
            inner = _readFileStorePointer(oneOfOnes[tokenId].completeSvgContract);
        } else {
            bytes32 packed = storedTraits[tokenId];
            if (packed == bytes32(0)) {
                if (placeholderSvgPointer != address(0)) {
                    inner = _readFileStorePointer(placeholderSvgPointer);
                } else {
                    revert TraitsNotStored();
                }
            } else {
                CharacterType charType = CharacterType(uint8(uint256(packed) >> 96));
                inner = _assembleSVG(_unpackCharacterData(packed), charType);
            }
        }

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 58 58" fill="none" id="', tokenId.toString(), '" data-token-id="', tokenId.toString(), '">',
            inner,
            "</svg>"
        ));
    }

    function getTraitsMetadataForToken(uint256 tokenId) public view returns (string memory) {
        if (!revealed) {
            return '{"trait_type":"Status","value":"Unrevealed"}';
        }

        if (oneOfOnes[tokenId].exists) {
            return _formatOneOfOneMetadata(oneOfOnes[tokenId].characterName);
        }

        bytes32 packed = storedTraits[tokenId];
        if (packed == bytes32(0)) {
            return '{"trait_type":"Status","value":"Unrevealed"}';
        }

        CharacterType charType = CharacterType(uint8(uint256(packed) >> 96));
        return _formatTraitsMetadata(_unpackCharacterData(packed), charType);
    }

    // =============================================================
    //                         TRAIT MANAGEMENT
    // =============================================================

    function addTrait(
        uint8 characterType,
        uint8 category,
        string calldata name,
        uint16 probability,
        address fileStorePointer
    ) external onlyOwner {
        if (characterType > uint8(CharacterType.ONE_OF_ONE)) revert InvalidCharacterType();
        if (category >= CATEGORY_COUNT) revert InvalidCategory();
        if (probability == 0) revert InvalidProbability();
        if (fileStorePointer == address(0)) revert InvalidPointer();

        TraitConfig[] storage arr = traits[characterType][category];
        arr.push(TraitConfig({name: name, probability: probability, svgContract: fileStorePointer}));

        emit TraitAdded(characterType, category, arr.length - 1, name, probability);
    }

    function batchAddTraits(
        uint8[] calldata characterTypes,
        uint8[] calldata categories,
        string[] calldata names,
        uint16[] calldata probabilities,
        address[] calldata fileStorePointers
    ) external onlyOwner {
        uint256 len = characterTypes.length;
        if (
            len != categories.length ||
            len != names.length ||
            len != probabilities.length ||
            len != fileStorePointers.length
        ) revert ArrayLengthMismatch();

        for (uint256 i; i < len; ) {
            uint8 ctype = characterTypes[i];
            uint8 cat = categories[i];
            if (ctype > uint8(CharacterType.ONE_OF_ONE)) revert InvalidCharacterType();
            if (cat >= CATEGORY_COUNT) revert InvalidCategory();
            if (probabilities[i] == 0) revert InvalidProbability();
            if (fileStorePointers[i] == address(0)) revert InvalidPointer();

            TraitConfig[] storage arr = traits[ctype][cat];
            arr.push(TraitConfig({name: names[i], probability: probabilities[i], svgContract: fileStorePointers[i]}));

            emit TraitAdded(ctype, cat, arr.length - 1, names[i], probabilities[i]);
            unchecked { ++i; }
        }
    }

    function setOneOfOne(
        uint256 tokenId,
        string calldata characterName,
        address fileStorePointer
    ) external onlyOwner {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        if (fileStorePointer == address(0)) revert InvalidPointer();

        oneOfOnes[tokenId] = OneOfOneData({
            characterName: characterName,
            completeSvgContract: fileStorePointer,
            exists: true
        });

        emit OneOfOneSet(tokenId, characterName);
    }

    function batchSetOneOfOnes(
        uint256[] calldata tokenIds,
        string[] calldata characterNames,
        address[] calldata fileStorePointers
    ) external onlyOwner {
        uint256 len = tokenIds.length;
        if (len != characterNames.length || len != fileStorePointers.length) revert ArrayLengthMismatch();

        for (uint256 i; i < len; ) {
            uint256 tid = tokenIds[i];
            if (tid == 0 || tid > MAX_SUPPLY) revert InvalidTokenId();
            if (fileStorePointers[i] == address(0)) revert InvalidPointer();

            oneOfOnes[tid] = OneOfOneData({
                characterName: characterNames[i],
                completeSvgContract: fileStorePointers[i],
                exists: true
            });

            emit OneOfOneSet(tid, characterNames[i]);
            unchecked { ++i; }
        }
    }

    // =============================================================
    //                    PLACEHOLDER MANAGEMENT
    // =============================================================

    function setPlaceholderSvg(address pointer) external onlyOwner {
        if (pointer == address(0)) revert InvalidPointer();
        placeholderSvgPointer = pointer;
        emit PlaceholderSvgSet(pointer);
    }

    // =============================================================
    //                      REVEAL MANAGEMENT
    // =============================================================

    function reveal() external onlyOwner {
        revealed = true;
        emit Revealed();
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    function getOneOfOneInfo(uint256 tokenId)
        external
        view
        returns (string memory characterName, address svgContract, bool exists)
    {
        OneOfOneData storage ooo = oneOfOnes[tokenId];
        return (ooo.characterName, ooo.completeSvgContract, ooo.exists);
    }

    // =============================================================
    //                    INTERNAL HELPER FUNCTIONS
    // =============================================================

    function _readFileStorePointer(address ptr) internal view returns (bytes memory) {
        if (ptr == address(0)) revert InvalidPointer();
        File memory file = abi.decode(SSTORE2.read(ptr), (File));
        return bytes(file.read());
    }

    function _unpackCharacterData(bytes32 packed) internal pure returns (CharacterData memory d) {
        uint256 v = uint256(packed);
        d.backdrop     = uint8(v);
        d.head         = uint8(v >> 8);
        d.expression   = uint8(v >> 16);
        d.eyes         = uint8(v >> 24);
        d.nose         = uint8(v >> 32);
        d.eartip       = uint8(v >> 40);
        d.earAccessory = uint8(v >> 48);
        d.facialHair   = uint8(v >> 56);
        d.mouth        = uint8(v >> 64);
        d.chin         = uint8(v >> 72);
        d.neck         = uint8(v >> 80);
        d.accessory    = uint8(v >> 88);
    }

    function _assembleSVG(CharacterData memory d, CharacterType charType) internal view returns (bytes memory) {
        uint8 t = uint8(charType);
        uint8[12] memory idx = [
            d.backdrop, d.head, d.expression, d.eyes,
            d.nose, d.eartip, d.earAccessory, d.facialHair,
            d.mouth, d.chin, d.neck, d.accessory
        ];

        bytes memory layers;
        for (uint8 i; i < CATEGORY_COUNT; ) {
            uint8 sel = idx[i];
            if (sel != 0) {
                TraitConfig[] storage arr = traits[t][i];
                if (arr.length == 0 && t != uint8(CharacterType.NORMAL)) {
                    arr = traits[uint8(CharacterType.NORMAL)][i];
                }
                if (sel <= arr.length) {
                    address ptr = arr[sel - 1].svgContract;
                    if (ptr != address(0)) {
                        layers = abi.encodePacked(layers, _readFileStorePointer(ptr));
                    }
                }
            }
            unchecked { ++i; }
        }

        return layers;
    }

    function _formatOneOfOneMetadata(string memory nm) internal view returns (string memory) {
        bytes memory m = abi.encodePacked('{"trait_type":"Character Type","value":"One of One"}');
        for (uint8 i; i < CATEGORY_COUNT; ) {
            m = abi.encodePacked(
                m, ',{"trait_type":"', categoryNames[i], '","value":"', nm, '"}'
            );
            unchecked { ++i; }
        }
        return string(m);
    }

    function _formatTraitsMetadata(CharacterData memory d, CharacterType charType) internal view returns (string memory) {
        bytes memory m = abi.encodePacked(
            '{"trait_type":"Character Type","value":"',
            (charType == CharacterType.SPECIAL ? "Special" : "Normal"),
            '"}'
        );

        uint8 t = uint8(charType);
        uint8[12] memory idx = [
            d.backdrop, d.head, d.expression, d.eyes,
            d.nose, d.eartip, d.earAccessory, d.facialHair,
            d.mouth, d.chin, d.neck, d.accessory
        ];

        for (uint8 i; i < CATEGORY_COUNT; ) {
            uint8 sel = idx[i];
            if (sel != 0) {
                TraitConfig[] storage arr = traits[t][i];
                if (arr.length == 0 && t != uint8(CharacterType.NORMAL)) {
                    arr = traits[uint8(CharacterType.NORMAL)][i];
                }
                if (sel <= arr.length) {
                    TraitConfig storage conf = arr[sel - 1];
                    m = abi.encodePacked(
                        m, ',{"trait_type":"', categoryNames[i], '","value":"', conf.name, '"}'
                    );
                }
            }
            unchecked { ++i; }
        }
        return string(m);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDealerRendererSVG} from "./IDealerRendererSVG.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {SSTORE2} from "solady/src/utils/SSTORE2.sol";

/**
 * @title DealerRendererSVG - On-Chain SVG Generator
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Generates dynamic SVG art for dealers based on token seed and character type.
 *      Supports three character types: Normal, Special, and One-of-One.
 *      Uses SSTORE2 for gas-efficient on-chain SVG storage.
 * @author Dealers.Exe Team
 */
contract DealerRendererSVG is IDealerRendererSVG {
    using LibString for uint256;

    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 public constant MAX_SUPPLY = 8888;
    uint256 public constant SPECIAL_COUNT = 500;
    uint256 public constant ONE_OF_ONE_COUNT = 35;
    uint256 public constant NORMAL_COUNT = MAX_SUPPLY - SPECIAL_COUNT - ONE_OF_ONE_COUNT;

    // =============================================================
    //                            ENUMS
    // =============================================================

    enum CharacterType {
        NORMAL,
        SPECIAL,
        ONE_OF_ONE
    }

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

    mapping(uint256 => CharacterType) public tokenTypeAssignments;
    bool public distributionInitialized;

    mapping(uint8 => mapping(uint8 => TraitConfig[])) public traits;

    mapping(uint256 => OneOfOneData) public oneOfOnes;

    string[11] public categoryNames = [
        "Backdrop", "Head", "Expression", "Eyes", "Nose", "Eartip",
        "Ear Accessory", "Mouth", "Chin", "Neck", "Accessory"
    ];

    address public owner;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event DistributionInitialized();
    event CharacterTypeAssigned(uint256 indexed tokenId, CharacterType characterType);
    event TraitAdded(uint8 indexed characterType, uint8 indexed category, uint8 indexed traitIndex, string name, uint16 probability);
    event OneOfOneSet(uint256 indexed tokenId, string characterName);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotOwner();
    error AlreadyInitialized();
    error InvalidTokenId();
    error InvalidCharacterType();
    error InvalidCategory();
    error InvalidProbability();
    error ArrayLengthMismatch();
    error ZeroAddress();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // =============================================================
    //                    DISTRIBUTION / ASSIGNMENT
    // =============================================================

    /**
     * @notice Initialize character type distribution using Fisher-Yates shuffle
     * @param seed Random seed for deterministic shuffling
     */
    function initializeDistribution(uint256 seed) external onlyOwner {
        if (distributionInitialized) revert AlreadyInitialized();

        uint256[] memory tokenIds = new uint256[](MAX_SUPPLY);
        for (uint256 i; i < MAX_SUPPLY; ) {
            tokenIds[i] = i + 1;
            unchecked { ++i; }
        }

        for (uint256 i = MAX_SUPPLY - 1; i > 0; ) {
            uint256 j = uint256(keccak256(abi.encode(seed, i))) % (i + 1);
            (tokenIds[i], tokenIds[j]) = (tokenIds[j], tokenIds[i]);
            unchecked { --i; }
        }

        uint256 idx;

        for (uint256 i; i < ONE_OF_ONE_COUNT; ) {
            uint256 tid = tokenIds[idx];
            tokenTypeAssignments[tid] = CharacterType.ONE_OF_ONE;
            emit CharacterTypeAssigned(tid, CharacterType.ONE_OF_ONE);
            unchecked { ++i; ++idx; }
        }

        for (uint256 i; i < SPECIAL_COUNT; ) {
            uint256 tid = tokenIds[idx];
            tokenTypeAssignments[tid] = CharacterType.SPECIAL;
            emit CharacterTypeAssigned(tid, CharacterType.SPECIAL);
            unchecked { ++i; ++idx; }
        }

        for (uint256 i = idx; i < MAX_SUPPLY; ) {
            uint256 tid = tokenIds[i];
            tokenTypeAssignments[tid] = CharacterType.NORMAL;
            emit CharacterTypeAssigned(tid, CharacterType.NORMAL);
            unchecked { ++i; }
        }

        distributionInitialized = true;
        emit DistributionInitialized();
    }

    /**
     * @notice Get the character type for a token as uint8
     * @param tokenId The token ID to query
     * @return Character type as uint8 (0=Normal, 1=Special, 2=OneOfOne)
     */
    function getCharacterType(uint256 tokenId) public view returns (uint8) {
        if (!distributionInitialized) {
            return uint8(CharacterType.NORMAL);
        }
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        return uint8(tokenTypeAssignments[tokenId]);
    }

    // =============================================================
    //                           RENDERING
    // =============================================================

    /**
     * @notice Generate the complete SVG for a token
     * @param tokenId The token ID to render
     * @param seed Random seed for trait selection
     * @return Complete SVG string
     */
    function getSVG(uint256 tokenId, uint256 seed) external view returns (string memory) {
        CharacterType charType = _getCharacterTypeEnum(tokenId);

        OneOfOneData storage ooo = oneOfOnes[tokenId];
        if (charType == CharacterType.ONE_OF_ONE && ooo.exists) {
            return string(SSTORE2.read(ooo.completeSvgContract));
        }

        CharacterData memory data = _generateCharacterData(seed, charType);
        return _assembleSVG(data, charType);
    }

    /**
     * @notice Get traits metadata JSON for a seed (backward compatible)
     * @param seed Random seed for trait selection
     * @return JSON string of trait metadata
     */
    function getTraitsMetadata(uint256 seed) external view returns (string memory) {
        return getTraitsMetadataForToken(0, seed);
    }

    /**
     * @notice Get traits metadata JSON for a specific token
     * @param tokenId The token ID to query
     * @param seed Random seed for trait selection
     * @return JSON string of trait metadata
     */
    function getTraitsMetadataForToken(uint256 tokenId, uint256 seed) public view returns (string memory) {
        CharacterType charType = _getCharacterTypeEnum(tokenId);

        OneOfOneData storage ooo = oneOfOnes[tokenId];
        if (charType == CharacterType.ONE_OF_ONE && ooo.exists) {
            return _formatOneOfOneMetadata(ooo.characterName);
        }

        CharacterData memory data = _generateCharacterData(seed, charType);
        return _formatTraitsMetadata(data, charType);
    }

    // =============================================================
    //                         TRAIT MANAGEMENT
    // =============================================================

    /**
     * @notice Add a new trait to the configuration
     * @param characterType Type of character (0=Normal, 1=Special, 2=OneOfOne)
     * @param category Trait category index (0-10)
     * @param name Human-readable trait name
     * @param probability Weight for random selection
     * @param svgData Raw SVG bytes to store
     */
    function addTrait(
        uint8 characterType,
        uint8 category,
        string calldata name,
        uint16 probability,
        bytes calldata svgData
    ) external onlyOwner {
        if (characterType > uint8(CharacterType.ONE_OF_ONE)) revert InvalidCharacterType();
        if (category >= 11) revert InvalidCategory();
        if (probability == 0) revert InvalidProbability();

        address ptr = SSTORE2.write(svgData);
        TraitConfig[] storage arr = traits[characterType][category];
        arr.push(TraitConfig({name: name, probability: probability, svgContract: ptr}));

        emit TraitAdded(characterType, category, uint8(arr.length - 1), name, probability);
    }

    /**
     * @notice Add multiple traits in a single transaction
     * @param characterTypes Array of character types
     * @param categories Array of category indices
     * @param names Array of trait names
     * @param probabilities Array of selection weights
     * @param svgDataArray Array of SVG data bytes
     */
    function batchAddTraits(
        uint8[] calldata characterTypes,
        uint8[] calldata categories,
        string[] calldata names,
        uint16[] calldata probabilities,
        bytes[] calldata svgDataArray
    ) external onlyOwner {
        uint256 len = characterTypes.length;
        if (
            len != categories.length ||
            len != names.length ||
            len != probabilities.length ||
            len != svgDataArray.length
        ) revert ArrayLengthMismatch();

        for (uint256 i; i < len; ) {
            uint8 ctype = characterTypes[i];
            uint8 cat = categories[i];
            if (ctype > uint8(CharacterType.ONE_OF_ONE)) revert InvalidCharacterType();
            if (cat >= 11) revert InvalidCategory();
            if (probabilities[i] == 0) revert InvalidProbability();

            address ptr = SSTORE2.write(svgDataArray[i]);
            TraitConfig[] storage arr = traits[ctype][cat];
            arr.push(TraitConfig({name: names[i], probability: probabilities[i], svgContract: ptr}));

            emit TraitAdded(ctype, cat, uint8(arr.length - 1), names[i], probabilities[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Set a complete SVG for a one-of-one token
     * @param tokenId The token ID to configure
     * @param characterName Name for the unique character
     * @param completeSvgData Complete SVG bytes to store
     */
    function setOneOfOne(
        uint256 tokenId,
        string calldata characterName,
        bytes calldata completeSvgData
    ) external onlyOwner {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();

        address ptr = SSTORE2.write(completeSvgData);
        oneOfOnes[tokenId] = OneOfOneData({
            characterName: characterName,
            completeSvgContract: ptr,
            exists: true
        });

        emit OneOfOneSet(tokenId, characterName);
    }

    /**
     * @notice Set multiple one-of-one tokens in a single transaction
     * @param tokenIds Array of token IDs
     * @param characterNames Array of character names
     * @param completeSvgDataArray Array of complete SVG bytes
     */
    function batchSetOneOfOnes(
        uint256[] calldata tokenIds,
        string[] calldata characterNames,
        bytes[] calldata completeSvgDataArray
    ) external onlyOwner {
        uint256 len = tokenIds.length;
        if (len != characterNames.length || len != completeSvgDataArray.length) revert ArrayLengthMismatch();

        for (uint256 i; i < len; ) {
            uint256 tid = tokenIds[i];
            if (tid == 0 || tid > MAX_SUPPLY) revert InvalidTokenId();

            address ptr = SSTORE2.write(completeSvgDataArray[i]);
            oneOfOnes[tid] = OneOfOneData({
                characterName: characterNames[i],
                completeSvgContract: ptr,
                exists: true
            });

            emit OneOfOneSet(tid, characterNames[i]);
            unchecked { ++i; }
        }
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Preview the character type for a token
     * @param tokenId The token ID to query
     * @return The character type enum value
     */
    function previewCharacterType(uint256 tokenId) external view returns (CharacterType) {
        if (!distributionInitialized) revert AlreadyInitialized();
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        return tokenTypeAssignments[tokenId];
    }

    /**
     * @notice Get paginated list of token IDs by character type
     * @param charType The character type to filter by
     * @param offset Number of matches to skip
     * @param limit Maximum number of results to return
     * @return tokenIds Array of matching token IDs
     */
    function getTokenIdsByType(CharacterType charType, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory tokenIds)
    {
        if (!distributionInitialized) revert AlreadyInitialized();

        uint256[] memory res = new uint256[](limit);
        uint256 found;
        uint256 skipped;

        for (uint256 i = 1; i <= MAX_SUPPLY && found < limit; ) {
            if (tokenTypeAssignments[i] == charType) {
                if (skipped >= offset) {
                    res[found] = i;
                    unchecked { ++found; }
                } else {
                    unchecked { ++skipped; }
                }
            }
            unchecked { ++i; }
        }

        assembly { mstore(res, found) }
        return res;
    }

    /**
     * @notice Get the number of traits for a character type and category
     * @param characterType The character type (0=Normal, 1=Special, 2=OneOfOne)
     * @param category The category index (0-10)
     * @return Number of configured traits
     */
    function getTraitCount(uint8 characterType, uint8 category) external view returns (uint256) {
        if (characterType > uint8(CharacterType.ONE_OF_ONE)) revert InvalidCharacterType();
        if (category >= 11) revert InvalidCategory();
        return traits[characterType][category].length;
    }

    /**
     * @notice Get detailed information about a specific trait
     * @param characterType The character type
     * @param category The category index
     * @param traitIndex The trait index within the category
     * @return name Trait name
     * @return probability Selection weight
     * @return svgContract SSTORE2 pointer address
     */
    function getTraitInfo(uint8 characterType, uint8 category, uint8 traitIndex)
        external
        view
        returns (string memory name, uint16 probability, address svgContract)
    {
        if (characterType > uint8(CharacterType.ONE_OF_ONE)) revert InvalidCharacterType();
        if (category >= 11) revert InvalidCategory();
        TraitConfig storage tr = traits[characterType][category][traitIndex];
        return (tr.name, tr.probability, tr.svgContract);
    }

    /**
     * @notice Get one-of-one configuration for a token
     * @param tokenId The token ID to query
     * @return characterName The unique character name
     * @return svgContract SSTORE2 pointer address
     * @return exists Whether the one-of-one is configured
     */
    function getOneOfOneInfo(uint256 tokenId)
        external
        view
        returns (string memory characterName, address svgContract, bool exists)
    {
        OneOfOneData storage ooo = oneOfOnes[tokenId];
        return (ooo.characterName, ooo.completeSvgContract, ooo.exists);
    }

    /**
     * @notice Get collection supply configuration
     * @return maxSupply Total max supply
     * @return normalCount Number of normal characters
     * @return specialCount Number of special characters
     * @return oneOfOneCount Number of one-of-one characters
     */
    function getCollectionConfig()
        external
        pure
        returns (uint256 maxSupply, uint256 normalCount, uint256 specialCount, uint256 oneOfOneCount)
    {
        return (MAX_SUPPLY, NORMAL_COUNT, SPECIAL_COUNT, ONE_OF_ONE_COUNT);
    }

    // =============================================================
    //                         ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Transfer ownership of the contract
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    // =============================================================
    //                    INTERNAL HELPER FUNCTIONS
    // =============================================================

    function _getCharacterTypeEnum(uint256 tokenId) internal view returns (CharacterType) {
        if (!distributionInitialized) return CharacterType.NORMAL;
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        return tokenTypeAssignments[tokenId];
    }

    function _generateCharacterData(uint256 seed, CharacterType charType) internal view returns (CharacterData memory d) {
        uint8 t = uint8(charType);

        d.backdrop     = _selectTraitByProbability(t, 0,  uint256(seed >> 8));
        d.head         = _selectTraitByProbability(t, 1,  uint256(seed >> 16));
        d.expression   = _selectTraitByProbability(t, 2,  uint256(seed >> 24));
        d.eyes         = _selectTraitByProbability(t, 3,  uint256(seed >> 32));
        d.nose         = _selectTraitByProbability(t, 4,  uint256(seed >> 40));
        d.eartip       = _selectTraitByProbability(t, 5,  uint256(seed >> 48));
        d.earAccessory = _selectTraitByProbability(t, 6,  uint256(seed >> 56));
        d.mouth        = _selectTraitByProbability(t, 7,  uint256(seed >> 64));
        d.chin         = _selectTraitByProbability(t, 8,  uint256(seed >> 72));
        d.neck         = _selectTraitByProbability(t, 9,  uint256(seed >> 80));
        d.accessory    = _selectTraitByProbability(t, 10, uint256(seed >> 88));
    }

    function _selectTraitByProbability(uint8 characterType, uint8 category, uint256 rnd) internal view returns (uint8) {
        TraitConfig[] storage arr = traits[characterType][category];
        if (arr.length == 0 && characterType != uint8(CharacterType.NORMAL)) {
            arr = traits[uint8(CharacterType.NORMAL)][category];
        }
        uint256 n = arr.length;
        if (n == 0) return 0;

        uint256 total;
        for (uint256 i; i < n; ) {
            total += arr[i].probability;
            unchecked { ++i; }
        }
        if (total == 0) return 0;

        uint256 roll = rnd % total;
        uint256 acc;
        for (uint8 i; i < n; ) {
            acc += arr[i].probability;
            if (roll < acc) {
                return i + 1;
            }
            unchecked { ++i; }
        }
        return uint8(n);
    }

    function _assembleSVG(CharacterData memory d, CharacterType charType) internal view returns (string memory) {
        uint8 t = uint8(charType);
        uint8[11] memory idx = [
            d.backdrop, d.head, d.expression, d.eyes,
            d.nose, d.eartip, d.earAccessory, d.mouth,
            d.chin, d.neck, d.accessory
        ];

        bytes memory layers;
        for (uint8 i; i < 11; ) {
            uint8 sel = idx[i];
            if (sel != 0) {
                TraitConfig[] storage arr = traits[t][i];
                if (sel <= arr.length) {
                    address ptr = arr[sel - 1].svgContract;
                    if (ptr != address(0)) {
                        layers = abi.encodePacked(layers, SSTORE2.read(ptr));
                    }
                }
            }
            unchecked { ++i; }
        }

        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">',
                layers,
                "</svg>"
            )
        );
    }

    function _formatOneOfOneMetadata(string memory nm) internal view returns (string memory) {
        bytes memory m = abi.encodePacked('{"trait_type":"Character Type","value":"One of One"}');
        for (uint8 i; i < 11; ) {
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
        uint8[11] memory idx = [
            d.backdrop, d.head, d.expression, d.eyes,
            d.nose, d.eartip, d.earAccessory, d.mouth,
            d.chin, d.neck, d.accessory
        ];

        for (uint8 i; i < 11; ) {
            uint8 sel = idx[i];
            if (sel != 0) {
                TraitConfig[] storage arr = traits[t][i];
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

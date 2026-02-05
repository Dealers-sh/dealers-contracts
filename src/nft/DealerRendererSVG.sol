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
 * @dev Generates dynamic SVG art for dealers based on token seed and character type.
 *      Supports three character types: Normal, Special, and One-of-One.
 *      Uses SSTORE2 for gas-efficient on-chain SVG storage.
 * @author Dealers.Exe Team
 */
contract DealerRendererSVG is IDealerRendererSVG, Ownable {
    using LibString for uint256;

    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 public constant MAX_SUPPLY = 8888;
    uint256 public constant SPECIAL_COUNT = 500;
    uint256 public constant ONE_OF_ONE_COUNT = 35;
    uint256 public constant NORMAL_COUNT = MAX_SUPPLY - SPECIAL_COUNT - ONE_OF_ONE_COUNT;
    uint8 public constant CATEGORY_COUNT = 12;

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

    mapping(uint256 => CharacterType) public tokenTypeAssignments;
    bool public distributionInitialized;

    mapping(uint8 => mapping(uint8 => TraitConfig[])) public traits;

    mapping(uint256 => OneOfOneData) public oneOfOnes;
    mapping(uint256 => bool) public isReservedOneOfOne;
    uint256[] public reservedOneOfOneTokenIds;

    address public placeholderSvgPointer;

    struct OneOfOneSVG {
        string name;
        address svgPointer;
    }
    OneOfOneSVG[] public oneOfOneSVGPool;

    mapping(uint256 => uint256) public tokenPoolIndex;

    // Array size must match CATEGORY_COUNT
    string[12] public categoryNames = [
        "Backdrop", "Head", "Expression", "Eyes", "Nose", "Eartip",
        "Ear Accessory", "Facial Hair", "Mouth", "Chin", "Neck", "Accessory"
    ];

    struct IncompatibilityRule {
        uint16 traitA;
        uint16 traitB;
    }

    uint16 public constant MAX_RULES = 256;
    IncompatibilityRule[] public incompatibilityRules;
    mapping(uint16 => bool) private _hasIncompatibilities;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event DistributionInitialized();
    event CharacterTypeAssigned(uint256 indexed tokenId, CharacterType characterType);
    event TraitAdded(uint8 indexed characterType, uint8 indexed category, uint256 traitIndex, string name, uint16 probability);
    event OneOfOneSet(uint256 indexed tokenId, string characterName);
    event PlaceholderSvgSet(address indexed pointer);
    event OneOfOneAddedToPool(uint256 indexed index, string name);
    event PoolSvgAssigned(uint256 indexed tokenId, uint256 indexed poolIndex);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotInitialized();
    error InvalidTokenId();
    error InvalidTokenType();
    error InvalidCharacterType();
    error InvalidCategory();
    error InvalidTraitIndex();
    error InvalidProbability();
    error ArrayLengthMismatch();
    error InvalidOneOfOneConfiguration();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor() {
        _initializeOwner(msg.sender);
    }

    // =============================================================
    //                    DISTRIBUTION / ASSIGNMENT
    // =============================================================

    /**
     * @notice Initialize character type distribution using Fisher-Yates shuffle
     * @dev Reserved one-of-ones (set via setOneOfOne before reveal) are forced as ONE_OF_ONE.
     *      Remaining ONE_OF_ONE slots are filled randomly and assigned pool SVGs.
     * @param seed Random seed for deterministic shuffling
     */
    function initializeDistribution(uint256 seed) external onlyOwner {
        if (distributionInitialized) revert AlreadyInitialized();

        uint256 reservedCount = reservedOneOfOneTokenIds.length;
        if (reservedCount > ONE_OF_ONE_COUNT) revert TooManyReservedOneOfOnes();

        uint256 randomOneOfOneSlots = ONE_OF_ONE_COUNT - reservedCount;
        uint256 poolSize = oneOfOneSVGPool.length;
        if (poolSize < randomOneOfOneSlots) revert InsufficientPoolSize();

        for (uint256 i; i < reservedCount; ) {
            uint256 tid = reservedOneOfOneTokenIds[i];
            tokenTypeAssignments[tid] = CharacterType.ONE_OF_ONE;
            emit CharacterTypeAssigned(tid, CharacterType.ONE_OF_ONE);
            unchecked { ++i; }
        }

        uint256[] memory nonReservedTokenIds = new uint256[](MAX_SUPPLY - reservedCount);
        uint256 nrIdx;
        for (uint256 i = 1; i <= MAX_SUPPLY; ) {
            if (!isReservedOneOfOne[i]) {
                nonReservedTokenIds[nrIdx] = i;
                unchecked { ++nrIdx; }
            }
            unchecked { ++i; }
        }

        for (uint256 i = nonReservedTokenIds.length - 1; i > 0; ) {
            uint256 j = uint256(keccak256(abi.encode(seed, i))) % (i + 1);
            (nonReservedTokenIds[i], nonReservedTokenIds[j]) = (nonReservedTokenIds[j], nonReservedTokenIds[i]);
            unchecked { --i; }
        }

        uint256[] memory poolIndices = new uint256[](poolSize);
        for (uint256 i; i < poolSize; ) {
            poolIndices[i] = i + 1;
            unchecked { ++i; }
        }
        for (uint256 i = poolSize - 1; i > 0; ) {
            uint256 j = uint256(keccak256(abi.encode(seed, "pool", i))) % (i + 1);
            (poolIndices[i], poolIndices[j]) = (poolIndices[j], poolIndices[i]);
            unchecked { --i; }
        }

        uint256 idx;
        for (uint256 i; i < randomOneOfOneSlots; ) {
            uint256 tid = nonReservedTokenIds[idx];
            tokenTypeAssignments[tid] = CharacterType.ONE_OF_ONE;
            tokenPoolIndex[tid] = poolIndices[i];
            emit CharacterTypeAssigned(tid, CharacterType.ONE_OF_ONE);
            emit PoolSvgAssigned(tid, poolIndices[i]);
            unchecked { ++i; ++idx; }
        }

        for (uint256 i; i < SPECIAL_COUNT; ) {
            uint256 tid = nonReservedTokenIds[idx];
            tokenTypeAssignments[tid] = CharacterType.SPECIAL;
            emit CharacterTypeAssigned(tid, CharacterType.SPECIAL);
            unchecked { ++i; ++idx; }
        }

        uint256 remaining = nonReservedTokenIds.length;
        for (uint256 i = idx; i < remaining; ) {
            uint256 tid = nonReservedTokenIds[i];
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
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        if (!distributionInitialized) {
            return uint8(CharacterType.NORMAL);
        }
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
        if (!distributionInitialized && placeholderSvgPointer != address(0)) {
            return string(_readFileStorePointer(placeholderSvgPointer));
        }

        CharacterType charType = _getCharacterTypeEnum(tokenId);

        OneOfOneData storage ooo = oneOfOnes[tokenId];
        if (charType == CharacterType.ONE_OF_ONE && ooo.exists) {
            return string(_readFileStorePointer(ooo.completeSvgContract));
        }

        if (charType == CharacterType.ONE_OF_ONE) {
            uint256 poolIdx = tokenPoolIndex[tokenId];
            if (poolIdx > 0 && poolIdx <= oneOfOneSVGPool.length) {
                return string(_readFileStorePointer(oneOfOneSVGPool[poolIdx - 1].svgPointer));
            }
            revert InvalidOneOfOneConfiguration();
        }

        CharacterData memory data = _generateCharacterData(seed, charType);
        return _assembleSVG(data, charType);
    }

    /**
     * @notice Get traits metadata JSON for a specific token
     * @param tokenId The token ID to query
     * @param seed Random seed for trait selection
     * @return JSON string of trait metadata
     */
    function getTraitsMetadataForToken(uint256 tokenId, uint256 seed) public view returns (string memory) {
        if (!distributionInitialized) {
            return '{"trait_type":"Status","value":"Unrevealed"}';
        }

        CharacterType charType = _getCharacterTypeEnum(tokenId);

        OneOfOneData storage ooo = oneOfOnes[tokenId];
        if (charType == CharacterType.ONE_OF_ONE && ooo.exists) {
            return _formatOneOfOneMetadata(ooo.characterName);
        }

        if (charType == CharacterType.ONE_OF_ONE) {
            uint256 poolIdx = tokenPoolIndex[tokenId];
            if (poolIdx > 0 && poolIdx <= oneOfOneSVGPool.length) {
                return _formatOneOfOneMetadata(oneOfOneSVGPool[poolIdx - 1].name);
            }
        }

        CharacterData memory data = _generateCharacterData(seed, charType);
        return _formatTraitsMetadata(data, charType);
    }

    // =============================================================
    //                         TRAIT MANAGEMENT
    // =============================================================

    /**
     * @notice Add a new trait to the configuration using a FileStore pointer
     * @param characterType Type of character (0=Normal, 1=Special, 2=OneOfOne)
     * @param category Trait category index (0-11)
     * @param name Human-readable trait name
     * @param probability Weight for random selection
     * @param fileStorePointer SSTORE2 pointer to ABI-encoded File struct
     */
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

    /**
     * @notice Add multiple traits in a single transaction using FileStore pointers
     * @param characterTypes Array of character types
     * @param categories Array of category indices
     * @param names Array of trait names
     * @param probabilities Array of selection weights
     * @param fileStorePointers Array of SSTORE2 pointers to ABI-encoded File structs
     */
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

    /**
     * @notice Set a complete SVG for a one-of-one token using a FileStore pointer
     * @param tokenId The token ID to configure
     * @param characterName Name for the unique character
     * @param fileStorePointer SSTORE2 pointer to ABI-encoded File struct
     */
    function setOneOfOne(
        uint256 tokenId,
        string calldata characterName,
        address fileStorePointer
    ) external onlyOwner {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        if (distributionInitialized && tokenTypeAssignments[tokenId] != CharacterType.ONE_OF_ONE) {
            revert InvalidTokenType();
        }
        if (fileStorePointer == address(0)) revert InvalidPointer();

        _reserveOneOfOne(tokenId);

        oneOfOnes[tokenId] = OneOfOneData({
            characterName: characterName,
            completeSvgContract: fileStorePointer,
            exists: true
        });

        emit OneOfOneSet(tokenId, characterName);
    }

    /**
     * @notice Set multiple one-of-one tokens in a single transaction using FileStore pointers
     * @param tokenIds Array of token IDs
     * @param characterNames Array of character names
     * @param fileStorePointers Array of SSTORE2 pointers to ABI-encoded File structs
     */
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
            if (distributionInitialized && tokenTypeAssignments[tid] != CharacterType.ONE_OF_ONE) {
                revert InvalidTokenType();
            }
            if (fileStorePointers[i] == address(0)) revert InvalidPointer();

            _reserveOneOfOne(tid);

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
    //                    PLACEHOLDER & POOL MANAGEMENT
    // =============================================================

    /**
     * @notice Set the placeholder SVG shown before reveal
     * @param pointer SSTORE2 pointer to ABI-encoded File struct
     */
    function setPlaceholderSvg(address pointer) external onlyOwner {
        if (pointer == address(0)) revert InvalidPointer();
        placeholderSvgPointer = pointer;
        emit PlaceholderSvgSet(pointer);
    }

    /**
     * @notice Add a one-of-one SVG to the pool for random assignment
     * @param name Character name for the one-of-one
     * @param pointer SSTORE2 pointer to ABI-encoded File struct
     */
    function addOneOfOneToPool(string calldata name, address pointer) external onlyOwner {
        if (distributionInitialized) revert AlreadyInitialized();
        if (pointer == address(0)) revert InvalidPointer();

        oneOfOneSVGPool.push(OneOfOneSVG({name: name, svgPointer: pointer}));
        emit OneOfOneAddedToPool(oneOfOneSVGPool.length - 1, name);
    }

    /**
     * @notice Add multiple one-of-one SVGs to the pool in a single transaction
     * @param names Array of character names
     * @param pointers Array of SSTORE2 pointers to ABI-encoded File structs
     */
    function batchAddOneOfOnesToPool(
        string[] calldata names,
        address[] calldata pointers
    ) external onlyOwner {
        if (distributionInitialized) revert AlreadyInitialized();
        uint256 len = names.length;
        if (len != pointers.length) revert ArrayLengthMismatch();

        for (uint256 i; i < len; ) {
            if (pointers[i] == address(0)) revert InvalidPointer();
            oneOfOneSVGPool.push(OneOfOneSVG({name: names[i], svgPointer: pointers[i]}));
            emit OneOfOneAddedToPool(oneOfOneSVGPool.length - 1, names[i]);
            unchecked { ++i; }
        }
    }

    // =============================================================
    //                 INCOMPATIBILITY RULE MANAGEMENT
    // =============================================================

    function addIncompatibilityRule(
        uint8 categoryA,
        uint8 traitIndexA,
        uint8 categoryB,
        uint8 traitIndexB
    ) external onlyOwner {
        if (distributionInitialized) revert RulesLocked();
        if (categoryA >= CATEGORY_COUNT || categoryB >= CATEGORY_COUNT) revert InvalidCategory();
        if (traitIndexA == 0 || traitIndexB == 0) revert InvalidRule();
        if (incompatibilityRules.length >= MAX_RULES) revert MaxRulesExceeded();

        uint16 traitA = _encodeTraitId(categoryA, traitIndexA);
        uint16 traitB = _encodeTraitId(categoryB, traitIndexB);
        (uint16 normA, uint16 normB) = _normalizeRule(traitA, traitB);

        (, bool found) = _findRuleIndex(normA, normB);
        if (found) revert DuplicateRule();

        incompatibilityRules.push(IncompatibilityRule({traitA: normA, traitB: normB}));
        _hasIncompatibilities[normA] = true;
        _hasIncompatibilities[normB] = true;

        emit IncompatibilityRuleAdded(categoryA, traitIndexA, categoryB, traitIndexB);
    }

    function batchAddIncompatibilityRules(
        uint8[] calldata categoriesA,
        uint8[] calldata traitIndicesA,
        uint8[] calldata categoriesB,
        uint8[] calldata traitIndicesB
    ) external onlyOwner {
        if (distributionInitialized) revert RulesLocked();
        uint256 len = categoriesA.length;
        if (len != traitIndicesA.length || len != categoriesB.length || len != traitIndicesB.length) {
            revert ArrayLengthMismatch();
        }
        if (incompatibilityRules.length + len > MAX_RULES) revert MaxRulesExceeded();

        for (uint256 i; i < len; ) {
            uint8 catA = categoriesA[i];
            uint8 idxA = traitIndicesA[i];
            uint8 catB = categoriesB[i];
            uint8 idxB = traitIndicesB[i];

            if (catA >= CATEGORY_COUNT || catB >= CATEGORY_COUNT) revert InvalidCategory();
            if (idxA == 0 || idxB == 0) revert InvalidRule();

            uint16 traitA = _encodeTraitId(catA, idxA);
            uint16 traitB = _encodeTraitId(catB, idxB);
            (uint16 normA, uint16 normB) = _normalizeRule(traitA, traitB);

            (, bool found) = _findRuleIndex(normA, normB);
            if (found) revert DuplicateRule();

            incompatibilityRules.push(IncompatibilityRule({traitA: normA, traitB: normB}));
            _hasIncompatibilities[normA] = true;
            _hasIncompatibilities[normB] = true;

            emit IncompatibilityRuleAdded(catA, idxA, catB, idxB);
            unchecked { ++i; }
        }
    }

    function removeIncompatibilityRule(
        uint8 categoryA,
        uint8 traitIndexA,
        uint8 categoryB,
        uint8 traitIndexB
    ) external onlyOwner {
        if (distributionInitialized) revert RulesLocked();

        uint16 traitA = _encodeTraitId(categoryA, traitIndexA);
        uint16 traitB = _encodeTraitId(categoryB, traitIndexB);
        (uint16 normA, uint16 normB) = _normalizeRule(traitA, traitB);

        (uint256 idx, bool found) = _findRuleIndex(normA, normB);
        if (!found) revert RuleNotFound();

        uint256 lastIdx = incompatibilityRules.length - 1;
        if (idx != lastIdx) {
            incompatibilityRules[idx] = incompatibilityRules[lastIdx];
        }
        incompatibilityRules.pop();

        emit IncompatibilityRuleRemoved(categoryA, traitIndexA, categoryB, traitIndexB);
    }

    function clearAllIncompatibilityRules() external onlyOwner {
        if (distributionInitialized) revert RulesLocked();

        uint256 count = incompatibilityRules.length;
        for (uint256 i; i < count; ) {
            IncompatibilityRule storage rule = incompatibilityRules[i];
            _hasIncompatibilities[rule.traitA] = false;
            _hasIncompatibilities[rule.traitB] = false;
            unchecked { ++i; }
        }
        delete incompatibilityRules;

        emit AllIncompatibilityRulesCleared(count);
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

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
        if (!distributionInitialized) revert NotInitialized();

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
     * @notice Get the size of the one-of-one SVG pool
     * @return Number of SVGs in the pool
     */
    function getOneOfOneSVGPoolSize() external view returns (uint256) {
        return oneOfOneSVGPool.length;
    }

    function getReservedOneOfOneCount() external view returns (uint256) {
        return reservedOneOfOneTokenIds.length;
    }

    function getIncompatibilityRuleCount() external view returns (uint256) {
        return incompatibilityRules.length;
    }

    function getIncompatibilityRule(uint256 index)
        external
        view
        returns (uint8 categoryA, uint8 traitIndexA, uint8 categoryB, uint8 traitIndexB)
    {
        if (index >= incompatibilityRules.length) revert InvalidTraitIndex();
        IncompatibilityRule storage rule = incompatibilityRules[index];
        (categoryA, traitIndexA) = _decodeTraitId(rule.traitA);
        (categoryB, traitIndexB) = _decodeTraitId(rule.traitB);
    }

    function areTraitsIncompatible(
        uint8 categoryA,
        uint8 traitIndexA,
        uint8 categoryB,
        uint8 traitIndexB
    ) external view returns (bool) {
        uint16 traitA = _encodeTraitId(categoryA, traitIndexA);
        uint16 traitB = _encodeTraitId(categoryB, traitIndexB);
        return _areIncompatible(traitA, traitB);
    }

    function getIncompatibleTraits(uint8 category, uint8 traitIndex)
        external
        view
        returns (uint8[] memory categories, uint8[] memory indices)
    {
        uint16 targetTrait = _encodeTraitId(category, traitIndex);
        uint256 count;
        uint256 len = incompatibilityRules.length;

        for (uint256 i; i < len; ) {
            IncompatibilityRule storage rule = incompatibilityRules[i];
            if (rule.traitA == targetTrait || rule.traitB == targetTrait) {
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }

        categories = new uint8[](count);
        indices = new uint8[](count);
        uint256 idx;

        for (uint256 i; i < len; ) {
            IncompatibilityRule storage rule = incompatibilityRules[i];
            uint16 other;
            if (rule.traitA == targetTrait) {
                other = rule.traitB;
            } else if (rule.traitB == targetTrait) {
                other = rule.traitA;
            } else {
                unchecked { ++i; }
                continue;
            }
            (categories[idx], indices[idx]) = _decodeTraitId(other);
            unchecked { ++idx; ++i; }
        }
    }

    // =============================================================
    //                    INTERNAL HELPER FUNCTIONS
    // =============================================================

    function _readFileStorePointer(address ptr) internal view returns (bytes memory) {
        if (ptr == address(0)) revert InvalidPointer();
        File memory file = abi.decode(SSTORE2.read(ptr), (File));
        return bytes(file.read());
    }

    function _reserveOneOfOne(uint256 tokenId) internal {
        if (!isReservedOneOfOne[tokenId]) {
            if (reservedOneOfOneTokenIds.length >= ONE_OF_ONE_COUNT) {
                revert TooManyReservedOneOfOnes();
            }
            isReservedOneOfOne[tokenId] = true;
            reservedOneOfOneTokenIds.push(tokenId);
        }
    }

    function _getCharacterTypeEnum(uint256 tokenId) internal view returns (CharacterType) {
        if (!distributionInitialized) return CharacterType.NORMAL;
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId();
        return tokenTypeAssignments[tokenId];
    }

    function _encodeTraitId(uint8 category, uint8 traitIndex) internal pure returns (uint16) {
        return (uint16(category) << 8) | uint16(traitIndex);
    }

    function _decodeTraitId(uint16 packed) internal pure returns (uint8 category, uint8 traitIndex) {
        category = uint8(packed >> 8);
        traitIndex = uint8(packed & 0xFF);
    }

    function _normalizeRule(uint16 a, uint16 b) internal pure returns (uint16, uint16) {
        return a < b ? (a, b) : (b, a);
    }

    function _findRuleIndex(uint16 traitA, uint16 traitB) internal view returns (uint256, bool) {
        uint256 len = incompatibilityRules.length;
        for (uint256 i; i < len; ) {
            IncompatibilityRule storage rule = incompatibilityRules[i];
            if (rule.traitA == traitA && rule.traitB == traitB) {
                return (i, true);
            }
            unchecked { ++i; }
        }
        return (0, false);
    }

    function _areIncompatible(uint16 traitA, uint16 traitB) internal view returns (bool) {
        if (!_hasIncompatibilities[traitA] && !_hasIncompatibilities[traitB]) {
            return false;
        }
        (uint16 normA, uint16 normB) = _normalizeRule(traitA, traitB);
        (, bool found) = _findRuleIndex(normA, normB);
        return found;
    }

    function _hasConflict(uint16 candidateTrait, uint8[12] memory selectedTraits) internal view returns (bool) {
        if (!_hasIncompatibilities[candidateTrait]) return false;

        for (uint8 cat; cat < CATEGORY_COUNT; ) {
            uint8 sel = selectedTraits[cat];
            if (sel != 0) {
                uint16 existingTrait = _encodeTraitId(cat, sel);
                if (_areIncompatible(candidateTrait, existingTrait)) {
                    return true;
                }
            }
            unchecked { ++cat; }
        }
        return false;
    }

    function _selectTraitWithConflictResolution(
        uint8 characterType,
        uint8 category,
        uint256 baseSeed,
        uint8[12] memory selectedTraits
    ) internal view returns (uint8) {
        uint8 selection = _selectTraitByProbability(characterType, category, baseSeed);
        if (selection == 0) return 0;

        uint16 candidateTrait = _encodeTraitId(category, selection);
        if (!_hasConflict(candidateTrait, selectedTraits)) {
            return selection;
        }

        for (uint8 attempt = 1; attempt <= 5; ) {
            uint256 newSeed = uint256(keccak256(abi.encode(baseSeed, category, attempt)));
            selection = _selectTraitByProbability(characterType, category, newSeed);
            if (selection == 0) return 0;

            candidateTrait = _encodeTraitId(category, selection);
            if (!_hasConflict(candidateTrait, selectedTraits)) {
                return selection;
            }
            unchecked { ++attempt; }
        }

        TraitConfig[] storage arr = traits[characterType][category];
        if (arr.length == 0 && characterType != uint8(CharacterType.NORMAL)) {
            arr = traits[uint8(CharacterType.NORMAL)][category];
        }
        uint256 n = arr.length;
        for (uint8 i = 1; i <= n; ) {
            candidateTrait = _encodeTraitId(category, i);
            if (!_hasConflict(candidateTrait, selectedTraits)) {
                return i;
            }
            unchecked { ++i; }
        }

        return _selectTraitByProbability(characterType, category, baseSeed);
    }

    function _generateCharacterData(uint256 seed, CharacterType charType) internal view returns (CharacterData memory d) {
        if (incompatibilityRules.length == 0) {
            return _generateCharacterDataSimple(seed, charType);
        }
        return _generateCharacterDataWithRules(seed, charType);
    }

    function _generateCharacterDataSimple(uint256 seed, CharacterType charType) internal view returns (CharacterData memory d) {
        uint8 t = uint8(charType);

        d.backdrop     = _selectTraitByProbability(t, 0,  uint256(seed >> 8));
        d.head         = _selectTraitByProbability(t, 1,  uint256(seed >> 16));
        d.expression   = _selectTraitByProbability(t, 2,  uint256(seed >> 24));
        d.eyes         = _selectTraitByProbability(t, 3,  uint256(seed >> 32));
        d.nose         = _selectTraitByProbability(t, 4,  uint256(seed >> 40));
        d.eartip       = _selectTraitByProbability(t, 5,  uint256(seed >> 48));
        d.earAccessory = _selectTraitByProbability(t, 6,  uint256(seed >> 56));
        d.facialHair   = _selectTraitByProbability(t, 7,  uint256(seed >> 64));
        d.mouth        = _selectTraitByProbability(t, 8,  uint256(seed >> 72));
        d.chin         = _selectTraitByProbability(t, 9,  uint256(seed >> 80));
        d.neck         = _selectTraitByProbability(t, 10, uint256(seed >> 88));
        d.accessory    = _selectTraitByProbability(t, 11, uint256(seed >> 96));
    }

    function _generateCharacterDataWithRules(uint256 seed, CharacterType charType) internal view returns (CharacterData memory d) {
        uint8 t = uint8(charType);
        uint8[12] memory selected;

        selected[0] = _selectTraitWithConflictResolution(t, 0, uint256(seed >> 8), selected);
        selected[1] = _selectTraitWithConflictResolution(t, 1, uint256(seed >> 16), selected);
        selected[2] = _selectTraitWithConflictResolution(t, 2, uint256(seed >> 24), selected);
        selected[3] = _selectTraitWithConflictResolution(t, 3, uint256(seed >> 32), selected);
        selected[4] = _selectTraitWithConflictResolution(t, 4, uint256(seed >> 40), selected);
        selected[5] = _selectTraitWithConflictResolution(t, 5, uint256(seed >> 48), selected);
        selected[6] = _selectTraitWithConflictResolution(t, 6, uint256(seed >> 56), selected);
        selected[7] = _selectTraitWithConflictResolution(t, 7, uint256(seed >> 64), selected);
        selected[8] = _selectTraitWithConflictResolution(t, 8, uint256(seed >> 72), selected);
        selected[9] = _selectTraitWithConflictResolution(t, 9, uint256(seed >> 80), selected);
        selected[10] = _selectTraitWithConflictResolution(t, 10, uint256(seed >> 88), selected);
        selected[11] = _selectTraitWithConflictResolution(t, 11, uint256(seed >> 96), selected);

        d.backdrop = selected[0];
        d.head = selected[1];
        d.expression = selected[2];
        d.eyes = selected[3];
        d.nose = selected[4];
        d.eartip = selected[5];
        d.earAccessory = selected[6];
        d.facialHair = selected[7];
        d.mouth = selected[8];
        d.chin = selected[9];
        d.neck = selected[10];
        d.accessory = selected[11];
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

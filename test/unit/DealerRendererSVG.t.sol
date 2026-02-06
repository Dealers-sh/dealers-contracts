// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/nft/DealerRendererSVG.sol";
import "../../src/nft/IDealerRendererSVG.sol";
import {File, BytecodeSlice} from "../../src/nft/File.sol";
import {SSTORE2} from "solady/src/utils/SSTORE2.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

contract DealerRendererSVGTest is Test {
    DealerRendererSVG public renderer;
    address public owner;
    address public nonOwner;

    event IncompatibilityRuleAdded(uint8 categoryA, uint8 traitIndexA, uint8 categoryB, uint8 traitIndexB);
    event IncompatibilityRuleRemoved(uint8 categoryA, uint8 traitIndexA, uint8 categoryB, uint8 traitIndexB);
    event AllIncompatibilityRulesCleared(uint256 count);

    function setUp() public {
        owner = address(this);
        nonOwner = makeAddr("nonOwner");
        renderer = new DealerRendererSVG();

        _addBasicTraits();
    }

    function _createFileStorePointer(bytes memory data) internal returns (address) {
        address contentPointer = SSTORE2.write(data);
        uint32 dataLength = uint32(data.length);

        BytecodeSlice[] memory slices = new BytecodeSlice[](1);
        slices[0] = BytecodeSlice({
            pointer: contentPointer,
            start: 1,
            end: dataLength + 1
        });

        File memory file = File({
            size: dataLength,
            slices: slices
        });

        return SSTORE2.write(abi.encode(file));
    }

    function _addBasicTraits() internal {
        bytes memory dummySvg = bytes("<rect/>");
        for (uint8 cat; cat < 12; cat++) {
            for (uint8 i; i < 5; i++) {
                address ptr = _createFileStorePointer(dummySvg);
                renderer.addTrait(0, cat, string(abi.encodePacked("Trait", uint8(i + 48))), 100, ptr);
            }
        }
    }

    function _addPoolSvgs(uint256 count) internal {
        bytes memory dummySvg = bytes("<svg><text>Pool SVG</text></svg>");
        for (uint256 i; i < count; i++) {
            address ptr = _createFileStorePointer(dummySvg);
            renderer.addOneOfOneToPool(string(abi.encodePacked("Pool", i)), ptr);
        }
    }

    function _setupForDistribution() internal {
        _addPoolSvgs(35);
    }

    // =============================================================
    //                      RULE ADDITION TESTS
    // =============================================================

    function test_addIncompatibilityRule_success() public {
        vm.expectEmit(true, true, true, true);
        emit IncompatibilityRuleAdded(0, 1, 1, 2);

        renderer.addIncompatibilityRule(0, 1, 1, 2);

        assertEq(renderer.getIncompatibilityRuleCount(), 1);
    }

    function test_addIncompatibilityRule_revertsWhenLocked() public {
        _setupForDistribution();
        renderer.initializeDistribution(12345);

        vm.expectRevert(IDealerRendererSVG.RulesLocked.selector);
        renderer.addIncompatibilityRule(0, 1, 1, 2);
    }

    function test_addIncompatibilityRule_revertsInvalidCategoryA() public {
        vm.expectRevert(DealerRendererSVG.InvalidCategory.selector);
        renderer.addIncompatibilityRule(12, 1, 1, 2);
    }

    function test_addIncompatibilityRule_revertsInvalidCategoryB() public {
        vm.expectRevert(DealerRendererSVG.InvalidCategory.selector);
        renderer.addIncompatibilityRule(0, 1, 12, 2);
    }

    function test_addIncompatibilityRule_revertsInvalidTraitIndexA() public {
        vm.expectRevert(IDealerRendererSVG.InvalidRule.selector);
        renderer.addIncompatibilityRule(0, 0, 1, 2);
    }

    function test_addIncompatibilityRule_revertsInvalidTraitIndexB() public {
        vm.expectRevert(IDealerRendererSVG.InvalidRule.selector);
        renderer.addIncompatibilityRule(0, 1, 1, 0);
    }

    function test_addIncompatibilityRule_revertsDuplicate() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);

        vm.expectRevert(IDealerRendererSVG.DuplicateRule.selector);
        renderer.addIncompatibilityRule(0, 1, 1, 2);
    }

    function test_addIncompatibilityRule_revertsDuplicateReversed() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);

        vm.expectRevert(IDealerRendererSVG.DuplicateRule.selector);
        renderer.addIncompatibilityRule(1, 2, 0, 1);
    }

    function test_addIncompatibilityRule_revertsMaxExceeded() public {
        for (uint16 i; i < 256; i++) {
            uint8 catA = uint8(i % 12);
            uint8 catB = uint8((i + 1) % 12);
            uint8 idxA = uint8((i / 12) % 5) + 1;
            uint8 idxB = uint8((i / 60) % 5) + 1;
            if (catA == catB && idxA == idxB) {
                idxB = idxA == 5 ? 1 : idxA + 1;
            }
            renderer.addIncompatibilityRule(catA, idxA, catB, idxB);
        }

        vm.expectRevert(IDealerRendererSVG.MaxRulesExceeded.selector);
        renderer.addIncompatibilityRule(0, 1, 11, 5);
    }

    function test_addIncompatibilityRule_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        renderer.addIncompatibilityRule(0, 1, 1, 2);
    }

    // =============================================================
    //                    BATCH ADDITION TESTS
    // =============================================================

    function test_batchAddIncompatibilityRules_success() public {
        uint8[] memory catsA = new uint8[](2);
        uint8[] memory idxsA = new uint8[](2);
        uint8[] memory catsB = new uint8[](2);
        uint8[] memory idxsB = new uint8[](2);

        catsA[0] = 0; idxsA[0] = 1; catsB[0] = 1; idxsB[0] = 2;
        catsA[1] = 2; idxsA[1] = 3; catsB[1] = 3; idxsB[1] = 4;

        renderer.batchAddIncompatibilityRules(catsA, idxsA, catsB, idxsB);

        assertEq(renderer.getIncompatibilityRuleCount(), 2);
    }

    function test_batchAddIncompatibilityRules_revertsArrayMismatch() public {
        uint8[] memory catsA = new uint8[](2);
        uint8[] memory idxsA = new uint8[](1);
        uint8[] memory catsB = new uint8[](2);
        uint8[] memory idxsB = new uint8[](2);

        vm.expectRevert(DealerRendererSVG.ArrayLengthMismatch.selector);
        renderer.batchAddIncompatibilityRules(catsA, idxsA, catsB, idxsB);
    }

    function test_batchAddIncompatibilityRules_revertsMaxExceeded() public {
        for (uint16 i; i < 255; i++) {
            uint8 catA = uint8(i % 12);
            uint8 catB = uint8((i + 1) % 12);
            uint8 idxA = uint8((i / 12) % 5) + 1;
            uint8 idxB = uint8((i / 60) % 5) + 1;
            if (catA == catB && idxA == idxB) {
                idxB = idxA == 5 ? 1 : idxA + 1;
            }
            renderer.addIncompatibilityRule(catA, idxA, catB, idxB);
        }

        uint8[] memory catsA = new uint8[](2);
        uint8[] memory idxsA = new uint8[](2);
        uint8[] memory catsB = new uint8[](2);
        uint8[] memory idxsB = new uint8[](2);

        catsA[0] = 0; idxsA[0] = 1; catsB[0] = 11; idxsB[0] = 5;
        catsA[1] = 1; idxsA[1] = 1; catsB[1] = 11; idxsB[1] = 5;

        vm.expectRevert(IDealerRendererSVG.MaxRulesExceeded.selector);
        renderer.batchAddIncompatibilityRules(catsA, idxsA, catsB, idxsB);
    }

    function test_batchAddIncompatibilityRules_revertsWhenLocked() public {
        _setupForDistribution();
        renderer.initializeDistribution(12345);

        uint8[] memory catsA = new uint8[](1);
        uint8[] memory idxsA = new uint8[](1);
        uint8[] memory catsB = new uint8[](1);
        uint8[] memory idxsB = new uint8[](1);

        catsA[0] = 0; idxsA[0] = 1; catsB[0] = 1; idxsB[0] = 2;

        vm.expectRevert(IDealerRendererSVG.RulesLocked.selector);
        renderer.batchAddIncompatibilityRules(catsA, idxsA, catsB, idxsB);
    }

    // =============================================================
    //                      RULE REMOVAL TESTS
    // =============================================================

    function test_removeIncompatibilityRule_success() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);
        assertEq(renderer.getIncompatibilityRuleCount(), 1);

        vm.expectEmit(true, true, true, true);
        emit IncompatibilityRuleRemoved(0, 1, 1, 2);

        renderer.removeIncompatibilityRule(0, 1, 1, 2);

        assertEq(renderer.getIncompatibilityRuleCount(), 0);
    }

    function test_removeIncompatibilityRule_revertsNotFound() public {
        vm.expectRevert(IDealerRendererSVG.RuleNotFound.selector);
        renderer.removeIncompatibilityRule(0, 1, 1, 2);
    }

    function test_removeIncompatibilityRule_revertsWhenLocked() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);
        _setupForDistribution();
        renderer.initializeDistribution(12345);

        vm.expectRevert(IDealerRendererSVG.RulesLocked.selector);
        renderer.removeIncompatibilityRule(0, 1, 1, 2);
    }

    function test_removeIncompatibilityRule_worksReversed() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);
        renderer.removeIncompatibilityRule(1, 2, 0, 1);

        assertEq(renderer.getIncompatibilityRuleCount(), 0);
    }

    // =============================================================
    //                      CLEAR RULES TESTS
    // =============================================================

    function test_clearAllIncompatibilityRules_success() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);
        renderer.addIncompatibilityRule(2, 3, 3, 4);

        vm.expectEmit(true, true, true, true);
        emit AllIncompatibilityRulesCleared(2);

        renderer.clearAllIncompatibilityRules();

        assertEq(renderer.getIncompatibilityRuleCount(), 0);
    }

    function test_clearAllIncompatibilityRules_revertsWhenLocked() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);
        _setupForDistribution();
        renderer.initializeDistribution(12345);

        vm.expectRevert(IDealerRendererSVG.RulesLocked.selector);
        renderer.clearAllIncompatibilityRules();
    }

    // =============================================================
    //                      VIEW FUNCTIONS TESTS
    // =============================================================

    function test_getIncompatibilityRuleCount() public {
        assertEq(renderer.getIncompatibilityRuleCount(), 0);

        renderer.addIncompatibilityRule(0, 1, 1, 2);
        assertEq(renderer.getIncompatibilityRuleCount(), 1);

        renderer.addIncompatibilityRule(2, 3, 3, 4);
        assertEq(renderer.getIncompatibilityRuleCount(), 2);
    }

    function test_getIncompatibilityRule() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);

        (uint8 catA, uint8 idxA, uint8 catB, uint8 idxB) = renderer.getIncompatibilityRule(0);

        assertEq(catA, 0);
        assertEq(idxA, 1);
        assertEq(catB, 1);
        assertEq(idxB, 2);
    }

    function test_getIncompatibilityRule_revertsInvalidIndex() public {
        vm.expectRevert(DealerRendererSVG.InvalidTraitIndex.selector);
        renderer.getIncompatibilityRule(0);
    }

    function test_areTraitsIncompatible_true() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);

        assertTrue(renderer.areTraitsIncompatible(0, 1, 1, 2));
        assertTrue(renderer.areTraitsIncompatible(1, 2, 0, 1));
    }

    function test_areTraitsIncompatible_false() public {
        assertFalse(renderer.areTraitsIncompatible(0, 1, 1, 2));

        renderer.addIncompatibilityRule(0, 1, 1, 2);
        assertFalse(renderer.areTraitsIncompatible(0, 1, 2, 3));
    }

    function test_getIncompatibleTraits() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);
        renderer.addIncompatibilityRule(0, 1, 2, 3);

        (uint8[] memory cats, uint8[] memory idxs) = renderer.getIncompatibleTraits(0, 1);

        assertEq(cats.length, 2);
        assertEq(idxs.length, 2);

        bool found1_2 = false;
        bool found2_3 = false;
        for (uint256 i; i < cats.length; i++) {
            if (cats[i] == 1 && idxs[i] == 2) found1_2 = true;
            if (cats[i] == 2 && idxs[i] == 3) found2_3 = true;
        }
        assertTrue(found1_2);
        assertTrue(found2_3);
    }

    function test_getIncompatibleTraits_empty() public {
        (uint8[] memory cats, uint8[] memory idxs) = renderer.getIncompatibleTraits(0, 1);

        assertEq(cats.length, 0);
        assertEq(idxs.length, 0);
    }

    // =============================================================
    //                  CONFLICT RESOLUTION TESTS
    // =============================================================

    function test_conflictResolution_avoidsConflicts() public {
        renderer.addIncompatibilityRule(0, 1, 1, 1);

        uint256 seed = 12345;
        string memory svg = renderer.getSVG(1, seed);

        assertTrue(bytes(svg).length > 0);
    }

    function test_conflictResolution_determinism() public {
        renderer.addIncompatibilityRule(0, 1, 1, 1);
        renderer.addIncompatibilityRule(2, 2, 3, 2);

        uint256 seed = 67890;

        string memory svg1 = renderer.getSVG(1, seed);
        string memory svg2 = renderer.getSVG(1, seed);

        assertEq(keccak256(bytes(svg1)), keccak256(bytes(svg2)));
    }

    function test_noRules_usesSimplePath() public {
        uint256 seed = 12345;
        string memory svg = renderer.getSVG(1, seed);

        assertTrue(bytes(svg).length > 0);
    }

    function test_conflictResolution_multipleRulesPerTrait() public {
        renderer.addIncompatibilityRule(0, 1, 1, 1);
        renderer.addIncompatibilityRule(0, 1, 2, 1);
        renderer.addIncompatibilityRule(0, 1, 3, 1);

        uint256 seed = 11111;
        string memory svg = renderer.getSVG(1, seed);

        assertTrue(bytes(svg).length > 0);
    }

    // =============================================================
    //                      EDGE CASES TESTS
    // =============================================================

    function test_bidirectionalDetection() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);

        assertTrue(renderer.areTraitsIncompatible(0, 1, 1, 2));
        assertTrue(renderer.areTraitsIncompatible(1, 2, 0, 1));
    }

    function test_sameCategoryDifferentTraits() public {
        renderer.addIncompatibilityRule(0, 1, 0, 2);

        assertTrue(renderer.areTraitsIncompatible(0, 1, 0, 2));
        assertEq(renderer.getIncompatibilityRuleCount(), 1);
    }

    function test_ruleRemovalMaintainsOtherRules() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);
        renderer.addIncompatibilityRule(2, 3, 3, 4);
        renderer.addIncompatibilityRule(4, 5, 5, 1);

        renderer.removeIncompatibilityRule(2, 3, 3, 4);

        assertEq(renderer.getIncompatibilityRuleCount(), 2);
        assertTrue(renderer.areTraitsIncompatible(0, 1, 1, 2));
        assertTrue(renderer.areTraitsIncompatible(4, 5, 5, 1));
        assertFalse(renderer.areTraitsIncompatible(2, 3, 3, 4));
    }

    function test_clearAndReaddRules() public {
        renderer.addIncompatibilityRule(0, 1, 1, 2);
        renderer.clearAllIncompatibilityRules();

        renderer.addIncompatibilityRule(0, 1, 1, 2);
        assertEq(renderer.getIncompatibilityRuleCount(), 1);
    }

    function test_specialCharacter_fallsBackToNormalTraits() public {
        _setupForDistribution();
        renderer.initializeDistribution(42);

        uint256[] memory specialTokens = renderer.getTokenIdsByType(
            IDealerRendererSVG.CharacterType.SPECIAL,
            0,
            1
        );
        require(specialTokens.length > 0, "No SPECIAL tokens found");

        uint256 specialTokenId = specialTokens[0];
        uint256 seed = 12345;

        string memory svg = renderer.getSVG(specialTokenId, seed);
        assertTrue(bytes(svg).length > 50, "SVG should contain traits from NORMAL fallback");

        string memory metadata = renderer.getTraitsMetadataForToken(specialTokenId, seed);
        assertTrue(bytes(metadata).length > 50, "Metadata should contain traits from NORMAL fallback");

        bytes memory metaBytes = bytes(metadata);
        bool hasSpecialType = false;
        for (uint256 i = 0; i < metaBytes.length - 7; i++) {
            if (metaBytes[i] == "S" && metaBytes[i+1] == "p" && metaBytes[i+2] == "e" &&
                metaBytes[i+3] == "c" && metaBytes[i+4] == "i" && metaBytes[i+5] == "a" && metaBytes[i+6] == "l") {
                hasSpecialType = true;
                break;
            }
        }
        assertTrue(hasSpecialType, "Metadata should show Character Type as Special");
    }

    // =============================================================
    //                      FUZZ TESTS
    // =============================================================

    function testFuzz_addIncompatibilityRule(uint8 catA, uint8 idxA, uint8 catB, uint8 idxB) public {
        catA = uint8(bound(catA, 0, 11));
        catB = uint8(bound(catB, 0, 11));
        idxA = uint8(bound(idxA, 1, 255));
        idxB = uint8(bound(idxB, 1, 255));

        renderer.addIncompatibilityRule(catA, idxA, catB, idxB);

        assertTrue(renderer.areTraitsIncompatible(catA, idxA, catB, idxB));
    }

    function testFuzz_conflictResolution_neverReverts(uint256 seed) public {
        renderer.addIncompatibilityRule(0, 1, 1, 1);
        renderer.addIncompatibilityRule(1, 2, 2, 2);

        string memory svg = renderer.getSVG(1, seed);
        assertTrue(bytes(svg).length > 0);
    }

    // =============================================================
    //                    FILESTORE INTEGRATION TESTS
    // =============================================================

    function test_addTrait_withFileStorePointer() public {
        bytes memory svgData = bytes("<circle r='10'/>");
        address ptr = _createFileStorePointer(svgData);

        renderer.addTrait(0, 0, "TestCircle", 100, ptr);
    }

    function test_addTrait_revertsInvalidPointer() public {
        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.addTrait(0, 0, "Test", 100, address(0));
    }

    function test_batchAddTraits_withFileStorePointers() public {
        uint8[] memory characterTypes = new uint8[](2);
        uint8[] memory categories = new uint8[](2);
        string[] memory names = new string[](2);
        uint16[] memory probabilities = new uint16[](2);
        address[] memory pointers = new address[](2);

        characterTypes[0] = 1; categories[0] = 0; names[0] = "Special1"; probabilities[0] = 50;
        characterTypes[1] = 1; categories[1] = 0; names[1] = "Special2"; probabilities[1] = 50;

        pointers[0] = _createFileStorePointer(bytes("<rect/>"));
        pointers[1] = _createFileStorePointer(bytes("<ellipse/>"));

        renderer.batchAddTraits(characterTypes, categories, names, probabilities, pointers);
    }

    function test_batchAddTraits_revertsInvalidPointer() public {
        uint8[] memory characterTypes = new uint8[](2);
        uint8[] memory categories = new uint8[](2);
        string[] memory names = new string[](2);
        uint16[] memory probabilities = new uint16[](2);
        address[] memory pointers = new address[](2);

        characterTypes[0] = 0; categories[0] = 0; names[0] = "Test1"; probabilities[0] = 50;
        characterTypes[1] = 0; categories[1] = 0; names[1] = "Test2"; probabilities[1] = 50;

        pointers[0] = _createFileStorePointer(bytes("<rect/>"));
        pointers[1] = address(0);

        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.batchAddTraits(characterTypes, categories, names, probabilities, pointers);
    }

    function test_setOneOfOne_withFileStorePointer() public {
        bytes memory svgData = bytes("<svg><text>One of One</text></svg>");
        address ptr = _createFileStorePointer(svgData);

        renderer.setOneOfOne(1, "Legendary", ptr);

        (string memory characterName, address svgContract, bool exists) = renderer.getOneOfOneInfo(1);
        assertEq(characterName, "Legendary");
        assertEq(svgContract, ptr);
        assertTrue(exists);
    }

    function test_setOneOfOne_revertsInvalidPointer() public {
        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.setOneOfOne(1, "Test", address(0));
    }

    function test_batchSetOneOfOnes_withFileStorePointers() public {
        uint256[] memory tokenIds = new uint256[](2);
        string[] memory names = new string[](2);
        address[] memory pointers = new address[](2);

        tokenIds[0] = 1; names[0] = "Legend1";
        tokenIds[1] = 2; names[1] = "Legend2";

        pointers[0] = _createFileStorePointer(bytes("<svg>1</svg>"));
        pointers[1] = _createFileStorePointer(bytes("<svg>2</svg>"));

        renderer.batchSetOneOfOnes(tokenIds, names, pointers);

        (string memory name1,, bool exists1) = renderer.getOneOfOneInfo(1);
        (string memory name2,, bool exists2) = renderer.getOneOfOneInfo(2);
        assertEq(name1, "Legend1");
        assertEq(name2, "Legend2");
        assertTrue(exists1);
        assertTrue(exists2);
    }

    function test_batchSetOneOfOnes_revertsInvalidPointer() public {
        uint256[] memory tokenIds = new uint256[](2);
        string[] memory names = new string[](2);
        address[] memory pointers = new address[](2);

        tokenIds[0] = 1; names[0] = "Test1";
        tokenIds[1] = 2; names[1] = "Test2";

        pointers[0] = _createFileStorePointer(bytes("<svg/>"));
        pointers[1] = address(0);

        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.batchSetOneOfOnes(tokenIds, names, pointers);
    }

    function test_getSVG_readsFromFileStorePointer() public {
        bytes memory svgContent = bytes("<rect x='0' y='0' width='100' height='100'/>");
        address ptr = _createFileStorePointer(svgContent);

        renderer.addTrait(0, 0, "TestRect", 10000, ptr);

        uint256 seed = 999999;
        string memory svg = renderer.getSVG(1, seed);

        assertTrue(bytes(svg).length > 0);
        assertGt(bytes(svg).length, 50);
    }

    function test_getSVG_oneOfOne_readsFromFileStorePointer() public {
        bytes memory fullSvg = bytes('<svg xmlns="http://www.w3.org/2000/svg"><text>Legend</text></svg>');
        address ptr = _createFileStorePointer(fullSvg);

        renderer.setOneOfOne(404, "TheLegend", ptr);

        _setupForDistribution();
        renderer.initializeDistribution(42);

        string memory svg = renderer.getSVG(404, 0);
        assertEq(svg, string(fullSvg));
    }

    // =============================================================
    //                    PLACEHOLDER SVG TESTS
    // =============================================================

    function test_setPlaceholderSvg_success() public {
        bytes memory placeholderData = bytes('<svg><text>Unrevealed</text></svg>');
        address ptr = _createFileStorePointer(placeholderData);

        renderer.setPlaceholderSvg(ptr);

        assertEq(renderer.placeholderSvgPointer(), ptr);
    }

    function test_setPlaceholderSvg_revertsInvalidPointer() public {
        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.setPlaceholderSvg(address(0));
    }

    function test_getSVG_returnsPlaceholderBeforeReveal() public {
        bytes memory placeholderData = bytes('<svg><text>Unrevealed</text></svg>');
        address ptr = _createFileStorePointer(placeholderData);

        renderer.setPlaceholderSvg(ptr);

        string memory svg = renderer.getSVG(1, 12345);
        assertEq(svg, string(placeholderData));
    }

    function test_getSVG_returnsRealSvgAfterReveal() public {
        bytes memory placeholderData = bytes('<svg><text>Unrevealed</text></svg>');
        address ptr = _createFileStorePointer(placeholderData);

        renderer.setPlaceholderSvg(ptr);
        _setupForDistribution();
        renderer.initializeDistribution(42);

        string memory svg = renderer.getSVG(1, 12345);
        assertFalse(keccak256(bytes(svg)) == keccak256(placeholderData));
    }

    function test_getTraitsMetadata_returnsUnrevealedBeforeDistribution() public {
        string memory metadata = renderer.getTraitsMetadataForToken(1, 12345);
        assertEq(metadata, '{"trait_type":"Status","value":"Unrevealed"}');
    }

    // =============================================================
    //                    POOL SVG TESTS
    // =============================================================

    function test_addOneOfOneToPool_success() public {
        bytes memory svgData = bytes('<svg><text>Pool 1</text></svg>');
        address ptr = _createFileStorePointer(svgData);

        renderer.addOneOfOneToPool("PoolChar1", ptr);

        assertEq(renderer.getOneOfOneSVGPoolSize(), 1);
    }

    function test_addOneOfOneToPool_revertsAfterDistribution() public {
        _setupForDistribution();
        renderer.initializeDistribution(42);

        bytes memory svgData = bytes('<svg><text>Pool</text></svg>');
        address ptr = _createFileStorePointer(svgData);

        vm.expectRevert(Ownable.AlreadyInitialized.selector);
        renderer.addOneOfOneToPool("Late", ptr);
    }

    function test_batchAddOneOfOnesToPool_success() public {
        string[] memory names = new string[](3);
        address[] memory pointers = new address[](3);

        names[0] = "Pool1";
        names[1] = "Pool2";
        names[2] = "Pool3";

        pointers[0] = _createFileStorePointer(bytes("<svg>1</svg>"));
        pointers[1] = _createFileStorePointer(bytes("<svg>2</svg>"));
        pointers[2] = _createFileStorePointer(bytes("<svg>3</svg>"));

        renderer.batchAddOneOfOnesToPool(names, pointers);

        assertEq(renderer.getOneOfOneSVGPoolSize(), 3);
    }

    function test_initializeDistribution_revertsInsufficientPool() public {
        vm.expectRevert(IDealerRendererSVG.InsufficientPoolSize.selector);
        renderer.initializeDistribution(42);
    }

    function test_initializeDistribution_reservedTokensGetTheirSvg() public {
        bytes memory reservedSvg = bytes('<svg><text>Reserved 404</text></svg>');
        address reservedPtr = _createFileStorePointer(reservedSvg);

        renderer.setOneOfOne(404, "404", reservedPtr);
        _setupForDistribution();
        renderer.initializeDistribution(42);

        assertEq(renderer.getCharacterType(404), 2);

        string memory svg = renderer.getSVG(404, 0);
        assertEq(svg, string(reservedSvg));
    }

    function test_initializeDistribution_randomOneOfOnesGetPoolSvgs() public {
        _setupForDistribution();
        renderer.initializeDistribution(42);

        uint256 foundPoolAssignment = 0;
        for (uint256 i = 1; i <= 8888 && foundPoolAssignment == 0; i++) {
            if (renderer.getCharacterType(i) == 2) {
                uint256 poolIdx = renderer.tokenPoolIndex(i);
                if (poolIdx > 0) {
                    foundPoolAssignment = i;
                }
            }
        }

        assertTrue(foundPoolAssignment > 0, "Should find at least one pool-assigned one-of-one");
    }

    function test_getSVG_poolAssignedOneOfOne() public {
        bytes memory poolSvg = bytes('<svg><text>Pool SVG Content</text></svg>');
        address poolPtr = _createFileStorePointer(poolSvg);

        string[] memory names = new string[](35);
        address[] memory pointers = new address[](35);
        for (uint256 i; i < 35; i++) {
            names[i] = string(abi.encodePacked("PoolChar", i));
            pointers[i] = poolPtr;
        }
        renderer.batchAddOneOfOnesToPool(names, pointers);

        renderer.initializeDistribution(42);

        uint256 poolAssignedToken;
        for (uint256 i = 1; i <= 8888; i++) {
            if (renderer.getCharacterType(i) == 2 && renderer.tokenPoolIndex(i) > 0) {
                poolAssignedToken = i;
                break;
            }
        }

        string memory svg = renderer.getSVG(poolAssignedToken, 0);
        assertEq(svg, string(poolSvg));
    }

    function test_reservedOneOfOnes_forcedAsOneOfOne() public {
        renderer.setOneOfOne(1, "First", _createFileStorePointer(bytes("<svg>1</svg>")));
        renderer.setOneOfOne(8888, "Last", _createFileStorePointer(bytes("<svg>8888</svg>")));
        renderer.setOneOfOne(4444, "Middle", _createFileStorePointer(bytes("<svg>4444</svg>")));

        _setupForDistribution();
        renderer.initializeDistribution(999);

        assertEq(renderer.getCharacterType(1), 2);
        assertEq(renderer.getCharacterType(8888), 2);
        assertEq(renderer.getCharacterType(4444), 2);
    }
}

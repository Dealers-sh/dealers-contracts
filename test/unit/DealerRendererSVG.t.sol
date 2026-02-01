// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/nft/DealerRendererSVG.sol";
import "../../src/nft/IDealerRendererSVG.sol";

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

    function _addBasicTraits() internal {
        bytes memory dummySvg = bytes("<rect/>");
        for (uint8 cat; cat < 11; cat++) {
            for (uint8 i; i < 5; i++) {
                renderer.addTrait(0, cat, string(abi.encodePacked("Trait", uint8(i + 48))), 100, dummySvg);
            }
        }
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
        renderer.initializeDistribution(12345);

        vm.expectRevert(IDealerRendererSVG.RulesLocked.selector);
        renderer.addIncompatibilityRule(0, 1, 1, 2);
    }

    function test_addIncompatibilityRule_revertsInvalidCategoryA() public {
        vm.expectRevert(DealerRendererSVG.InvalidCategory.selector);
        renderer.addIncompatibilityRule(11, 1, 1, 2);
    }

    function test_addIncompatibilityRule_revertsInvalidCategoryB() public {
        vm.expectRevert(DealerRendererSVG.InvalidCategory.selector);
        renderer.addIncompatibilityRule(0, 1, 11, 2);
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
            uint8 catA = uint8(i % 11);
            uint8 catB = uint8((i + 1) % 11);
            uint8 idxA = uint8((i / 11) % 5) + 1;
            uint8 idxB = uint8((i / 55) % 5) + 1;
            if (catA == catB && idxA == idxB) {
                idxB = idxA == 5 ? 1 : idxA + 1;
            }
            renderer.addIncompatibilityRule(catA, idxA, catB, idxB);
        }

        vm.expectRevert(IDealerRendererSVG.MaxRulesExceeded.selector);
        renderer.addIncompatibilityRule(0, 1, 10, 5);
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
            uint8 catA = uint8(i % 11);
            uint8 catB = uint8((i + 1) % 11);
            uint8 idxA = uint8((i / 11) % 5) + 1;
            uint8 idxB = uint8((i / 55) % 5) + 1;
            if (catA == catB && idxA == idxB) {
                idxB = idxA == 5 ? 1 : idxA + 1;
            }
            renderer.addIncompatibilityRule(catA, idxA, catB, idxB);
        }

        uint8[] memory catsA = new uint8[](2);
        uint8[] memory idxsA = new uint8[](2);
        uint8[] memory catsB = new uint8[](2);
        uint8[] memory idxsB = new uint8[](2);

        catsA[0] = 0; idxsA[0] = 1; catsB[0] = 10; idxsB[0] = 5;
        catsA[1] = 1; idxsA[1] = 1; catsB[1] = 10; idxsB[1] = 5;

        vm.expectRevert(IDealerRendererSVG.MaxRulesExceeded.selector);
        renderer.batchAddIncompatibilityRules(catsA, idxsA, catsB, idxsB);
    }

    function test_batchAddIncompatibilityRules_revertsWhenLocked() public {
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

    // =============================================================
    //                      FUZZ TESTS
    // =============================================================

    function testFuzz_addIncompatibilityRule(uint8 catA, uint8 idxA, uint8 catB, uint8 idxB) public {
        catA = uint8(bound(catA, 0, 10));
        catB = uint8(bound(catB, 0, 10));
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
}

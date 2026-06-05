// SPDX-License-Identifier: UNLICENSED
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

    event TraitsStored(uint256 indexed tokenId);
    event TraitUpdated(uint256 indexed tokenId, uint8 indexed category, uint8 traitIndex);
    event TraitPointerUpdated(
        uint8 indexed characterType, uint8 indexed category, uint256 indexed traitIndex, address newPointer
    );

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
        slices[0] = BytecodeSlice({pointer: contentPointer, start: 1, end: dataLength + 1});

        File memory file = File({size: dataLength, slices: slices});

        return SSTORE2.write(abi.encode(file));
    }

    function _addBasicTraits() internal {
        bytes memory dummySvg = bytes("<rect/>");
        for (uint8 cat; cat < 12; cat++) {
            for (uint8 i; i < 5; i++) {
                address ptr = _createFileStorePointer(dummySvg);
                renderer.addTrait(0, cat, string(abi.encodePacked("Trait", uint8(i + 48))), ptr);
            }
        }
    }

    function _packTraits(uint8[12] memory t) internal pure returns (bytes32) {
        return _packTraitsWithType(t, 0);
    }

    function _packTraitsWithType(uint8[12] memory t, uint8 charType) internal pure returns (bytes32) {
        return bytes32(
            uint256(t[0]) | (uint256(t[1]) << 8) | (uint256(t[2]) << 16) | (uint256(t[3]) << 24) | (uint256(t[4]) << 32)
                | (uint256(t[5]) << 40) | (uint256(t[6]) << 48) | (uint256(t[7]) << 56) | (uint256(t[8]) << 64)
                | (uint256(t[9]) << 72) | (uint256(t[10]) << 80) | (uint256(t[11]) << 88) | (uint256(charType) << 96)
        );
    }

    function _svgPrefix(uint256 tokenId) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 58 58" fill="none" id="',
                vm.toString(tokenId),
                '" data-token-id="',
                vm.toString(tokenId),
                '">'
            )
        );
    }

    function _wrapSvg(uint256 tokenId, string memory inner) internal pure returns (string memory) {
        return string(abi.encodePacked(_svgPrefix(tokenId), inner, "</svg>"));
    }

    // =============================================================
    //                    BATCH SET TRAITS TESTS
    // =============================================================

    function test_batchSetTraits_storesAndReadsBack() public {
        uint256[] memory ids = new uint256[](2);
        bytes32[] memory packed = new bytes32[](2);

        ids[0] = 100;
        ids[1] = 200;

        uint8[12] memory t1 = [1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2];
        uint8[12] memory t2 = [5, 4, 3, 2, 1, 5, 4, 3, 2, 1, 5, 4];

        packed[0] = _packTraits(t1);
        packed[1] = _packTraits(t2);

        renderer.batchSetTraits(ids, packed);

        uint8[12] memory result1 = renderer.getStoredTraits(ids[0]);
        uint8[12] memory result2 = renderer.getStoredTraits(ids[1]);

        for (uint8 i; i < 12; i++) {
            assertEq(result1[i], t1[i]);
            assertEq(result2[i], t2[i]);
        }
    }

    function test_batchSetTraits_revertsArrayLengthMismatch() public {
        uint256[] memory ids = new uint256[](2);
        bytes32[] memory packed = new bytes32[](1);

        vm.expectRevert(DealerRendererSVG.ArrayLengthMismatch.selector);
        renderer.batchSetTraits(ids, packed);
    }

    function test_batchSetTraits_revertsInvalidTokenId() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 0;
        packed[0] = bytes32(uint256(1));

        vm.expectRevert(DealerRendererSVG.InvalidTokenId.selector);
        renderer.batchSetTraits(ids, packed);
    }

    function test_batchSetTraits_revertsInvalidTokenIdTooHigh() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 8889;
        packed[0] = bytes32(uint256(1));

        vm.expectRevert(DealerRendererSVG.InvalidTokenId.selector);
        renderer.batchSetTraits(ids, packed);
    }

    function test_batchSetTraits_revertsNonOwner() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 1;
        packed[0] = bytes32(uint256(1));

        vm.prank(nonOwner);
        vm.expectRevert();
        renderer.batchSetTraits(ids, packed);
    }

    function test_batchSetTraits_emitsEvents() public {
        uint256[] memory ids = new uint256[](2);
        bytes32[] memory packed = new bytes32[](2);
        ids[0] = 1;
        ids[1] = 2;
        packed[0] = bytes32(uint256(1));
        packed[1] = bytes32(uint256(2));

        vm.expectEmit(true, true, true, true);
        emit TraitsStored(1);
        vm.expectEmit(true, true, true, true);
        emit TraitsStored(2);

        renderer.batchSetTraits(ids, packed);
    }

    // =============================================================
    //                  SET TRAIT FOR TOKEN TESTS
    // =============================================================

    function test_setTraitForToken_modifiesSingleCategory() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 1;
        uint8[12] memory t = [uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2];
        packed[0] = _packTraits(t);
        renderer.batchSetTraits(ids, packed);

        renderer.setTraitForToken(1, 3, 99);

        uint8[12] memory result = renderer.getStoredTraits(1);
        assertEq(result[0], 1);
        assertEq(result[1], 2);
        assertEq(result[2], 3);
        assertEq(result[3], 99);
        assertEq(result[4], 5);
        assertEq(result[5], 1);
        assertEq(result[6], 2);
        assertEq(result[7], 3);
        assertEq(result[8], 4);
        assertEq(result[9], 5);
        assertEq(result[10], 1);
        assertEq(result[11], 2);
    }

    function test_setTraitForToken_revertsInvalidTokenId() public {
        vm.expectRevert(DealerRendererSVG.InvalidTokenId.selector);
        renderer.setTraitForToken(0, 0, 1);
    }

    function test_setTraitForToken_revertsInvalidCategory() public {
        vm.expectRevert(DealerRendererSVG.InvalidCategory.selector);
        renderer.setTraitForToken(1, 12, 1);
    }

    function test_setTraitForToken_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        renderer.setTraitForToken(1, 0, 1);
    }

    function test_setTraitForToken_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit TraitUpdated(1, 3, 99);

        renderer.setTraitForToken(1, 3, 99);
    }

    // =============================================================
    //                      isTraitStored TESTS
    // =============================================================

    function test_isTraitStored_falseByDefault() public view {
        assertFalse(renderer.isTraitStored(1));
    }

    function test_isTraitStored_trueAfterSet() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 1;
        packed[0] = _packTraits([uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2]);
        renderer.batchSetTraits(ids, packed);

        assertTrue(renderer.isTraitStored(1));
    }

    // =============================================================
    //                    CHARACTER TYPE TESTS
    // =============================================================

    function test_getCharacterType_normal() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 100;
        packed[0] = _packTraitsWithType([uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2], 0);
        renderer.batchSetTraits(ids, packed);

        assertEq(renderer.getCharacterType(100), 0);
    }

    function test_getCharacterType_special() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 100;
        packed[0] = _packTraitsWithType([uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2], 1);
        renderer.batchSetTraits(ids, packed);

        assertEq(renderer.getCharacterType(100), 1);
    }

    function test_getCharacterType_oneOfOne() public {
        address ptr = _createFileStorePointer(bytes("<text>1of1</text>"));
        renderer.setOneOfOne(100, "Legend", ptr);

        assertEq(renderer.getCharacterType(100), 2);
    }

    function test_getCharacterType_defaultBeforeTraits() public view {
        assertEq(renderer.getCharacterType(100), 0);
    }

    function test_getCharacterType_revertsInvalidTokenId() public {
        vm.expectRevert(DealerRendererSVG.InvalidTokenId.selector);
        renderer.getCharacterType(0);

        vm.expectRevert(DealerRendererSVG.InvalidTokenId.selector);
        renderer.getCharacterType(8889);
    }

    // =============================================================
    //                      getSVG TESTS
    // =============================================================

    function test_getSVG_returnsPlaceholderWhenTraitsNotStored() public {
        bytes memory placeholderInner = bytes("<text>Unrevealed</text>");
        address ptr = _createFileStorePointer(placeholderInner);
        renderer.setPlaceholderSvg(ptr);

        string memory svg = renderer.getSVG(1);
        assertEq(svg, _wrapSvg(1, "<text>Unrevealed</text>"));
    }

    function test_getSVG_revertsTraitsNotStoredNoPlaceholder() public {
        vm.expectRevert(IDealerRendererSVG.TraitsNotStored.selector);
        renderer.getSVG(1);
    }

    function test_getSVG_readsStoredTraits() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 100;
        packed[0] = _packTraits([uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2]);
        renderer.batchSetTraits(ids, packed);
        renderer.reveal();

        string memory svg = renderer.getSVG(100);
        assertTrue(bytes(svg).length > 50);
    }

    function test_getSVG_containsTokenIdAttribute() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 100;
        packed[0] = _packTraits([uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
        renderer.batchSetTraits(ids, packed);
        renderer.reveal();

        string memory svg = renderer.getSVG(100);
        string memory expectedPrefix = _svgPrefix(100);

        bytes memory svgBytes = bytes(svg);
        bytes memory prefixBytes = bytes(expectedPrefix);

        for (uint256 i; i < prefixBytes.length; i++) {
            assertEq(svgBytes[i], prefixBytes[i]);
        }
    }

    function test_getSVG_oneOfOne() public {
        bytes memory innerContent = bytes("<text>Legend</text>");
        address ptr = _createFileStorePointer(innerContent);
        renderer.setOneOfOne(404, "TheLegend", ptr);
        renderer.reveal();

        string memory svg = renderer.getSVG(404);
        assertEq(svg, _wrapSvg(404, "<text>Legend</text>"));
    }

    function test_getSVG_showsPlaceholderBeforeRevealEvenWithTraits() public {
        bytes memory placeholderInner = bytes("<text>Unrevealed</text>");
        address ptr = _createFileStorePointer(placeholderInner);
        renderer.setPlaceholderSvg(ptr);

        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 100;
        packed[0] = _packTraits([uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2]);
        renderer.batchSetTraits(ids, packed);

        string memory svg = renderer.getSVG(100);
        assertEq(svg, _wrapSvg(100, "<text>Unrevealed</text>"));
    }

    function test_getSVG_showsPlaceholderBeforeRevealEvenWithOneOfOne() public {
        bytes memory placeholderInner = bytes("<text>Unrevealed</text>");
        address placeholderPtr = _createFileStorePointer(placeholderInner);
        renderer.setPlaceholderSvg(placeholderPtr);

        address oooPtr = _createFileStorePointer(bytes("<text>Legend</text>"));
        renderer.setOneOfOne(404, "TheLegend", oooPtr);

        string memory svg = renderer.getSVG(404);
        assertEq(svg, _wrapSvg(404, "<text>Unrevealed</text>"));
    }

    function test_getSVG_specialUsesSpecialTraitPool() public {
        bytes memory specialSvg = bytes("<circle class='special'/>");
        for (uint8 cat; cat < 12; cat++) {
            address ptr = _createFileStorePointer(specialSvg);
            renderer.addTrait(1, cat, "SpecialTrait", ptr);
        }

        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 500;
        packed[0] = _packTraitsWithType([uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 1);
        renderer.batchSetTraits(ids, packed);
        renderer.reveal();

        string memory svg = renderer.getSVG(500);
        assertTrue(bytes(svg).length > 50);
    }

    // =============================================================
    //                  TRAITS METADATA TESTS
    // =============================================================

    function test_getTraitsMetadata_unrevealedWhenTraitsNotStored() public view {
        string memory metadata = renderer.getTraitsMetadataForToken(1);
        assertEq(metadata, '{"trait_type":"Status","value":"Unrevealed"}');
    }

    function test_getTraitsMetadata_returnsCorrectNames() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 100;
        packed[0] = _packTraits([uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
        renderer.batchSetTraits(ids, packed);
        renderer.reveal();

        string memory metadata = renderer.getTraitsMetadataForToken(100);
        assertTrue(bytes(metadata).length > 50);

        bytes memory metaBytes = bytes(metadata);
        bool hasNormalType = false;
        for (uint256 i = 0; i < metaBytes.length - 5; i++) {
            if (
                metaBytes[i] == "N" && metaBytes[i + 1] == "o" && metaBytes[i + 2] == "r" && metaBytes[i + 3] == "m"
                    && metaBytes[i + 4] == "a" && metaBytes[i + 5] == "l"
            ) {
                hasNormalType = true;
                break;
            }
        }
        assertTrue(hasNormalType);
    }

    function test_getTraitsMetadata_unrevealedEvenWithTraitsStored() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 100;
        packed[0] = _packTraits([uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
        renderer.batchSetTraits(ids, packed);

        string memory metadata = renderer.getTraitsMetadataForToken(100);
        assertEq(metadata, '{"trait_type":"Status","value":"Unrevealed"}');
    }

    function test_getTraitsMetadata_specialFallsBackToNormal() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 100;
        packed[0] = _packTraitsWithType([uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 1);
        renderer.batchSetTraits(ids, packed);
        renderer.reveal();

        string memory metadata = renderer.getTraitsMetadataForToken(100);
        assertTrue(bytes(metadata).length > 50);

        bytes memory metaBytes = bytes(metadata);
        bool hasSpecialType = false;
        for (uint256 i = 0; i < metaBytes.length - 6; i++) {
            if (
                metaBytes[i] == "S" && metaBytes[i + 1] == "p" && metaBytes[i + 2] == "e" && metaBytes[i + 3] == "c"
                    && metaBytes[i + 4] == "i" && metaBytes[i + 5] == "a" && metaBytes[i + 6] == "l"
            ) {
                hasSpecialType = true;
                break;
            }
        }
        assertTrue(hasSpecialType);
    }

    function test_getTraitsMetadata_oneOfOne() public {
        address ptr = _createFileStorePointer(bytes("<text>1of1</text>"));
        renderer.setOneOfOne(100, "TheBoss", ptr);
        renderer.reveal();

        string memory metadata = renderer.getTraitsMetadataForToken(100);

        bytes memory metaBytes = bytes(metadata);
        bool hasOneOfOne = false;
        for (uint256 i = 0; i < metaBytes.length - 9; i++) {
            if (
                metaBytes[i] == "O" && metaBytes[i + 1] == "n" && metaBytes[i + 2] == "e" && metaBytes[i + 3] == " "
                    && metaBytes[i + 4] == "o" && metaBytes[i + 5] == "f"
            ) {
                hasOneOfOne = true;
                break;
            }
        }
        assertTrue(hasOneOfOne);
    }

    // =============================================================
    //                    PACK / UNPACK ROUNDTRIP
    // =============================================================

    function test_packUnpack_roundtrip() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 1;

        uint8[12] memory t = [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
        packed[0] = _packTraits(t);
        renderer.batchSetTraits(ids, packed);

        uint8[12] memory result = renderer.getStoredTraits(1);
        for (uint8 i; i < 12; i++) {
            assertEq(result[i], t[i]);
        }
    }

    function test_packUnpack_maxValues() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 1;

        uint8[12] memory t = [uint8(255), 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255];
        packed[0] = _packTraits(t);
        renderer.batchSetTraits(ids, packed);

        uint8[12] memory result = renderer.getStoredTraits(1);
        for (uint8 i; i < 12; i++) {
            assertEq(result[i], 255);
        }
    }

    function test_packWithType_preservesCharType() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 1;

        uint8[12] memory t = [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
        packed[0] = _packTraitsWithType(t, 1);
        renderer.batchSetTraits(ids, packed);

        uint8[12] memory result = renderer.getStoredTraits(1);
        for (uint8 i; i < 12; i++) {
            assertEq(result[i], t[i]);
        }

        assertEq(renderer.getCharacterType(1), 1);
    }

    // =============================================================
    //                TRAIT UPLOAD TESTS
    // =============================================================

    function test_addTrait_withFileStorePointer() public {
        bytes memory svgData = bytes("<circle r='10'/>");
        address ptr = _createFileStorePointer(svgData);

        renderer.addTrait(0, 0, "TestCircle", ptr);
    }

    function test_addTrait_revertsInvalidPointer() public {
        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.addTrait(0, 0, "Test", address(0));
    }

    function test_batchAddTraits_withFileStorePointers() public {
        uint8[] memory characterTypes = new uint8[](2);
        uint8[] memory categories = new uint8[](2);
        string[] memory names = new string[](2);
        address[] memory pointers = new address[](2);

        characterTypes[0] = 1;
        categories[0] = 0;
        names[0] = "Special1";
        characterTypes[1] = 1;
        categories[1] = 0;
        names[1] = "Special2";

        pointers[0] = _createFileStorePointer(bytes("<rect/>"));
        pointers[1] = _createFileStorePointer(bytes("<ellipse/>"));

        renderer.batchAddTraits(characterTypes, categories, names, pointers);
    }

    function test_batchAddTraits_revertsInvalidPointer() public {
        uint8[] memory characterTypes = new uint8[](2);
        uint8[] memory categories = new uint8[](2);
        string[] memory names = new string[](2);
        address[] memory pointers = new address[](2);

        characterTypes[0] = 0;
        categories[0] = 0;
        names[0] = "Test1";
        characterTypes[1] = 0;
        categories[1] = 0;
        names[1] = "Test2";

        pointers[0] = _createFileStorePointer(bytes("<rect/>"));
        pointers[1] = address(0);

        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.batchAddTraits(characterTypes, categories, names, pointers);
    }

    // =============================================================
    //                  ONE-OF-ONE TESTS
    // =============================================================

    function test_setOneOfOne_withFileStorePointer() public {
        bytes memory svgData = bytes("<text>One of One</text>");
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

        tokenIds[0] = 1;
        names[0] = "Legend1";
        tokenIds[1] = 2;
        names[1] = "Legend2";

        pointers[0] = _createFileStorePointer(bytes("<text>1</text>"));
        pointers[1] = _createFileStorePointer(bytes("<text>2</text>"));

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

        tokenIds[0] = 1;
        names[0] = "Test1";
        tokenIds[1] = 2;
        names[1] = "Test2";

        pointers[0] = _createFileStorePointer(bytes("<text/>"));
        pointers[1] = address(0);

        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.batchSetOneOfOnes(tokenIds, names, pointers);
    }

    // =============================================================
    //                    PLACEHOLDER SVG TESTS
    // =============================================================

    function test_setPlaceholderSvg_success() public {
        bytes memory placeholderData = bytes("<text>Unrevealed</text>");
        address ptr = _createFileStorePointer(placeholderData);

        renderer.setPlaceholderSvg(ptr);

        assertEq(renderer.placeholderSvgPointer(), ptr);
    }

    function test_setPlaceholderSvg_revertsInvalidPointer() public {
        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.setPlaceholderSvg(address(0));
    }

    // =============================================================
    //                      REVEAL TESTS
    // =============================================================

    function test_reveal_setsFlag() public {
        assertFalse(renderer.revealed());
        renderer.reveal();
        assertTrue(renderer.revealed());
    }

    function test_reveal_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        renderer.reveal();
    }

    // =============================================================
    //                      OWNER ACCESS TESTS
    // =============================================================

    function test_addTrait_revertsNonOwner() public {
        address ptr = _createFileStorePointer(bytes("<rect/>"));

        vm.prank(nonOwner);
        vm.expectRevert();
        renderer.addTrait(0, 0, "Test", ptr);
    }

    // =============================================================
    //                  updateTraitPointer TESTS
    // =============================================================

    function test_updateTraitPointer_swapsRenderedBytes() public {
        address newPtr = _createFileStorePointer(bytes("<text>updated</text>"));
        renderer.updateTraitPointer(0, 0, 1, newPtr);

        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 1;
        packed[0] = _packTraits([uint8(1), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        renderer.batchSetTraits(ids, packed);
        renderer.reveal();

        string memory svg = renderer.getSVG(1);
        assertEq(svg, _wrapSvg(1, "<text>updated</text>"));
    }

    function test_updateTraitPointer_emitsEvent() public {
        address newPtr = _createFileStorePointer(bytes("<text>x</text>"));

        vm.expectEmit(true, true, true, true);
        emit TraitPointerUpdated(0, 3, 2, newPtr);

        renderer.updateTraitPointer(0, 3, 2, newPtr);
    }

    function test_updateTraitPointer_revertsInvalidPointer() public {
        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.updateTraitPointer(0, 0, 1, address(0));
    }

    function test_updateTraitPointer_revertsTraitIndexZero() public {
        address ptr = _createFileStorePointer(bytes("<rect/>"));
        vm.expectRevert(DealerRendererSVG.InvalidTraitIndex.selector);
        renderer.updateTraitPointer(0, 0, 0, ptr);
    }

    function test_updateTraitPointer_revertsTraitIndexOutOfBounds() public {
        address ptr = _createFileStorePointer(bytes("<rect/>"));
        vm.expectRevert(DealerRendererSVG.InvalidTraitIndex.selector);
        renderer.updateTraitPointer(0, 0, 6, ptr);
    }

    function test_updateTraitPointer_revertsInvalidCategory() public {
        address ptr = _createFileStorePointer(bytes("<rect/>"));
        vm.expectRevert(DealerRendererSVG.InvalidCategory.selector);
        renderer.updateTraitPointer(0, 12, 1, ptr);
    }

    function test_updateTraitPointer_revertsInvalidCharacterType() public {
        address ptr = _createFileStorePointer(bytes("<rect/>"));
        vm.expectRevert(DealerRendererSVG.InvalidCharacterType.selector);
        renderer.updateTraitPointer(3, 0, 1, ptr);
    }

    function test_updateTraitPointer_revertsNonOwner() public {
        address ptr = _createFileStorePointer(bytes("<rect/>"));
        vm.prank(nonOwner);
        vm.expectRevert();
        renderer.updateTraitPointer(0, 0, 1, ptr);
    }

    // =============================================================
    //                      traitCount TESTS
    // =============================================================

    function test_traitCount_matchesAddedTraits() public view {
        for (uint8 cat; cat < 12; cat++) {
            assertEq(renderer.traitCount(0, cat), 5);
        }
    }

    function test_traitCount_zeroForUnconfigured() public view {
        for (uint8 cat; cat < 12; cat++) {
            assertEq(renderer.traitCount(1, cat), 0);
        }
    }

    function test_traitCount_growsAfterAdd() public {
        address ptr = _createFileStorePointer(bytes("<rect/>"));
        renderer.addTrait(0, 5, "Extra", ptr);
        assertEq(renderer.traitCount(0, 5), 6);
    }

    // =============================================================
    //                      FUZZ TESTS
    // =============================================================

    function testFuzz_packUnpack_roundtrip(
        uint8 a,
        uint8 b,
        uint8 c,
        uint8 d,
        uint8 e,
        uint8 f,
        uint8 g,
        uint8 h,
        uint8 i,
        uint8 j,
        uint8 k,
        uint8 l
    ) public {
        uint8[12] memory t = [a, b, c, d, e, f, g, h, i, j, k, l];
        bytes32 packed = _packTraits(t);

        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packedArr = new bytes32[](1);
        ids[0] = 1;
        packedArr[0] = packed;
        renderer.batchSetTraits(ids, packedArr);

        uint8[12] memory result = renderer.getStoredTraits(1);
        for (uint8 idx; idx < 12; idx++) {
            assertEq(result[idx], t[idx]);
        }
    }

    function testFuzz_setTraitForToken_preservesOtherCategories(uint8 category, uint8 newValue) public {
        category = uint8(bound(category, 0, 11));

        uint8[12] memory t = [uint8(10), 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120];

        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 1;
        packed[0] = _packTraits(t);
        renderer.batchSetTraits(ids, packed);

        renderer.setTraitForToken(1, category, newValue);

        uint8[12] memory result = renderer.getStoredTraits(1);
        for (uint8 idx; idx < 12; idx++) {
            if (idx == category) {
                assertEq(result[idx], newValue);
            } else {
                assertEq(result[idx], t[idx]);
            }
        }
    }
}

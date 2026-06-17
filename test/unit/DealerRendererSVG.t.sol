// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/nft/DealerRendererSVG.sol";
import "../../src/nft/IDealerRendererSVG.sol";
import {File, BytecodeSlice} from "../../src/nft/File.sol";
import {SSTORE2} from "solady/src/utils/SSTORE2.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

contract MockNFTPool {
    mapping(uint256 => uint32) public tokenToPool;

    function setPool(uint256 tokenId, uint32 poolIndex) external {
        tokenToPool[tokenId] = poolIndex;
    }
}

contract DealerRendererSVGTest is Test {
    DealerRendererSVG public renderer;
    MockNFTPool public pool;
    address public owner;
    address public nonOwner;

    event TraitsStored(uint256 indexed poolIndex);
    event TraitUpdated(uint256 indexed poolIndex, uint8 indexed category, uint8 traitIndex);
    event TraitPointerUpdated(
        uint8 indexed characterType, uint8 indexed category, uint256 indexed traitIndex, address newPointer
    );

    function setUp() public {
        owner = address(this);
        nonOwner = makeAddr("nonOwner");
        renderer = new DealerRendererSVG();
        pool = new MockNFTPool();
        renderer.setDealersNFT(address(pool));

        _addBasicTraits();
    }

    /// @dev Bind a tokenId to a pool index (simulates DealersNFT.resolve()).
    function _reveal(uint256 tokenId, uint256 poolIndex) internal {
        pool.setPool(tokenId, uint32(poolIndex));
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

    function _setTrait(uint256 poolIndex, uint8[12] memory t, uint8 charType) internal {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = poolIndex;
        packed[0] = _packTraitsWithType(t, charType);
        renderer.batchSetTraits(ids, packed);
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

    function test_batchSetTraits_revertsInvalidPoolIndex() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = 0;
        packed[0] = bytes32(uint256(1));

        vm.expectRevert(DealerRendererSVG.InvalidPoolIndex.selector);
        renderer.batchSetTraits(ids, packed);
    }

    function test_batchSetTraits_revertsInvalidPoolIndexTooHigh() public {
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory packed = new bytes32[](1);
        ids[0] = renderer.MAX_SUPPLY() + 1;
        packed[0] = bytes32(uint256(1));

        vm.expectRevert(DealerRendererSVG.InvalidPoolIndex.selector);
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
        _setTrait(1, [uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2], 0);

        renderer.setTraitForToken(1, 3, 99);

        uint8[12] memory result = renderer.getStoredTraits(1);
        assertEq(result[0], 1);
        assertEq(result[3], 99);
        assertEq(result[11], 2);
    }

    function test_setTraitForToken_revertsInvalidPoolIndex() public {
        vm.expectRevert(DealerRendererSVG.InvalidPoolIndex.selector);
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
        _setTrait(1, [uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2], 0);
        assertTrue(renderer.isTraitStored(1));
    }

    // =============================================================
    //                    CHARACTER TYPE TESTS
    // =============================================================

    function test_getCharacterType_normal() public {
        _setTrait(100, [uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2], 0);
        _reveal(100, 100);
        assertEq(renderer.getCharacterType(100), 0);
    }

    function test_getCharacterType_special() public {
        _setTrait(100, [uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2], 1);
        _reveal(100, 100);
        assertEq(renderer.getCharacterType(100), 1);
    }

    function test_getCharacterType_oneOfOne() public {
        address ptr = _createFileStorePointer(bytes("<text>1of1</text>"));
        renderer.setOneOfOne(100, "Legend", ptr);
        _reveal(100, 100);
        assertEq(renderer.getCharacterType(100), 2);
    }

    function test_getCharacterType_normalWhenUnrevealed() public view {
        assertEq(renderer.getCharacterType(100), 0);
    }

    function test_getCharacterType_revertsInvalidTokenId() public {
        uint256 tooHigh = renderer.MAX_SUPPLY() + 1;

        vm.expectRevert(DealerRendererSVG.InvalidTokenId.selector);
        renderer.getCharacterType(0);

        vm.expectRevert(DealerRendererSVG.InvalidTokenId.selector);
        renderer.getCharacterType(tooHigh);
    }

    // =============================================================
    //                      getSVG TESTS
    // =============================================================

    function test_getSVG_returnsPlaceholderWhenUnrevealed() public {
        bytes memory placeholderInner = bytes("<text>Unrevealed</text>");
        address ptr = _createFileStorePointer(placeholderInner);
        renderer.setPlaceholderSvg(ptr);

        string memory svg = renderer.getSVG(1);
        assertEq(svg, _wrapSvg(1, "<text>Unrevealed</text>"));
    }

    function test_getSVG_revertsUnrevealedNoPlaceholder() public {
        vm.expectRevert(IDealerRendererSVG.TraitsNotStored.selector);
        renderer.getSVG(1);
    }

    function test_getSVG_readsStoredTraitsWhenRevealed() public {
        _setTrait(100, [uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2], 0);
        _reveal(100, 100);

        string memory svg = renderer.getSVG(100);
        assertTrue(bytes(svg).length > 50);
    }

    function test_getSVG_containsTokenIdAttribute() public {
        _setTrait(100, [uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 0);
        _reveal(100, 100);

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
        _reveal(404, 404);

        string memory svg = renderer.getSVG(404);
        assertEq(svg, _wrapSvg(404, "<text>Legend</text>"));
    }

    function test_getSVG_poolIndexDiffersFromTokenId() public {
        // Token 7 reveals to pool slot 100's artwork; the SVG wrapper still shows token 7.
        _setTrait(100, [uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 0);
        _reveal(7, 100);

        string memory svg = renderer.getSVG(7);
        bytes memory svgBytes = bytes(svg);
        bytes memory prefixBytes = bytes(_svgPrefix(7));
        for (uint256 i; i < prefixBytes.length; i++) {
            assertEq(svgBytes[i], prefixBytes[i]);
        }
        assertTrue(bytes(svg).length > 50);
    }

    function test_getSVG_placeholderWhenUnrevealedEvenWithPoolTraits() public {
        bytes memory placeholderInner = bytes("<text>Unrevealed</text>");
        address ptr = _createFileStorePointer(placeholderInner);
        renderer.setPlaceholderSvg(ptr);

        _setTrait(100, [uint8(1), 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2], 0);
        // token 100 not yet assigned -> placeholder despite pool slot 100 holding traits

        string memory svg = renderer.getSVG(100);
        assertEq(svg, _wrapSvg(100, "<text>Unrevealed</text>"));
    }

    function test_getSVG_specialUsesSpecialTraitPool() public {
        bytes memory specialSvg = bytes("<circle class='special'/>");
        for (uint8 cat; cat < 12; cat++) {
            address ptr = _createFileStorePointer(specialSvg);
            renderer.addTrait(1, cat, "SpecialTrait", ptr);
        }

        _setTrait(500, [uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 1);
        _reveal(500, 500);

        string memory svg = renderer.getSVG(500);
        assertTrue(bytes(svg).length > 50);
    }

    // =============================================================
    //                  TRAITS METADATA TESTS
    // =============================================================

    function test_getTraitsMetadata_unrevealedByDefault() public view {
        string memory metadata = renderer.getTraitsMetadataForToken(1);
        assertEq(metadata, '{"trait_type":"Status","value":"Unrevealed"}');
    }

    function test_getTraitsMetadata_returnsCorrectNames() public {
        _setTrait(100, [uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 0);
        _reveal(100, 100);

        string memory metadata = renderer.getTraitsMetadataForToken(100);
        assertTrue(_contains(metadata, "Normal"));
    }

    function test_getTraitsMetadata_unrevealedEvenWithPoolTraits() public {
        _setTrait(100, [uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 0);
        // token 100 unassigned

        string memory metadata = renderer.getTraitsMetadataForToken(100);
        assertEq(metadata, '{"trait_type":"Status","value":"Unrevealed"}');
    }

    function test_getTraitsMetadata_special() public {
        _setTrait(100, [uint8(1), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 1);
        _reveal(100, 100);

        string memory metadata = renderer.getTraitsMetadataForToken(100);
        assertTrue(_contains(metadata, "Special"));
    }

    function test_getTraitsMetadata_oneOfOne() public {
        address ptr = _createFileStorePointer(bytes("<text>1of1</text>"));
        renderer.setOneOfOne(100, "TheBoss", ptr);
        _reveal(100, 100);

        string memory metadata = renderer.getTraitsMetadataForToken(100);
        assertTrue(_contains(metadata, "One of One"));
    }

    // =============================================================
    //                    PACK / UNPACK ROUNDTRIP
    // =============================================================

    function test_packUnpack_roundtrip() public {
        _setTrait(1, [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 0);

        uint8[12] memory result = renderer.getStoredTraits(1);
        uint8[12] memory t = [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
        for (uint8 i; i < 12; i++) {
            assertEq(result[i], t[i]);
        }
    }

    function test_packUnpack_maxValues() public {
        _setTrait(1, [uint8(255), 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255], 0);

        uint8[12] memory result = renderer.getStoredTraits(1);
        for (uint8 i; i < 12; i++) {
            assertEq(result[i], 255);
        }
    }

    function test_packWithType_preservesCharType() public {
        _setTrait(1, [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 1);
        _reveal(1, 1);

        uint8[12] memory result = renderer.getStoredTraits(1);
        uint8[12] memory t = [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
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

    function test_setOneOfOne_revertsInvalidPoolIndex() public {
        address ptr = _createFileStorePointer(bytes("<text/>"));
        vm.expectRevert(DealerRendererSVG.InvalidPoolIndex.selector);
        renderer.setOneOfOne(0, "Test", ptr);
    }

    function test_batchSetOneOfOnes_withFileStorePointers() public {
        uint256[] memory poolIndices = new uint256[](2);
        string[] memory names = new string[](2);
        address[] memory pointers = new address[](2);

        poolIndices[0] = 1;
        names[0] = "Legend1";
        poolIndices[1] = 2;
        names[1] = "Legend2";

        pointers[0] = _createFileStorePointer(bytes("<text>1</text>"));
        pointers[1] = _createFileStorePointer(bytes("<text>2</text>"));

        renderer.batchSetOneOfOnes(poolIndices, names, pointers);

        (string memory name1,, bool exists1) = renderer.getOneOfOneInfo(1);
        (string memory name2,, bool exists2) = renderer.getOneOfOneInfo(2);
        assertEq(name1, "Legend1");
        assertEq(name2, "Legend2");
        assertTrue(exists1);
        assertTrue(exists2);
    }

    function test_batchSetOneOfOnes_revertsInvalidPointer() public {
        uint256[] memory poolIndices = new uint256[](2);
        string[] memory names = new string[](2);
        address[] memory pointers = new address[](2);

        poolIndices[0] = 1;
        names[0] = "Test1";
        poolIndices[1] = 2;
        names[1] = "Test2";

        pointers[0] = _createFileStorePointer(bytes("<text/>"));
        pointers[1] = address(0);

        vm.expectRevert(IDealerRendererSVG.InvalidPointer.selector);
        renderer.batchSetOneOfOnes(poolIndices, names, pointers);
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
    //                    NFT INTEGRATION TESTS
    // =============================================================

    function test_setDealersNFT_success() public {
        MockNFTPool newPool = new MockNFTPool();
        renderer.setDealersNFT(address(newPool));
        assertEq(renderer.dealersNFT(), address(newPool));
    }

    function test_setDealersNFT_revertsZeroAddress() public {
        vm.expectRevert(DealerRendererSVG.InvalidAddress.selector);
        renderer.setDealersNFT(address(0));
    }

    function test_setDealersNFT_revertsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        renderer.setDealersNFT(address(pool));
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

        _setTrait(1, [uint8(1), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0);
        _reveal(1, 1);

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
        _setTrait(1, t, 0);

        uint8[12] memory result = renderer.getStoredTraits(1);
        for (uint8 idx; idx < 12; idx++) {
            assertEq(result[idx], t[idx]);
        }
    }

    function testFuzz_setTraitForToken_preservesOtherCategories(uint8 category, uint8 newValue) public {
        category = uint8(bound(category, 0, 11));

        uint8[12] memory t = [uint8(10), 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120];
        _setTrait(1, t, 0);

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

    // =============================================================
    //                      HELPERS
    // =============================================================

    function _contains(string memory str, string memory substr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory subBytes = bytes(substr);
        if (subBytes.length > strBytes.length) return false;
        for (uint256 i = 0; i <= strBytes.length - subBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < subBytes.length; j++) {
                if (strBytes[i + j] != subBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/nft/DealersNFT.sol";

contract DealersNFTInterfaceTest is Test {
    DealersNFT internal nft;

    // Canonical EIP interface ids
    bytes4 internal constant ID_ERC165 = 0x01ffc9a7;
    bytes4 internal constant ID_ERC721 = 0x80ac58cd;
    bytes4 internal constant ID_ERC721_METADATA = 0x5b5e139f;
    bytes4 internal constant ID_ERC721_ENUMERABLE = 0x780e9d63;
    bytes4 internal constant ID_ERC2981 = 0x2a55205a;

    function setUp() public {
        nft = new DealersNFT(address(0xBEEF));
    }

    function test_supportsInterface_supported() public view {
        assertTrue(nft.supportsInterface(ID_ERC165), "ERC165");
        assertTrue(nft.supportsInterface(ID_ERC721), "ERC721");
        assertTrue(nft.supportsInterface(ID_ERC721_METADATA), "ERC721Metadata");
        assertTrue(nft.supportsInterface(ID_ERC721_ENUMERABLE), "ERC721Enumerable");
        assertTrue(nft.supportsInterface(ID_ERC2981), "ERC2981");
    }

    function test_supportsInterface_unsupported() public view {
        // ERC165 spec: 0xffffffff MUST return false
        assertFalse(nft.supportsInterface(0xffffffff), "0xffffffff must be false");
        assertFalse(nft.supportsInterface(0xdeadbeef), "random id false");
        assertFalse(nft.supportsInterface(0x00000000), "zero id false");
    }

    function test_erc2981InterfaceId_matchesConstant() public pure {
        assertEq(type(IERC2981).interfaceId, ID_ERC2981);
    }
}

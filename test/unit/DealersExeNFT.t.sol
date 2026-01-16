// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../base/BaseTest.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract DealersExeNFTTest is BaseTest {
    using MessageHashUtils for bytes32;

    uint256 internal constant MINT_PRICE = 0.01 ether;

    function setUp() public override {
        super.setUp();
    }

    function _generateSignature(
        string memory tag,
        address sender,
        address dest,
        uint256 count
    ) internal view returns (bytes memory) {
        bytes32 msgHash = keccak256(abi.encodePacked(tag, sender, dest, count))
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, msgHash);
        return abi.encodePacked(r, s, v);
    }

    // =============================================================
    //                    MINTING STAGES (4)
    // =============================================================

    function test_mintPublic_revertWhenDisabled() public {
        assertEq(uint8(nft.mintStatus()), uint8(DealersExeNFT.MintStatus.DISABLED));

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.NotPublicMint.selector);
        nft.mintPublic{value: MINT_PRICE}(player1, 1);
    }

    function test_mintFamily_revertWhenNotFamily() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        bytes memory sig = _generateSignature("FAMILY", player1, player1, 1);

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.NotFamilyMint.selector);
        nft.mintFamily{value: MINT_PRICE}(player1, 1, sig);
    }

    function test_mintWhitelist_revertWhenNotWhitelist() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes memory sig = _generateSignature("WHITELIST", player1, player1, 1);

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.NotWhitelistMint.selector);
        nft.mintWhitelist{value: MINT_PRICE}(player1, 1, sig);
    }

    function test_setMintStatus_changesStage() public {
        assertEq(uint8(nft.mintStatus()), uint8(DealersExeNFT.MintStatus.DISABLED));

        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);
        assertEq(uint8(nft.mintStatus()), uint8(DealersExeNFT.MintStatus.FAMILY));

        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.WHITELIST);
        assertEq(uint8(nft.mintStatus()), uint8(DealersExeNFT.MintStatus.WHITELIST));

        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);
        assertEq(uint8(nft.mintStatus()), uint8(DealersExeNFT.MintStatus.PUBLIC));
    }

    // =============================================================
    //                    SIGNATURES (6)
    // =============================================================

    function test_mintFamily_validSignature() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes memory sig = _generateSignature("FAMILY", player1, player1, 1);

        uint256 balanceBefore = nft.balanceOf(player1);

        vm.prank(player1);
        nft.mintFamily{value: MINT_PRICE}(player1, 1, sig);

        assertEq(nft.balanceOf(player1), balanceBefore + 1);
    }

    function test_mintFamily_revertInvalidSignature() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes memory sig = _generateSignature("WRONG_TAG", player1, player1, 1);

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.InvalidSignature.selector);
        nft.mintFamily{value: MINT_PRICE}(player1, 1, sig);
    }

    function test_mintFamily_revertReplaySignature() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes memory sig = _generateSignature("FAMILY", player1, player1, 1);

        vm.prank(player1);
        nft.mintFamily{value: MINT_PRICE}(player1, 1, sig);

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.SignatureAlreadyUsed.selector);
        nft.mintFamily{value: MINT_PRICE}(player1, 1, sig);
    }

    function test_mintWhitelist_validSignature() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.WHITELIST);

        bytes memory sig = _generateSignature("WHITELIST", player1, player1, 1);

        uint256 balanceBefore = nft.balanceOf(player1);

        vm.prank(player1);
        nft.mintWhitelist{value: MINT_PRICE}(player1, 1, sig);

        assertEq(nft.balanceOf(player1), balanceBefore + 1);
    }

    function test_mintWhitelist_revertWrongSigner() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.WHITELIST);

        uint256 wrongPrivateKey = 0xBAD;
        bytes32 msgHash = keccak256(abi.encodePacked("WHITELIST", player1, player1, uint256(1)))
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, msgHash);
        bytes memory wrongSig = abi.encodePacked(r, s, v);

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.InvalidSignature.selector);
        nft.mintWhitelist{value: MINT_PRICE}(player1, 1, wrongSig);
    }

    function test_isSignatureUsed_tracksCorrectly() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes memory sig = _generateSignature("FAMILY", player1, player1, 1);

        assertFalse(nft.isSignatureUsed(sig));

        vm.prank(player1);
        nft.mintFamily{value: MINT_PRICE}(player1, 1, sig);

        assertTrue(nft.isSignatureUsed(sig));
    }

    // =============================================================
    //                    SUPPLY (5)
    // =============================================================

    function test_mintPublic_revertTotalSupplyReached() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        uint256 maxSupply = nft.MAX_SUPPLY();

        uint256 mintStatusPublic = uint256(DealersExeNFT.MintStatus.PUBLIC);
        uint256 packedValue = mintStatusPublic | (maxSupply << 8);

        vm.store(
            address(nft),
            bytes32(uint256(10)),
            bytes32(packedValue)
        );

        assertEq(nft.totalMinted(), maxSupply);

        address extraMinter = makeAddr("extraMinter");
        vm.deal(extraMinter, 1 ether);

        vm.prank(extraMinter);
        vm.expectRevert(DealersExeNFT.TotalSupplyReached.selector);
        nft.mintPublic{value: MINT_PRICE}(extraMinter, 1);
    }

    function test_mintPublic_revertMaxPerWallet() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        uint256 maxPerWallet = nft.MAX_PER_WALLET();
        uint256 totalCost = MINT_PRICE * (maxPerWallet + 1);

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.InvalidMint.selector);
        nft.mintPublic{value: totalCost}(player1, maxPerWallet + 1);
    }

    function test_reserve_mintsToOwner() public {
        uint256 balanceBefore = nft.balanceOf(owner);
        uint256 supplyBefore = nft.totalSupply();

        vm.prank(owner);
        nft.reserve(5);

        assertEq(nft.balanceOf(owner), balanceBefore + 5);
        assertEq(nft.totalSupply(), supplyBefore + 5);
    }

    function test_reserveTo_mintsToRecipient() public {
        uint256 balanceBefore = nft.balanceOf(player1);

        vm.prank(owner);
        nft.reserveTo(3, player1);

        assertEq(nft.balanceOf(player1), balanceBefore + 3);
    }

    function test_reserveToMany_mintsToBatch() public {
        address[] memory recipients = new address[](3);
        recipients[0] = player1;
        recipients[1] = player2;
        recipients[2] = makeAddr("player3");

        uint256 bal1Before = nft.balanceOf(player1);
        uint256 bal2Before = nft.balanceOf(player2);
        uint256 bal3Before = nft.balanceOf(recipients[2]);

        vm.prank(owner);
        nft.reserveToMany(2, recipients);

        assertEq(nft.balanceOf(player1), bal1Before + 2);
        assertEq(nft.balanceOf(player2), bal2Before + 2);
        assertEq(nft.balanceOf(recipients[2]), bal3Before + 2);
    }

    // =============================================================
    //                    CORE INIT (4)
    // =============================================================

    function test_mint_initializesDealerInCore() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        uint256 nextTokenId = nft.currentTokenId();

        vm.prank(player1);
        nft.mintPublic{value: MINT_PRICE}(player1, 1);

        (
            uint8 currentArea,
            uint256 reputation,
            uint8 dailyAttemptsRemaining,
            uint8 heatLevel,
            ,
            bool isInitialized
        ) = core.getDealerData(nextTokenId);

        assertTrue(isInitialized);
        assertEq(currentArea, core.STARTING_AREA());
        assertEq(reputation, core.STARTING_REPUTATION());
        assertEq(dailyAttemptsRemaining, core.BASE_MAX_ATTEMPTS());
        assertEq(heatLevel, 0);
    }

    function test_mint_generatesTokenSeed() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        uint256 nextTokenId = nft.currentTokenId();

        vm.prank(player1);
        nft.mintPublic{value: MINT_PRICE}(player1, 1);

        uint256 seed = nft.getTokenSeed(nextTokenId);
        assertGt(seed, 0);
    }

    function test_mint_emitsDealerInitialized() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        uint256 nextTokenId = nft.currentTokenId();

        vm.expectEmit(true, true, false, false);
        emit DealersExeNFT.DealerInitialized(nextTokenId, player1);

        vm.prank(player1);
        nft.mintPublic{value: MINT_PRICE}(player1, 1);
    }

    function test_mint_withoutCore_noInitialization() public {
        DealersExeNFT nftNoCore = new DealersExeNFT(signer, devWallet);

        vm.prank(address(this));
        nftNoCore.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        uint256 nextTokenId = nftNoCore.currentTokenId();

        vm.prank(player1);
        nftNoCore.mintPublic{value: MINT_PRICE}(player1, 1);

        assertEq(nftNoCore.balanceOf(player1), 1);
        assertEq(nftNoCore.ownerOf(nextTokenId), player1);

        assertEq(nftNoCore.dealersExeCore(), address(0));
    }

    // =============================================================
    //                    METADATA (4)
    // =============================================================

    function test_tokenURI_returnsBase64Json() public {
        uint256 tokenId = _mintAndInitialize(player1);

        string memory uri = nft.tokenURI(tokenId);

        bytes memory expectedPrefix = bytes("data:application/json;base64,");
        bytes memory uriBytes = bytes(uri);

        for (uint256 i = 0; i < expectedPrefix.length; i++) {
            assertEq(uriBytes[i], expectedPrefix[i]);
        }
    }

    function test_tokenJson_includesTraits() public {
        uint256 tokenId = _mintAndInitialize(player1);

        string memory json = nft.tokenJson(tokenId);

        assertTrue(_containsSubstring(json, '"name":"Dealer #'));
        assertTrue(_containsSubstring(json, '"attributes":['));
        assertTrue(_containsSubstring(json, '"trait_type":"Area"'));
        assertTrue(_containsSubstring(json, '"trait_type":"Reputation"'));
        assertTrue(_containsSubstring(json, '"trait_type":"Heat Level"'));
    }

    function test_tokenURI_revertTokenDoesNotExist() public {
        uint256 nonExistentTokenId = 99999;

        vm.expectRevert(DealersExeNFT.TokenDoesNotExist.selector);
        nft.tokenURI(nonExistentTokenId);
    }

    function test_getTokenSeed_returnsConsistent() public {
        uint256 tokenId = _mintAndInitialize(player1);

        uint256 seed1 = nft.getTokenSeed(tokenId);
        uint256 seed2 = nft.getTokenSeed(tokenId);

        assertEq(seed1, seed2);
        assertGt(seed1, 0);
    }

    // =============================================================
    //                    PAYMENT (3)
    // =============================================================

    function test_mintPublic_revertInsufficientETH() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        uint256 insufficientAmount = MINT_PRICE - 1;

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.InsufficientETH.selector);
        nft.mintPublic{value: insufficientAmount}(player1, 1);
    }

    function test_withdrawAll_sendsToOwner() public {
        DealersExeNFT freshNft = new DealersExeNFT(signer, devWallet);

        freshNft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);
        freshNft.transferOwnership(devWallet);

        vm.prank(player1);
        freshNft.mintPublic{value: MINT_PRICE * 5}(player1, 5);

        uint256 contractBalance = address(freshNft).balance;
        assertGt(contractBalance, 0);

        uint256 ownerBalanceBefore = devWallet.balance;

        vm.prank(devWallet);
        freshNft.withdrawAll();

        assertEq(address(freshNft).balance, 0);
        assertEq(devWallet.balance, ownerBalanceBefore + contractBalance);
    }

    function test_withdrawAmount_sendsSpecific() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        vm.prank(player1);
        nft.mintPublic{value: MINT_PRICE * 5}(player1, 5);

        uint256 contractBalanceBefore = address(nft).balance;
        uint256 withdrawAmount = MINT_PRICE * 2;
        uint256 player2BalanceBefore = player2.balance;

        vm.prank(owner);
        nft.withdrawAmount(player2, withdrawAmount);

        assertEq(address(nft).balance, contractBalanceBefore - withdrawAmount);
        assertEq(player2.balance, player2BalanceBefore + withdrawAmount);
    }

    // =============================================================
    //                    ROYALTY (2)
    // =============================================================

    function test_royaltyInfo_returns5Percent() public view {
        uint256 salePrice = 1 ether;
        uint256 expectedRoyalty = (salePrice * 500) / 10000;

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(1, salePrice);

        assertEq(receiver, devWallet);
        assertEq(royaltyAmount, expectedRoyalty);
        assertEq(royaltyAmount, 0.05 ether);
    }

    function test_setRoyaltyReceiver_changes() public {
        address newReceiver = makeAddr("newRoyaltyReceiver");

        vm.prank(owner);
        nft.setRoyaltyReceiver(newReceiver);

        (address receiver, ) = nft.royaltyInfo(1, 1 ether);
        assertEq(receiver, newReceiver);
    }

    // =============================================================
    //                    ADMIN (2)
    // =============================================================

    function test_setDealersExeCore_updates() public {
        address newCore = makeAddr("newCore");

        vm.prank(owner);
        nft.setDealersExeCore(newCore);

        assertEq(nft.dealersExeCore(), newCore);
    }

    function test_setSignerAddress_changes() public {
        address newSigner = makeAddr("newSigner");

        vm.prank(owner);
        nft.setSignerAddress(newSigner);

        assertEq(nft.signerAddress(), newSigner);
    }

    // =============================================================
    //                    HELPER FUNCTIONS
    // =============================================================

    function _containsSubstring(string memory str, string memory substr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory substrBytes = bytes(substr);

        if (substrBytes.length > strBytes.length) return false;

        for (uint256 i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}

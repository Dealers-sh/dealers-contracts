// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";

contract DealersExeNFTTest is BaseTest {
    uint256 internal constant MINT_PRICE = 0.01 ether;

    uint256 internal constant PLAYER1_FAMILY_ALLOCATION = 3;
    uint256 internal constant PLAYER2_FAMILY_ALLOCATION = 2;
    uint256 internal constant PLAYER1_WHITELIST_ALLOCATION = 5;
    uint256 internal constant PLAYER2_WHITELIST_ALLOCATION = 3;

    bytes32 internal familyRoot;
    bytes32 internal whitelistRoot;

    bytes32 internal player1FamilyLeaf;
    bytes32 internal player2FamilyLeaf;
    bytes32 internal player1WhitelistLeaf;
    bytes32 internal player2WhitelistLeaf;

    function setUp() public override {
        super.setUp();
        _setupMerkleTrees();
    }

    function _setupMerkleTrees() internal {
        player1FamilyLeaf = _computeLeaf(player1, PLAYER1_FAMILY_ALLOCATION);
        player2FamilyLeaf = _computeLeaf(player2, PLAYER2_FAMILY_ALLOCATION);
        familyRoot = _computeMerkleRoot(player1FamilyLeaf, player2FamilyLeaf);

        player1WhitelistLeaf = _computeLeaf(player1, PLAYER1_WHITELIST_ALLOCATION);
        player2WhitelistLeaf = _computeLeaf(player2, PLAYER2_WHITELIST_ALLOCATION);
        whitelistRoot = _computeMerkleRoot(player1WhitelistLeaf, player2WhitelistLeaf);

        vm.startPrank(owner);
        nft.setFamilyMerkleRoot(familyRoot);
        nft.setWhitelistMerkleRoot(whitelistRoot);
        vm.stopPrank();
    }

    function _getFamilyProofForPlayer1() internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = player2FamilyLeaf;
        return proof;
    }

    function _getFamilyProofForPlayer2() internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = player1FamilyLeaf;
        return proof;
    }

    function _getWhitelistProofForPlayer1() internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = player2WhitelistLeaf;
        return proof;
    }

    function _getWhitelistProofForPlayer2() internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = player1WhitelistLeaf;
        return proof;
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

        bytes32[] memory proof = _getFamilyProofForPlayer1();

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.NotFamilyMint.selector);
        nft.mintFamily(1, PLAYER1_FAMILY_ALLOCATION, proof);
    }

    function test_mintWhitelist_revertWhenNotWhitelist() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes32[] memory proof = _getWhitelistProofForPlayer1();

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.NotWhitelistMint.selector);
        nft.mintWhitelist{value: MINT_PRICE}(1, PLAYER1_WHITELIST_ALLOCATION, proof);
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
    //                    FAMILY MINT (6)
    // =============================================================

    function test_mintFamily_freeWithValidProof() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes32[] memory proof = _getFamilyProofForPlayer1();
        uint256 balanceBefore = nft.balanceOf(player1);
        uint256 ethBefore = player1.balance;

        vm.prank(player1);
        nft.mintFamily(1, PLAYER1_FAMILY_ALLOCATION, proof);

        assertEq(nft.balanceOf(player1), balanceBefore + 1);
        assertEq(player1.balance, ethBefore);
        assertEq(nft.getFamilyClaimed(player1), 1);
    }

    function test_mintFamily_revertInvalidProof() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = bytes32(uint256(0xBAD));

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.InvalidMerkleProof.selector);
        nft.mintFamily(1, PLAYER1_FAMILY_ALLOCATION, badProof);
    }

    function test_mintFamily_revertExceedsAllocation() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes32[] memory proof = _getFamilyProofForPlayer1();

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.ExceedsAllocation.selector);
        nft.mintFamily(PLAYER1_FAMILY_ALLOCATION + 1, PLAYER1_FAMILY_ALLOCATION, proof);
    }

    function test_mintFamily_multipleTransactions() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes32[] memory proof = _getFamilyProofForPlayer1();

        vm.prank(player1);
        nft.mintFamily(1, PLAYER1_FAMILY_ALLOCATION, proof);
        assertEq(nft.getFamilyClaimed(player1), 1);

        vm.prank(player1);
        nft.mintFamily(2, PLAYER1_FAMILY_ALLOCATION, proof);
        assertEq(nft.getFamilyClaimed(player1), 3);

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.ExceedsAllocation.selector);
        nft.mintFamily(1, PLAYER1_FAMILY_ALLOCATION, proof);
    }

    function test_mintFamily_revertWrongAllocationClaim() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes32[] memory proof = _getFamilyProofForPlayer1();

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.InvalidMerkleProof.selector);
        nft.mintFamily(1, 999, proof);
    }

    function test_mintFamily_revertMerkleRootNotSet() public {
        DealersExeNFT freshNft = new DealersExeNFT(devWallet);

        vm.prank(address(this));
        freshNft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.MerkleRootNotSet.selector);
        freshNft.mintFamily(1, 1, proof);
    }

    // =============================================================
    //                    WHITELIST MINT (5)
    // =============================================================

    function test_mintWhitelist_paidWithValidProof() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.WHITELIST);

        bytes32[] memory proof = _getWhitelistProofForPlayer1();
        uint256 balanceBefore = nft.balanceOf(player1);
        uint256 ethBefore = player1.balance;

        vm.prank(player1);
        nft.mintWhitelist{value: MINT_PRICE}(1, PLAYER1_WHITELIST_ALLOCATION, proof);

        assertEq(nft.balanceOf(player1), balanceBefore + 1);
        assertEq(player1.balance, ethBefore - MINT_PRICE);
        assertEq(nft.getWhitelistClaimed(player1), 1);
    }

    function test_mintWhitelist_revertInsufficientETH() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.WHITELIST);

        bytes32[] memory proof = _getWhitelistProofForPlayer1();

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.InsufficientETH.selector);
        nft.mintWhitelist{value: MINT_PRICE - 1}(1, PLAYER1_WHITELIST_ALLOCATION, proof);
    }

    function test_mintWhitelist_refundsExcessETH() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.WHITELIST);

        bytes32[] memory proof = _getWhitelistProofForPlayer1();
        uint256 ethBefore = player1.balance;
        uint256 overpay = 0.1 ether;

        vm.prank(player1);
        nft.mintWhitelist{value: MINT_PRICE + overpay}(1, PLAYER1_WHITELIST_ALLOCATION, proof);

        assertEq(player1.balance, ethBefore - MINT_PRICE);
    }

    function test_mintWhitelist_revertInvalidProof() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.WHITELIST);

        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = bytes32(uint256(0xBAD));

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.InvalidMerkleProof.selector);
        nft.mintWhitelist{value: MINT_PRICE}(1, PLAYER1_WHITELIST_ALLOCATION, badProof);
    }

    function test_mintWhitelist_revertExceedsAllocation() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.WHITELIST);

        bytes32[] memory proof = _getWhitelistProofForPlayer1();

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.ExceedsAllocation.selector);
        nft.mintWhitelist{value: MINT_PRICE * 6}(6, PLAYER1_WHITELIST_ALLOCATION, proof);
    }

    // =============================================================
    //                    SUPPLY (5)
    // =============================================================

    function test_mintPublic_revertTotalSupplyReached() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        uint256 maxSupply = nft.MAX_SUPPLY();

        // Storage layout: mintStatus (1 byte) | paused (1 byte) | totalMinted (4 bytes)
        uint256 mintStatusPublic = uint256(DealersExeNFT.MintStatus.PUBLIC);
        uint256 packedValue = mintStatusPublic | (maxSupply << 16);

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
        DealersExeNFT nftNoCore = new DealersExeNFT(devWallet);

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
        assertTrue(_containsSubstring(json, '"trait_type":"Rank"'));
        assertTrue(_containsSubstring(json, '"trait_type":"Infamy"'));
        assertTrue(_containsSubstring(json, '"trait_type":"Area"'));
        assertTrue(_containsSubstring(json, '"trait_type":"Heat"'));
    }

    function test_tokenURI_revertTokenDoesNotExist() public {
        uint256 nonExistentTokenId = 99999;

        vm.expectRevert(DealersExeNFT.TokenDoesNotExist.selector);
        nft.tokenURI(nonExistentTokenId);
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

    function test_withdraw_allToOwner() public {
        DealersExeNFT freshNft = new DealersExeNFT(devWallet);

        freshNft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);
        freshNft.transferOwnership(devWallet);

        vm.prank(player1);
        freshNft.mintPublic{value: MINT_PRICE * 5}(player1, 5);

        uint256 contractBalance = address(freshNft).balance;
        assertGt(contractBalance, 0);

        uint256 ownerBalanceBefore = devWallet.balance;

        vm.prank(devWallet);
        freshNft.withdraw(address(0), 0);

        assertEq(address(freshNft).balance, 0);
        assertEq(devWallet.balance, ownerBalanceBefore + contractBalance);
    }

    function test_withdraw_specificAmount() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        vm.prank(player1);
        nft.mintPublic{value: MINT_PRICE * 5}(player1, 5);

        uint256 contractBalanceBefore = address(nft).balance;
        uint256 withdrawAmount = MINT_PRICE * 2;
        uint256 player2BalanceBefore = player2.balance;

        vm.prank(owner);
        nft.withdraw(player2, withdrawAmount);

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
    //                    PAUSE (3)
    // =============================================================

    function test_pause_blocksMinting() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        vm.prank(owner);
        nft.pause();

        vm.prank(player1);
        vm.expectRevert(DealersExeNFT.ContractPaused.selector);
        nft.mintPublic{value: MINT_PRICE}(player1, 1);
    }

    function test_pause_allowsReserve() public {
        vm.prank(owner);
        nft.pause();

        uint256 balanceBefore = nft.balanceOf(owner);

        vm.prank(owner);
        nft.reserve(1);

        assertEq(nft.balanceOf(owner), balanceBefore + 1);
    }

    function test_unpause_resumesMinting() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        vm.prank(owner);
        nft.pause();

        vm.prank(owner);
        nft.unpause();

        uint256 balanceBefore = nft.balanceOf(player1);

        vm.prank(player1);
        nft.mintPublic{value: MINT_PRICE}(player1, 1);

        assertEq(nft.balanceOf(player1), balanceBefore + 1);
    }

    // =============================================================
    //                    ADMIN (3)
    // =============================================================

    function test_setDealersExeCore_updates() public {
        address newCore = makeAddr("newCore");

        vm.prank(owner);
        nft.setDealersExeCore(newCore);

        assertEq(nft.dealersExeCore(), newCore);
    }

    function test_setFamilyMerkleRoot_updates() public {
        bytes32 newRoot = bytes32(uint256(123));

        vm.prank(owner);
        nft.setFamilyMerkleRoot(newRoot);

        assertEq(nft.familyMerkleRoot(), newRoot);
    }

    function test_setWhitelistMerkleRoot_updates() public {
        bytes32 newRoot = bytes32(uint256(456));

        vm.prank(owner);
        nft.setWhitelistMerkleRoot(newRoot);

        assertEq(nft.whitelistMerkleRoot(), newRoot);
    }

    // =============================================================
    //                    CLAIM TRACKING (2)
    // =============================================================

    function test_getFamilyClaimed_tracksCorrectly() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.FAMILY);

        bytes32[] memory proof = _getFamilyProofForPlayer1();

        assertEq(nft.getFamilyClaimed(player1), 0);

        vm.prank(player1);
        nft.mintFamily(2, PLAYER1_FAMILY_ALLOCATION, proof);

        assertEq(nft.getFamilyClaimed(player1), 2);
    }

    function test_getWhitelistClaimed_tracksCorrectly() public {
        vm.prank(owner);
        nft.setMintStatus(DealersExeNFT.MintStatus.WHITELIST);

        bytes32[] memory proof = _getWhitelistProofForPlayer1();

        assertEq(nft.getWhitelistClaimed(player1), 0);

        vm.prank(player1);
        nft.mintWhitelist{value: MINT_PRICE * 3}(3, PLAYER1_WHITELIST_ALLOCATION, proof);

        assertEq(nft.getWhitelistClaimed(player1), 3);
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

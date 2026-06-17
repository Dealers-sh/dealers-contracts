// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";

contract DealersNFTTest is BaseTest {
    uint256 internal constant MINT_PRICE = 0.01 ether;

    function setUp() public override {
        super.setUp();
        vm.prank(owner);
        nft.setMintOpen(true);
    }

    function _roll(uint256 delta) internal {
        vm.roll(block.number + delta);
    }

    function _mintOne(address to) internal returns (uint256 tokenId) {
        tokenId = nft.currentTokenId();
        vm.prank(to);
        nft.mint{value: MINT_PRICE}(to, 1);
    }

    function _mintAndReveal(address to) internal returns (uint256 tokenId) {
        tokenId = _mintOne(to);
        _roll(uint256(nft.REVEAL_DELAY()) + 1);
        nft.resolve(tokenId);
    }

    // =============================================================
    //                    MINT GATING
    // =============================================================

    function test_mint_revertWhenClosed() public {
        vm.prank(owner);
        nft.setMintOpen(false);

        vm.prank(player1);
        vm.expectRevert(DealersNFT.MintNotOpen.selector);
        nft.mint{value: MINT_PRICE}(player1, 1);
    }

    function test_setMintOpen_togglesAndEmits() public {
        vm.prank(owner);
        nft.setMintOpen(false);
        assertFalse(nft.mintOpen());

        vm.expectEmit(false, false, false, true);
        emit DealersNFT.MintOpenChanged(true);
        vm.prank(owner);
        nft.setMintOpen(true);
        assertTrue(nft.mintOpen());
    }

    function test_getMintConfig_reportsOpen() public view {
        (bool open, uint256 price, uint256 maxPerWallet,, uint256 maxSupply) = nft.getMintConfig();
        assertTrue(open);
        assertEq(price, MINT_PRICE);
        assertEq(maxPerWallet, nft.MAX_PER_WALLET());
        assertEq(maxSupply, nft.MAX_SUPPLY());
    }

    // =============================================================
    //                    MINT / COMMIT
    // =============================================================

    function test_mint_mintsAndLeavesArtPending() public {
        uint256 tokenId = nft.currentTokenId();

        vm.prank(player1);
        nft.mint{value: MINT_PRICE}(player1, 1);

        assertEq(nft.ownerOf(tokenId), player1);
        assertEq(nft.tokenToPool(tokenId), 0, "art should be unrevealed at mint");
        assertEq(nft.revealBlockOf(tokenId), uint64(block.number) + nft.REVEAL_DELAY());
    }

    function test_mint_initializesDealerAtCommit() public {
        uint256 tokenId = nft.currentTokenId();

        vm.prank(player1);
        nft.mint{value: MINT_PRICE}(player1, 1);

        (uint8 currentArea, uint256 reputation,, uint8 heatLevel,, bool isInitialized) = core.getDealerData(tokenId);
        assertTrue(isInitialized, "gameplay must be live at commit");
        assertEq(currentArea, core.STARTING_AREA());
        assertEq(reputation, core.STARTING_REPUTATION());
        assertEq(heatLevel, 0);
    }

    function test_mint_emitsCommitAndInitialized() public {
        uint256 tokenId = nft.currentTokenId();
        uint64 expectedRevealBlock = uint64(block.number) + nft.REVEAL_DELAY();

        vm.expectEmit(true, true, false, true);
        emit DealersNFT.MintCommitted(tokenId, player1, expectedRevealBlock);
        vm.expectEmit(true, true, false, false);
        emit DealersNFT.DealerInitialized(tokenId, player1);

        vm.prank(player1);
        nft.mint{value: MINT_PRICE}(player1, 1);
    }

    function test_mint_revertInsufficientETH() public {
        vm.prank(player1);
        vm.expectRevert(DealersNFT.InsufficientETH.selector);
        nft.mint{value: MINT_PRICE - 1}(player1, 1);
    }

    function test_mint_refundsExcess() public {
        uint256 ethBefore = player1.balance;
        uint256 overpay = 0.1 ether;

        vm.prank(player1);
        nft.mint{value: MINT_PRICE + overpay}(player1, 1);

        assertEq(player1.balance, ethBefore - MINT_PRICE);
    }

    function test_mint_revertExceedsPerWallet() public {
        uint256 maxPerWallet = nft.MAX_PER_WALLET();
        vm.prank(player1);
        vm.expectRevert(DealersNFT.InvalidMint.selector);
        nft.mint{value: MINT_PRICE * (maxPerWallet + 1)}(player1, maxPerWallet + 1);
    }

    function test_mint_revertWhenPaused() public {
        vm.prank(owner);
        nft.pause();

        vm.prank(player1);
        vm.expectRevert(DealersNFT.ContractPaused.selector);
        nft.mint{value: MINT_PRICE}(player1, 1);
    }

    function test_mint_revertTotalSupplyReached() public {
        uint256 maxSupply = nft.MAX_SUPPLY();
        // slot 10 packs: mintOpen (byte 0) | paused (byte 1) | totalMinted (bytes 2-5)
        uint256 packed = uint256(1) | (maxSupply << 16); // keep mintOpen=true, totalMinted=maxSupply
        vm.store(address(nft), bytes32(uint256(10)), bytes32(packed));

        assertEq(nft.totalMinted(), maxSupply);
        assertTrue(nft.mintOpen());

        vm.prank(player1);
        vm.expectRevert(DealersNFT.TotalSupplyReached.selector);
        nft.mint{value: MINT_PRICE}(player1, 1);
    }

    // =============================================================
    //                    RESERVE (commit path)
    // =============================================================

    function test_reserve_mintsAndCommits() public {
        uint256 tokenId = nft.currentTokenId();

        vm.prank(owner);
        nft.reserve(2);

        assertEq(nft.balanceOf(owner), 2);
        assertEq(nft.tokenToPool(tokenId), 0);
        assertGt(nft.revealBlockOf(tokenId), 0);
    }

    function test_reserveTo_mintsToRecipient() public {
        vm.prank(owner);
        nft.reserveTo(3, player1);
        assertEq(nft.balanceOf(player1), 3);
    }

    function test_reserveToMany_mintsToBatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = player1;
        recipients[1] = player2;

        vm.prank(owner);
        nft.reserveToMany(2, recipients);

        assertEq(nft.balanceOf(player1), 2);
        assertEq(nft.balanceOf(player2), 2);
    }

    function test_pause_allowsReserve() public {
        vm.prank(owner);
        nft.pause();

        vm.prank(owner);
        nft.reserve(1);
        assertEq(nft.balanceOf(owner), 1);
    }

    // =============================================================
    //                    REVEAL / RESOLVE
    // =============================================================

    function test_resolve_revertTooEarly() public {
        uint256 tokenId = _mintOne(player1);

        vm.expectRevert(DealersNFT.TooEarly.selector);
        nft.resolve(tokenId);

        _roll(uint256(nft.REVEAL_DELAY())); // now block == revealBlock, still too early
        vm.expectRevert(DealersNFT.TooEarly.selector);
        nft.resolve(tokenId);
    }

    function test_resolve_revertTokenDoesNotExist() public {
        vm.expectRevert(DealersNFT.TokenDoesNotExist.selector);
        nft.resolve(99999);
    }

    function test_resolve_assignsPoolIndex() public {
        uint256 tokenId = _mintOne(player1);
        _roll(uint256(nft.REVEAL_DELAY()) + 1);

        nft.resolve(tokenId);

        uint32 poolIndex = nft.tokenToPool(tokenId);
        assertGt(poolIndex, 0, "must be revealed");
        assertLe(poolIndex, uint32(nft.MAX_SUPPLY()));
        assertEq(nft.revealBlockOf(tokenId), 0, "anchor cleared on reveal");
    }

    function test_resolve_emitsRevealedAndMetadataUpdate() public {
        uint256 tokenId = _mintOne(player1);
        _roll(uint256(nft.REVEAL_DELAY()) + 1);

        vm.recordLogs();
        nft.resolve(tokenId);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawRevealed;
        bool sawMetadata;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == DealersNFT.DealerRevealed.selector) sawRevealed = true;
            if (logs[i].topics[0] == DealersNFT.BatchMetadataUpdate.selector) sawMetadata = true;
        }
        assertTrue(sawRevealed, "DealerRevealed not emitted");
        assertTrue(sawMetadata, "BatchMetadataUpdate not emitted");
    }

    function test_resolve_revertAlreadyRevealed() public {
        uint256 tokenId = _mintAndReveal(player1);

        vm.expectRevert(DealersNFT.AlreadyRevealed.selector);
        nft.resolve(tokenId);
    }

    function test_resolve_permissionlessByAnyCaller() public {
        uint256 tokenId = _mintOne(player1);
        _roll(uint256(nft.REVEAL_DELAY()) + 1);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        nft.resolve(tokenId);

        assertGt(nft.tokenToPool(tokenId), 0);
    }

    function test_resolve_outcomeIndependentOfCaller() public {
        // Two identical fresh collections (no core), same block, same tokenId:
        // resolved by different callers must yield the same pool index.
        DealersNFT a = new DealersNFT(devWallet);
        DealersNFT b = new DealersNFT(devWallet);
        a.setMintOpen(true);
        b.setMintOpen(true);

        uint256 tokenId = 1;
        vm.prank(player1);
        a.mint{value: MINT_PRICE}(player1, 1);
        vm.prank(player1);
        b.mint{value: MINT_PRICE}(player1, 1);

        _roll(uint256(a.REVEAL_DELAY()) + 1);

        vm.prank(player1);
        a.resolve(tokenId);
        vm.prank(player2);
        b.resolve(tokenId);

        assertEq(a.tokenToPool(tokenId), b.tokenToPool(tokenId), "caller changed the outcome");
    }

    function test_resolve_reanchorsWhenBlockhashStale() public {
        uint256 tokenId = _mintOne(player1);
        uint64 originalAnchor = nft.revealBlockOf(tokenId);

        _roll(300); // blockhash(originalAnchor) now unavailable

        vm.expectEmit(true, false, false, false);
        emit DealersNFT.RevealReAnchored(tokenId, 0);
        nft.resolve(tokenId);

        assertEq(nft.tokenToPool(tokenId), 0, "must stay unrevealed after re-anchor");
        uint64 newAnchor = nft.revealBlockOf(tokenId);
        assertGt(newAnchor, originalAnchor);
        assertEq(newAnchor, uint64(block.number) + nft.REVEAL_DELAY());

        _roll(uint256(nft.REVEAL_DELAY()) + 1);
        nft.resolve(tokenId);
        assertGt(nft.tokenToPool(tokenId), 0, "reveal succeeds after re-anchor");
    }

    // =============================================================
    //                    POOL DRAW
    // =============================================================

    function test_pool_drawsAreUnique() public {
        uint256 count = nft.MAX_PER_WALLET();
        uint256 first = nft.currentTokenId();

        vm.prank(player1);
        nft.mint{value: MINT_PRICE * count}(player1, count);

        _roll(uint256(nft.REVEAL_DELAY()) + 1);

        uint256[] memory ids = new uint256[](count);
        for (uint256 i; i < count; i++) {
            ids[i] = first + i;
        }
        nft.resolveMany(ids);

        for (uint256 i; i < count; i++) {
            uint32 pi = nft.tokenToPool(ids[i]);
            assertGt(pi, 0);
            assertLe(pi, uint32(nft.MAX_SUPPLY()));
            for (uint256 j = i + 1; j < count; j++) {
                assertTrue(pi != nft.tokenToPool(ids[j]), "pool index collision");
            }
        }
    }

    function test_pool_remainingDecrements() public {
        uint32 before = nft.poolRemaining();
        _mintAndReveal(player1);
        assertEq(nft.poolRemaining(), before - 1);
    }

    // =============================================================
    //                    RESOLVE MANY
    // =============================================================

    function test_resolveMany_skipsTooEarlyAndAlreadyRevealed() public {
        uint256 revealedId = _mintAndReveal(player1);
        uint256 pendingId = _mintOne(player1); // fresh, too early

        uint256[] memory ids = new uint256[](3);
        ids[0] = revealedId; // already revealed -> skip
        ids[1] = pendingId; // too early -> skip
        ids[2] = 99999; // nonexistent -> skip

        nft.resolveMany(ids); // must not revert

        assertEq(nft.tokenToPool(pendingId), 0, "too-early token untouched");
    }

    // =============================================================
    //                    VIEWS
    // =============================================================

    function test_isRevealable_lifecycle() public {
        uint256 tokenId = _mintOne(player1);
        assertFalse(nft.isRevealable(tokenId), "not revealable before anchor");

        _roll(uint256(nft.REVEAL_DELAY()) + 1);
        assertTrue(nft.isRevealable(tokenId), "revealable after anchor");

        nft.resolve(tokenId);
        assertFalse(nft.isRevealable(tokenId), "not revealable after reveal");
    }

    function test_pendingTokensOf_filtersRevealed() public {
        uint256 t1 = _mintOne(player1);
        uint256 t2 = _mintOne(player1);
        _roll(uint256(nft.REVEAL_DELAY()) + 1);
        nft.resolve(t1);

        uint256[] memory pending = nft.pendingTokensOf(player1);
        assertEq(pending.length, 1);
        assertEq(pending[0], t2);
    }

    // =============================================================
    //                    METADATA
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

    function test_tokenJson_includesDynamicTraits() public {
        uint256 tokenId = _mintAndInitialize(player1);
        string memory json = nft.tokenJson(tokenId);

        assertTrue(_containsSubstring(json, '"name":"Dealer #'));
        assertTrue(_containsSubstring(json, '"trait_type":"Rank"'));
        assertTrue(_containsSubstring(json, '"trait_type":"Area"'));
        assertTrue(_containsSubstring(json, '"trait_type":"Heat"'));
    }

    function test_tokenURI_revertTokenDoesNotExist() public {
        vm.expectRevert(DealersNFT.TokenDoesNotExist.selector);
        nft.tokenURI(99999);
    }

    // =============================================================
    //                    PAYMENT / ADMIN
    // =============================================================

    function test_withdraw_allToOwner() public {
        DealersNFT freshNft = new DealersNFT(devWallet);
        freshNft.setMintOpen(true);
        freshNft.transferOwnership(devWallet);

        vm.prank(player1);
        freshNft.mint{value: MINT_PRICE * 5}(player1, 5);

        uint256 contractBalance = address(freshNft).balance;
        assertGt(contractBalance, 0);
        uint256 ownerBalanceBefore = devWallet.balance;

        vm.prank(devWallet);
        freshNft.withdraw(address(0), 0);

        assertEq(address(freshNft).balance, 0);
        assertEq(devWallet.balance, ownerBalanceBefore + contractBalance);
    }

    function test_setDealersCore_updates() public {
        address newCore = makeAddr("newCore");
        vm.prank(owner);
        nft.setDealersCore(newCore);
        assertEq(nft.dealersCore(), newCore);
    }

    function test_pause_unpause_resumesMinting() public {
        vm.prank(owner);
        nft.pause();
        vm.prank(owner);
        nft.unpause();

        vm.prank(player1);
        nft.mint{value: MINT_PRICE}(player1, 1);
        assertEq(nft.balanceOf(player1), 1);
    }

    // =============================================================
    //                    ROYALTY
    // =============================================================

    function test_royaltyInfo_returns5Percent() public view {
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(1, 1 ether);
        assertEq(receiver, devWallet);
        assertEq(royaltyAmount, 0.05 ether);
    }

    function test_setRoyaltyReceiver_changes() public {
        address newReceiver = makeAddr("newRoyaltyReceiver");
        vm.prank(owner);
        nft.setRoyaltyReceiver(newReceiver);
        (address receiver,) = nft.royaltyInfo(1, 1 ether);
        assertEq(receiver, newReceiver);
    }

    // =============================================================
    //                    HELPERS
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../integration/BaseTest.sol";

contract DealersExeBoostsTest is BaseTest {
    event BoostPurchased(
        uint256 indexed dealerId,
        uint256 indexed tierId,
        address indexed buyer,
        uint64 expiresAt
    );

    event BoostTierUpdated(
        uint256 indexed tierId,
        uint256 price,
        uint64 duration,
        bool isActive
    );

    event BoostTierActiveStatusChanged(uint256 indexed tierId, bool isActive);

    uint256 constant GRINDER_TIER = 1;
    uint256 constant HUSTLER_TIER = 2;
    uint256 constant KINGPIN_TIER = 3;

    uint256 constant GRINDER_PRICE = 0.0025 ether;
    uint256 constant HUSTLER_PRICE = 0.005 ether;
    uint256 constant KINGPIN_PRICE = 0.01 ether;

    uint64 constant DURATION_3_DAYS = 3 days;
    uint64 constant DURATION_7_DAYS = 7 days;

    uint256 public dealer1;
    uint256 public dealer2;
    uint256 public dealer3;

    function setUp() public override {
        super.setUp();
        dealer1 = _mintNFT(player1);
        dealer2 = _mintNFT(player1);
        dealer3 = _mintNFT(player2);
    }

    // =============================================================
    //                   DEFAULT TIER CONFIGURATION
    // =============================================================

    function test_defaultTiers_grinderConfig() public view {
        DealersExeBoosts.BoostTier memory tier = boosts.getBoostTier(GRINDER_TIER);

        assertEq(tier.price, GRINDER_PRICE);
        assertEq(tier.duration, DURATION_3_DAYS);
        assertEq(tier.drugMultiplier, 125);  // 1.25x
        assertEq(tier.repMultiplier, 125);   // 1.25x
        assertEq(tier.extraAttempts, 3);
        assertEq(tier.cashMultiplier, 125);  // 1.25x
        assertFalse(tier.freeAreaMovement);
        assertFalse(tier.doubleHeistEntries);
        assertTrue(tier.isActive);
    }

    function test_defaultTiers_hustlerConfig() public view {
        DealersExeBoosts.BoostTier memory tier = boosts.getBoostTier(HUSTLER_TIER);

        assertEq(tier.price, HUSTLER_PRICE);
        assertEq(tier.duration, DURATION_7_DAYS);
        assertEq(tier.drugMultiplier, 150);  // 1.5x
        assertEq(tier.repMultiplier, 150);   // 1.5x
        assertEq(tier.extraAttempts, 5);
        assertEq(tier.cashMultiplier, 150);  // 1.5x
        assertFalse(tier.freeAreaMovement);
        assertFalse(tier.doubleHeistEntries);
        assertTrue(tier.isActive);
    }

    function test_defaultTiers_kingpinConfig() public view {
        DealersExeBoosts.BoostTier memory tier = boosts.getBoostTier(KINGPIN_TIER);

        assertEq(tier.price, KINGPIN_PRICE);
        assertEq(tier.duration, 30 days);    // Kingpin is 30 days
        assertEq(tier.drugMultiplier, 175);  // 1.75x
        assertEq(tier.repMultiplier, 200);   // 2x
        assertEq(tier.extraAttempts, 10);
        assertEq(tier.cashMultiplier, 175);  // 1.75x
        assertTrue(tier.freeAreaMovement);
        assertTrue(tier.doubleHeistEntries);
        assertTrue(tier.isActive);
    }

    // =============================================================
    //                      SINGLE PURCHASE
    // =============================================================

    function test_purchaseBoost_appliesBoost() public {
        vm.prank(player1);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);

        assertTrue(core.hasActiveBoost(dealer1));

        DealersExeCore.BoostData memory boost = core.getBoost(dealer1);
        assertEq(boost.drugMultiplier, 125);  // 1.25x
        assertEq(boost.repMultiplier, 125);   // 1.25x
        assertEq(boost.extraAttempts, 3);
        assertEq(boost.cashMultiplier, 125);  // 1.25x
        assertFalse(boost.freeAreaMovement);
        assertFalse(boost.doubleHeistEntries);
        assertEq(boost.expiresAt, uint64(block.timestamp + DURATION_3_DAYS));
    }

    function test_purchaseBoost_revertsWhenActiveBoost() public {
        vm.startPrank(player1);

        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
        assertTrue(core.hasActiveBoost(dealer1));

        vm.expectRevert(DealersExeBoosts.BoostAlreadyActive.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);

        vm.stopPrank();
    }

    function test_purchaseBoost_allowedAfterExpiry() public {
        vm.startPrank(player1);

        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
        uint64 firstExpiry = core.getBoost(dealer1).expiresAt;

        vm.warp(block.timestamp + DURATION_3_DAYS + 1);
        assertFalse(core.hasActiveBoost(dealer1));

        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
        uint64 secondExpiry = core.getBoost(dealer1).expiresAt;

        vm.stopPrank();

        assertGt(secondExpiry, firstExpiry);
    }

    function test_purchaseBoost_revertInsufficientPayment() public {
        vm.prank(player1);
        vm.expectRevert(DealersExeBoosts.InsufficientPayment.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE - 1}(dealer1, GRINDER_TIER);
    }

    function test_purchaseBoost_refundsExcess() public {
        uint256 excessAmount = 0.05 ether;
        uint256 balanceBefore = player1.balance;

        vm.prank(player1);
        boosts.purchaseBoost{value: GRINDER_PRICE + excessAmount}(dealer1, GRINDER_TIER);

        uint256 balanceAfter = player1.balance;
        assertEq(balanceBefore - balanceAfter, GRINDER_PRICE);
    }

    function test_purchaseBoost_anyoneCanGift() public {
        vm.prank(player2);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
        assertTrue(core.hasActiveBoost(dealer1));
    }

    function test_purchaseBoost_revertInvalidTier() public {
        vm.startPrank(player1);

        vm.expectRevert(DealersExeBoosts.InvalidTier.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, 0);

        vm.expectRevert(DealersExeBoosts.InvalidTier.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, 99);

        vm.stopPrank();
    }

    function test_purchaseBoost_revertTierNotActive() public {
        boosts.setTierActive(GRINDER_TIER, false);

        vm.prank(player1);
        vm.expectRevert(DealersExeBoosts.TierNotActive.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
    }

    // =============================================================
    //                      BATCH PURCHASE
    // =============================================================

    function test_purchaseBoostBatch_appliesAll() public {
        uint256[] memory dealerIds = new uint256[](2);
        dealerIds[0] = dealer1;
        dealerIds[1] = dealer2;

        uint256 totalCost = GRINDER_PRICE * 2;

        vm.prank(player1);
        boosts.purchaseBoostBatch{value: totalCost}(dealerIds, GRINDER_TIER);

        assertTrue(core.hasActiveBoost(dealer1));
        assertTrue(core.hasActiveBoost(dealer2));
    }

    function test_purchaseBoostBatch_skipsNonOwned() public {
        uint256[] memory dealerIds = new uint256[](2);
        dealerIds[0] = dealer1;
        dealerIds[1] = dealer3;

        uint256 totalCost = GRINDER_PRICE * 2;

        vm.prank(player1);
        boosts.purchaseBoostBatch{value: totalCost}(dealerIds, GRINDER_TIER);

        assertTrue(core.hasActiveBoost(dealer1));
        assertFalse(core.hasActiveBoost(dealer3));
    }

    function test_purchaseBoostBatch_skipsDuplicates() public {
        uint256[] memory dealerIds = new uint256[](2);
        dealerIds[0] = dealer1;
        dealerIds[1] = dealer1;

        uint256 totalCost = GRINDER_PRICE * 2;
        uint256 balanceBefore = player1.balance;

        vm.prank(player1);
        boosts.purchaseBoostBatch{value: totalCost}(dealerIds, GRINDER_TIER);

        assertTrue(core.hasActiveBoost(dealer1));
        DealersExeCore.BoostData memory boost = core.getBoost(dealer1);
        assertEq(boost.expiresAt, uint64(block.timestamp + DURATION_3_DAYS));
        assertEq(balanceBefore - player1.balance, GRINDER_PRICE);
    }

    function test_purchaseBoostBatch_refundsForSkipped() public {
        uint256[] memory dealerIds = new uint256[](2);
        dealerIds[0] = dealer1;
        dealerIds[1] = dealer3;

        uint256 totalCost = GRINDER_PRICE * 2;
        uint256 balanceBefore = player1.balance;

        vm.prank(player1);
        boosts.purchaseBoostBatch{value: totalCost}(dealerIds, GRINDER_TIER);

        uint256 balanceAfter = player1.balance;
        assertEq(balanceBefore - balanceAfter, GRINDER_PRICE);
    }

    function test_purchaseBoostBatch_revertEmptyBatch() public {
        uint256[] memory dealerIds = new uint256[](0);

        vm.prank(player1);
        vm.expectRevert(DealersExeBoosts.EmptyBatch.selector);
        boosts.purchaseBoostBatch{value: GRINDER_PRICE}(dealerIds, GRINDER_TIER);
    }

    // =============================================================
    //                     PAYMENT
    // =============================================================

    function test_purchaseBoost_sendsToPaymentHandler() public {
        uint256 handlerBalanceBefore = address(paymentHandler).balance;
        uint256 bankBalanceBefore = bankVault.balance;

        vm.prank(player1);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);

        uint256 handlerBalanceAfter = address(paymentHandler).balance;
        uint256 bankBalanceAfter = bankVault.balance;

        // Marketplace fee split: 20% to bank vault, 80% to dev wallet (held in handler)
        uint256 bankFee = (GRINDER_PRICE * 2000) / 10000;  // 20% to bank
        uint256 devFee = (GRINDER_PRICE * 8000) / 10000;   // 80% to dev (pending in handler)

        assertEq(handlerBalanceAfter - handlerBalanceBefore, devFee);
        assertEq(bankBalanceAfter - bankBalanceBefore, bankFee);
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function test_getBoostTier_returnsCorrect() public view {
        DealersExeBoosts.BoostTier memory tier = boosts.getBoostTier(GRINDER_TIER);

        assertEq(tier.price, GRINDER_PRICE);
        assertEq(tier.duration, DURATION_3_DAYS);
    }

    function test_getActiveTiers_filtersInactive() public {
        boosts.setTierActive(GRINDER_TIER, false);

        (DealersExeBoosts.BoostTier[] memory tiers, uint256[] memory tierIds) = boosts.getActiveTiers();

        assertEq(tiers.length, 2);
        assertEq(tierIds.length, 2);
        assertEq(tierIds[0], HUSTLER_TIER);
        assertEq(tierIds[1], KINGPIN_TIER);
    }

    function test_checkBoostStatus_returnsExpiry() public {
        (bool hasBoostBefore, uint64 expiryBefore) = boosts.checkBoostStatus(dealer1);
        assertFalse(hasBoostBefore);
        assertEq(expiryBefore, 0);

        vm.prank(player1);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);

        (bool hasBoostAfter, uint64 expiryAfter) = boosts.checkBoostStatus(dealer1);
        assertTrue(hasBoostAfter);
        assertEq(expiryAfter, uint64(block.timestamp + DURATION_3_DAYS));

        vm.warp(block.timestamp + DURATION_3_DAYS + 1);

        (bool hasBoostExpired,) = boosts.checkBoostStatus(dealer1);
        assertFalse(hasBoostExpired);
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    function test_setBoostTier_createsNew() public {
        DealersExeBoosts.BoostTier memory newTier = DealersExeBoosts.BoostTier({
            price: 0.5 ether,
            duration: 60 days,
            drugMultiplier: 250,
            repMultiplier: 250,
            extraAttempts: 15,
            freeAreaMovement: true,
            doubleHeistEntries: true,
            cashMultiplier: 250,
            isActive: true
        });

        uint256 tiersBefore = boosts.totalTiers();

        boosts.setBoostTier(tiersBefore + 1, newTier);

        assertEq(boosts.totalTiers(), tiersBefore + 1);

        DealersExeBoosts.BoostTier memory storedTier = boosts.getBoostTier(tiersBefore + 1);
        assertEq(storedTier.price, 0.5 ether);
        assertEq(storedTier.duration, 60 days);
        assertEq(storedTier.drugMultiplier, 250);
    }

    function test_setBoostTier_updatesExisting() public {
        DealersExeBoosts.BoostTier memory updatedTier = DealersExeBoosts.BoostTier({
            price: 0.02 ether,
            duration: 48 hours,
            drugMultiplier: 250,
            repMultiplier: 175,
            extraAttempts: 5,
            freeAreaMovement: false,
            doubleHeistEntries: false,
            cashMultiplier: 175,
            isActive: true
        });

        boosts.setBoostTier(GRINDER_TIER, updatedTier);

        DealersExeBoosts.BoostTier memory storedTier = boosts.getBoostTier(GRINDER_TIER);
        assertEq(storedTier.price, 0.02 ether);
        assertEq(storedTier.duration, 48 hours);
        assertEq(storedTier.drugMultiplier, 250);
        assertEq(storedTier.repMultiplier, 175);
    }

    function test_setTierActive_toggles() public {
        assertTrue(boosts.getBoostTier(GRINDER_TIER).isActive);

        boosts.setTierActive(GRINDER_TIER, false);
        assertFalse(boosts.getBoostTier(GRINDER_TIER).isActive);

        boosts.setTierActive(GRINDER_TIER, true);
        assertTrue(boosts.getBoostTier(GRINDER_TIER).isActive);
    }

    function test_emergencyWithdraw_works() public {
        vm.deal(address(boosts), 1 ether);

        address recipient = makeAddr("recipient");
        uint256 recipientBalanceBefore = recipient.balance;
        boosts.emergencyWithdraw(recipient, 0.5 ether);
        uint256 recipientBalanceAfter = recipient.balance;

        assertEq(recipientBalanceAfter - recipientBalanceBefore, 0.5 ether);
        assertEq(address(boosts).balance, 0.5 ether);
    }

    // =============================================================
    //                      PAUSE FUNCTIONALITY
    // =============================================================

    function test_pause_preventsBoostPurchase() public {
        boosts.pause();
        assertTrue(boosts.paused());

        vm.prank(player1);
        vm.expectRevert(DealersExeBoosts.ContractPaused.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
    }

    function test_pause_preventsBoostBatchPurchase() public {
        boosts.pause();

        uint256[] memory dealerIds = new uint256[](2);
        dealerIds[0] = dealer1;
        dealerIds[1] = dealer2;

        vm.prank(player1);
        vm.expectRevert(DealersExeBoosts.ContractPaused.selector);
        boosts.purchaseBoostBatch{value: GRINDER_PRICE * 2}(dealerIds, GRINDER_TIER);
    }

    function test_unpause_allowsBoostPurchase() public {
        boosts.pause();
        assertTrue(boosts.paused());

        boosts.unpause();
        assertFalse(boosts.paused());

        vm.prank(player1);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);

        assertTrue(core.hasActiveBoost(dealer1));
    }

    function test_pause_onlyOwner() public {
        vm.prank(player1);
        vm.expectRevert();
        boosts.pause();
    }

    function test_unpause_onlyOwner() public {
        boosts.pause();

        vm.prank(player1);
        vm.expectRevert();
        boosts.unpause();
    }
}

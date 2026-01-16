// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
        string name,
        uint256 price,
        uint64 duration,
        bool isActive
    );

    event BoostTierActiveStatusChanged(uint256 indexed tierId, bool isActive);

    uint256 constant GRINDER_TIER = 1;
    uint256 constant HUSTLER_TIER = 2;
    uint256 constant KINGPIN_TIER = 3;

    uint256 constant GRINDER_PRICE = 0.01 ether;
    uint256 constant HUSTLER_PRICE = 0.05 ether;
    uint256 constant KINGPIN_PRICE = 0.15 ether;

    uint64 constant DURATION_24_HOURS = 24 hours;
    uint64 constant DURATION_7_DAYS = 7 days;
    uint64 constant DURATION_30_DAYS = 30 days;

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
        assertEq(tier.duration, DURATION_24_HOURS);
        assertEq(tier.drugMultiplier, 200);
        assertEq(tier.repMultiplier, 150);
        assertEq(tier.extraAttempts, 3);
        assertEq(tier.cashMultiplier, 150);
        assertFalse(tier.freeAreaMovement);
        assertFalse(tier.doubleHeistEntries);
        assertTrue(tier.isActive);
    }

    function test_defaultTiers_hustlerConfig() public view {
        DealersExeBoosts.BoostTier memory tier = boosts.getBoostTier(HUSTLER_TIER);

        assertEq(tier.price, HUSTLER_PRICE);
        assertEq(tier.duration, DURATION_7_DAYS);
        assertEq(tier.drugMultiplier, 200);
        assertEq(tier.repMultiplier, 200);
        assertEq(tier.extraAttempts, 5);
        assertEq(tier.cashMultiplier, 175);
        assertFalse(tier.freeAreaMovement);
        assertFalse(tier.doubleHeistEntries);
        assertTrue(tier.isActive);
    }

    function test_defaultTiers_kingpinConfig() public view {
        DealersExeBoosts.BoostTier memory tier = boosts.getBoostTier(KINGPIN_TIER);

        assertEq(tier.price, KINGPIN_PRICE);
        assertEq(tier.duration, DURATION_30_DAYS);
        assertEq(tier.drugMultiplier, 200);
        assertEq(tier.repMultiplier, 200);
        assertEq(tier.extraAttempts, 10);
        assertEq(tier.cashMultiplier, 200);
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
        assertEq(boost.drugMultiplier, 200);
        assertEq(boost.repMultiplier, 150);
        assertEq(boost.extraAttempts, 3);
        assertEq(boost.cashMultiplier, 150);
        assertFalse(boost.freeAreaMovement);
        assertFalse(boost.doubleHeistEntries);
        assertEq(boost.expiresAt, uint64(block.timestamp + DURATION_24_HOURS));
    }

    function test_purchaseBoost_extendsExisting() public {
        vm.startPrank(player1);

        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
        uint64 firstExpiry = core.getBoost(dealer1).expiresAt;

        vm.warp(block.timestamp + 12 hours);

        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
        uint64 secondExpiry = core.getBoost(dealer1).expiresAt;

        vm.stopPrank();

        assertEq(secondExpiry, firstExpiry + DURATION_24_HOURS);
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

    function test_purchaseBoost_revertNotOwner() public {
        vm.prank(player2);
        vm.expectRevert(DealersExeBoosts.NotDealerOwner.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
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

    function test_purchaseBoostBatch_handlesDuplicates() public {
        uint256[] memory dealerIds = new uint256[](2);
        dealerIds[0] = dealer1;
        dealerIds[1] = dealer1;

        uint256 totalCost = GRINDER_PRICE * 2;

        vm.prank(player1);
        boosts.purchaseBoostBatch{value: totalCost}(dealerIds, GRINDER_TIER);

        assertTrue(core.hasActiveBoost(dealer1));
        DealersExeCore.BoostData memory boost = core.getBoost(dealer1);
        assertEq(boost.expiresAt, uint64(block.timestamp + DURATION_24_HOURS * 2));
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
    //                     PAYMENT & STATS
    // =============================================================

    function test_purchaseBoost_updatesStatistics() public {
        vm.prank(player1);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);

        assertEq(boosts.totalBoostsSold(), 1);
        assertEq(boosts.tierSalesCount(GRINDER_TIER), 1);
        assertEq(boosts.totalRevenue(), GRINDER_PRICE);

        vm.prank(player1);
        boosts.purchaseBoost{value: HUSTLER_PRICE}(dealer2, HUSTLER_TIER);

        assertEq(boosts.totalBoostsSold(), 2);
        assertEq(boosts.tierSalesCount(GRINDER_TIER), 1);
        assertEq(boosts.tierSalesCount(HUSTLER_TIER), 1);
        assertEq(boosts.totalRevenue(), GRINDER_PRICE + HUSTLER_PRICE);
    }

    function test_purchaseBoost_sendsToPaymentHandler() public {
        uint256 handlerBalanceBefore = address(paymentHandler).balance;
        uint256 bankBalanceBefore = bankVault.balance;

        vm.prank(player1);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);

        uint256 handlerBalanceAfter = address(paymentHandler).balance;
        uint256 bankBalanceAfter = bankVault.balance;

        uint256 bankFee = (GRINDER_PRICE * 500) / 10000;
        uint256 expectedHandlerIncrease = GRINDER_PRICE - bankFee;

        assertEq(handlerBalanceAfter - handlerBalanceBefore, expectedHandlerIncrease);
        assertEq(bankBalanceAfter - bankBalanceBefore, bankFee);
    }

    function test_getSalesStats_returnsCorrect() public {
        vm.startPrank(player1);
        boosts.purchaseBoost{value: GRINDER_PRICE}(dealer1, GRINDER_TIER);
        boosts.purchaseBoost{value: HUSTLER_PRICE}(dealer1, HUSTLER_TIER);
        vm.stopPrank();

        vm.prank(player2);
        boosts.purchaseBoost{value: KINGPIN_PRICE}(dealer3, KINGPIN_TIER);

        (
            uint256 sold,
            uint256 revenue,
            uint256 tier1Sales,
            uint256 tier2Sales,
            uint256 tier3Sales
        ) = boosts.getSalesStats();

        assertEq(sold, 3);
        assertEq(revenue, GRINDER_PRICE + HUSTLER_PRICE + KINGPIN_PRICE);
        assertEq(tier1Sales, 1);
        assertEq(tier2Sales, 1);
        assertEq(tier3Sales, 1);
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function test_getBoostTier_returnsCorrect() public view {
        DealersExeBoosts.BoostTier memory tier = boosts.getBoostTier(GRINDER_TIER);

        assertEq(keccak256(bytes(tier.name)), keccak256(bytes("Grinder")));
        assertEq(tier.price, GRINDER_PRICE);
        assertEq(tier.duration, DURATION_24_HOURS);
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
        assertEq(expiryAfter, uint64(block.timestamp + DURATION_24_HOURS));

        vm.warp(block.timestamp + DURATION_24_HOURS + 1);

        (bool hasBoostExpired,) = boosts.checkBoostStatus(dealer1);
        assertFalse(hasBoostExpired);
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    function test_setBoostTier_createsNew() public {
        DealersExeBoosts.BoostTier memory newTier = DealersExeBoosts.BoostTier({
            name: "Ultimate",
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
            name: "Grinder Plus",
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
}

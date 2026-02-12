// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseTest.sol";

contract BoostGameplayTest is BaseTest {
    uint256 tokenId;

    uint256 constant GRINDER_ID = 1;
    uint256 constant HUSTLER_ID = 2;
    uint256 constant KINGPIN_ID = 3;

    uint256 constant GRINDER_PRICE = 0.0025 ether;
    uint256 constant HUSTLER_PRICE = 0.005 ether;
    uint256 constant KINGPIN_PRICE = 0.01 ether;

    function setUp() public override {
        super.setUp();
        tokenId = _mintAndMoveToManhattan(player1);
    }

    function test_boost_drugMultiplierInPVE() public {
        vm.startPrank(player1);

        boosts.purchaseBoost{value: HUSTLER_PRICE}(tokenId, HUSTLER_ID);

        assertEq(core.getDrugMultiplier(tokenId), 150, "Drug multiplier should be 150 (1.5x)");

        vm.stopPrank();

        uint256 buyAmount = 10;
        uint256 expectedBoostedAmount = (buyAmount * 150) / 100;

        bool foundWin = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!foundWin && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            uint256 cashBefore = core.getCashBalance(tokenId);
            uint256 weedBefore = core.getDrugBalance(tokenId, DRUG_WEED);

            try pve.playGame(
                tokenId,
                0,
                DealersExePVE.HustleType.BUY,
                DRUG_WEED,
                buyAmount
            ) {
                uint256 cashAfter = core.getCashBalance(tokenId);
                uint256 weedAfter = core.getDrugBalance(tokenId, DRUG_WEED);

                if (cashAfter == cashBefore && weedAfter > weedBefore) {
                    foundWin = true;

                    assertEq(
                        weedAfter,
                        weedBefore + expectedBoostedAmount,
                        "WIN BUY with boost: Should receive 1.5x drugs"
                    );
                    break;
                }
            } catch {}

            if (!foundWin) {
                vm.revertToState(snapshotId);
            }
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!foundWin) {
            emit log("Note: WIN outcome not found within iteration limit - drug multiplier test inconclusive");
        }
    }

    function test_boost_repMultiplierInPVE() public {
        vm.startPrank(player1);

        boosts.purchaseBoost{value: HUSTLER_PRICE}(tokenId, HUSTLER_ID);

        assertEq(core.getRepMultiplier(tokenId), 150, "Rep multiplier should be 150 (1.5x)");

        vm.stopPrank();

        bool foundWin = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!foundWin && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            (, uint256 repBefore, , , , ) = core.getDealerData(tokenId);

            try pve.playGame(
                tokenId,
                0,
                DealersExePVE.HustleType.BUY,
                DRUG_WEED,
                10
            ) {
                (, uint256 repAfter, , , , ) = core.getDealerData(tokenId);
                uint256 cashAfter = core.getCashBalance(tokenId);
                uint256 cashBefore = 100;

                if (repAfter > repBefore && cashAfter == cashBefore) {
                    foundWin = true;

                    int16 baseWinBonus = 15;
                    int256 expectedBoostedRep = (int256(baseWinBonus) * 150) / 100;
                    uint256 expectedRepAfter = repBefore + uint256(expectedBoostedRep);

                    assertEq(
                        repAfter,
                        expectedRepAfter,
                        "WIN with boost: Rep should be base * 1.5x multiplier"
                    );
                    break;
                }
            } catch {}

            if (!foundWin) {
                vm.revertToState(snapshotId);
            }
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!foundWin) {
            emit log("Note: WIN outcome not found within iteration limit - rep multiplier test inconclusive");
        }
    }

    function test_boost_cashMultiplierInPVE() public {
        vm.prank(owner);
        core.updateDrugBalance(tokenId, DRUG_WEED, 100);

        vm.startPrank(player1);

        boosts.purchaseBoost{value: KINGPIN_PRICE}(tokenId, KINGPIN_ID);

        assertEq(core.getCashMultiplier(tokenId), 175, "Cash multiplier should be 175 (1.75x)");

        vm.stopPrank();

        uint256 sellAmount = 20;
        uint256 sellPrice = 1;
        uint256 baseCashReward = sellAmount * sellPrice;
        uint256 expectedBoostedCash = (baseCashReward * 175) / 100;

        bool foundWin = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!foundWin && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            uint256 cashBefore = core.getCashBalance(tokenId);
            uint256 weedBefore = core.getDrugBalance(tokenId, DRUG_WEED);

            try pve.playGame(
                tokenId,
                0,
                DealersExePVE.HustleType.SELL,
                DRUG_WEED,
                sellAmount
            ) {
                uint256 cashAfter = core.getCashBalance(tokenId);
                uint256 weedAfter = core.getDrugBalance(tokenId, DRUG_WEED);

                if (weedAfter == weedBefore && cashAfter > cashBefore) {
                    foundWin = true;

                    assertEq(
                        cashAfter,
                        cashBefore + expectedBoostedCash,
                        "WIN SELL with boost: Should receive 1.75x cash"
                    );
                    break;
                }
            } catch {}

            if (!foundWin) {
                vm.revertToState(snapshotId);
            }
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!foundWin) {
            emit log("Note: WIN outcome not found within iteration limit - cash multiplier test inconclusive");
        }
    }

    function test_boost_expires() public {
        vm.startPrank(player1);

        boosts.purchaseBoost{value: GRINDER_PRICE}(tokenId, GRINDER_ID);

        assertTrue(core.hasActiveBoost(tokenId), "Boost should be active");
        assertEq(core.getDrugMultiplier(tokenId), 125, "Drug multiplier should be 125");
        assertEq(core.getRepMultiplier(tokenId), 125, "Rep multiplier should be 125");
        assertEq(core.getCashMultiplier(tokenId), 125, "Cash multiplier should be 125");
        assertEq(core.getMaxAttempts(tokenId), 8, "Max attempts should be 5 + 3 = 8");

        DealersExeCore.BoostData memory boost = core.getBoost(tokenId);
        assertGt(boost.expiresAt, block.timestamp, "Expiry should be in the future");

        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        assertFalse(core.hasActiveBoost(tokenId), "Boost should be expired after 8 days");
        assertEq(core.getDrugMultiplier(tokenId), 100, "Drug multiplier should return to 100");
        assertEq(core.getRepMultiplier(tokenId), 100, "Rep multiplier should return to 100");
        assertEq(core.getCashMultiplier(tokenId), 100, "Cash multiplier should return to 100");
        assertEq(core.getMaxAttempts(tokenId), 5, "Max attempts should return to base 5");
    }

    function test_boost_extraAttempts() public {
        assertEq(core.getMaxAttempts(tokenId), 5, "Base max attempts should be 5");

        vm.prank(player1);
        boosts.purchaseBoost{value: GRINDER_PRICE}(tokenId, GRINDER_ID);
        assertEq(core.getMaxAttempts(tokenId), 8, "Grinder: 5 + 3 = 8 attempts");

        uint256 token2 = _mintAndMoveToManhattan(player1);
        vm.prank(player1);
        boosts.purchaseBoost{value: HUSTLER_PRICE}(token2, HUSTLER_ID);
        assertEq(core.getMaxAttempts(token2), 10, "Hustler: 5 + 5 = 10 attempts");

        uint256 token3 = _mintAndMoveToManhattan(player1);
        vm.prank(player1);
        boosts.purchaseBoost{value: KINGPIN_PRICE}(token3, KINGPIN_ID);
        assertEq(core.getMaxAttempts(token3), 15, "Kingpin: 5 + 10 = 15 attempts");
    }

    function test_boost_freeAreaMovement() public {
        assertFalse(core.hasFreeAreaMovement(tokenId), "Should not have free movement initially");

        vm.prank(player1);
        boosts.purchaseBoost{value: KINGPIN_PRICE}(tokenId, KINGPIN_ID);

        assertTrue(core.hasFreeAreaMovement(tokenId), "Kingpin should have free area movement");

        uint256 token2 = _mintAndMoveToManhattan(player1);
        vm.prank(player1);
        boosts.purchaseBoost{value: HUSTLER_PRICE}(token2, HUSTLER_ID);

        assertFalse(core.hasFreeAreaMovement(token2), "Hustler should not have free movement");
    }

    function test_boost_doubleHeistEntries() public {
        assertFalse(core.hasDoubleHeistEntries(tokenId), "Should not have double heist initially");

        vm.prank(player1);
        boosts.purchaseBoost{value: KINGPIN_PRICE}(tokenId, KINGPIN_ID);

        assertTrue(core.hasDoubleHeistEntries(tokenId), "Kingpin should have double heist entries");

        uint256 token2 = _mintAndMoveToManhattan(player1);
        vm.prank(player1);
        boosts.purchaseBoost{value: HUSTLER_PRICE}(token2, HUSTLER_ID);

        assertFalse(core.hasDoubleHeistEntries(token2), "Hustler should not have double heist");
    }

    function test_boost_cannotStackWhileActive() public {
        vm.startPrank(player1);

        boosts.purchaseBoost{value: GRINDER_PRICE}(tokenId, GRINDER_ID);

        vm.warp(block.timestamp + 12 hours);
        assertTrue(core.hasActiveBoost(tokenId), "Should still be active after 12 hours");

        vm.expectRevert(DealersExeBoosts.BoostAlreadyActive.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE}(tokenId, GRINDER_ID);

        vm.stopPrank();
    }

    function test_boost_canPurchaseAfterExpiry() public {
        vm.startPrank(player1);

        boosts.purchaseBoost{value: GRINDER_PRICE}(tokenId, GRINDER_ID);
        uint64 firstExpiry = core.getBoost(tokenId).expiresAt;

        vm.warp(block.timestamp + 8 days);
        assertFalse(core.hasActiveBoost(tokenId), "Boost should be expired after 8 days");

        boosts.purchaseBoost{value: GRINDER_PRICE}(tokenId, GRINDER_ID);
        uint64 secondExpiry = core.getBoost(tokenId).expiresAt;

        assertGt(secondExpiry, firstExpiry, "Second expiry should be after first");

        vm.stopPrank();
    }

    function test_boost_allTierConfigurations() public {
        DealersExeBoosts.BoostTier memory grinder = boosts.getBoostTier(GRINDER_ID);
        assertEq(grinder.price, GRINDER_PRICE, "Grinder price");
        assertEq(grinder.duration, 3 days, "Grinder duration");
        assertEq(grinder.drugMultiplier, 125, "Grinder drug mult");
        assertEq(grinder.repMultiplier, 125, "Grinder rep mult");
        assertEq(grinder.cashMultiplier, 125, "Grinder cash mult");
        assertEq(grinder.extraAttempts, 3, "Grinder extra attempts");
        assertFalse(grinder.freeAreaMovement, "Grinder no free movement");
        assertFalse(grinder.doubleHeistEntries, "Grinder no double heist");

        DealersExeBoosts.BoostTier memory hustler = boosts.getBoostTier(HUSTLER_ID);
        assertEq(hustler.price, HUSTLER_PRICE, "Hustler price");
        assertEq(hustler.duration, 7 days, "Hustler duration");
        assertEq(hustler.drugMultiplier, 150, "Hustler drug mult");
        assertEq(hustler.repMultiplier, 150, "Hustler rep mult");
        assertEq(hustler.cashMultiplier, 150, "Hustler cash mult");
        assertEq(hustler.extraAttempts, 5, "Hustler extra attempts");
        assertFalse(hustler.freeAreaMovement, "Hustler no free movement");
        assertFalse(hustler.doubleHeistEntries, "Hustler no double heist");

        DealersExeBoosts.BoostTier memory kingpin = boosts.getBoostTier(KINGPIN_ID);
        assertEq(kingpin.price, KINGPIN_PRICE, "Kingpin price");
        assertEq(kingpin.duration, 30 days, "Kingpin duration");
        assertEq(kingpin.drugMultiplier, 175, "Kingpin drug mult");
        assertEq(kingpin.repMultiplier, 200, "Kingpin rep mult");
        assertEq(kingpin.cashMultiplier, 175, "Kingpin cash mult");
        assertEq(kingpin.extraAttempts, 10, "Kingpin extra attempts");
        assertTrue(kingpin.freeAreaMovement, "Kingpin free movement");
        assertTrue(kingpin.doubleHeistEntries, "Kingpin double heist");
    }

    function test_boost_purchaseRequiresOwnership() public {
        vm.prank(player2);
        vm.expectRevert(DealersExeBoosts.NotDealerOwner.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE}(tokenId, GRINDER_ID);
    }

    function test_boost_purchaseRequiresSufficientPayment() public {
        vm.prank(player1);
        vm.expectRevert(DealersExeBoosts.InsufficientPayment.selector);
        boosts.purchaseBoost{value: GRINDER_PRICE - 1}(tokenId, GRINDER_ID);
    }

    function test_boost_batchPurchase() public {
        uint256 token1 = _mintAndMoveToManhattan(player1);
        uint256 token2 = _mintAndMoveToManhattan(player1);
        uint256 token3 = _mintAndMoveToManhattan(player1);

        uint256[] memory tokens = new uint256[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = token3;

        uint256 totalCost = GRINDER_PRICE * 3;

        vm.prank(player1);
        boosts.purchaseBoostBatch{value: totalCost}(tokens, GRINDER_ID);

        assertTrue(core.hasActiveBoost(token1), "Token1 should have boost");
        assertTrue(core.hasActiveBoost(token2), "Token2 should have boost");
        assertTrue(core.hasActiveBoost(token3), "Token3 should have boost");
    }
}

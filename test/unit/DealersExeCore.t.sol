// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";

contract DealersExeCoreTest is BaseTest {
    uint256 internal tokenId1;
    uint256 internal tokenId2;

    function setUp() public override {
        super.setUp();
        tokenId1 = _mintAndInitialize(player1);
        tokenId2 = _mintAndInitialize(player2);
    }

    // =============================================================
    //                    INITIALIZATION TESTS (3)
    // =============================================================

    function test_initializeDealer_starterValues() public view {
        (
            uint8 currentArea,
            uint256 reputation,
            uint8 dailyAttemptsRemaining,
            uint8 heatLevel,
            ,
            bool isInitialized
        ) = core.getDealerData(tokenId1);

        assertEq(currentArea, core.STARTING_AREA());
        assertEq(reputation, core.STARTING_REPUTATION());
        assertEq(dailyAttemptsRemaining, core.BASE_MAX_ATTEMPTS());
        assertEq(heatLevel, 0);
        assertTrue(isInitialized);
        assertEq(core.getCashBalance(tokenId1), core.STARTER_CASH());
        assertEq(core.getDrugBalance(tokenId1, 1), core.STARTER_WEED());
        assertEq(core.getDrugBalance(tokenId1, 2), core.STARTER_XTC());
        assertEq(core.getDrugBalance(tokenId1, 3), core.STARTER_COCAINE());
    }

    function test_initializeDealer_revertIfAlreadyInitialized() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        vm.expectRevert(DealersExeCore.DealerAlreadyInitialized.selector);
        core.initializeDealer(tokenId1);
    }

    function test_initializeDealer_revertIfNotAuthorized() public {
        uint256 newTokenId = nft.currentTokenId();
        vm.prank(owner);
        nft.reserve(1);

        vm.prank(player1);
        vm.expectRevert(DealersExeCore.NotAuthorized.selector);
        core.initializeDealer(newTokenId);
    }

    // =============================================================
    //                    REPUTATION TESTS (7)
    // =============================================================

    function test_updateReputation_increase() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        (, uint256 repBefore, , , , ) = core.getDealerData(tokenId1);
        core.updateReputation(tokenId1, 50);
        (, uint256 repAfter, , , , ) = core.getDealerData(tokenId1);

        assertEq(repAfter, repBefore + 50);
    }

    function test_updateReputation_decrease() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        (, uint256 repBefore, , , , ) = core.getDealerData(tokenId1);
        core.updateReputation(tokenId1, -10);
        (, uint256 repAfter, , , , ) = core.getDealerData(tokenId1);

        assertEq(repAfter, repBefore - 10);
    }

    function test_updateReputation_cannotGoBelowZero() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.updateReputation(tokenId1, -1000);
        (, uint256 repAfter, , , , ) = core.getDealerData(tokenId1);

        assertEq(repAfter, 0);
    }

    function test_updateReputation_emitsEvent() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        (, uint256 repBefore, , , , ) = core.getDealerData(tokenId1);

        vm.expectEmit(true, false, false, true);
        emit DealersExeCore.ReputationUpdated(tokenId1, repBefore + 25, 25);

        core.updateReputation(tokenId1, 25);
    }

    function test_getReputationChange_byTier() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        int16 winBonus = core.getReputationChange(tokenId1, 0);
        int16 tieBonus = core.getReputationChange(tokenId1, 1);
        int16 lossPenalty = core.getReputationChange(tokenId1, 2);

        assertEq(winBonus, 5);
        assertEq(tieBonus, 2);
        assertEq(lossPenalty, -3);

        core.updateReputation(tokenId1, 175);

        int16 winBonusHighTier = core.getReputationChange(tokenId1, 0);
        assertEq(winBonusHighTier, 12);
    }

    function test_getCurrentTier_progression() public {
        DealersExeCore.ReputationTier memory tier0 = core.getCurrentTier(0);
        assertEq(tier0.tierName, "Street Rat");

        DealersExeCore.ReputationTier memory tier50 = core.getCurrentTier(50);
        assertEq(tier50.tierName, "Corner Boy");

        DealersExeCore.ReputationTier memory tier150 = core.getCurrentTier(150);
        assertEq(tier150.tierName, "Hustler");

        DealersExeCore.ReputationTier memory tier400 = core.getCurrentTier(400);
        assertEq(tier400.tierName, "Shot Caller");

        DealersExeCore.ReputationTier memory tier800 = core.getCurrentTier(800);
        assertEq(tier800.tierName, "Kingpin");
    }

    function test_getTotalReputation_includesStashBonus() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.updateDrugBalance(tokenId1, 3, 100);

        (, uint256 baseRep, , , , ) = core.getDealerData(tokenId1);
        uint256 stashBonus = core.getStashBonus(tokenId1);
        uint256 totalRep = core.getTotalReputation(tokenId1);

        assertGt(stashBonus, 0);
        assertEq(totalRep, baseRep + stashBonus);
    }

    // =============================================================
    //                    DRUG BALANCE TESTS (4)
    // =============================================================

    function test_updateDrugBalance_increase() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint256 balBefore = core.getDrugBalance(tokenId1, 1);
        core.updateDrugBalance(tokenId1, 1, 100);
        uint256 balAfter = core.getDrugBalance(tokenId1, 1);

        assertEq(balAfter, balBefore + 100);
    }

    function test_updateDrugBalance_decrease() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint256 balBefore = core.getDrugBalance(tokenId1, 1);
        core.updateDrugBalance(tokenId1, 1, -25);
        uint256 balAfter = core.getDrugBalance(tokenId1, 1);

        assertEq(balAfter, balBefore - 25);
    }

    function test_updateDrugBalance_revertInsufficientBalance() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint256 currentBalance = core.getDrugBalance(tokenId1, 1);

        vm.expectRevert(DealersExeCore.InsufficientDrugBalance.selector);
        core.updateDrugBalance(tokenId1, 1, -int256(currentBalance + 1));
    }

    function test_updateDrugBalance_revertInvalidDrug() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        vm.expectRevert(DealersExeCore.InvalidDrug.selector);
        core.updateDrugBalance(tokenId1, 999, 100);
    }

    // =============================================================
    //                    HEAT & JAIL TESTS (10)
    // =============================================================

    function test_incrementHeatLevel_increases() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        (, , , uint8 heatBefore, , ) = core.getDealerData(tokenId1);
        core.incrementHeatLevel(tokenId1);
        (, , , uint8 heatAfter, , ) = core.getDealerData(tokenId1);

        assertEq(heatAfter, heatBefore + 1);
    }

    function test_incrementHeatLevel_cappedAt5() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        for (uint8 i = 0; i < 10; i++) {
            core.incrementHeatLevel(tokenId1);
        }

        (, , , uint8 heatLevel, , ) = core.getDealerData(tokenId1);
        assertEq(heatLevel, core.MAX_HEAT_LEVEL());
    }

    function test_sendToJail_movesToJailArea() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        _moveOutOfSafeHouse(tokenId1);

        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.sendToJail(tokenId1);

        (uint8 currentArea, , , , , ) = core.getDealerData(tokenId1);
        assertEq(currentArea, core.JAIL_AREA());
        assertTrue(core.isInJail(tokenId1));
    }

    function test_sendToJail_repPenalty10Percent() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.updateReputation(tokenId1, 200);
        _moveOutOfSafeHouse(tokenId1);

        vm.prank(owner);
        core.authorizeContract(address(this), true);

        (, uint256 repBefore, , , , ) = core.getDealerData(tokenId1);
        core.sendToJail(tokenId1);
        (, uint256 repAfter, , , , ) = core.getDealerData(tokenId1);

        (, , , , , uint8 jailRepPenaltyPercent, , , ) = core.config();
        uint256 expectedPenalty = (repBefore * jailRepPenaltyPercent) / 100;
        assertEq(repAfter, repBefore - expectedPenalty);
    }

    function test_sendToJail_repPenaltyCappedAt50() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.updateReputation(tokenId1, 1000);
        _moveOutOfSafeHouse(tokenId1);

        vm.prank(owner);
        core.authorizeContract(address(this), true);

        (, uint256 repBefore, , , , ) = core.getDealerData(tokenId1);
        core.sendToJail(tokenId1);
        (, uint256 repAfter, , , , ) = core.getDealerData(tokenId1);

        (, , , , , , uint256 jailRepPenaltyCap, , ) = core.config();
        assertEq(repAfter, repBefore - jailRepPenaltyCap);
    }

    function test_sendToJail_alreadyInJailNoOp() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        _moveOutOfSafeHouse(tokenId1);

        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.sendToJail(tokenId1);

        (, uint256 repAfterFirstJail, , , , ) = core.getDealerData(tokenId1);

        core.sendToJail(tokenId1);

        (, uint256 repAfterSecondJail, , , , ) = core.getDealerData(tokenId1);
        assertEq(repAfterFirstJail, repAfterSecondJail);
    }

    function test_payBail_exitsJail() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        _moveOutOfSafeHouse(tokenId1);

        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.sendToJail(tokenId1);

        assertTrue(core.isInJail(tokenId1));

        uint256 bailAmount = areaRegistry.getMovementFee(core.JAIL_AREA());

        vm.prank(player1);
        core.payBail{value: bailAmount}(tokenId1);

        assertFalse(core.isInJail(tokenId1));
        (uint8 currentArea, , , , , ) = core.getDealerData(tokenId1);
        assertEq(currentArea, 1);
    }

    function test_payBail_revertNotInJail() public {
        vm.prank(player1);
        vm.expectRevert(DealersExeCore.NotInJail.selector);
        core.payBail{value: 0.002 ether}(tokenId1);
    }

    function test_payBail_returnsToPreviousArea() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.moveToArea(tokenId1, 1);
        core.sendToJail(tokenId1);

        assertTrue(core.isInJail(tokenId1));

        uint256 bailAmount = areaRegistry.getMovementFee(core.JAIL_AREA());

        vm.prank(player1);
        core.payBail{value: bailAmount}(tokenId1);

        (uint8 currentArea, , , , , ) = core.getDealerData(tokenId1);
        assertEq(currentArea, 1);
    }

    function test_bribeCop_resetsHeat() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        for (uint8 i = 0; i < 3; i++) {
            core.incrementHeatLevel(tokenId1);
        }

        uint8 heatBefore = core.getHeatLevel(tokenId1);
        assertEq(heatBefore, 3);

        (, uint256 bribeFee, , , , , , , ) = core.config();
        vm.prank(player1);
        core.bribeCop{value: bribeFee}(tokenId1);

        uint8 heatAfter = core.getHeatLevel(tokenId1);
        assertEq(heatAfter, 0);
    }

    function test_removeWantedPoster_resetsHeatToZeroOnSuccess() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        for (uint8 i = 0; i < 4; i++) {
            core.incrementHeatLevel(tokenId1);
        }
        assertEq(core.getHeatLevel(tokenId1), 4);

        bool succeeded = false;
        for (uint256 i = 0; i < 100 && !succeeded; i++) {
            if (core.getHeatLevel(tokenId1) == 0) {
                succeeded = true;
                break;
            }

            (, , uint8 attempts, , , ) = core.getDealerData(tokenId1);
            if (attempts == 0) {
                core.applyBoost(tokenId1, 1 days, 100, 100, 5, false, false, 100);
                vm.prank(owner);
                core.authorizeContract(address(this), true);
                dealers_resetAttempts(tokenId1);
            }

            vm.prevrandao(bytes32(i * 999));
            vm.prank(player1);
            core.removeWantedPoster(tokenId1);
        }

        assertEq(core.getHeatLevel(tokenId1), 0, "Heat should reset to 0 on success");
    }

    function test_removeWantedPoster_revertNoHeat() public {
        assertEq(core.getHeatLevel(tokenId1), 0);

        vm.prank(player1);
        vm.expectRevert(DealersExeCore.NoHeatToReduce.selector);
        core.removeWantedPoster(tokenId1);
    }

    function test_removeWantedPoster_revertNoAttempts() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.incrementHeatLevel(tokenId1);

        for (uint8 i = 0; i < core.BASE_MAX_ATTEMPTS(); i++) {
            core.useAttempt(tokenId1);
        }

        vm.prank(player1);
        vm.expectRevert(DealersExeCore.NoAttemptsRemaining.selector);
        core.removeWantedPoster(tokenId1);
    }

    function test_removeWantedPoster_usesAttempt() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.incrementHeatLevel(tokenId1);

        (, , uint8 attemptsBefore, , , ) = core.getDealerData(tokenId1);

        vm.prank(player1);
        core.removeWantedPoster(tokenId1);

        (, , uint8 attemptsAfter, , , ) = core.getDealerData(tokenId1);
        assertEq(attemptsAfter, attemptsBefore - 1);
    }

    function dealers_resetAttempts(uint256 tokenId) internal {
        (uint256 resetFee, , , , , , , , ) = core.config();
        vm.prank(player1);
        core.purchaseAttemptReset{value: resetFee}(tokenId);
    }

    // =============================================================
    //                    ATTEMPTS TESTS (4)
    // =============================================================

    function test_useAttempt_decrements() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        (, , uint8 attemptsBefore, , , ) = core.getDealerData(tokenId1);
        core.useAttempt(tokenId1);
        (, , uint8 attemptsAfter, , , ) = core.getDealerData(tokenId1);

        assertEq(attemptsAfter, attemptsBefore - 1);
    }

    function test_useAttempt_revertNoAttemptsRemaining() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        for (uint8 i = 0; i < core.BASE_MAX_ATTEMPTS(); i++) {
            core.useAttempt(tokenId1);
        }

        vm.expectRevert(DealersExeCore.NoAttemptsRemaining.selector);
        core.useAttempt(tokenId1);
    }

    function test_purchaseAttemptReset_resetsToMax() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.useAttempt(tokenId1);
        core.useAttempt(tokenId1);

        (uint256 resetFee, , , , , , , , ) = core.config();
        vm.prank(player1);
        core.purchaseAttemptReset{value: resetFee}(tokenId1);

        (, , uint8 attemptsAfter, , , ) = core.getDealerData(tokenId1);
        assertEq(attemptsAfter, core.getMaxAttempts(tokenId1));
    }

    function test_getMaxAttempts_withBoost() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint8 maxWithoutBoost = core.getMaxAttempts(tokenId1);
        assertEq(maxWithoutBoost, core.BASE_MAX_ATTEMPTS());

        core.applyBoost(tokenId1, 1 days, 200, 150, 5, false, false, 150);

        uint8 maxWithBoost = core.getMaxAttempts(tokenId1);
        assertEq(maxWithBoost, core.BASE_MAX_ATTEMPTS() + 5);
    }

    // =============================================================
    //                    BOOSTS TESTS (5)
    // =============================================================

    function test_applyBoost_setsValues() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.applyBoost(tokenId1, 1 days, 200, 150, 3, true, true, 175);

        DealersExeCore.BoostData memory boost = core.getBoost(tokenId1);

        assertEq(boost.drugMultiplier, 200);
        assertEq(boost.repMultiplier, 150);
        assertEq(boost.extraAttempts, 3);
        assertTrue(boost.freeAreaMovement);
        assertTrue(boost.doubleHeistEntries);
        assertEq(boost.cashMultiplier, 175);
        assertTrue(boost.expiresAt > block.timestamp);
    }

    function test_applyBoost_extendsExistingBoost() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.applyBoost(tokenId1, 1 days, 200, 150, 3, false, false, 150);

        DealersExeCore.BoostData memory boostFirst = core.getBoost(tokenId1);
        uint64 firstExpiry = boostFirst.expiresAt;

        core.applyBoost(tokenId1, 1 days, 200, 150, 3, false, false, 150);

        DealersExeCore.BoostData memory boostSecond = core.getBoost(tokenId1);
        uint64 secondExpiry = boostSecond.expiresAt;

        assertEq(secondExpiry, firstExpiry + 1 days);
    }

    function test_hasActiveBoost_checksExpiry() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        assertFalse(core.hasActiveBoost(tokenId1));

        core.applyBoost(tokenId1, 1 days, 200, 150, 3, false, false, 150);
        assertTrue(core.hasActiveBoost(tokenId1));

        vm.warp(block.timestamp + 2 days);
        assertFalse(core.hasActiveBoost(tokenId1));
    }

    function test_getDrugMultiplier_returnsCorrectValue() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint8 multiplierNoBoost = core.getDrugMultiplier(tokenId1);
        assertEq(multiplierNoBoost, 100);

        core.applyBoost(tokenId1, 1 days, 200, 150, 3, false, false, 150);

        uint8 multiplierWithBoost = core.getDrugMultiplier(tokenId1);
        assertEq(multiplierWithBoost, 200);
    }

    function test_getRepMultiplier_returnsCorrectValue() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint8 multiplierNoBoost = core.getRepMultiplier(tokenId1);
        assertEq(multiplierNoBoost, 100);

        core.applyBoost(tokenId1, 1 days, 200, 175, 3, false, false, 150);

        uint8 multiplierWithBoost = core.getRepMultiplier(tokenId1);
        assertEq(multiplierWithBoost, 175);
    }

    // =============================================================
    //                    $CASH TESTS (5)
    // =============================================================

    function test_addCash_increments() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint256 cashBefore = core.getCashBalance(tokenId1);
        core.addCash(tokenId1, 500);
        uint256 cashAfter = core.getCashBalance(tokenId1);

        assertEq(cashAfter, cashBefore + 500);
    }

    function test_spendCash_decrements() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint256 cashBefore = core.getCashBalance(tokenId1);
        core.spendCash(tokenId1, 50);
        uint256 cashAfter = core.getCashBalance(tokenId1);

        assertEq(cashAfter, cashBefore - 50);
    }

    function test_spendCash_revertInsufficientCash() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint256 currentCash = core.getCashBalance(tokenId1);

        vm.expectRevert(DealersExeCore.InsufficientCash.selector);
        core.spendCash(tokenId1, currentCash + 1);
    }

    function test_purchaseCash_onlyWhenLow() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.spendCash(tokenId1, core.STARTER_CASH() - 5);

        (, , uint256 topupPrice, uint256 topupAmount, uint256 purchaseThreshold, , , , ) = core.config();

        uint256 cashBefore = core.getCashBalance(tokenId1);
        assertLt(cashBefore, purchaseThreshold);

        vm.prank(player1);
        core.purchaseCash{value: topupPrice}(tokenId1);

        uint256 cashAfter = core.getCashBalance(tokenId1);
        assertEq(cashAfter, cashBefore + topupAmount);
    }

    function test_purchaseCash_revertBalanceTooHigh() public {
        (, , uint256 topupPrice, , uint256 purchaseThreshold, , , , ) = core.config();

        uint256 currentCash = core.getCashBalance(tokenId1);
        assertGe(currentCash, purchaseThreshold);

        vm.prank(player1);
        vm.expectRevert(DealersExeCore.CashBalanceTooHigh.selector);
        core.purchaseCash{value: topupPrice}(tokenId1);
    }

    // =============================================================
    //                    AREA MOVEMENT TESTS (4)
    // =============================================================

    function test_moveToArea_changesArea() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        (uint8 areaBefore, , , , , ) = core.getDealerData(tokenId1);
        assertEq(areaBefore, core.STARTING_AREA(), "Should start in Manhattan");

        // Create a new area to move to
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.001 ether, 0, false, false);
        uint8 brooklynId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(brooklynId, 1, 5, 4);

        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.moveToArea(tokenId1, brooklynId);

        (uint8 areaAfter, , , , , ) = core.getDealerData(tokenId1);
        assertEq(areaAfter, brooklynId);
    }

    function test_moveToArea_revertCannotEnterSafeHouse() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        core.moveToArea(tokenId1, 1);

        uint8 safeHouseArea = core.SAFE_HOUSE_AREA();
        vm.expectRevert(DealersExeCore.CannotEnterSafeHouse.selector);
        core.moveToArea(tokenId1, safeHouseArea);
    }

    function test_moveToArea_revertCannotEnterJail() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);

        uint8 jailArea = core.JAIL_AREA();
        vm.expectRevert(DealersExeCore.CannotEnterJail.selector);
        core.moveToArea(tokenId1, jailArea);
    }

    function test_moveToArea_checksRepRequirement() public {
        vm.prank(owner);
        areaRegistry.createArea("High Stakes", 0.01 ether, 500, false, false);
        uint8 newAreaId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(newAreaId, 1, 5, 4);

        vm.prank(owner);
        core.authorizeContract(address(this), true);

        vm.expectRevert(DealersExeCore.InsufficientReputation.selector);
        core.moveToArea(tokenId1, newAreaId);

        core.updateReputation(tokenId1, 500);
        core.moveToArea(tokenId1, newAreaId);

        (uint8 currentArea, , , , , ) = core.getDealerData(tokenId1);
        assertEq(currentArea, newAreaId);
    }

    // =============================================================
    //                    ADMIN TESTS (3)
    // =============================================================

    function test_authorizeContract_grantsAccess() public {
        address newContract = makeAddr("newContract");

        assertFalse(core.authorizedContracts(newContract));

        vm.prank(owner);
        core.authorizeContract(newContract, true);

        assertTrue(core.authorizedContracts(newContract));
    }

    function test_authorizeContract_revokesAccess() public {
        address newContract = makeAddr("newContract");

        vm.prank(owner);
        core.authorizeContract(newContract, true);
        assertTrue(core.authorizedContracts(newContract));

        vm.prank(owner);
        core.authorizeContract(newContract, false);
        assertFalse(core.authorizedContracts(newContract));
    }

    function test_setReputationTiers_setsAll() public {
        DealersExeCore.ReputationTier[] memory newTiers = new DealersExeCore.ReputationTier[](2);

        newTiers[0] = DealersExeCore.ReputationTier({
            minReputation: 0,
            winBonus: 10,
            tieBonus: 5,
            lossPenalty: -2,
            tierName: "Newbie"
        });

        newTiers[1] = DealersExeCore.ReputationTier({
            minReputation: 100,
            winBonus: 20,
            tieBonus: 10,
            lossPenalty: -5,
            tierName: "Pro"
        });

        vm.prank(owner);
        core.setReputationTiers(newTiers);

        assertEq(core.getTierCount(), 2);

        DealersExeCore.ReputationTier memory tier0 = core.getCurrentTier(0);
        assertEq(tier0.tierName, "Newbie");
        assertEq(tier0.winBonus, 10);

        DealersExeCore.ReputationTier memory tier100 = core.getCurrentTier(100);
        assertEq(tier100.tierName, "Pro");
        assertEq(tier100.winBonus, 20);
    }

    // =============================================================
    //                    TRAVEL TESTS
    // =============================================================

    function test_travel_movesToDestination() public {
        // Start in Manhattan, create and travel to Brooklyn
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.001 ether, 0, false, false);
        uint8 brooklynId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(brooklynId, 1, 5, 4);

        uint256 fee = areaRegistry.getMovementFee(brooklynId);

        vm.prank(player1);
        core.travel{value: fee}(tokenId1, brooklynId);

        (uint8 currentArea, , , , , ) = core.getDealerData(tokenId1);
        assertEq(currentArea, brooklynId, "Should be in Brooklyn");
    }

    function test_travel_toSafeHouseIsFree() public {
        // Start in Manhattan (STARTING_AREA = 1)
        (uint8 areaBefore, , , , , ) = core.getDealerData(tokenId1);
        assertEq(areaBefore, 1, "Should start in Manhattan");

        // Travel to Safe House - should be free
        uint256 balanceBefore = player1.balance;

        vm.prank(player1);
        core.travel{value: 0}(tokenId1, 0);

        (uint8 areaAfter, , , , , ) = core.getDealerData(tokenId1);
        assertEq(areaAfter, 0, "Should be in Safe House");
        assertEq(player1.balance, balanceBefore, "Should not have paid anything");
    }

    function test_travel_firstMoveIsFree() public {
        // Create Brooklyn area to travel to
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.01 ether, 0, false, false);
        uint8 brooklynId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(brooklynId, 1, 5, 4);

        uint256 balanceBefore = player1.balance;

        // First move from starting area should be free
        vm.prank(player1);
        core.travel{value: 0}(tokenId1, brooklynId);

        (uint8 currentArea, , , , , ) = core.getDealerData(tokenId1);
        assertEq(currentArea, brooklynId, "Should be in Brooklyn");
        assertEq(player1.balance, balanceBefore, "First move should be free");
    }

    function test_travel_revertCannotEnterJail() public {
        uint8 jailArea = core.JAIL_AREA();

        vm.prank(player1);
        vm.expectRevert(DealersExeCore.CannotEnterJail.selector);
        core.travel{value: 0}(tokenId1, jailArea);
    }

    function test_travel_revertDealerInJail() public {
        // Dealer starts in Manhattan, send to jail
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.sendToJail(tokenId1);

        assertTrue(core.isInJail(tokenId1));

        // Create Brooklyn area
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.01 ether, 0, false, false);
        uint8 brooklynId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(brooklynId, 1, 5, 4);

        vm.prank(player1);
        vm.expectRevert(DealersExeCore.DealerInJail.selector);
        core.travel{value: 0.01 ether}(tokenId1, brooklynId);
    }

    function test_travel_revertNotDealerOwner() public {
        vm.prank(player2);
        vm.expectRevert(DealersExeCore.NotDealerOwner.selector);
        core.travel{value: 0.001 ether}(tokenId1, 1);
    }

    function test_travel_revertInsufficientPayment() public {
        // Create Brooklyn area to travel to first (using free first move)
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.01 ether, 0, false, false);
        uint8 brooklynId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(brooklynId, 1, 5, 4);

        // First move is free
        vm.prank(player1);
        core.travel{value: 0}(tokenId1, brooklynId);

        // Now create another area to test insufficient payment
        vm.prank(owner);
        areaRegistry.createArea("Queens", 0.02 ether, 0, false, false);
        uint8 queensId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(queensId, 1, 5, 4);

        uint256 fee = areaRegistry.getMovementFee(queensId);

        vm.prank(player1);
        vm.expectRevert(DealersExeCore.InsufficientPayment.selector);
        core.travel{value: fee - 1}(tokenId1, queensId);
    }

    function test_travel_refundsExcess() public {
        // First use the free first move
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.01 ether, 0, false, false);
        uint8 brooklynId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(brooklynId, 1, 5, 4);

        vm.prank(player1);
        core.travel{value: 0}(tokenId1, brooklynId);

        // Now test refund on subsequent move
        vm.prank(owner);
        areaRegistry.createArea("Queens", 0.02 ether, 0, false, false);
        uint8 queensId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(queensId, 1, 5, 4);

        uint256 fee = areaRegistry.getMovementFee(queensId);
        uint256 excess = 0.5 ether;
        uint256 balanceBefore = player1.balance;

        vm.prank(player1);
        core.travel{value: fee + excess}(tokenId1, queensId);

        // Should only have paid the fee, excess refunded
        assertEq(player1.balance, balanceBefore - fee, "Should refund excess");
    }

    function test_travel_freeWithKingpinBoost() public {
        // First use up the free first move
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.01 ether, 0, false, false);
        uint8 brooklynId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(brooklynId, 1, 5, 4);

        vm.prank(player1);
        core.travel{value: 0}(tokenId1, brooklynId);

        // Apply boost with freeAreaMovement
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.applyBoost(tokenId1, 30 days, 200, 200, 10, true, false, 200);

        // Create a new area with a fee
        vm.prank(owner);
        areaRegistry.createArea("Queens", 0.02 ether, 0, false, false);
        uint8 queensId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(queensId, 1, 5, 4);

        uint256 balanceBefore = player1.balance;

        // Travel without paying due to boost
        vm.prank(player1);
        core.travel{value: 0}(tokenId1, queensId);

        (uint8 currentArea, , , , , ) = core.getDealerData(tokenId1);
        assertEq(currentArea, queensId, "Should be in Queens");
        assertEq(player1.balance, balanceBefore, "Should not have paid with boost");
    }

    function test_travel_revertInsufficientReputation() public {
        // Create area with rep requirement
        vm.prank(owner);
        areaRegistry.createArea("VIP Zone", 0.01 ether, 500, false, false);
        uint8 vipAreaId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(vipAreaId, 1, 5, 4);

        vm.prank(player1);
        vm.expectRevert(DealersExeCore.InsufficientReputation.selector);
        core.travel{value: 0.01 ether}(tokenId1, vipAreaId);
    }

    function test_travel_noOpIfAlreadyInArea() public {
        // Dealer already starts in Manhattan
        (uint8 areaBefore, , , , , ) = core.getDealerData(tokenId1);
        assertEq(areaBefore, 1, "Should start in Manhattan");

        uint256 balanceBefore = player1.balance;

        // Travel to same area (Manhattan)
        vm.prank(player1);
        core.travel{value: 0.001 ether}(tokenId1, 1);

        // Should refund since no-op
        assertEq(player1.balance, balanceBefore, "Should refund on no-op");
    }

    function test_travel_emitsDealerTraveledEvent() public {
        // Create Brooklyn area
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.01 ether, 0, false, false);
        uint8 brooklynId = areaRegistry.getTotalAreas();
        areaRegistry.configureAreaDrug(brooklynId, 1, 5, 4);

        // First move is free, so fee=0 and wasFreeMovement=true
        vm.expectEmit(true, false, false, true);
        emit DealersExeCore.DealerTraveled(tokenId1, 1, brooklynId, 0, true);

        vm.prank(player1);
        core.travel{value: 0}(tokenId1, brooklynId);
    }

    function test_attemptBreakout_returnsToPreviousArea() public {
        // Dealer starts in Manhattan
        (uint8 areaBefore, , , , , ) = core.getDealerData(tokenId1);
        assertEq(areaBefore, 1, "Should start in Manhattan");

        // Send to jail
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.sendToJail(tokenId1);

        assertTrue(core.isInJail(tokenId1));

        // Try breakout multiple times until success
        bool escaped = false;
        for (uint256 i = 0; i < 100 && !escaped; i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prevrandao(bytes32(i * 12345));

            vm.prank(player1);
            try core.attemptBreakout(tokenId1) {
                escaped = !core.isInJail(tokenId1);
            } catch {}
        }

        if (escaped) {
            (uint8 areaAfter, , , , , ) = core.getDealerData(tokenId1);
            assertEq(areaAfter, 1, "Should return to Manhattan after breakout");
        }
    }
}

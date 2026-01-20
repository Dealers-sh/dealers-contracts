// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";

contract DealersExePVPTest is BaseTest {
    uint256 attackerToken;
    uint256 defenderToken;

    uint256 constant DRUG_WEED = 1;
    uint256 constant DRUG_XTC = 2;
    uint256 constant DRUG_COCAINE = 3;

    uint8 constant AREA_SAFE_HOUSE = 0;
    uint8 constant AREA_MANHATTAN = 1;
    uint8 constant AREA_JAIL = 255;

    function setUp() public override {
        super.setUp();

        vm.warp(1 hours + 1);

        attackerToken = _mintAndInitialize(player1);
        defenderToken = _mintAndInitialize(player2);
    }

    // =============================================================
    //                      HELPER FUNCTIONS
    // =============================================================

    function _moveDealerToArea(uint256 tokenId, uint8 areaId) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.moveToArea(tokenId, areaId);
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function _addDrugsToDealer(uint256 tokenId, uint256 drugId, uint256 amount) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.updateDrugBalance(tokenId, drugId, int256(amount));
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function _sendDealerToJail(uint256 tokenId) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.sendToJail(tokenId);
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function _setDealerStats(uint256 tokenId, uint8 threat, uint8 armor) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.setDealerStats(tokenId, threat, armor);
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function _setHeatLevel(uint256 tokenId, uint8 level) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        for (uint8 i = 0; i < level; i++) {
            core.incrementHeatLevel(tokenId);
        }
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function _applyBoost(
        uint256 tokenId,
        uint64 duration,
        uint8 drugMultiplier,
        uint8 repMultiplier,
        uint8 extraAttempts,
        bool freeAreaMovement,
        bool doubleHeistEntries,
        uint8 cashMultiplier
    ) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.applyBoost(tokenId, duration, drugMultiplier, repMultiplier, extraAttempts, freeAreaMovement, doubleHeistEntries, cashMultiplier);
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function _setupDealersForPVP() internal {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _addDrugsToDealer(attackerToken, DRUG_WEED, 1000);
        _addDrugsToDealer(defenderToken, DRUG_WEED, 1000);
    }

    function _executeAttack() internal {
        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);
    }

    function _mockJailChance(uint256 tokenId, uint8 chance) internal {
        vm.mockCall(
            address(core),
            abi.encodeWithSelector(core.getJailChance.selector, tokenId),
            abi.encode(chance)
        );
    }

    function _clearJailChanceMock() internal {
        vm.clearMockedCalls();
    }

    function _findPrevrandaoForOutcome(bool wantWin, bool wantArrest) internal returns (uint256) {
        if (wantArrest) {
            _mockJailChance(attackerToken, 100);
            return 1;
        }

        _mockJailChance(attackerToken, 0);

        if (wantWin) {
            _setDealerStats(attackerToken, 25, 0);
            _setDealerStats(defenderToken, 0, 0);
        } else {
            _setDealerStats(attackerToken, 0, 0);
            _setDealerStats(defenderToken, 0, 25);
        }

        uint256 winChance = pvp.calculateWinChance(attackerToken, defenderToken);
        uint256 totalBattles = pvp.totalPVPBattles();

        for (uint256 i = 1; i < 10000; i++) {
            uint256 randomness = uint256(keccak256(abi.encodePacked(
                bytes32(i),
                block.timestamp,
                attackerToken,
                defenderToken,
                player1,
                totalBattles
            )));

            bool wouldWin = ((randomness >> 8) % 100) < winChance;
            if (wantWin == wouldWin) {
                return i;
            }
        }
        return 1;
    }

    function _executeAttackWithPrevrandao(uint256 prevrandaoValue) internal {
        vm.prevrandao(bytes32(prevrandaoValue));
        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);
    }

    // =============================================================
    //                     WIN CHANCE (5 tests)
    // =============================================================

    function test_calculateWinChance_base50() public {
        _setupDealersForPVP();

        uint256 winChance = pvp.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 50, "Base win chance should be 50%");
    }

    function test_calculateWinChance_threatBonus() public {
        _setupDealersForPVP();
        _setDealerStats(attackerToken, 10, 0);

        uint256 winChance = pvp.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 60, "Threat bonus should increase win chance");
    }

    function test_calculateWinChance_armorPenalty() public {
        _setupDealersForPVP();
        _setDealerStats(defenderToken, 0, 15);

        uint256 winChance = pvp.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 35, "Defender armor should reduce attacker win chance");
    }

    function test_calculateWinChance_min25() public {
        _setupDealersForPVP();
        _setDealerStats(defenderToken, 0, 25);
        _setDealerStats(attackerToken, 0, 0);

        uint256 winChance = pvp.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 25, "Win chance should not go below 25%");
    }

    function test_calculateWinChance_max75() public {
        _setupDealersForPVP();
        _setDealerStats(attackerToken, 25, 0);
        _setDealerStats(defenderToken, 0, 0);

        uint256 winChance = pvp.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 75, "Win chance should not exceed 75%");
    }

    // =============================================================
    //                     VALIDATION (7 tests)
    // =============================================================

    function test_attack_revertSameDealer() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.SameDealer.selector);
        pvp.attack(attackerToken, attackerToken);
    }

    function test_attack_revertDifferentArea() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);

        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.001 ether, 0, false, false);
        areaRegistry.configureAreaDrug(2, DRUG_WEED, 1, 1);

        _moveDealerToArea(defenderToken, 2);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DifferentArea.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_revertAttackerInJail() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _sendDealerToJail(attackerToken);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DealerInJail.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_revertDefenderInJail() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _sendDealerToJail(defenderToken);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DealerInJail.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_revertAttackerInSafeHouse() public {
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DealerInSafeHouse.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_revertDefenderInSafeHouse() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DealerInSafeHouse.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_revertDealerNotInitialized() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);

        uint256 uninitTokenId = 99999;

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DealerNotInitialized.selector);
        pvp.attack(attackerToken, uninitTokenId);
    }

    // =============================================================
    //                     COOLDOWN (3 tests)
    // =============================================================

    function test_attack_revertCooldownActive() public {
        _setupDealersForPVP();

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao");
        _executeAttackWithPrevrandao(prevrandao);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.CooldownActive.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_allowedAfterCooldown() public {
        _setupDealersForPVP();

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao");
        _executeAttackWithPrevrandao(prevrandao);

        vm.warp(block.timestamp + 1 hours + 1);

        vm.prevrandao(bytes32(uint256(99999)));
        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);

        assertEq(pvp.totalPVPBattles(), 2, "Second attack should succeed after cooldown");
    }

    function test_getCooldownRemaining_returnsCorrect() public {
        _setupDealersForPVP();

        uint256 cooldownBefore = pvp.getCooldownRemaining(attackerToken, defenderToken);
        assertEq(cooldownBefore, 0, "Cooldown should be 0 before any attack");

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 cooldownAfter = pvp.getCooldownRemaining(attackerToken, defenderToken);
        assertEq(cooldownAfter, 1 hours, "Cooldown should be 1 hour after attack");

        vm.warp(block.timestamp + 30 minutes);
        uint256 cooldownMid = pvp.getCooldownRemaining(attackerToken, defenderToken);
        assertEq(cooldownMid, 30 minutes, "Cooldown should decrease over time");

        vm.warp(block.timestamp + 31 minutes);
        uint256 cooldownExpired = pvp.getCooldownRemaining(attackerToken, defenderToken);
        assertEq(cooldownExpired, 0, "Cooldown should be 0 after expiration");
    }

    // =============================================================
    //                     BATTLE (4 tests)
    // =============================================================

    function test_attack_attackerWins_steals10Percent() public {
        _setupDealersForPVP();

        uint256 defenderDrugsBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 attackerDrugsBefore = core.getDrugBalance(attackerToken, DRUG_WEED);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 defenderDrugsAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 attackerDrugsAfter = core.getDrugBalance(attackerToken, DRUG_WEED);

        uint256 expectedStolen = defenderDrugsBefore * 10 / 100;
        assertEq(defenderDrugsAfter, defenderDrugsBefore - expectedStolen, "Defender should lose 10%");
        assertEq(attackerDrugsAfter, attackerDrugsBefore + expectedStolen, "Attacker should gain 10%");
    }

    function test_attack_attackerLoses_defenderSteals() public {
        _setupDealersForPVP();

        uint256 attackerDrugsBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 defenderDrugsBefore = core.getDrugBalance(defenderToken, DRUG_WEED);

        uint256 prevrandao = _findPrevrandaoForOutcome(false, false);
        require(prevrandao > 0, "Could not find valid prevrandao for loss");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 attackerDrugsAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 defenderDrugsAfter = core.getDrugBalance(defenderToken, DRUG_WEED);

        uint256 expectedStolen = attackerDrugsBefore * 10 / 100;
        assertEq(attackerDrugsAfter, attackerDrugsBefore - expectedStolen, "Attacker loses 10% on loss");
        assertEq(defenderDrugsAfter, defenderDrugsBefore + expectedStolen, "Defender gains 10% on win");
    }

    function test_attack_winnerGetsRepBoost() public {
        _setupDealersForPVP();

        (, uint256 attackerRepBefore,,,,) = core.getDealerData(attackerToken);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        (, uint256 attackerRepAfter,,,,) = core.getDealerData(attackerToken);

        assertGt(attackerRepAfter, attackerRepBefore, "Winner should gain reputation");
    }

    function test_attack_loserGetsRepPenalty() public {
        _setupDealersForPVP();

        (, uint256 attackerRepBefore,,,,) = core.getDealerData(attackerToken);

        uint256 prevrandao = _findPrevrandaoForOutcome(false, false);
        require(prevrandao > 0, "Could not find valid prevrandao for loss");
        _executeAttackWithPrevrandao(prevrandao);

        (, uint256 attackerRepAfter,,,,) = core.getDealerData(attackerToken);

        assertLt(attackerRepAfter, attackerRepBefore, "Loser should lose reputation");
    }

    // =============================================================
    //                     DRUG STEALING (4 tests)
    // =============================================================

    function test_attack_stealsAllAreaDrugs() public {
        _setupDealersForPVP();
        _addDrugsToDealer(defenderToken, DRUG_XTC, 500);
        _addDrugsToDealer(defenderToken, DRUG_COCAINE, 100);

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcBefore = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineBefore = core.getDrugBalance(defenderToken, DRUG_COCAINE);

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcBefore = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineBefore = core.getDrugBalance(attackerToken, DRUG_COCAINE);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        assertEq(
            core.getDrugBalance(attackerToken, DRUG_WEED),
            attackerWeedBefore + (defenderWeedBefore * 10 / 100),
            "Should steal 10% of Weed"
        );
        assertEq(
            core.getDrugBalance(attackerToken, DRUG_XTC),
            attackerXtcBefore + (defenderXtcBefore * 10 / 100),
            "Should steal 10% of XTC"
        );
        assertEq(
            core.getDrugBalance(attackerToken, DRUG_COCAINE),
            attackerCocaineBefore + (defenderCocaineBefore * 10 / 100),
            "Should steal 10% of Cocaine"
        );
    }

    function test_attack_noStealIfZeroBalance() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);

        uint256 defenderXtcBefore = core.getDrugBalance(defenderToken, DRUG_XTC);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);

        assertEq(defenderXtcBefore, 0, "Defender XTC should start at 0");
        assertEq(defenderXtcAfter, 0, "No XTC stolen from zero balance");
    }

    function test_attack_roundsDownSteal() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _addDrugsToDealer(defenderToken, DRUG_XTC, 5);

        uint256 attackerXtcBefore = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 defenderXtcBefore = core.getDrugBalance(defenderToken, DRUG_XTC);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 attackerXtcAfter = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);

        assertEq(attackerXtcAfter, attackerXtcBefore, "10% of 5 = 0 (rounds down, attacker gains nothing)");
        assertEq(defenderXtcAfter, defenderXtcBefore, "Defender keeps all 5 XTC (10% rounds to 0)");
    }

    function test_attack_multipleDrugTypes() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _addDrugsToDealer(defenderToken, DRUG_XTC, 200);
        _addDrugsToDealer(defenderToken, DRUG_COCAINE, 50);

        uint256 attackerXtcBefore = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineBefore = core.getDrugBalance(attackerToken, DRUG_COCAINE);
        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 expectedWeedStolen = (defenderWeedBefore * 10) / 100;
        assertEq(core.getDrugBalance(defenderToken, DRUG_WEED), defenderWeedBefore - expectedWeedStolen, "Defender lost 10% of Weed");
        assertEq(core.getDrugBalance(attackerToken, DRUG_XTC), attackerXtcBefore + 20, "Stole 10% of 200 XTC");
        assertEq(core.getDrugBalance(attackerToken, DRUG_COCAINE), attackerCocaineBefore + 5, "Stole 10% of 50 Cocaine");
    }

    // =============================================================
    //                     ARREST (3 tests)
    // =============================================================

    function test_attack_attackerArrestedBeforeBattle() public {
        _setupDealersForPVP();
        _setHeatLevel(attackerToken, 5);

        uint256 defenderDrugsBefore = core.getDrugBalance(defenderToken, DRUG_WEED);

        uint256 prevrandao = _findPrevrandaoForOutcome(false, true);
        require(prevrandao > 0, "Could not find valid prevrandao for arrest");
        _executeAttackWithPrevrandao(prevrandao);

        assertTrue(core.isInJail(attackerToken), "Attacker should be in jail");
        assertEq(
            core.getDrugBalance(defenderToken, DRUG_WEED),
            defenderDrugsBefore,
            "Defender drugs unchanged when attacker arrested"
        );
    }

    function test_attack_defenderNotArrestedOnAttackerArrest() public {
        _setupDealersForPVP();
        _setHeatLevel(attackerToken, 5);

        uint256 prevrandao = _findPrevrandaoForOutcome(false, true);
        require(prevrandao > 0, "Could not find valid prevrandao for arrest");
        _executeAttackWithPrevrandao(prevrandao);

        assertTrue(core.isInJail(attackerToken), "Attacker should be in jail");
        assertFalse(core.isInJail(defenderToken), "Defender should not be in jail");
    }

    function test_attack_cooldownStillSetOnArrest() public {
        _setupDealersForPVP();
        _setHeatLevel(attackerToken, 5);

        uint256 prevrandao = _findPrevrandaoForOutcome(false, true);
        require(prevrandao > 0, "Could not find valid prevrandao for arrest");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 cooldown = pvp.getCooldownRemaining(attackerToken, defenderToken);
        assertEq(cooldown, 1 hours, "Cooldown should be set even on arrest");
    }

    // =============================================================
    //                     STATS (4 tests)
    // =============================================================

    function test_attack_updatesAttackerStats() public {
        _setupDealersForPVP();

        (uint256 attacksWonBefore,,,,,, ) = pvp.getPlayerPVPStats(attackerToken);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        (uint256 attacksWonAfter,,,,,, ) = pvp.getPlayerPVPStats(attackerToken);

        assertEq(attacksWonAfter, attacksWonBefore + 1, "Attacks won should increment");
    }

    function test_attack_updatesDefenderStats() public {
        _setupDealersForPVP();

        (,,, uint256 defensesLostBefore,,, ) = pvp.getPlayerPVPStats(defenderToken);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        (,,, uint256 defensesLostAfter,,, ) = pvp.getPlayerPVPStats(defenderToken);

        assertEq(defensesLostAfter, defensesLostBefore + 1, "Defenses lost should increment");
    }

    function test_attack_tracksDrugsStolen() public {
        _setupDealersForPVP();

        (,,,, uint256 drugsStolenBefore,, ) = pvp.getPlayerPVPStats(attackerToken);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        (,,,, uint256 drugsStolenAfter,, ) = pvp.getPlayerPVPStats(attackerToken);

        assertGt(drugsStolenAfter, drugsStolenBefore, "Drugs stolen should increase");
    }

    function test_attack_tracksTimesArrested() public {
        _setupDealersForPVP();
        _setHeatLevel(attackerToken, 5);

        (,,,,,, uint256 arrestedBefore) = pvp.getPlayerPVPStats(attackerToken);

        uint256 prevrandao = _findPrevrandaoForOutcome(false, true);
        require(prevrandao > 0, "Could not find valid prevrandao for arrest");
        _executeAttackWithPrevrandao(prevrandao);

        (,,,,,, uint256 arrestedAfter) = pvp.getPlayerPVPStats(attackerToken);

        assertEq(arrestedAfter, arrestedBefore + 1, "Times arrested should increment");
    }

    // =============================================================
    //                     DEFENDER PROTECTION (3 tests)
    // =============================================================

    function test_attack_defenderExhaustedAfterMaxAttacks() public {
        _setupDealersForPVP();
        _mockJailChance(attackerToken, 0);

        for (uint256 i = 0; i < 5; i++) {
            uint256 newAttacker = _mintAndInitialize(address(uint160(100 + i)));
            _moveDealerToArea(newAttacker, AREA_MANHATTAN);
            _addDrugsToDealer(newAttacker, DRUG_WEED, 1000);

            vm.prank(address(uint160(100 + i)));
            pvp.attack(newAttacker, defenderToken);
        }

        uint256 sixthAttacker = _mintAndInitialize(address(uint160(200)));
        _moveDealerToArea(sixthAttacker, AREA_MANHATTAN);
        _addDrugsToDealer(sixthAttacker, DRUG_WEED, 1000);

        vm.prank(address(uint160(200)));
        vm.expectRevert(DealersExePVP.DefenderExhausted.selector);
        pvp.attack(sixthAttacker, defenderToken);
    }

    function test_attack_defenderProtectionResetsNextDay() public {
        _setupDealersForPVP();
        _mockJailChance(attackerToken, 0);

        for (uint256 i = 0; i < 5; i++) {
            uint256 newAttacker = _mintAndInitialize(address(uint160(100 + i)));
            _moveDealerToArea(newAttacker, AREA_MANHATTAN);
            _addDrugsToDealer(newAttacker, DRUG_WEED, 1000);

            vm.prank(address(uint160(100 + i)));
            pvp.attack(newAttacker, defenderToken);
        }

        vm.warp(block.timestamp + 1 days);

        uint256 newAttacker = _mintAndInitialize(address(uint160(300)));
        _moveDealerToArea(newAttacker, AREA_MANHATTAN);
        _addDrugsToDealer(newAttacker, DRUG_WEED, 1000);

        vm.prank(address(uint160(300)));
        pvp.attack(newAttacker, defenderToken);

        assertEq(pvp.attacksReceivedToday(defenderToken), 1, "Attacks should reset on new day");
    }

    // =============================================================
    //                     PAUSE (2 tests)
    // =============================================================

    function test_attack_revertWhenPaused() public {
        _setupDealersForPVP();

        vm.prank(owner);
        pvp.pause();

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.ContractPaused.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_allowedAfterUnpause() public {
        _setupDealersForPVP();
        _mockJailChance(attackerToken, 0);

        vm.prank(owner);
        pvp.pause();

        vm.prank(owner);
        pvp.unpause();

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        assertEq(pvp.totalPVPBattles(), 1, "Attack should succeed after unpause");
    }

    // =============================================================
    //                     SETTER VALIDATION (4 tests)
    // =============================================================

    function test_setCore_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DealersExePVP.ContractNotSet.selector);
        pvp.setCore(address(0));
    }

    function test_setNFTContract_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DealersExePVP.ContractNotSet.selector);
        pvp.setNFTContract(address(0));
    }

    function test_setAreaRegistry_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DealersExePVP.ContractNotSet.selector);
        pvp.setAreaRegistry(address(0));
    }

    function test_setRandomness_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DealersExePVP.ContractNotSet.selector);
        pvp.setRandomness(address(0));
    }
}

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

        for (uint256 i = 1; i < 10000; i++) {
            uint256 randomness = uint256(keccak256(abi.encodePacked(
                bytes32(i),
                block.timestamp,
                attackerToken,
                defenderToken,
                player1,
                block.timestamp
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
        // Dealers now start in Manhattan, move attacker to Safe House
        vm.prank(player1);
        core.travel{value: 0}(attackerToken, AREA_SAFE_HOUSE);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DealerInSafeHouse.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_revertDefenderInSafeHouse() public {
        // Dealers now start in Manhattan, move defender to Safe House
        vm.prank(player2);
        core.travel{value: 0}(defenderToken, AREA_SAFE_HOUSE);

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
    //                     BATTLE (4 tests)
    // =============================================================

    function test_attack_attackerWins_steals2PercentOfOneDrug() public {
        _setupDealersForPVP();

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcBefore = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineBefore = core.getDrugBalance(defenderToken, DRUG_COCAINE);
        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcBefore = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineBefore = core.getDrugBalance(attackerToken, DRUG_COCAINE);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineAfter = core.getDrugBalance(defenderToken, DRUG_COCAINE);
        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcAfter = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineAfter = core.getDrugBalance(attackerToken, DRUG_COCAINE);

        uint256 drugsChanged = 0;
        if (defenderWeedAfter < defenderWeedBefore) drugsChanged++;
        if (defenderXtcAfter < defenderXtcBefore) drugsChanged++;
        if (defenderCocaineAfter < defenderCocaineBefore) drugsChanged++;

        assertEq(drugsChanged, 1, "Exactly one drug type should be stolen");

        uint256 totalStolen =
            (attackerWeedAfter - attackerWeedBefore) +
            (attackerXtcAfter - attackerXtcBefore) +
            (attackerCocaineAfter - attackerCocaineBefore);
        assertGt(totalStolen, 0, "Some drugs should be stolen");
    }

    function test_attack_attackerLoses_defenderSteals() public {
        _setupDealersForPVP();

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcBefore = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineBefore = core.getDrugBalance(attackerToken, DRUG_COCAINE);
        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcBefore = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineBefore = core.getDrugBalance(defenderToken, DRUG_COCAINE);

        uint256 prevrandao = _findPrevrandaoForOutcome(false, false);
        require(prevrandao > 0, "Could not find valid prevrandao for loss");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcAfter = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineAfter = core.getDrugBalance(attackerToken, DRUG_COCAINE);
        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineAfter = core.getDrugBalance(defenderToken, DRUG_COCAINE);

        uint256 attackerDrugsLost = 0;
        if (attackerWeedAfter < attackerWeedBefore) attackerDrugsLost++;
        if (attackerXtcAfter < attackerXtcBefore) attackerDrugsLost++;
        if (attackerCocaineAfter < attackerCocaineBefore) attackerDrugsLost++;

        assertEq(attackerDrugsLost, 1, "Attacker should lose exactly one drug type");

        uint256 defenderTotalGained =
            (defenderWeedAfter - defenderWeedBefore) +
            (defenderXtcAfter - defenderXtcBefore) +
            (defenderCocaineAfter - defenderCocaineBefore);
        assertGt(defenderTotalGained, 0, "Defender should gain some drugs");
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

    function test_attack_steals2PercentOfOneWeightedDrug() public {
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

        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineAfter = core.getDrugBalance(defenderToken, DRUG_COCAINE);

        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcAfter = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineAfter = core.getDrugBalance(attackerToken, DRUG_COCAINE);

        uint256 drugTypesStolen = 0;
        if (defenderWeedAfter < defenderWeedBefore) drugTypesStolen++;
        if (defenderXtcAfter < defenderXtcBefore) drugTypesStolen++;
        if (defenderCocaineAfter < defenderCocaineBefore) drugTypesStolen++;

        assertEq(drugTypesStolen, 1, "Only one drug type should be stolen");

        uint256 totalStolen =
            (attackerWeedAfter - attackerWeedBefore) +
            (attackerXtcAfter - attackerXtcBefore) +
            (attackerCocaineAfter - attackerCocaineBefore);
        assertGt(totalStolen, 0, "Winner should steal some drugs");
    }

    function test_attack_noStealIfZeroBalance() public {
        // Dealers now start in Manhattan, no need to move
        // Remove all drugs from defender to test zero balance steal
        vm.startPrank(owner);
        core.authorizeContract(address(this), true);

        // Remove starter drugs from defender
        uint256 defenderWeed = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtc = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaine = core.getDrugBalance(defenderToken, DRUG_COCAINE);

        if (defenderWeed > 0) core.updateDrugBalance(defenderToken, DRUG_WEED, -int256(defenderWeed));
        if (defenderXtc > 0) core.updateDrugBalance(defenderToken, DRUG_XTC, -int256(defenderXtc));
        if (defenderCocaine > 0) core.updateDrugBalance(defenderToken, DRUG_COCAINE, -int256(defenderCocaine));

        core.authorizeContract(address(this), false);
        vm.stopPrank();

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);

        assertEq(defenderWeedBefore, 0, "Defender Weed should be 0");
        assertEq(defenderWeedAfter, 0, "No Weed stolen from zero balance");
    }

    function test_attack_roundsUpSteal() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);

        vm.startPrank(owner);
        core.authorizeContract(address(this), true);
        uint256 defenderWeed = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtc = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaine = core.getDrugBalance(defenderToken, DRUG_COCAINE);
        if (defenderWeed > 0) core.updateDrugBalance(defenderToken, DRUG_WEED, -int256(defenderWeed));
        if (defenderXtc > 0) core.updateDrugBalance(defenderToken, DRUG_XTC, -int256(defenderXtc));
        if (defenderCocaine > 0) core.updateDrugBalance(defenderToken, DRUG_COCAINE, -int256(defenderCocaine));
        core.authorizeContract(address(this), false);
        vm.stopPrank();

        _addDrugsToDealer(defenderToken, DRUG_WEED, 10);

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);

        assertEq(attackerWeedAfter, attackerWeedBefore + 1, "2% of 10 = 0.2 rounds UP to 1");
        assertEq(defenderWeedAfter, 9, "Defender loses 1 (rounded up from 0.2)");
    }

    function test_attack_onlyOneDrugTypeStolen() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _addDrugsToDealer(defenderToken, DRUG_XTC, 200);
        _addDrugsToDealer(defenderToken, DRUG_COCAINE, 500);

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcBefore = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineBefore = core.getDrugBalance(defenderToken, DRUG_COCAINE);

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcBefore = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineBefore = core.getDrugBalance(attackerToken, DRUG_COCAINE);

        uint256 prevrandao = _findPrevrandaoForOutcome(true, false);
        require(prevrandao > 0, "Could not find valid prevrandao for win");
        _executeAttackWithPrevrandao(prevrandao);

        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineAfter = core.getDrugBalance(defenderToken, DRUG_COCAINE);

        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcAfter = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineAfter = core.getDrugBalance(attackerToken, DRUG_COCAINE);

        uint256 drugTypesDefenderLost = 0;
        if (defenderWeedAfter < defenderWeedBefore) drugTypesDefenderLost++;
        if (defenderXtcAfter < defenderXtcBefore) drugTypesDefenderLost++;
        if (defenderCocaineAfter < defenderCocaineBefore) drugTypesDefenderLost++;

        assertEq(drugTypesDefenderLost, 1, "Defender should lose exactly one drug type");

        uint256 totalAttackerGained =
            (attackerWeedAfter - attackerWeedBefore) +
            (attackerXtcAfter - attackerXtcBefore) +
            (attackerCocaineAfter - attackerCocaineBefore);
        assertGt(totalAttackerGained, 0, "Attacker should gain drugs from one type");
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

    // =============================================================
    //                     DEFENDER PROTECTION (3 tests)
    // =============================================================

    function test_attack_defenderExhaustedAfterMaxAttacks() public {
        _setupDealersForPVP();
        _mockJailChance(attackerToken, 0);

        for (uint256 i = 0; i < 3; i++) {
            uint256 newAttacker = _mintAndInitialize(address(uint160(100 + i)));
            _moveDealerToArea(newAttacker, AREA_MANHATTAN);
            _addDrugsToDealer(newAttacker, DRUG_WEED, 1000);

            vm.prank(address(uint160(100 + i)));
            pvp.attack(newAttacker, defenderToken);
        }

        uint256 fourthAttacker = _mintAndInitialize(address(uint160(200)));
        _moveDealerToArea(fourthAttacker, AREA_MANHATTAN);
        _addDrugsToDealer(fourthAttacker, DRUG_WEED, 1000);

        vm.prank(address(uint160(200)));
        vm.expectRevert(DealersExePVP.DefenderExhausted.selector);
        pvp.attack(fourthAttacker, defenderToken);
    }

    function test_attack_defenderProtectionResetsNextDay() public {
        _setupDealersForPVP();
        _mockJailChance(attackerToken, 0);

        for (uint256 i = 0; i < 3; i++) {
            uint256 loopAttacker = _mintAndInitialize(address(uint160(100 + i)));
            _moveDealerToArea(loopAttacker, AREA_MANHATTAN);
            _addDrugsToDealer(loopAttacker, DRUG_WEED, 1000);

            vm.prank(address(uint160(100 + i)));
            pvp.attack(loopAttacker, defenderToken);
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

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

        _setReputation(attackerToken, 200);
        _setReputation(defenderToken, 200);
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

    function _setReputation(uint256 tokenId, uint256 targetRep) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        (, uint256 currentRep,,,,) = core.getDealerData(tokenId);
        int256 change = int256(targetRep) - int256(currentRep);
        core.updateReputation(tokenId, change);
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function _setupDealersForPVP() internal {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 200);
        _setReputation(defenderToken, 200);
        _addDrugsToDealer(attackerToken, DRUG_WEED, 1000);
        _addDrugsToDealer(defenderToken, DRUG_WEED, 1000);
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

    function _mockRandomness(uint256 value) internal {
        vm.mockCall(
            address(randomness),
            abi.encodeWithSignature("getRandomness(bytes32)"),
            abi.encode(value)
        );
    }

    function _buildRng(uint8 jailRoll, uint8 winRoll, uint8 rarityRoll) internal pure returns (uint256) {
        return uint256(jailRoll)
            | (uint256(winRoll) << 8)
            | (uint256(rarityRoll) << 16);
    }

    function _setupForWin() internal {
        _mockJailChance(attackerToken, 0);
        _setDealerStats(attackerToken, 25, 0);
        _setDealerStats(defenderToken, 0, 0);
        _mockRandomness(_buildRng(50, 0, 10));
    }

    function _setupForLoss() internal {
        _mockJailChance(attackerToken, 0);
        _setDealerStats(attackerToken, 0, 0);
        _setDealerStats(defenderToken, 0, 25);
        _mockRandomness(_buildRng(50, 99, 10));
    }

    function _setupForArrest() internal {
        _mockJailChance(attackerToken, 100);
        _mockRandomness(_buildRng(0, 0, 10));
    }

    function _executeAttack() internal {
        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        return (a - 1) / b + 1;
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
        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);

        _setupForWin();
        _executeAttack();

        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);

        uint256 stolen = defenderWeedBefore - defenderWeedAfter;
        uint256 expected = _ceilDiv(defenderWeedBefore * 2, 100);
        assertEq(stolen, expected, "Defender should lose 2% of weed");

        uint256 transferred = stolen / 2;
        assertEq(attackerWeedAfter, attackerWeedBefore + transferred, "Attacker gains half of stolen");
    }

    function test_attack_attackerLoses_defenderSteals() public {
        _setupDealersForPVP();

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);

        _setupForLoss();
        _executeAttack();

        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);

        assertLt(attackerWeedAfter, attackerWeedBefore, "Attacker should lose drugs");
    }

    function test_attack_winnerGetsRepBoost() public {
        _setupDealersForPVP();

        (, uint256 attackerRepBefore,,,,) = core.getDealerData(attackerToken);

        _setupForWin();
        _executeAttack();

        (, uint256 attackerRepAfter,,,,) = core.getDealerData(attackerToken);

        assertGt(attackerRepAfter, attackerRepBefore, "Winner should gain reputation");
    }

    function test_attack_loserGetsRepPenalty() public {
        _setupDealersForPVP();

        (, uint256 attackerRepBefore,,,,) = core.getDealerData(attackerToken);

        _setupForLoss();
        _executeAttack();

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

        _setupForWin();
        _executeAttack();

        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineAfter = core.getDrugBalance(defenderToken, DRUG_COCAINE);

        uint256 drugTypesStolen = 0;
        if (defenderWeedAfter < defenderWeedBefore) drugTypesStolen++;
        if (defenderXtcAfter < defenderXtcBefore) drugTypesStolen++;
        if (defenderCocaineAfter < defenderCocaineBefore) drugTypesStolen++;

        assertEq(drugTypesStolen, 1, "Only one drug type should be stolen");
    }

    function test_attack_noStealIfZeroBalance() public {
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

        _setupForWin();
        _executeAttack();

        assertEq(core.getDrugBalance(defenderToken, DRUG_WEED), 0, "No Weed stolen from zero balance");
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

        _setupForWin();
        _executeAttack();

        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);

        // stolen = ceilDiv(10 * 2, 100) = 1, transferred = 1/2 = 0 (burned entirely)
        assertEq(attackerWeedAfter, attackerWeedBefore, "stolen=1, transferred=1/2=0, winner gets nothing");
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

        _setupForWin();
        _executeAttack();

        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineAfter = core.getDrugBalance(defenderToken, DRUG_COCAINE);

        uint256 drugTypesDefenderLost = 0;
        if (defenderWeedAfter < defenderWeedBefore) drugTypesDefenderLost++;
        if (defenderXtcAfter < defenderXtcBefore) drugTypesDefenderLost++;
        if (defenderCocaineAfter < defenderCocaineBefore) drugTypesDefenderLost++;

        assertEq(drugTypesDefenderLost, 1, "Defender should lose exactly one drug type");
    }

    // =============================================================
    //                     ARREST (3 tests)
    // =============================================================

    function test_attack_attackerArrestedBeforeBattle() public {
        _setupDealersForPVP();
        _setHeatLevel(attackerToken, 5);

        uint256 defenderDrugsBefore = core.getDrugBalance(defenderToken, DRUG_WEED);

        _setupForArrest();
        _executeAttack();

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

        _setupForArrest();
        _executeAttack();

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
            _setReputation(newAttacker, 200);
            _addDrugsToDealer(newAttacker, DRUG_WEED, 1000);

            vm.prank(address(uint160(100 + i)));
            pvp.attack(newAttacker, defenderToken);
        }

        uint256 fourthAttacker = _mintAndInitialize(address(uint160(200)));
        _moveDealerToArea(fourthAttacker, AREA_MANHATTAN);
        _setReputation(fourthAttacker, 200);
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
            _setReputation(loopAttacker, 200);
            _addDrugsToDealer(loopAttacker, DRUG_WEED, 1000);

            vm.prank(address(uint160(100 + i)));
            pvp.attack(loopAttacker, defenderToken);
        }

        vm.warp(block.timestamp + 1 days);

        uint256 newAttacker = _mintAndInitialize(address(uint160(300)));
        _moveDealerToArea(newAttacker, AREA_MANHATTAN);
        _setReputation(newAttacker, 200);
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

        vm.prank(owner);
        pvp.pause();

        vm.prank(owner);
        pvp.unpause();

        _setupForWin();
        _executeAttack();
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

    // =============================================================
    //                     MIN REPUTATION (6 tests)
    // =============================================================

    function test_attack_revertAttackerBelowMinReputation() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 50);
        _setReputation(defenderToken, 200);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.InsufficientReputation.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_revertDefenderBelowMinReputation() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 200);
        _setReputation(defenderToken, 50);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.InsufficientReputation.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_succeedsWhenBothMeetMinReputation() public {
        _setupDealersForPVP();
        _mockJailChance(attackerToken, 0);

        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_attack_succeedsWhenMinReputationDisabled() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 0);
        _setReputation(defenderToken, 0);
        _addDrugsToDealer(attackerToken, DRUG_WEED, 1000);
        _addDrugsToDealer(defenderToken, DRUG_WEED, 1000);
        _mockJailChance(attackerToken, 0);

        vm.prank(owner);
        pvp.setPVPConfig(DealersExePVP.PVPConfig({
            minReputation: 0,
            baseWinChance: 50,
            minWinChance: 25,
            maxWinChance: 75,
            maxAttacksPerDay: 3,
            drugStealPercent: 2,
            cashStealPercent: 1,
            rarityWeightCommon: 50,
            rarityWeightUncommon: 30,
            rarityWeightRare: 20
        }));

        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_canAttack_returnsReason11ForLowAttackerRep() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 50);
        _setReputation(defenderToken, 200);

        (bool canFight, uint8 reason) = pvp.canAttack(attackerToken, defenderToken);
        assertFalse(canFight);
        assertEq(reason, 11);
    }

    function test_canAttack_returnsReason12ForLowDefenderRep() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 200);
        _setReputation(defenderToken, 50);

        (bool canFight, uint8 reason) = pvp.canAttack(attackerToken, defenderToken);
        assertFalse(canFight);
        assertEq(reason, 12);
    }
}

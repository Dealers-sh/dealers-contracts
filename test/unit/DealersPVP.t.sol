// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";

contract DealersPVPTest is BaseTest {
    uint256 attackerToken;
    uint256 defenderToken;

    uint256 constant DRUG_WEED = 4;
    uint256 constant DRUG_XTC = 5;
    uint256 constant DRUG_COCAINE = 6;

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
        core.forceMove(tokenId, core.JAIL_AREA());
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
        bool,
        uint8 cashMultiplier
    ) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.applyBoost(
            tokenId, duration, drugMultiplier, repMultiplier, extraAttempts, freeAreaMovement, cashMultiplier
        );
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

    function _mockJailChance(uint256 tokenId, uint16) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.setHeatLevel(tokenId, 0);
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    /// @dev Cached values for the next _executeAttack to feed into commit-reveal mock
    uint256 internal _stagedRand;

    function _stageRand(uint16 jailRng, uint16 winRng, uint16 drugRng, uint16 dropRng) internal {
        _stagedRand = _packRand(jailRng, winRng, drugRng, dropRng, 0);
    }

    function _setupForWin() internal {
        _mockJailChance(attackerToken, 0);
        _setDealerStats(attackerToken, 25, 0);
        _setDealerStats(defenderToken, 0, 0);
        _stageRand(999, 0, 10, 0); // jailRng high (no arrest), winRng=0 (win), drugRng=10, dropRng=0 (no drop)
    }

    function _setupForLoss() internal {
        _mockJailChance(attackerToken, 0);
        _setDealerStats(attackerToken, 0, 0);
        _setDealerStats(defenderToken, 0, 25);
        _stageRand(999, 99, 10, 0); // no arrest, winRng=99 (loss against weakened win chance)
    }

    function _setupForArrest() internal {
        _stageRand(0, 0, 0, 0); // jailRng=0 forces arrest if heat > 0
    }

    function _executeAttack() internal {
        vm.prank(player1);
        uint64 seq = pvp.commitAttack(attackerToken, defenderToken);
        _mockReveal(seq, _stagedRand);
        _advanceToRevealable(seq);
        pvp.resolveAttack(seq);
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

        uint256 winChance = multicall.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 50, "Base win chance should be 50%");
    }

    function test_calculateWinChance_threatBonus() public {
        _setupDealersForPVP();
        _setDealerStats(attackerToken, 10, 0);

        uint256 winChance = multicall.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 60, "Threat bonus should increase win chance");
    }

    function test_calculateWinChance_armorPenalty() public {
        _setupDealersForPVP();
        _setDealerStats(defenderToken, 0, 15);

        uint256 winChance = multicall.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 35, "Defender armor should reduce attacker win chance");
    }

    function test_calculateWinChance_min25() public {
        _setupDealersForPVP();
        _setDealerStats(defenderToken, 0, 25);
        _setDealerStats(attackerToken, 0, 0);

        uint256 winChance = multicall.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 25, "Win chance should not go below 25%");
    }

    function test_calculateWinChance_max75() public {
        _setupDealersForPVP();
        _setDealerStats(attackerToken, 25, 0);
        _setDealerStats(defenderToken, 0, 0);

        uint256 winChance = multicall.calculateWinChance(attackerToken, defenderToken);

        assertEq(winChance, 75, "Win chance should not exceed 75%");
    }

    // =============================================================
    //                     VALIDATION (7 tests)
    // =============================================================

    function test_attack_revertSameDealer() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);

        vm.prank(player1);
        vm.expectRevert(DealersPVP.SameDealer.selector);
        pvp.commitAttack(attackerToken, attackerToken);
    }

    function test_attack_revertDifferentArea() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);

        vm.prank(owner);
        uint8 brooklynId = areaRegistry.createArea("Brooklyn", 0.001 ether, 0, false, false);
        areaRegistry.configureAreaDrug(brooklynId, DRUG_WEED, 1, 1);

        _moveDealerToArea(defenderToken, brooklynId);

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DifferentArea.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_attack_revertAttackerInJail() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _sendDealerToJail(attackerToken);

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DealerInJail.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_attack_revertDefenderInJail() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _sendDealerToJail(defenderToken);

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DealerInJail.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_attack_revertAttackerInSafeHouse() public {
        // Dealers now start in Manhattan, move attacker to Safe House
        vm.prank(player1);
        actions.travel{value: 0}(attackerToken, AREA_SAFE_HOUSE);

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DealerInSafeHouse.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_attack_revertDefenderInSafeHouse() public {
        // Dealers now start in Manhattan, move defender to Safe House
        vm.prank(player2);
        actions.travel{value: 0}(defenderToken, AREA_SAFE_HOUSE);

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DealerInSafeHouse.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_attack_revertDealerNotInitialized() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);

        uint256 uninitTokenId = 99999;

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DealerNotInitialized.selector);
        pvp.commitAttack(attackerToken, uninitTokenId);
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

        assertEq(attackerWeedAfter, attackerWeedBefore + stolen, "Attacker gains all stolen drugs");
    }

    function test_attack_attackerLoses_noStealFromAttacker() public {
        _setupDealersForPVP();

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);

        _setupForLoss();
        _executeAttack();

        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);

        assertEq(attackerWeedAfter, attackerWeedBefore, "Attacker drugs unchanged on loss");
        assertEq(defenderWeedAfter, defenderWeedBefore, "Defender drugs unchanged on attacker loss");
    }

    function test_attack_attackerLoses_defenderGetsFlat2Rep() public {
        _setupDealersForPVP();

        (, uint256 defenderRepBefore,,,,) = core.getDealerData(defenderToken);

        _setupForLoss();
        _executeAttack();

        (, uint256 defenderRepAfter,,,,) = core.getDealerData(defenderToken);

        assertEq(defenderRepAfter, defenderRepBefore + 2, "Defender should gain flat +2 rep");
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
        _addDrugsToDealer(attackerToken, DRUG_XTC, 500);
        _addDrugsToDealer(attackerToken, DRUG_COCAINE, 100);
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

        // stolen = ceilDiv(10 * 2, 100) = 1, winner gets all
        assertEq(attackerWeedAfter, attackerWeedBefore + 1, "stolen=1, winner gets all");
        assertEq(defenderWeedAfter, 9, "Defender loses 1 (rounded up from 0.2)");
    }

    function test_attack_onlyOneDrugTypeStolen() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _addDrugsToDealer(attackerToken, DRUG_XTC, 200);
        _addDrugsToDealer(attackerToken, DRUG_COCAINE, 500);
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

        assertTrue(_isInJail(attackerToken), "Attacker should be in jail");
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

        assertTrue(_isInJail(attackerToken), "Attacker should be in jail");
        assertFalse(_isInJail(defenderToken), "Defender should not be in jail");
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
            pvp.commitAttack(newAttacker, defenderToken);
        }

        uint256 fourthAttacker = _mintAndInitialize(address(uint160(200)));
        _moveDealerToArea(fourthAttacker, AREA_MANHATTAN);
        _setReputation(fourthAttacker, 200);
        _addDrugsToDealer(fourthAttacker, DRUG_WEED, 1000);

        vm.prank(address(uint160(200)));
        vm.expectRevert(DealersPVP.DefenderExhausted.selector);
        pvp.commitAttack(fourthAttacker, defenderToken);
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
            pvp.commitAttack(loopAttacker, defenderToken);
        }

        vm.warp(block.timestamp + 1 days);

        uint256 newAttacker = _mintAndInitialize(address(uint160(300)));
        _moveDealerToArea(newAttacker, AREA_MANHATTAN);
        _setReputation(newAttacker, 200);
        _addDrugsToDealer(newAttacker, DRUG_WEED, 1000);

        vm.prank(address(uint160(300)));
        pvp.commitAttack(newAttacker, defenderToken);

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
        vm.expectRevert(DealersPVP.ContractPaused.selector);
        pvp.commitAttack(attackerToken, defenderToken);
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
        vm.expectRevert(DealersPVP.ContractNotSet.selector);
        pvp.setCore(address(0));
    }

    function test_setNFTContract_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DealersPVP.ContractNotSet.selector);
        pvp.setNFTContract(address(0));
    }

    function test_setAreaRegistry_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DealersPVP.ContractNotSet.selector);
        pvp.setAreaRegistry(address(0));
    }

    function test_setRandomness_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DealersPVP.ContractNotSet.selector);
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
        vm.expectRevert(DealersPVP.InsufficientReputation.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_attack_revertDefenderBelowMinReputation() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 200);
        _setReputation(defenderToken, 50);

        vm.prank(player1);
        vm.expectRevert(DealersPVP.InsufficientReputation.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_attack_succeedsWhenBothMeetMinReputation() public {
        _setupDealersForPVP();
        _mockJailChance(attackerToken, 0);

        vm.prank(player1);
        pvp.commitAttack(attackerToken, defenderToken);
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
        pvp.setPVPConfig(
            IDealersPVP.PVPConfig({
                minReputation: 0,
                baseWinChance: 50,
                minWinChance: 25,
                maxWinChance: 75,
                maxAttacksPerDay: 3,
                drugStealPercent: 2,
                cashStealPercent: 1,
                rarityWeightCommon: 50,
                rarityWeightUncommon: 30,
                rarityWeightRare: 20,
                repRangePercent: 100,
                defenderRepBonus: 2,
                repRangeThreshold: 0
            })
        );

        vm.prank(player1);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_canAttack_returnsReason11ForOutOfRepRange() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 1000);
        _setReputation(defenderToken, 2000);

        (bool canFight, uint8 reason) = multicall.canAttack(attackerToken, defenderToken);
        assertFalse(canFight);
        assertEq(reason, 11);
    }

    function test_canAttack_returnsReason12ForBelowMinReputation() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 50);
        _setReputation(defenderToken, 50);

        (bool canFight, uint8 reason) = multicall.canAttack(attackerToken, defenderToken);
        assertFalse(canFight);
        assertEq(reason, 12);
    }

    function test_pvpStats_attackerWinUpdatesStats() public {
        _setupDealersForPVP();
        _setupForWin();
        _executeAttack();

        IDealersPVP.PvpStats memory attackerStats = pvp.getDealerPvpStats(attackerToken);
        IDealersPVP.PvpStats memory defenderStats = pvp.getDealerPvpStats(defenderToken);

        assertEq(attackerStats.attackWins, 1);
        assertEq(attackerStats.attackLosses, 0);
        assertEq(defenderStats.defendLosses, 1);
        assertEq(defenderStats.defendWins, 0);
    }

    function test_pvpStats_defenderWinUpdatesStats() public {
        _setupDealersForPVP();
        _setupForLoss();
        _executeAttack();

        IDealersPVP.PvpStats memory attackerStats = pvp.getDealerPvpStats(attackerToken);
        IDealersPVP.PvpStats memory defenderStats = pvp.getDealerPvpStats(defenderToken);

        assertEq(attackerStats.attackLosses, 1);
        assertEq(attackerStats.attackWins, 0);
        assertEq(defenderStats.defendWins, 1);
        assertEq(defenderStats.defendLosses, 0);
    }

    // =============================================================
    //                     REP RANGE (6 tests)
    // =============================================================

    function test_canAttack_failsForOutOfRepRange() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 1000);
        _setReputation(defenderToken, 2000);

        (bool canFight, uint8 reason) = multicall.canAttack(attackerToken, defenderToken);
        assertFalse(canFight, "Should not be able to attack out of rep range");
        assertEq(reason, 11, "Reason should be 11 (out of rep range)");
    }

    function test_canAttack_succeedsWithinRepRange() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 1000);
        _setReputation(defenderToken, 1200);

        (bool canFight,) = multicall.canAttack(attackerToken, defenderToken);
        assertTrue(canFight, "Should be able to attack within rep range");
    }

    function test_canAttack_repRangeEdgeCases() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 1000);

        // Exactly at upper boundary: 1000 + 25% = 1250
        _setReputation(defenderToken, 1250);
        (bool canFight,) = multicall.canAttack(attackerToken, defenderToken);
        assertTrue(canFight, "Exactly at upper boundary should succeed");

        // One above upper boundary
        _setReputation(defenderToken, 1251);
        (canFight,) = multicall.canAttack(attackerToken, defenderToken);
        assertFalse(canFight, "One above upper boundary should fail");

        // Exactly at lower boundary: 1000 - 25% = 750
        _setReputation(defenderToken, 750);
        (canFight,) = multicall.canAttack(attackerToken, defenderToken);
        assertTrue(canFight, "Exactly at lower boundary should succeed");

        // One below lower boundary
        _setReputation(defenderToken, 749);
        (canFight,) = multicall.canAttack(attackerToken, defenderToken);
        assertFalse(canFight, "One below lower boundary should fail");
    }

    function test_getPotentialTargets_filtersOnRepRange() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 1000);

        uint256 inRangeToken = _mintAndInitialize(address(uint160(500)));
        _moveDealerToArea(inRangeToken, AREA_MANHATTAN);
        _setReputation(inRangeToken, 1200);

        uint256 outOfRangeToken = _mintAndInitialize(address(uint160(501)));
        _moveDealerToArea(outOfRangeToken, AREA_MANHATTAN);
        _setReputation(outOfRangeToken, 2000);

        _setReputation(defenderToken, 900);

        (DealersMulticall.PVPTarget[] memory targets,) = multicall.getPotentialTargets(attackerToken, 0, 100);

        bool foundInRange = false;
        bool foundDefender = false;
        bool foundOutOfRange = false;
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i].tokenId == inRangeToken) foundInRange = true;
            if (targets[i].tokenId == defenderToken) foundDefender = true;
            if (targets[i].tokenId == outOfRangeToken) foundOutOfRange = true;
        }

        assertTrue(foundInRange, "In-range target should be included");
        assertTrue(foundDefender, "Defender within range should be included");
        assertFalse(foundOutOfRange, "Out-of-range target should be excluded");
    }

    function test_attack_revertsOutOfRepRange() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 1000);
        _setReputation(defenderToken, 2000);
        _addDrugsToDealer(attackerToken, DRUG_WEED, 1000);
        _addDrugsToDealer(defenderToken, DRUG_WEED, 1000);

        vm.prank(player1);
        vm.expectRevert(DealersPVP.OutOfRepRange.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_repRangePercent_updatable() public {
        _moveDealerToArea(attackerToken, AREA_MANHATTAN);
        _moveDealerToArea(defenderToken, AREA_MANHATTAN);
        _setReputation(attackerToken, 1000);
        _setReputation(defenderToken, 2000);

        (bool canFight,) = multicall.canAttack(attackerToken, defenderToken);
        assertFalse(canFight, "Should fail with default 25% range");

        vm.prank(owner);
        pvp.setPVPConfig(
            IDealersPVP.PVPConfig({
                minReputation: 100,
                baseWinChance: 50,
                minWinChance: 25,
                maxWinChance: 75,
                maxAttacksPerDay: 3,
                drugStealPercent: 2,
                cashStealPercent: 1,
                rarityWeightCommon: 50,
                rarityWeightUncommon: 30,
                rarityWeightRare: 20,
                repRangePercent: 100,
                defenderRepBonus: 2,
                repRangeThreshold: 0
            })
        );

        (canFight,) = multicall.canAttack(attackerToken, defenderToken);
        assertTrue(canFight, "Should succeed with 100% range");
    }

    // =============================================================
    //                     INFAMY (4 tests)
    // =============================================================

    function test_infamy_increasesOnWin() public {
        _setupDealersForPVP();

        uint256 infamyBefore = core.getInfamy(attackerToken);

        _setupForWin();
        _executeAttack();

        uint256 infamyAfter = core.getInfamy(attackerToken);
        assertEq(infamyAfter, infamyBefore + 3, "Attacker infamy should increase by 3 on win");
    }

    function test_infamy_decreasesOnLoss() public {
        _setupDealersForPVP();

        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.updateInfamy(attackerToken, 5);
        vm.prank(owner);
        core.authorizeContract(address(this), false);

        _setupForLoss();
        _executeAttack();

        uint256 infamyAfter = core.getInfamy(attackerToken);
        assertEq(infamyAfter, 4, "Attacker infamy should decrease by 1 on loss");
    }

    function test_infamy_floorAtZeroOnLoss() public {
        _setupDealersForPVP();

        assertEq(core.getInfamy(attackerToken), 0, "Attacker starts with 0 infamy");

        _setupForLoss();
        _executeAttack();

        assertEq(core.getInfamy(attackerToken), 0, "Infamy cannot go below 0");
    }

    function test_infamy_defenderUnchanged() public {
        _setupDealersForPVP();

        _setupForWin();
        _executeAttack();

        assertEq(core.getInfamy(defenderToken), 0, "Defender infamy unchanged after being attacked");
    }

    // =============================================================
    //                     LOOT DROPS (5 tests)
    // =============================================================

    function _setInfamy(uint256 tokenId, uint256 amount) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.updateInfamy(tokenId, int256(amount));
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function test_lootDrop_noDrop_zeroInfamy() public {
        _setupDealersForPVP();
        _stageRand(uint16(50), uint16(0), uint16(10), uint16(39)); // infamy 0: weights [40,60,0,0], roll 39 < 40 = no drop

        uint256 goodsBefore = core.getDrugBalance(attackerToken, 1);

        _setDealerStats(attackerToken, 25, 0);
        _setDealerStats(defenderToken, 0, 0);
        _executeAttack();

        assertEq(core.getDrugBalance(attackerToken, 1), goodsBefore, "No drop when roll < 40 at infamy 0");
    }

    function test_lootDrop_generalGoods_zeroInfamy() public {
        _setupDealersForPVP();
        _stageRand(uint16(50), uint16(0), uint16(10), uint16(50)); // infamy 0: weights [40,60,0,0], roll 50 -> General Goods

        uint256 goodsBefore = core.getDrugBalance(attackerToken, 1);

        _setDealerStats(attackerToken, 25, 0);
        _setDealerStats(defenderToken, 0, 0);
        _executeAttack();

        assertEq(core.getDrugBalance(attackerToken, 1), goodsBefore + 1, "General Goods at infamy 0");
    }

    function test_lootDrop_contraband_withInfamy20() public {
        _setupDealersForPVP();
        _setInfamy(attackerToken, 20);
        // infamy 20: weights [30,45,20,5], cumulative: 30,75,95,100
        _stageRand(uint16(50), uint16(0), uint16(10), uint16(80)); // roll 80 >= 75 and < 95 = Contraband

        uint256 contrabandBefore = core.getDrugBalance(attackerToken, 2);

        _setDealerStats(attackerToken, 25, 0);
        _setDealerStats(defenderToken, 0, 0);
        _executeAttack();

        assertEq(core.getDrugBalance(attackerToken, 2), contrabandBefore + 1, "Contraband at infamy 20");
    }

    function test_lootDrop_jewels_withInfamy50() public {
        _setupDealersForPVP();
        _setInfamy(attackerToken, 50);
        // infamy 50: weights [15,30,35,20], cumulative: 15,45,80,100
        _stageRand(uint16(50), uint16(0), uint16(10), uint16(95)); // roll 95 >= 80 and < 100 = Jewels

        uint256 jewelsBefore = core.getDrugBalance(attackerToken, 3);

        _setDealerStats(attackerToken, 25, 0);
        _setDealerStats(defenderToken, 0, 0);
        _executeAttack();

        assertEq(core.getDrugBalance(attackerToken, 3), jewelsBefore + 1, "Jewels at infamy 50");
    }

    function test_lootDrop_noDrop_onLoss() public {
        _setupDealersForPVP();
        _stageRand(uint16(50), uint16(99), uint16(10), uint16(50)); // loss, dropRng=50 would trigger goods if won

        uint256 goodsBefore = core.getDrugBalance(attackerToken, 1);

        _setDealerStats(attackerToken, 0, 0);
        _setDealerStats(defenderToken, 0, 25);
        _executeAttack();

        assertEq(core.getDrugBalance(attackerToken, 1), goodsBefore, "No loot drop on loss");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./BaseTest.sol";

contract PVPBattleFlowsTest is BaseTest {
    uint256 attackerToken;
    uint256 defenderToken;

    function setUp() public override {
        super.setUp();

        attackerToken = _mintAndMoveToManhattan(player1);
        defenderToken = _mintAndMoveToManhattan(player2);

        vm.prank(owner);
        core.updateReputation(attackerToken, 200);
        vm.prank(owner);
        core.updateReputation(defenderToken, 200);

        vm.prank(owner);
        core.updateDrugBalance(defenderToken, DRUG_WEED, 100);
        vm.prank(owner);
        core.updateDrugBalance(defenderToken, DRUG_XTC, 50);

        vm.warp(1 hours + 1);
    }

    function _execAttack(uint16 jailRng, uint16 winRng, uint16 drugRng) internal {
        uint256 rand = _packRand(jailRng, winRng, drugRng, 0, 0);
        _commitAndResolvePvp(player1, attackerToken, defenderToken, rand);
    }

    function test_pvpFlow_attackerWins() public {
        vm.prank(owner);
        core.setDealerStats(attackerToken, 25, 0);

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);

        _execAttack(999, 0, 10);

        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);

        uint256 stolen = defenderWeedBefore - defenderWeedAfter;
        uint256 expected = _ceilDiv(defenderWeedBefore * 2, 100);
        assertEq(stolen, expected, "Should steal 2% of weed (rounded up)");

        assertEq(attackerWeedAfter, attackerWeedBefore + stolen, "Attacker gains all stolen weed");
    }

    function test_pvpFlow_defenderWins() public {
        vm.prank(owner);
        core.setDealerStats(defenderToken, 0, 25);
        vm.prank(owner);
        core.updateDrugBalance(attackerToken, DRUG_WEED, 80);

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);

        _execAttack(999, 99, 10);

        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);

        assertEq(attackerWeedAfter, attackerWeedBefore, "Attacker should not lose drugs when defender wins");
    }

    function test_pvpFlow_attackerArrestedMidFight() public {
        for (uint8 i = 0; i < 5; i++) {
            vm.prank(owner);
            core.incrementHeatLevel(attackerToken);
        }

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);

        _execAttack(0, 0, 0);

        assertTrue(core.getGameState(attackerToken).isJailed, "Attacker should be in jail");
        assertEq(
            core.getDrugBalance(defenderToken, DRUG_WEED),
            defenderWeedBefore,
            "Defender drugs unchanged when attacker arrested"
        );

        (uint8 area, , , , , ) = core.getDealerData(attackerToken);
        assertEq(area, JAIL, "Attacker area should be JAIL");
    }

    function test_pvpFlow_mustBeSameArea() public {
        vm.prank(owner);
        uint8 brooklynId = areaRegistry.createArea("Brooklyn", 0.001 ether, 0, false, false);
        areaRegistry.configureAreaDrug(brooklynId, DRUG_WEED, 1, 1);

        uint256 brooklynToken = _mintNFT(player1);
        vm.prank(owner);
        core.moveToArea(brooklynToken, brooklynId);
        vm.prank(owner);
        core.updateReputation(brooklynToken, 200);

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DifferentArea.selector);
        pvp.commitAttack(brooklynToken, defenderToken);
    }

    function test_pvpFlow_cannotAttackSelf() public {
        vm.prank(player1);
        vm.expectRevert(DealersPVP.SameDealer.selector);
        pvp.commitAttack(attackerToken, attackerToken);
    }

    function test_pvpFlow_cannotAttackFromJail() public {
        vm.prank(owner);
        core.forceMove(attackerToken, core.JAIL_AREA());

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DealerInJail.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_pvpFlow_cannotAttackFromSafeHouse() public {
        uint256 safeToken = _mintNFT(player1);
        vm.prank(owner);
        core.updateReputation(safeToken, 200);

        vm.prank(player1);
        actions.travel{value: 0}(safeToken, SAFE_HOUSE);

        (uint8 area, , , , , ) = core.getDealerData(safeToken);
        assertEq(area, SAFE_HOUSE, "Should be in safe house");

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DealerInSafeHouse.selector);
        pvp.commitAttack(safeToken, defenderToken);
    }

    function test_pvpFlow_cannotAttackJailedDealer() public {
        vm.prank(owner);
        core.forceMove(defenderToken, core.JAIL_AREA());

        vm.prank(player1);
        vm.expectRevert(DealersPVP.DealerInJail.selector);
        pvp.commitAttack(attackerToken, defenderToken);
    }

    function test_pvpFlow_winChanceCalculation() public {
        uint256 baseChance = pvp.calculateWinChance(attackerToken, defenderToken);
        assertEq(baseChance, 50, "Base win chance should be 50%");

        vm.prank(owner);
        core.setDealerStats(attackerToken, 25, 0);

        uint256 highThreatChance = pvp.calculateWinChance(attackerToken, defenderToken);
        assertEq(highThreatChance, 75, "Max win chance should be 75%");

        vm.prank(owner);
        core.setDealerStats(attackerToken, 0, 0);
        vm.prank(owner);
        core.setDealerStats(defenderToken, 0, 25);

        uint256 highArmorChance = pvp.calculateWinChance(attackerToken, defenderToken);
        assertEq(highArmorChance, 25, "Min win chance should be 25%");
    }

    function test_pvpFlow_reputationChanges() public {
        (, uint256 attackerRepBefore, , , , ) = core.getDealerData(attackerToken);

        _execAttack(999, 0, 10);

        (, uint256 attackerRepAfter, , , , ) = core.getDealerData(attackerToken);
        assertTrue(attackerRepAfter != attackerRepBefore, "Reputation should change after battle");
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        return (a - 1) / b + 1;
    }
}

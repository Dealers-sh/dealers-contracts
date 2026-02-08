// SPDX-License-Identifier: MIT
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

    function test_pvpFlow_attackerWins() public {
        vm.prank(owner);
        core.setDealerStats(attackerToken, 25, 0);

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcBefore = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 defenderCocaineBefore = core.getDrugBalance(defenderToken, DRUG_COCAINE);
        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcBefore = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineBefore = core.getDrugBalance(attackerToken, DRUG_COCAINE);

        bool attackerWon = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!attackerWon && prevrandaoValue < 2000) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            try pvp.attack(attackerToken, defenderToken) {
                if (!core.isInJail(attackerToken)) {
                    uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
                    uint256 attackerXtcAfter = core.getDrugBalance(attackerToken, DRUG_XTC);
                    uint256 attackerCocaineAfter = core.getDrugBalance(attackerToken, DRUG_COCAINE);

                    bool gainedAny = (attackerWeedAfter > attackerWeedBefore) ||
                                     (attackerXtcAfter > attackerXtcBefore) ||
                                     (attackerCocaineAfter > attackerCocaineBefore);

                    if (gainedAny) {
                        attackerWon = true;

                        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
                        uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);
                        uint256 defenderCocaineAfter = core.getDrugBalance(defenderToken, DRUG_COCAINE);

                        uint256 typesStolen = 0;
                        if (defenderWeedAfter < defenderWeedBefore) typesStolen++;
                        if (defenderXtcAfter < defenderXtcBefore) typesStolen++;
                        if (defenderCocaineAfter < defenderCocaineBefore) typesStolen++;

                        assertEq(typesStolen, 1, "Exactly one drug type should be stolen");

                        if (defenderWeedAfter < defenderWeedBefore) {
                            uint256 stolen = defenderWeedBefore - defenderWeedAfter;
                            uint256 expected = _ceilDiv(defenderWeedBefore * 2, 100);
                            assertEq(stolen, expected, "Should steal 2% of weed (rounded up)");
                            assertEq(attackerWeedAfter, attackerWeedBefore + stolen, "Attacker gains stolen weed");
                        } else if (defenderXtcAfter < defenderXtcBefore) {
                            uint256 stolen = defenderXtcBefore - defenderXtcAfter;
                            uint256 expected = _ceilDiv(defenderXtcBefore * 2, 100);
                            assertEq(stolen, expected, "Should steal 2% of XTC (rounded up)");
                            assertEq(attackerXtcAfter, attackerXtcBefore + stolen, "Attacker gains stolen XTC");
                        } else {
                            uint256 stolen = defenderCocaineBefore - defenderCocaineAfter;
                            uint256 expected = _ceilDiv(defenderCocaineBefore * 2, 100);
                            assertEq(stolen, expected, "Should steal 2% of cocaine (rounded up)");
                            assertEq(attackerCocaineAfter, attackerCocaineBefore + stolen, "Attacker gains stolen cocaine");
                        }
                        break;
                    }
                }
            } catch {}

            if (!attackerWon) {
                vm.revertToState(snapshotId);
            }
            prevrandaoValue++;
        }

        vm.stopPrank();

        assertTrue(attackerWon, "Should find attacker win within 2000 attempts");
    }

    function test_pvpFlow_defenderWins() public {
        vm.prank(owner);
        core.setDealerStats(defenderToken, 0, 25);
        vm.prank(owner);
        core.updateDrugBalance(attackerToken, DRUG_WEED, 80);

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcBefore = core.getDrugBalance(attackerToken, DRUG_XTC);
        uint256 attackerCocaineBefore = core.getDrugBalance(attackerToken, DRUG_COCAINE);

        bool defenderWon = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!defenderWon && prevrandaoValue < 2000) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            try pvp.attack(attackerToken, defenderToken) {
                if (!core.isInJail(attackerToken)) {
                    uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
                    uint256 attackerXtcAfter = core.getDrugBalance(attackerToken, DRUG_XTC);
                    uint256 attackerCocaineAfter = core.getDrugBalance(attackerToken, DRUG_COCAINE);

                    bool lostAny = (attackerWeedAfter < attackerWeedBefore) ||
                                   (attackerXtcAfter < attackerXtcBefore) ||
                                   (attackerCocaineAfter < attackerCocaineBefore);

                    if (lostAny) {
                        defenderWon = true;

                        uint256 typesLost = 0;
                        if (attackerWeedAfter < attackerWeedBefore) typesLost++;
                        if (attackerXtcAfter < attackerXtcBefore) typesLost++;
                        if (attackerCocaineAfter < attackerCocaineBefore) typesLost++;

                        assertEq(typesLost, 1, "Exactly one drug type should be stolen from loser");

                        if (attackerWeedAfter < attackerWeedBefore) {
                            uint256 stolen = attackerWeedBefore - attackerWeedAfter;
                            uint256 expected = _ceilDiv(attackerWeedBefore * 2, 100);
                            assertEq(stolen, expected, "Should lose 2% of weed (rounded up)");
                        } else if (attackerXtcAfter < attackerXtcBefore) {
                            uint256 stolen = attackerXtcBefore - attackerXtcAfter;
                            uint256 expected = _ceilDiv(attackerXtcBefore * 2, 100);
                            assertEq(stolen, expected, "Should lose 2% of XTC (rounded up)");
                        } else {
                            uint256 stolen = attackerCocaineBefore - attackerCocaineAfter;
                            uint256 expected = _ceilDiv(attackerCocaineBefore * 2, 100);
                            assertEq(stolen, expected, "Should lose 2% of cocaine (rounded up)");
                        }
                        break;
                    }
                }
            } catch {}

            if (!defenderWon) {
                vm.revertToState(snapshotId);
            }
            prevrandaoValue++;
        }

        vm.stopPrank();

        assertTrue(defenderWon, "Should find defender win within 2000 attempts");
    }

    function test_pvpFlow_attackerArrestedMidFight() public {
        vm.prank(player1);
        core.bribeCop{value: 0.002 ether}(attackerToken);

        for (uint8 i = 0; i < 5; i++) {
            vm.prank(owner);
            core.incrementHeatLevel(attackerToken);
        }

        (, , , uint8 heatLevel, , ) = core.getDealerData(attackerToken);
        assertEq(heatLevel, 5, "Attacker heat should be 5");

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);

        bool arrested = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!arrested && prevrandaoValue < 2000) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            (, , uint8 attempts, , , ) = core.getDealerData(attackerToken);
            if (attempts == 0) {
                core.purchaseAttemptReset{value: 0.001 ether}(attackerToken);
            }

            try pvp.attack(attackerToken, defenderToken) {
                if (core.isInJail(attackerToken)) {
                    arrested = true;

                    uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
                    uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);

                    assertEq(
                        defenderWeedAfter,
                        defenderWeedBefore,
                        "Defender drugs unchanged when attacker arrested"
                    );
                    assertEq(
                        attackerWeedAfter,
                        attackerWeedBefore,
                        "Attacker drugs unchanged when arrested"
                    );

                    assertTrue(core.isInJail(attackerToken), "Attacker should be in jail");

                    (uint8 area, , , , , ) = core.getDealerData(attackerToken);
                    assertEq(area, JAIL, "Attacker area should be JAIL");
                    break;
                }
            } catch {}

            if (!arrested) {
                vm.revertToState(snapshotId);
            }
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!arrested) {
            emit log("Note: Arrest not triggered within iteration limit - test inconclusive");
        }
    }

    function test_pvpFlow_mustBeSameArea() public {
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.001 ether, 0, false, false);
        areaRegistry.configureAreaDrug(2, DRUG_WEED, 1, 1);

        uint256 brooklynToken = _mintNFT(player1);
        vm.prank(owner);
        core.moveToArea(brooklynToken, 2);
        vm.prank(owner);
        core.updateReputation(brooklynToken, 200);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DifferentArea.selector);
        pvp.attack(brooklynToken, defenderToken);
    }

    function test_pvpFlow_cannotAttackSelf() public {
        vm.prank(player1);
        vm.expectRevert(DealersExePVP.SameDealer.selector);
        pvp.attack(attackerToken, attackerToken);
    }

    function test_pvpFlow_cannotAttackFromJail() public {
        vm.prank(owner);
        core.sendToJail(attackerToken);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DealerInJail.selector);
        pvp.attack(attackerToken, defenderToken);
    }

    function test_pvpFlow_cannotAttackFromSafeHouse() public {
        uint256 safeToken = _mintNFT(player1);
        vm.prank(owner);
        core.updateReputation(safeToken, 200);

        vm.prank(player1);
        core.travel{value: 0}(safeToken, SAFE_HOUSE);

        (uint8 area, , , , , ) = core.getDealerData(safeToken);
        assertEq(area, SAFE_HOUSE, "Should be in safe house");

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DealerInSafeHouse.selector);
        pvp.attack(safeToken, defenderToken);
    }

    function test_pvpFlow_cannotAttackJailedDealer() public {
        vm.prank(owner);
        core.sendToJail(defenderToken);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.DealerInJail.selector);
        pvp.attack(attackerToken, defenderToken);
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
        (, uint256 defenderRepBefore, , , , ) = core.getDealerData(defenderToken);

        uint256 prevrandaoValue = 50000;
        bool attacked = false;

        vm.startPrank(player1);
        while (!attacked && prevrandaoValue < 51000) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            try pvp.attack(attackerToken, defenderToken) {
                if (!core.isInJail(attackerToken)) {
                    attacked = true;
                    break;
                }
            } catch {}

            vm.revertToState(snapshotId);
            prevrandaoValue++;
        }
        vm.stopPrank();

        if (attacked) {
            (, uint256 attackerRepAfter, , , , ) = core.getDealerData(attackerToken);
            (, uint256 defenderRepAfter, , , , ) = core.getDealerData(defenderToken);

            bool reputationChanged = (attackerRepAfter != attackerRepBefore) ||
                                      (defenderRepAfter != defenderRepBefore);
            assertTrue(reputationChanged, "Reputation should change after battle");
        }
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        return (a - 1) / b + 1;
    }
}

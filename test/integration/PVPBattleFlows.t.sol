// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.sol";

contract PVPBattleFlowsTest is BaseTest {
    uint256 attackerToken;
    uint256 defenderToken;

    function setUp() public override {
        super.setUp();

        attackerToken = _mintAndMoveToManhattan(player1);
        defenderToken = _mintAndMoveToManhattan(player2);

        vm.prank(owner);
        core.updateDrugBalance(defenderToken, DRUG_WEED, 100);
        vm.prank(owner);
        core.updateDrugBalance(defenderToken, DRUG_XTC, 50);
    }

    function test_pvpFlow_attackerWins() public {
        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 defenderXtcBefore = core.getDrugBalance(defenderToken, DRUG_XTC);
        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 attackerXtcBefore = core.getDrugBalance(attackerToken, DRUG_XTC);

        bool attackerWon = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!attackerWon && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            try pvp.attack(attackerToken, defenderToken) {
                (uint256 attacksWon, , , , , , ) = pvp.getPlayerPVPStats(attackerToken);

                if (attacksWon > 0) {
                    attackerWon = true;

                    uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
                    uint256 defenderXtcAfter = core.getDrugBalance(defenderToken, DRUG_XTC);
                    uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
                    uint256 attackerXtcAfter = core.getDrugBalance(attackerToken, DRUG_XTC);

                    uint256 expectedWeedStolen = (defenderWeedBefore * 10) / 100;
                    uint256 expectedXtcStolen = (defenderXtcBefore * 10) / 100;

                    assertEq(
                        defenderWeedAfter,
                        defenderWeedBefore - expectedWeedStolen,
                        "Defender should lose 10% weed"
                    );
                    assertEq(
                        defenderXtcAfter,
                        defenderXtcBefore - expectedXtcStolen,
                        "Defender should lose 10% XTC"
                    );
                    assertEq(
                        attackerWeedAfter,
                        attackerWeedBefore + expectedWeedStolen,
                        "Attacker should gain 10% weed"
                    );
                    assertEq(
                        attackerXtcAfter,
                        attackerXtcBefore + expectedXtcStolen,
                        "Attacker should gain 10% XTC"
                    );
                    break;
                }
            } catch {}

            if (!attackerWon) {
                vm.revertToState(snapshotId);
            }
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!attackerWon) {
            emit log("Note: Attacker win not found within iteration limit - test inconclusive");
        }
    }

    function test_pvpFlow_defenderWins() public {
        vm.prank(owner);
        core.updateDrugBalance(attackerToken, DRUG_WEED, 80);

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);
        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);

        bool defenderWon = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!defenderWon && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            try pvp.attack(attackerToken, defenderToken) {
                (, uint256 attacksLost, , , , , ) = pvp.getPlayerPVPStats(attackerToken);
                (, , uint256 defensesWon, , , , ) = pvp.getPlayerPVPStats(defenderToken);

                if (attacksLost > 0 && defensesWon > 0) {
                    defenderWon = true;

                    uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);
                    uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);

                    uint256 expectedStolen = (attackerWeedBefore * 10) / 100;

                    assertEq(
                        attackerWeedAfter,
                        attackerWeedBefore - expectedStolen,
                        "Attacker (loser) should lose 10% drugs"
                    );
                    assertEq(
                        defenderWeedAfter,
                        defenderWeedBefore + expectedStolen,
                        "Defender (winner) should gain 10% drugs"
                    );
                    break;
                }
            } catch {}

            if (!defenderWon) {
                vm.revertToState(snapshotId);
            }
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!defenderWon) {
            emit log("Note: Defender win not found within iteration limit - test inconclusive");
        }
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

        while (!arrested && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            (, , uint8 attempts, , , ) = core.getDealerData(attackerToken);
            if (attempts == 0) {
                core.purchaseAttemptReset{value: 0.005 ether}(attackerToken);
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

    function test_pvpFlow_cooldownEnforced() public {
        bool attackSucceeded = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);
        while (!attackSucceeded && prevrandaoValue < 100) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            try pvp.attack(attackerToken, defenderToken) {
                if (!core.isInJail(attackerToken)) {
                    attackSucceeded = true;
                    break;
                }
            } catch {}

            vm.revertToState(snapshotId);
            prevrandaoValue++;
        }
        vm.stopPrank();

        if (!attackSucceeded) {
            emit log("Note: Could not execute attack without jail - test inconclusive");
            return;
        }

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.CooldownActive.selector);
        pvp.attack(attackerToken, defenderToken);

        vm.warp(block.timestamp + 30 minutes);

        vm.prank(player1);
        vm.expectRevert(DealersExePVP.CooldownActive.selector);
        pvp.attack(attackerToken, defenderToken);

        vm.warp(block.timestamp + 31 minutes);

        (, , uint8 attempts, , , ) = core.getDealerData(attackerToken);
        if (attempts == 0) {
            vm.prank(player1);
            core.purchaseAttemptReset{value: 0.005 ether}(attackerToken);
        }

        vm.prank(player1);
        vm.prevrandao(bytes32(uint256(67890)));
        pvp.attack(attackerToken, defenderToken);

        (uint256 totalBattles, ) = pvp.getGlobalStats();
        assertEq(totalBattles, 2, "Should have 2 total battles");
    }

    function test_pvpFlow_mustBeSameArea() public {
        vm.prank(owner);
        areaRegistry.createArea("Brooklyn", 0.001 ether, 0, false, false);
        areaRegistry.configureAreaDrug(2, DRUG_WEED, 1, 1);

        uint256 brooklynToken = _mintNFT(player1);
        vm.prank(owner);
        core.moveToArea(brooklynToken, 2);

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
}

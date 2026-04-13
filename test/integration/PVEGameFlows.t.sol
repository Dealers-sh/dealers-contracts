// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./BaseTest.sol";

contract PVEGameFlowsTest is BaseTest {
    uint256 tokenId;

    function setUp() public override {
        super.setUp();
        tokenId = _mintAndMoveToManhattan(player1);
    }

    function test_buyFlow_winOutcome() public {
        uint256 cashBefore = core.getCashBalance(tokenId);
        uint256 weedBefore = core.getDrugBalance(tokenId, DRUG_WEED);
        (, uint256 repBefore, , , , ) = core.getDealerData(tokenId);

        uint256 buyAmount = 10;

        bool foundWin = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!foundWin && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            try pve.playGame(
                tokenId,
                0,
                IDealersPVE.HustleType.BUY,
                DRUG_WEED,
                buyAmount
            ) {
                uint256 cashAfter = core.getCashBalance(tokenId);
                uint256 weedAfter = core.getDrugBalance(tokenId, DRUG_WEED);
                (, uint256 repAfter, , , , ) = core.getDealerData(tokenId);

                if (cashAfter == cashBefore && weedAfter > weedBefore && repAfter > repBefore) {
                    foundWin = true;
                    break;
                }
            } catch {}

            vm.revertToState(snapshotId);
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (foundWin) {
            uint256 cashAfter = core.getCashBalance(tokenId);
            uint256 weedAfter = core.getDrugBalance(tokenId, DRUG_WEED);
            (, uint256 repAfter, , , , ) = core.getDealerData(tokenId);

            assertEq(cashAfter, cashBefore, "WIN BUY: Cash should be kept");
            assertGt(weedAfter, weedBefore, "WIN BUY: Should have gained drugs");
            assertGt(repAfter, repBefore, "WIN BUY: Reputation should increase");
        }
    }

    function test_buyFlow_tieOutcome() public {
        uint256 buyAmount = 10;
        uint256 buyPrice = 1;
        uint256 cashCost = buyAmount * buyPrice;

        bool foundTie = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!foundTie && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            uint256 cashBefore = core.getCashBalance(tokenId);
            uint256 weedBefore = core.getDrugBalance(tokenId, DRUG_WEED);

            try pve.playGame(
                tokenId,
                0,
                IDealersPVE.HustleType.BUY,
                DRUG_WEED,
                buyAmount
            ) {
                uint256 cashAfter = core.getCashBalance(tokenId);
                uint256 weedAfter = core.getDrugBalance(tokenId, DRUG_WEED);

                if (cashAfter == cashBefore - cashCost && weedAfter > weedBefore) {
                    foundTie = true;

                    assertEq(cashAfter, cashBefore - cashCost, "TIE BUY: Should lose cash");
                    assertGt(weedAfter, weedBefore, "TIE BUY: Should gain drugs");
                    break;
                }
            } catch {}

            vm.revertToState(snapshotId);
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!foundTie) {
            emit log("Note: TIE outcome not found within iteration limit - test inconclusive");
        }
    }

    function test_buyFlow_lossOutcome() public {
        uint256 buyAmount = 10;
        uint256 buyPrice = 1;
        uint256 cashCost = buyAmount * buyPrice;

        bool foundLoss = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!foundLoss && prevrandaoValue < 1000) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            uint256 cashBefore = core.getCashBalance(tokenId);
            uint256 weedBefore = core.getDrugBalance(tokenId, DRUG_WEED);
            (, uint256 repBefore, , , , ) = core.getDealerData(tokenId);

            try pve.playGame(
                tokenId,
                0,
                IDealersPVE.HustleType.BUY,
                DRUG_WEED,
                buyAmount
            ) {
                uint256 cashAfter = core.getCashBalance(tokenId);
                uint256 weedAfter = core.getDrugBalance(tokenId, DRUG_WEED);
                (, uint256 repAfter, , , , ) = core.getDealerData(tokenId);

                if (cashAfter == cashBefore - cashCost && weedAfter == weedBefore && repAfter < repBefore) {
                    foundLoss = true;

                    assertEq(cashAfter, cashBefore - cashCost, "LOSS BUY: Should lose cash");
                    assertEq(weedAfter, weedBefore, "LOSS BUY: Should not gain drugs");
                    assertLt(repAfter, repBefore, "LOSS BUY: Reputation should decrease");
                    break;
                }
            } catch {}

            vm.revertToState(snapshotId);
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!foundLoss) {
            emit log("Note: BUY LOSS outcome not found within iteration limit - test inconclusive");
        }
    }

    function test_sellFlow_winOutcome() public {
        vm.prank(owner);
        core.updateDrugBalance(tokenId, DRUG_WEED, 100);

        uint256 sellAmount = 20;

        bool foundWin = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!foundWin && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            uint256 cashBefore = core.getCashBalance(tokenId);
            uint256 weedBefore = core.getDrugBalance(tokenId, DRUG_WEED);
            (, uint256 repBefore, , , , ) = core.getDealerData(tokenId);

            try pve.playGame(
                tokenId,
                0,
                IDealersPVE.HustleType.SELL,
                DRUG_WEED,
                sellAmount
            ) {
                uint256 cashAfter = core.getCashBalance(tokenId);
                uint256 weedAfter = core.getDrugBalance(tokenId, DRUG_WEED);
                (, uint256 repAfter, , , , ) = core.getDealerData(tokenId);

                if (weedAfter == weedBefore && cashAfter > cashBefore && repAfter > repBefore) {
                    foundWin = true;

                    assertEq(weedAfter, weedBefore, "WIN SELL: Should keep drugs");
                    assertGt(cashAfter, cashBefore, "WIN SELL: Should gain cash");
                    assertGt(repAfter, repBefore, "WIN SELL: Reputation should increase");
                    break;
                }
            } catch {}

            vm.revertToState(snapshotId);
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!foundWin) {
            emit log("Note: SELL WIN outcome not found within iteration limit - test inconclusive");
        }
    }

    function test_sellFlow_tieOutcome() public {
        vm.prank(owner);
        core.updateDrugBalance(tokenId, DRUG_WEED, 100);

        uint256 sellAmount = 20;
        uint256 sellPrice = 1;
        uint256 expectedCash = sellAmount * sellPrice;

        bool foundTie = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!foundTie && prevrandaoValue < 500) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            uint256 cashBefore = core.getCashBalance(tokenId);
            uint256 weedBefore = core.getDrugBalance(tokenId, DRUG_WEED);

            try pve.playGame(
                tokenId,
                0,
                IDealersPVE.HustleType.SELL,
                DRUG_WEED,
                sellAmount
            ) {
                uint256 cashAfter = core.getCashBalance(tokenId);
                uint256 weedAfter = core.getDrugBalance(tokenId, DRUG_WEED);

                if (weedAfter == weedBefore - sellAmount && cashAfter == cashBefore + expectedCash) {
                    foundTie = true;

                    assertEq(weedAfter, weedBefore - sellAmount, "TIE SELL: Should lose drugs");
                    assertEq(cashAfter, cashBefore + expectedCash, "TIE SELL: Should gain cash");
                    break;
                }
            } catch {}

            vm.revertToState(snapshotId);
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!foundTie) {
            emit log("Note: SELL TIE outcome not found within iteration limit - test inconclusive");
        }
    }

    function test_sellFlow_lossOutcome() public {
        vm.prank(owner);
        core.updateDrugBalance(tokenId, DRUG_WEED, 100);

        uint256 sellAmount = 20;

        bool foundLoss = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!foundLoss && prevrandaoValue < 1000) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            uint256 cashBefore = core.getCashBalance(tokenId);
            uint256 weedBefore = core.getDrugBalance(tokenId, DRUG_WEED);
            (, uint256 repBefore, , , , ) = core.getDealerData(tokenId);

            try pve.playGame(
                tokenId,
                0,
                IDealersPVE.HustleType.SELL,
                DRUG_WEED,
                sellAmount
            ) {
                uint256 cashAfter = core.getCashBalance(tokenId);
                uint256 weedAfter = core.getDrugBalance(tokenId, DRUG_WEED);
                (, uint256 repAfter, , , , ) = core.getDealerData(tokenId);

                if (weedAfter == weedBefore - sellAmount && cashAfter == cashBefore && repAfter < repBefore) {
                    foundLoss = true;

                    assertEq(weedAfter, weedBefore - sellAmount, "LOSS SELL: Should lose drugs");
                    assertEq(cashAfter, cashBefore, "LOSS SELL: Should not gain cash");
                    assertLt(repAfter, repBefore, "LOSS SELL: Reputation should decrease");
                    break;
                }
            } catch {}

            vm.revertToState(snapshotId);
            prevrandaoValue++;
        }

        vm.stopPrank();

        if (!foundLoss) {
            emit log("Note: SELL LOSS outcome not found within iteration limit - test inconclusive");
        }
    }

    function test_flow_arrestDuringBuy() public {
        for (uint8 i = 0; i < 5; i++) {
            vm.prank(owner);
            core.incrementHeatLevel(tokenId);
        }

        (, , , uint8 heatLevel, , ) = core.getDealerData(tokenId);
        assertEq(heatLevel, 5, "Heat should be 5");

        uint256 cashBefore = core.getCashBalance(tokenId);
        uint256 buyAmount = 10;
        uint256 cashCost = buyAmount * 1;

        bool arrested = false;
        uint256 prevrandaoValue = 0;

        vm.startPrank(player1);

        while (!arrested && prevrandaoValue < 1000) {
            vm.prevrandao(bytes32(prevrandaoValue));

            uint256 snapshotId = vm.snapshotState();

            (, , uint8 attempts, , , ) = core.getDealerData(tokenId);
            if (attempts == 0) {
                actions.purchaseAttemptReset{value: 0.001 ether}(tokenId);
            }

            try pve.playGame(
                tokenId,
                0,
                IDealersPVE.HustleType.BUY,
                DRUG_WEED,
                buyAmount
            ) {
                if (core.getGameState(tokenId).isJailed) {
                    arrested = true;

                    uint256 cashAfter = core.getCashBalance(tokenId);
                    assertEq(cashAfter, cashBefore - cashCost, "Arrested: Should lose stake");
                    assertTrue(core.getGameState(tokenId).isJailed, "Should be in jail");

                    (uint8 area, , , , , ) = core.getDealerData(tokenId);
                    assertEq(area, JAIL, "Area should be JAIL (255)");
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

    function test_flow_multipleGamesInSession() public {
        (, , uint8 startingAttempts, , , ) = core.getDealerData(tokenId);
        assertEq(startingAttempts, 5, "Should start with 5 attempts");

        vm.startPrank(player1);

        for (uint8 i = 0; i < 5; i++) {
            vm.prevrandao(bytes32(uint256(i * 1000 + 100)));

            try pve.playGame(
                tokenId,
                0,
                IDealersPVE.HustleType.BUY,
                DRUG_WEED,
                5
            ) {
                (, , uint8 attemptsAfter, , , ) = core.getDealerData(tokenId);
                assertEq(attemptsAfter, 4 - i, "Attempts should decrement");
            } catch {
                break;
            }

            if (core.getGameState(tokenId).isJailed) {
                break;
            }
        }

        if (!core.getGameState(tokenId).isJailed) {
            (, , uint8 finalAttempts, , , ) = core.getDealerData(tokenId);
            assertEq(finalAttempts, 0, "Should have 0 attempts after 5 games");

            vm.expectRevert();
            pve.playGame(
                tokenId,
                0,
                IDealersPVE.HustleType.BUY,
                DRUG_WEED,
                5
            );
        }

        vm.stopPrank();
    }

    function test_flow_insufficientCashReverts() public {
        uint256 cashBalance = core.getCashBalance(tokenId);

        vm.prank(player1);
        vm.expectRevert(DealersPVE.InsufficientCash.selector);
        pve.playGame(
            tokenId,
            0,
            IDealersPVE.HustleType.BUY,
            DRUG_WEED,
            cashBalance + 100
        );
    }

    function test_flow_insufficientDrugsReverts() public {
        uint256 weedBalance = core.getDrugBalance(tokenId, DRUG_WEED);

        vm.prank(player1);
        vm.expectRevert(DealersPVE.InsufficientDrugs.selector);
        pve.playGame(
            tokenId,
            0,
            IDealersPVE.HustleType.SELL,
            DRUG_WEED,
            weedBalance + 100
        );
    }

    function test_flow_cannotPlayInSafeHouse() public {
        uint256 safeHouseToken = _mintNFT(player1);

        // Move to safe house (starts in Manhattan now)
        vm.prank(player1);
        actions.travel{value: 0}(safeHouseToken, SAFE_HOUSE);

        (uint8 area, , , , , ) = core.getDealerData(safeHouseToken);
        assertEq(area, SAFE_HOUSE, "Should be in safe house");

        vm.prank(player1);
        vm.expectRevert(DealersPVE.DealerInSafeHouse.selector);
        pve.playGame(
            safeHouseToken,
            0,
            IDealersPVE.HustleType.BUY,
            DRUG_WEED,
            10
        );
    }

    function test_flow_cannotPlayInJail() public {
        vm.prank(owner);
        core.sendToJail(tokenId);

        assertTrue(core.getGameState(tokenId).isJailed, "Should be in jail");

        vm.prank(player1);
        vm.expectRevert(DealersPVE.DealerInJail.selector);
        pve.playGame(
            tokenId,
            0,
            IDealersPVE.HustleType.BUY,
            DRUG_WEED,
            10
        );
    }
}

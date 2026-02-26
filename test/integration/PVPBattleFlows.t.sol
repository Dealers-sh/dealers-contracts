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

    function test_pvpFlow_attackerWins() public {
        vm.prank(owner);
        core.setDealerStats(attackerToken, 25, 0);

        vm.mockCall(
            address(core),
            abi.encodeWithSelector(core.getJailChance.selector, attackerToken),
            abi.encode(uint8(0))
        );

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);

        _mockRandomness(_buildRng(50, 0, 10));

        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);

        uint256 defenderWeedAfter = core.getDrugBalance(defenderToken, DRUG_WEED);
        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);

        uint256 stolen = defenderWeedBefore - defenderWeedAfter;
        uint256 expected = _ceilDiv(defenderWeedBefore * 2, 100);
        assertEq(stolen, expected, "Should steal 2% of weed (rounded up)");

        uint256 transferred = stolen / 2;
        assertEq(attackerWeedAfter, attackerWeedBefore + transferred, "Attacker gains half stolen weed");
    }

    function test_pvpFlow_defenderWins() public {
        vm.prank(owner);
        core.setDealerStats(defenderToken, 0, 25);
        vm.prank(owner);
        core.updateDrugBalance(attackerToken, DRUG_WEED, 80);

        vm.mockCall(
            address(core),
            abi.encodeWithSelector(core.getJailChance.selector, attackerToken),
            abi.encode(uint8(0))
        );

        uint256 attackerWeedBefore = core.getDrugBalance(attackerToken, DRUG_WEED);

        _mockRandomness(_buildRng(50, 99, 10));

        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);

        uint256 attackerWeedAfter = core.getDrugBalance(attackerToken, DRUG_WEED);

        assertLt(attackerWeedAfter, attackerWeedBefore, "Attacker should lose drugs");

        uint256 stolen = attackerWeedBefore - attackerWeedAfter;
        uint256 expected = _ceilDiv(attackerWeedBefore * 2, 100);
        assertEq(stolen, expected, "Should lose 2% of weed (rounded up)");
    }

    function test_pvpFlow_attackerArrestedMidFight() public {
        for (uint8 i = 0; i < 5; i++) {
            vm.prank(owner);
            core.incrementHeatLevel(attackerToken);
        }

        vm.mockCall(
            address(core),
            abi.encodeWithSelector(core.getJailChance.selector, attackerToken),
            abi.encode(uint8(100))
        );
        _mockRandomness(_buildRng(0, 0, 10));

        uint256 defenderWeedBefore = core.getDrugBalance(defenderToken, DRUG_WEED);

        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);

        assertTrue(core.isInJail(attackerToken), "Attacker should be in jail");
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

        vm.mockCall(
            address(core),
            abi.encodeWithSelector(core.getJailChance.selector, attackerToken),
            abi.encode(uint8(0))
        );
        _mockRandomness(_buildRng(50, 0, 10));

        vm.prank(player1);
        pvp.attack(attackerToken, defenderToken);

        (, uint256 attackerRepAfter, , , , ) = core.getDealerData(attackerToken);
        assertTrue(attackerRepAfter != attackerRepBefore, "Reputation should change after battle");
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        return (a - 1) / b + 1;
    }
}

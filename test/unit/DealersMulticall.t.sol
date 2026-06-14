// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";
import "../../src/core/DealersMulticall.sol";
import "../../src/utils/IDrugRegistry.sol";

contract DealersMulticallTest is BaseTest {
    uint256 internal tokenId1;

    function setUp() public override {
        super.setUp();
        tokenId1 = _mintAndInitialize(player1);
    }

    function test_getFullDealerState_starterValues() public view {
        DealersMulticall.FullDealerState memory state = multicall.getFullDealerState(tokenId1);

        assertEq(state.reputation, core.getGameState(tokenId1).totalReputation);
        assertEq(state.currentArea, core.STARTING_AREA());
        assertEq(state.heatLevel, 0);
        assertEq(state.dailyAttemptsRemaining, core.BASE_MAX_ATTEMPTS());
        assertEq(state.maxAttempts, core.BASE_MAX_ATTEMPTS());
        assertTrue(state.isInitialized);
        assertFalse(state.isJailed);
        assertFalse(state.isInSafeHouse);
        assertEq(state.jailChance, 0);
        assertEq(state.threat, 0);
        assertEq(state.armor, 0);
        assertEq(state.cashBalance, 250);
        assertFalse(state.boostActive);
        assertEq(state.pveWins, 0);
        assertEq(state.pveLosses, 0);
        assertEq(state.pveTies, 0);
        assertEq(state.pvpAttackWins, 0);
        assertEq(state.pvpDefendWins, 0);
        assertEq(state.lastBreakoutAttempt, 0);
        assertTrue(state.canBreakoutToday);
    }

    function test_getFullDealerState_drugBalances() public view {
        DealersMulticall.FullDealerState memory state = multicall.getFullDealerState(tokenId1);

        uint256[] memory allDrugs = drugRegistry.getAllDrugIds();
        assertEq(state.drugBalances.length, allDrugs.length);

        assertEq(state.drugBalances[0].drugId, 1);
        assertEq(state.drugBalances[0].balance, 0);

        assertEq(state.drugBalances[1].drugId, 2);
        assertEq(state.drugBalances[1].balance, 0);

        assertEq(state.drugBalances[2].drugId, 3);
        assertEq(state.drugBalances[2].balance, 0);

        assertEq(state.drugBalances[3].drugId, 4);
        assertEq(state.drugBalances[3].balance, core.STARTER_WEED());

        assertEq(state.drugBalances[4].drugId, 5);
        assertEq(state.drugBalances[4].balance, core.STARTER_XTC());

        assertEq(state.drugBalances[5].drugId, 6);
        assertEq(state.drugBalances[5].balance, core.STARTER_COCAINE());
    }

    function test_getFullDealerState_withBoost() public {
        vm.prank(player1);
        boosts.purchaseBoost{value: 0.0025 ether}(tokenId1, 1);

        DealersMulticall.FullDealerState memory state = multicall.getFullDealerState(tokenId1);

        assertTrue(state.boostActive);
        assertGt(state.boostExpiry, block.timestamp);
        assertEq(state.drugMultiplier, 110);
        assertEq(state.cashMultiplier, 110);
        assertEq(state.repMultiplier, 110);
        assertEq(state.maxAttempts, 7);
    }

    function test_getFullDealerState_reputationTitle() public view {
        DealersMulticall.FullDealerState memory state = multicall.getFullDealerState(tokenId1);
        assertEq(keccak256(bytes(state.reputationTitle)), keccak256(bytes("Outsider")));
    }

    function test_getAreaEconomy_manhattan() public view {
        DealersMulticall.AreaEconomy memory economy = multicall.getAreaEconomy(1);

        assertEq(keccak256(bytes(economy.areaName)), keccak256(bytes("Manhattan")));
        assertTrue(economy.isActive);
        assertFalse(economy.isSafeHouse);
        assertFalse(economy.isJail);
        assertEq(economy.areaId, 1);
        assertGt(economy.drugs.length, 0);

        for (uint256 i = 0; i < economy.drugs.length; i++) {
            assertGt(economy.drugs[i].drugId, 0);
            assertGt(economy.drugs[i].buyPrice, 0);
            assertGt(economy.drugs[i].sellPrice, 0);
        }
    }

    function test_getAreaEconomy_specialAreaFlags() public view {
        DealersMulticall.AreaEconomy memory safeHouse = multicall.getAreaEconomy(core.SAFE_HOUSE_AREA());
        assertTrue(safeHouse.isSafeHouse);
        assertFalse(safeHouse.isJail);

        DealersMulticall.AreaEconomy memory jail = multicall.getAreaEconomy(core.JAIL_AREA());
        assertTrue(jail.isJail);
        assertFalse(jail.isSafeHouse);
    }

    function test_getAllAreas() public view {
        DealersMulticall.AreaEconomy[] memory economies = multicall.getAllAreas();

        uint8 totalAreas = areaRegistry.getTotalAreas();
        assertEq(economies.length, totalAreas + 3);

        assertEq(economies[0].areaId, 0);
        assertTrue(economies[0].isSafeHouse);

        for (uint256 i = 1; i <= totalAreas; i++) {
            assertEq(economies[i].areaId, i);
            assertTrue(bytes(economies[i].areaName).length > 0);
        }

        assertEq(economies[totalAreas + 1].areaId, 254);

        assertEq(economies[totalAreas + 2].areaId, 255);
        assertTrue(economies[totalAreas + 2].isJail);
    }

    function test_getFullDealerState_revertUninitialized() public {
        uint256 fakeTokenId = 99999;
        vm.expectRevert(abi.encodeWithSelector(DealersMulticall.DealerNotInitialized.selector, fakeTokenId));
        multicall.getFullDealerState(fakeTokenId);
    }

    function test_constructor_revertZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(DealersMulticall.ZeroAddress.selector, "core"));
        new DealersMulticall(address(0), address(pve), address(pvp), address(areaRegistry), address(drugRegistry));

        vm.expectRevert(abi.encodeWithSelector(DealersMulticall.ZeroAddress.selector, "pve"));
        new DealersMulticall(address(core), address(0), address(pvp), address(areaRegistry), address(drugRegistry));

        vm.expectRevert(abi.encodeWithSelector(DealersMulticall.ZeroAddress.selector, "pvp"));
        new DealersMulticall(address(core), address(pve), address(0), address(areaRegistry), address(drugRegistry));

        vm.expectRevert(abi.encodeWithSelector(DealersMulticall.ZeroAddress.selector, "areaRegistry"));
        new DealersMulticall(address(core), address(pve), address(pvp), address(0), address(drugRegistry));

        vm.expectRevert(abi.encodeWithSelector(DealersMulticall.ZeroAddress.selector, "drugRegistry"));
        new DealersMulticall(address(core), address(pve), address(pvp), address(areaRegistry), address(0));
    }

    function test_getFullDealerState_drugRarityTyped() public view {
        DealersMulticall.FullDealerState memory state = multicall.getFullDealerState(tokenId1);

        assertEq(uint8(state.drugBalances[0].rarity), uint8(IDrugRegistry.DrugRarity.COMMON)); // General Goods
        assertEq(uint8(state.drugBalances[1].rarity), uint8(IDrugRegistry.DrugRarity.UNCOMMON)); // Contraband
        assertEq(uint8(state.drugBalances[2].rarity), uint8(IDrugRegistry.DrugRarity.RARE)); // Jewels
    }
}

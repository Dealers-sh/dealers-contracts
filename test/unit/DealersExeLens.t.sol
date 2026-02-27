// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";
import "../../src/core/DealersExeLens.sol";
import "../../src/utils/IDrugRegistry.sol";

contract DealersExeLensTest is BaseTest {
    DealersExeLens public lens;
    uint256 internal tokenId1;

    function setUp() public override {
        super.setUp();
        lens = new DealersExeLens(
            address(core),
            address(pve),
            address(pvp),
            address(areaRegistry),
            address(drugRegistry)
        );
        tokenId1 = _mintAndInitialize(player1);
    }

    function test_getFullDealerState_starterValues() public view {
        DealersExeLens.FullDealerState memory state = lens.getFullDealerState(tokenId1);

        assertEq(state.reputation, core.STARTING_REPUTATION());
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
    }

    function test_getFullDealerState_drugBalances() public view {
        DealersExeLens.FullDealerState memory state = lens.getFullDealerState(tokenId1);

        uint256[] memory allDrugs = drugRegistry.getAllDrugIds();
        assertEq(state.drugBalances.length, allDrugs.length);

        assertEq(state.drugBalances[0].drugId, 1);
        assertEq(state.drugBalances[0].balance, core.STARTER_WEED());

        assertEq(state.drugBalances[1].drugId, 2);
        assertEq(state.drugBalances[1].balance, core.STARTER_XTC());

        assertEq(state.drugBalances[2].drugId, 3);
        assertEq(state.drugBalances[2].balance, core.STARTER_COCAINE());

        assertEq(state.drugBalances[3].balance, 0);
        assertEq(state.drugBalances[4].balance, 0);
    }

    function test_getFullDealerState_withBoost() public {
        vm.prank(player1);
        boosts.purchaseBoost{value: 0.0025 ether}(tokenId1, 1);

        DealersExeLens.FullDealerState memory state = lens.getFullDealerState(tokenId1);

        assertTrue(state.boostActive);
        assertGt(state.boostExpiry, block.timestamp);
        assertEq(state.drugMultiplier, 125);
        assertEq(state.cashMultiplier, 125);
        assertEq(state.repMultiplier, 125);
        assertEq(state.maxAttempts, 8);
    }

    function test_getFullDealerState_reputationTitle() public view {
        DealersExeLens.FullDealerState memory state = lens.getFullDealerState(tokenId1);
        assertEq(keccak256(bytes(state.reputationTitle)), keccak256(bytes("Outsider")));
    }

    function test_getAreaEconomy_manhattan() public view {
        DealersExeLens.AreaEconomy memory economy = lens.getAreaEconomy(1);

        assertEq(keccak256(bytes(economy.areaName)), keccak256(bytes("Manhattan")));
        assertTrue(economy.isActive);
        assertEq(economy.areaId, 1);
        assertGt(economy.drugs.length, 0);

        for (uint256 i = 0; i < economy.drugs.length; i++) {
            assertGt(economy.drugs[i].drugId, 0);
            assertGt(economy.drugs[i].buyPrice, 0);
            assertGt(economy.drugs[i].sellPrice, 0);
        }
    }

    function test_getAllAreasEconomy() public view {
        DealersExeLens.AreaEconomy[] memory economies = lens.getAllAreasEconomy();

        uint8 totalAreas = areaRegistry.getTotalAreas();
        assertEq(economies.length, totalAreas);

        for (uint256 i = 0; i < economies.length; i++) {
            assertEq(economies[i].areaId, i + 1);
            assertTrue(bytes(economies[i].areaName).length > 0);
        }
    }

    function test_getFullDealerState_revertUninitialized() public {
        uint256 fakeTokenId = 99999;
        vm.expectRevert(abi.encodeWithSelector(DealersExeLens.DealerNotInitialized.selector, fakeTokenId));
        lens.getFullDealerState(fakeTokenId);
    }

    function test_constructor_revertZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(DealersExeLens.ZeroAddress.selector, "core"));
        new DealersExeLens(address(0), address(pve), address(pvp), address(areaRegistry), address(drugRegistry));

        vm.expectRevert(abi.encodeWithSelector(DealersExeLens.ZeroAddress.selector, "pve"));
        new DealersExeLens(address(core), address(0), address(pvp), address(areaRegistry), address(drugRegistry));

        vm.expectRevert(abi.encodeWithSelector(DealersExeLens.ZeroAddress.selector, "pvp"));
        new DealersExeLens(address(core), address(pve), address(0), address(areaRegistry), address(drugRegistry));

        vm.expectRevert(abi.encodeWithSelector(DealersExeLens.ZeroAddress.selector, "areaRegistry"));
        new DealersExeLens(address(core), address(pve), address(pvp), address(0), address(drugRegistry));

        vm.expectRevert(abi.encodeWithSelector(DealersExeLens.ZeroAddress.selector, "drugRegistry"));
        new DealersExeLens(address(core), address(pve), address(pvp), address(areaRegistry), address(0));
    }

    function test_getFullDealerState_drugRarityTyped() public view {
        DealersExeLens.FullDealerState memory state = lens.getFullDealerState(tokenId1);

        assertEq(uint8(state.drugBalances[0].rarity), uint8(IDrugRegistry.DrugRarity.COMMON));
        assertEq(uint8(state.drugBalances[1].rarity), uint8(IDrugRegistry.DrugRarity.UNCOMMON));
        assertEq(uint8(state.drugBalances[2].rarity), uint8(IDrugRegistry.DrugRarity.RARE));
    }
}

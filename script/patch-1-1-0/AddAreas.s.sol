// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/AreasConfig.s.sol";

/**
 * @title AddAreas - Patch 1.1.0 one-shot: create Warsaw (8) + Moscow (9) on the live registry
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev SetupAreas skips entirely once any area exists, so the two new areas are appended here from
 *      the canonical ladder (AreasConfig._areaSpecs, indices 7/8). createArea appends sequentially →
 *      ids 8/9, asserted against the spec. Idempotent: no-op once 9 areas exist. Requires AddDrugs
 *      first (places Slivo/Speed/Krokodil) and must run before SetupSeason, which then maintains all 9.
 *
 *   Usage:
 *     source .env && forge script script/patch-1-1-0/AddAreas.s.sol:AddAreas \
 *         --rpc-url <abstract-testnet|abstract-mainnet> --account dealersKeystore \
 *         --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
 * @author Berny0x
 */
contract AddAreas is AreasConfig {
    function run() external {
        _loadAddresses();
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        IAreaRegistry reg = IAreaRegistry(areaRegistry);
        uint8 total = reg.getTotalAreas();

        if (total >= 9) {
            console.log("AddAreas: Warsaw/Moscow already present, skipping");
            return;
        }
        require(total == 7, "AddAreas: unexpected area count (expected 7)");

        AreaSpec[] memory specs = _areaSpecs();
        vm.startBroadcast();
        for (uint256 i = 7; i < specs.length; ++i) {
            AreaSpec memory s = specs[i];
            uint8 id = reg.createArea(s.name, s.movementFee, s.minReputation, false, false);
            require(id == s.id, "AddAreas: unexpected area id");
            reg.batchConfigureAreaDrugs(s.id, s.drugIds, s.buyPrices, s.sellPrices);
        }
        vm.stopBroadcast();

        require(reg.getTotalAreas() == 9, "AddAreas: area count mismatch");
        require(reg.getAreaDrugCount(8) == 3, "AddAreas: Warsaw drug count");
        require(reg.getAreaDrugCount(9) == 3, "AddAreas: Moscow drug count");
        console.log("AddAreas: Warsaw (8) + Moscow (9) created");
    }
}

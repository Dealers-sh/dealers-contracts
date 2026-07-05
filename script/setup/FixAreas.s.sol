// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/AreasConfig.s.sol";

/**
 * @title FixAreas - Re-sync a live AreaRegistry to the canonical ladder
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Both testnet and mainnet were configured from the stale DeployAll ladder, where four
 *      area gates drifted (Amsterdam 75, Seoul 1200, Tokyo 2500, Dubai 10000) and Hong Kong
 *      carried pre-rebalance drug prices. This re-applies AreasConfig over the existing
 *      registry through the update setters — createArea would duplicate, so _syncAreas drives
 *      updateMinReputation / updateMovementFee / batchConfigureAreaDrugs instead. The setters
 *      are owner-only and non-destructive: dealer locations and untouched fields stand, and a
 *      value already correct is a harmless re-write. Target network is auto-resolved from
 *      chainid, so the same script corrects both — run it once against each RPC.
 *
 *   Usage:
 *     source .env && forge script script/setup/FixAreas.s.sol:FixAreas \
 *         --rpc-url <abstract-testnet|abstract-mainnet> --account dealersKeystore \
 *         --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
 * @author Berny0x
 */
contract FixAreas is AreasConfig {
    function run() external {
        _loadAddresses();
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        IAreaRegistry reg = IAreaRegistry(areaRegistry);

        console.log("Network:", _getNetworkFolder());
        console.log("AreaRegistry:", areaRegistry);
        console.log("Total areas:", reg.getTotalAreas());

        vm.startBroadcast();
        _syncAreas(reg);
        vm.stopBroadcast();

        _verify(reg);
    }

    /**
     * @dev Post-apply self-check. Reads every gate, fee and drug price back from the registry and
     *      asserts it equals the canonical spec, so a partial broadcast aborts the run loudly
     *      instead of silently leaving the ladder half-fixed.
     */
    function _verify(IAreaRegistry reg) internal view {
        AreaSpec[] memory specs = _areaSpecs();
        for (uint256 i; i < specs.length; ++i) {
            AreaSpec memory s = specs[i];
            require(reg.getMovementFee(s.id) == s.movementFee, "FixAreas: fee mismatch");
            require(reg.getMinReputation(s.id) == s.minReputation, "FixAreas: minRep mismatch");
            _assertDrugPrices(reg, s);
        }

        require(reg.getMinReputation(7) == 5500, "FixAreas: Dubai not Underboss");
        console.log("Verified: 7 gates re-synced, Dubai re-gated to 5500 (Underboss)");
    }

    function _assertDrugPrices(IAreaRegistry reg, AreaSpec memory s) internal view {
        for (uint256 j; j < s.drugIds.length; ++j) {
            (uint256 buy, uint256 sell) = reg.getDrugPricing(s.id, s.drugIds[j]);
            require(buy == s.buyPrices[j], "FixAreas: buy price mismatch");
            require(sell == s.sellPrices[j], "FixAreas: sell price mismatch");
        }
    }
}

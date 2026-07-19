// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/AreasConfig.s.sol";

/**
 * @title SetupSeason - Apply the season's area ladder (drug shuffle + fees + gates) to a live registry
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Per-season entry point for the economy shuffle. Each season edits the canonical ladder in
 *      AreasConfig — rotating drug identities and arbitrage routes while holding price slots and
 *      rarity fixed (pace-neutral, see AreasConfig._areaSpecs) — then runs this once per network to
 *      push the change onto the live AreaRegistry. Shares the sync path with FixAreas: createArea
 *      would duplicate, so _syncAreas drives updateMovementFee / updateMinReputation /
 *      batchConfigureAreaDrugs, which are owner-only and non-destructive (dealer locations and any
 *      already-correct field stand). Target network is auto-resolved from chainid — run it once
 *      against each RPC. Register any brand-new drugs (SetupDrugs) before applying a season that
 *      places them.
 *
 *   Usage:
 *     source .env && forge script script/setup/SetupSeason.s.sol:SetupSeason \
 *         --rpc-url <abstract-testnet|abstract-mainnet> --account dealersKeystore \
 *         --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
 * @author Berny0x
 */
contract SetupSeason is AreasConfig {
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
     *      asserts it matches the canonical spec, so a partial broadcast aborts loudly instead of
     *      leaving the ladder half-applied mid-season.
     */
    function _verify(IAreaRegistry reg) internal view {
        AreaSpec[] memory specs = _areaSpecs();
        for (uint256 i; i < specs.length; ++i) {
            AreaSpec memory s = specs[i];
            require(reg.getMovementFee(s.id) == s.movementFee, "SetupSeason: fee mismatch");
            require(reg.getMinReputation(s.id) == s.minReputation, "SetupSeason: minRep mismatch");
            require(reg.getAreaDrugCount(s.id) == s.drugIds.length, "SetupSeason: stale drug not pruned");
            for (uint256 j; j < s.drugIds.length; ++j) {
                (uint256 buy, uint256 sell) = reg.getDrugPricing(s.id, s.drugIds[j]);
                require(buy == s.buyPrices[j], "SetupSeason: buy price mismatch");
                require(sell == s.sellPrices[j], "SetupSeason: sell price mismatch");
            }
        }

        console.log("Verified: season ladder applied (7 areas, exactly 3 drugs each, fees + gates)");
    }
}

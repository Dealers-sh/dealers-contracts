// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupRebalance - One-off economy rebalance setters (PVE odds, jail, PVP steal)
 * @dev Usage:
 *   source .env && forge script script/setup/SetupRebalance.s.sol:SetupRebalance \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Requires DEALERS_CORE, DEALERS_PVE, DEALERS_PVP. Applies the sim-calibrated economy
 *   config (docs/ECONOMY_BALANCE_SIM.md, test/simulation/economy_sim.py) that isn't covered
 *   by SetupTiers/SetupHeists:
 *     - PVE odds 25/50/25 (was 20/50/30): F2P PVE becomes cash-EV-neutral so fresh wallets
 *       can sustain cap-stakes; boosted profit stays proportional to (multiplier - 1).
 *     - PVE stake scaling slope 2500 / headroom 10000: rep-stake divisor grows with total
 *       reputation (divisor = 50 + 0.25 * totalRep) so maxing the tier repCap costs ~5-10%
 *       of a typical bankroll at every rank, and commit stakes are capped at the tie-bonus
 *       cap-stake — closes the unbounded boosted-payout $CASH faucet.
 *     - jailChancePerHeat 7 (0.7%/heat, was 0.5%): active grinders get jailed ~every 4 days.
 *       Penalty cap STAYS 50 — a higher cap was sim-tested and collapses the PVP archetype
 *       (permanent heat-5 + infamy); the late-game jail cost is the lost day + bail.
 *     - cashStealPercent 2 (was 1): sacking a Don-tier player takes ~20k $CASH per win.
 *   setCoreConfig/setPVPConfig take full structs — every other field below re-asserts the
 *   current deployed value; keep them in sync with the constructor defaults.
 */
contract SetupRebalance is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");

        console.log("Core:", core);
        console.log("PVE :", pve);
        console.log("PVP :", pvp);

        vm.startBroadcast();

        IPVEContract(pve).setOutcomeOdds(50, 25);
        IPVEContract(pve).setStakeScaling(2500, 10000);

        IDealersCore(core).setCoreConfig(
            IDealersCore.CoreConfig({
                attemptResetFee: 0.001 ether,
                bribeCopFee: 0.001 ether,
                cashTopupPrice: 0.001 ether,
                cashTopupAmount: 100,
                cashPurchaseThreshold: 10,
                jailRepPenaltyPercent: 10,
                jailRepPenaltyCap: 50,
                wantedPosterSuccessChance: 50,
                breakoutSuccessChance: 50,
                jailDrugConfiscationPercent: 3,
                starterCash: 250,
                jailChancePerHeat: 7
            })
        );

        IPVPContract(pvp).setPVPConfig(
            IPVPContract.PVPConfig({
                minReputation: 200,
                baseWinChance: 50,
                minWinChance: 25,
                maxWinChance: 75,
                maxAttacksPerDay: 3,
                drugStealPercent: 2,
                cashStealPercent: 2,
                rarityWeightCommon: 75,
                rarityWeightUncommon: 20,
                rarityWeightRare: 5,
                repRangePercent: 25,
                defenderRepBonus: 2,
                repRangeThreshold: 22000
            })
        );

        vm.stopBroadcast();

        console.log("Rebalance applied:");
        console.log("  PVE odds: 25%% win / 50%% tie / 25%% loss");
        console.log("  PVE stake scaling: slope 2500 bps, headroom 10000 bps (max stake = tie cap-stake)");
        console.log("  jailChancePerHeat: 7 (0.7%% per heat level)");
        console.log("  PVP cashStealPercent: 2%%");
    }
}

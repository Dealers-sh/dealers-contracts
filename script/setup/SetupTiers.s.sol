// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupTiers - Configure 10-tier reputation system on an existing Core
 * @dev Usage:
 *   source .env && forge script script/SetupTiers.s.sol:SetupTiers \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Requires DEALERS_CORE env var.
 */
contract SetupTiers is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");

        IDealersCore coreContract = IDealersCore(core);

        console.log("Core address:", core);

        vm.startBroadcast();

        // Sim-calibrated ladder (docs/ECONOMY_BALANCE_SIM.md, test/simulation/economy_sim.py):
        // thresholds unchanged (heist gates 600/1500/5500 + achievement milestones stay aligned);
        // big early caps put a fresh wallet at 600 rep (heist unlock) in ~3 days F2P, mid/late
        // caps land Godfather-boost rep farmers at Godfather in ~106 days (F2P ~239, 2.25x).
        // loss/tie kept <= ~0.9 so cap-staking stays +EV; Legend stays the soft-bleed tier.
        ReputationTier[] memory tiers = new ReputationTier[](10);

        tiers[0] = ReputationTier({
            minReputation: 0,
            winBonus: 120,
            tieBonus: 60,
            lossPenalty: -3,
            repCap: 120,
            tierName: "Outsider"
        });
        tiers[1] = ReputationTier({
            minReputation: 100,
            winBonus: 90,
            tieBonus: 45,
            lossPenalty: -4,
            repCap: 90,
            tierName: "Associate"
        });
        tiers[2] = ReputationTier({
            minReputation: 250,
            winBonus: 60,
            tieBonus: 30,
            lossPenalty: -4,
            repCap: 60,
            tierName: "Dealer"
        });
        tiers[3] = ReputationTier({
            minReputation: 600,
            winBonus: 36,
            tieBonus: 18,
            lossPenalty: -5,
            repCap: 40,
            tierName: "Soldier"
        });
        tiers[4] = ReputationTier({
            minReputation: 1500,
            winBonus: 28,
            tieBonus: 14,
            lossPenalty: -6,
            repCap: 40,
            tierName: "Capo"
        });
        tiers[5] = ReputationTier({
            minReputation: 3000,
            winBonus: 22,
            tieBonus: 11,
            lossPenalty: -6,
            repCap: 44,
            tierName: "Consigliere"
        });
        tiers[6] = ReputationTier({
            minReputation: 5500,
            winBonus: 18,
            tieBonus: 9,
            lossPenalty: -7,
            repCap: 48,
            tierName: "Underboss"
        });
        tiers[7] = ReputationTier({
            minReputation: 10000,
            winBonus: 15,
            tieBonus: 7,
            lossPenalty: -6,
            repCap: 52,
            tierName: "Don"
        });
        tiers[8] = ReputationTier({
            minReputation: 22000,
            winBonus: 12,
            tieBonus: 6,
            lossPenalty: -8,
            repCap: 56,
            tierName: "Godfather"
        });
        tiers[9] = ReputationTier({
            minReputation: 50000,
            winBonus: 4,
            tieBonus: 2,
            lossPenalty: -10,
            repCap: 8,
            tierName: "Legend"
        });

        coreContract.setReputationTiers(tiers);
        coreContract.setMaxReputation(75000);

        vm.stopBroadcast();

        console.log("10 tiers configured (sim-calibrated ladder): Outsider -> Legend");
        console.log("MAX_REPUTATION set to 75000");
        console.log("Legend is a soft-bleed tier (+4/+2/-10, repCap=8)");
    }
}

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

        ReputationTier[] memory tiers = new ReputationTier[](10);

        tiers[0] = ReputationTier({
            minReputation: 0,
            winBonus: 60,
            tieBonus: 25,
            lossPenalty: -2,
            repCap: 35,
            tierName: "Outsider"
        });
        tiers[1] = ReputationTier({
            minReputation: 100,
            winBonus: 35,
            tieBonus: 18,
            lossPenalty: -3,
            repCap: 25,
            tierName: "Associate"
        });
        tiers[2] = ReputationTier({
            minReputation: 250,
            winBonus: 20,
            tieBonus: 10,
            lossPenalty: -3,
            repCap: 22,
            tierName: "Dealer"
        });
        tiers[3] = ReputationTier({
            minReputation: 600,
            winBonus: 12,
            tieBonus: 5,
            lossPenalty: -4,
            repCap: 22,
            tierName: "Soldier"
        });
        tiers[4] = ReputationTier({
            minReputation: 1500,
            winBonus: 9,
            tieBonus: 4,
            lossPenalty: -5,
            repCap: 24,
            tierName: "Capo"
        });
        tiers[5] = ReputationTier({
            minReputation: 3000,
            winBonus: 7,
            tieBonus: 3,
            lossPenalty: -5,
            repCap: 26,
            tierName: "Consigliere"
        });
        tiers[6] = ReputationTier({
            minReputation: 5500,
            winBonus: 6,
            tieBonus: 2,
            lossPenalty: -6,
            repCap: 28,
            tierName: "Underboss"
        });
        tiers[7] = ReputationTier({
            minReputation: 10000,
            winBonus: 5,
            tieBonus: 2,
            lossPenalty: -6,
            repCap: 30,
            tierName: "Don"
        });
        tiers[8] = ReputationTier({
            minReputation: 22000,
            winBonus: 4,
            tieBonus: 1,
            lossPenalty: -7,
            repCap: 32,
            tierName: "Godfather"
        });
        tiers[9] = ReputationTier({
            minReputation: 50000,
            winBonus: 2,
            tieBonus: 1,
            lossPenalty: -8,
            repCap: 4,
            tierName: "Legend"
        });

        coreContract.setReputationTiers(tiers);
        coreContract.setMaxReputation(75000);

        vm.stopBroadcast();

        console.log("10 tiers configured (convex 2.2x ladder): Outsider -> Legend");
        console.log("MAX_REPUTATION set to 75000");
        console.log("Legend is a soft-bleed tier (+2/+1/-8, repCap=4)");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupTiers - Configure 10-tier reputation system on an existing Core
 * @dev Usage:
 *   source .env && forge script script/SetupTiers.s.sol:SetupTiers \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 *
 *   Requires DEALERS_CORE env var.
 */
contract SetupTiers is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");

        IDealersExeCore coreContract = IDealersExeCore(core);

        console.log("Core address:", core);

        vm.startBroadcast();

        ReputationTier[] memory tiers = new ReputationTier[](10);

        tiers[0] = ReputationTier({minReputation: 0, winBonus: 50, tieBonus: 25, lossPenalty: -2, repCap: 25, tierName: "Outsider"});
        tiers[1] = ReputationTier({minReputation: 50, winBonus: 40, tieBonus: 20, lossPenalty: -3, repCap: 22, tierName: "Associate"});
        tiers[2] = ReputationTier({minReputation: 150, winBonus: 15, tieBonus: 8, lossPenalty: -3, repCap: 18, tierName: "Dealer"});
        tiers[3] = ReputationTier({minReputation: 300, winBonus: 9, tieBonus: 3, lossPenalty: -4, repCap: 17, tierName: "Soldier"});
        tiers[4] = ReputationTier({minReputation: 700, winBonus: 8, tieBonus: 3, lossPenalty: -4, repCap: 21, tierName: "Capo"});
        tiers[5] = ReputationTier({minReputation: 1250, winBonus: 7, tieBonus: 3, lossPenalty: -5, repCap: 24, tierName: "Consigliere"});
        tiers[6] = ReputationTier({minReputation: 1900, winBonus: 6, tieBonus: 2, lossPenalty: -5, repCap: 25, tierName: "Underboss"});
        tiers[7] = ReputationTier({minReputation: 2600, winBonus: 5, tieBonus: 2, lossPenalty: -6, repCap: 28, tierName: "Don"});
        tiers[8] = ReputationTier({minReputation: 3500, winBonus: 4, tieBonus: 2, lossPenalty: -6, repCap: 30, tierName: "Godfather"});
        tiers[9] = ReputationTier({minReputation: 5000, winBonus: 3, tieBonus: 1, lossPenalty: -7, repCap: 24, tierName: "Legend"});

        coreContract.setReputationTiers(tiers);
        coreContract.setMaxReputation(6000);

        vm.stopBroadcast();

        console.log("10 tiers configured: Outsider -> Legend");
        console.log("MAX_REPUTATION set to 6000");
    }
}

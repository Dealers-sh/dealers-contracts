// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupClaims - Configure all achievements
 * @dev Usage:
 *   source .env && forge script script/setup/SetupClaims.s.sol:SetupClaims \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract SetupClaims is DeployBase {
    uint8 constant PVE_WINS = 1;
    uint8 constant PVE_LOSSES = 2;
    uint8 constant PVE_TIES = 3;
    uint8 constant PVE_TOTAL = 4;
    uint8 constant PVP_ATTACK_WINS = 5;
    uint8 constant PVP_DEFEND_WINS = 6;
    uint8 constant PVP_TOTAL_WINS = 7;
    uint8 constant REPUTATION = 8;
    uint8 constant PVE_DEAL_CHOICES = 11;
    uint8 constant PVE_THREATEN_CHOICES = 12;
    uint8 constant PVE_BAIL_CHOICES = 13;

    uint8 constant REWARD_REP = 0;
    uint8 constant REWARD_CASH = 1;
    uint8 constant REWARD_DRUG = 2;

    uint256 constant GENERAL_GOODS = 1;
    uint256 constant CONTRABAND = 2;
    uint256 constant JEWELS = 3;
    uint256 constant WEED = 4;
    uint256 constant XTC = 5;
    uint256 constant COCAINE = 6;
    uint256 constant SHROOMS = 7;
    uint256 constant HEROIN = 8;

    function run() external {
        _loadAddresses();
        _requireAddress(claims, "DEALERS_CLAIMS");

        IClaimsContract c = IClaimsContract(claims);

        console.log("Claims address:", claims);
        console.log("Current achievement count:", c.achievementCount());

        vm.startBroadcast();

        // =================================================================
        //                     EARLY GAME (IDs 0-11)
        // =================================================================

        // #0: First Deal - play one PVE round
        c.setAchievement(0, _achievement(PVE_TOTAL, 0, 1, REWARD_CASH, 0, 25));

        // #1: Grinder - play 10 PVE rounds
        c.setAchievement(1, _achievement(PVE_TOTAL, 0, 10, REWARD_CASH, 0, 50));

        // #2: Winner - win 10 PVE rounds
        c.setAchievement(2, _achievement(PVE_WINS, 0, 10, REWARD_DRUG, XTC, 2));

        // #3: Stalemate King - tie 10 PVE rounds
        c.setAchievement(3, _achievement(PVE_TIES, 0, 10, REWARD_DRUG, XTC, 2));

        // #4: Hard Knocks - lose 10 PVE rounds
        c.setAchievement(4, _achievement(PVE_LOSSES, 0, 10, REWARD_CASH, 0, 50));

        // #5: Dealer's Choice - choose Deal 10 times
        c.setAchievement(5, _achievement(PVE_DEAL_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 1));

        // #6: Intimidator - choose Threaten 10 times
        c.setAchievement(6, _achievement(PVE_THREATEN_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 1));

        // #7: Escape Artist - choose Bail 10 times
        c.setAchievement(7, _achievement(PVE_BAIL_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 1));

        // #8: First Blood - win a PVP fight
        c.setAchievement(8, _achievement(PVP_TOTAL_WINS, 0, 1, REWARD_REP, 0, 10));

        // #9: Aggressor - win 10 PVP attacks
        c.setAchievement(9, _achievement(PVP_ATTACK_WINS, 0, 10, REWARD_DRUG, GENERAL_GOODS, 1));

        // #10: Fortress - win 10 PVP defenses
        c.setAchievement(10, _achievement(PVP_DEFEND_WINS, 0, 10, REWARD_DRUG, GENERAL_GOODS, 1));

        // #11: Made Man - reach 100 rep
        c.setAchievement(11, _achievement(REPUTATION, 0, 100, REWARD_DRUG, WEED, 20));

        // =================================================================
        //                   REPUTATION TIERS (IDs 12-20)
        // =================================================================

        c.setAchievement(12, _achievement(REPUTATION, 0, 50, REWARD_CASH, 0, 50));
        c.setAchievement(13, _achievement(REPUTATION, 0, 150, REWARD_CASH, 0, 150));
        // #21: Rep 250 -> 1 Heroin
        c.setAchievement(21, _achievement(REPUTATION, 0, 250, REWARD_DRUG, HEROIN, 1));
        c.setAchievement(14, _achievement(REPUTATION, 0, 300, REWARD_CASH, 0, 300));
        c.setAchievement(15, _achievement(REPUTATION, 0, 700, REWARD_CASH, 0, 700));
        c.setAchievement(16, _achievement(REPUTATION, 0, 1250, REWARD_CASH, 0, 1250));
        c.setAchievement(17, _achievement(REPUTATION, 0, 1900, REWARD_CASH, 0, 1900));
        c.setAchievement(18, _achievement(REPUTATION, 0, 2600, REWARD_CASH, 0, 2600));
        c.setAchievement(19, _achievement(REPUTATION, 0, 3500, REWARD_CASH, 0, 3500));
        c.setAchievement(20, _achievement(REPUTATION, 0, 5000, REWARD_CASH, 0, 5000));

        // =================================================================
        //                     PVP DRUG REWARDS (IDs 22-23)
        // =================================================================

        // #22: First Blood Loot - win a PVP fight (pairs with #8 REP reward)
        c.setAchievement(22, _achievement(PVP_TOTAL_WINS, 0, 1, REWARD_DRUG, GENERAL_GOODS, 1));

        // #23: Street Veteran - win 10 PVP fights
        c.setAchievement(23, _achievement(PVP_TOTAL_WINS, 0, 10, REWARD_DRUG, CONTRABAND, 1));

        vm.stopBroadcast();

        console.log("24 achievements configured:");
        console.log("  Early game (0-11):");
        console.log("    #0:  PVE_TOTAL    >= 1    -> 25 CASH");
        console.log("    #1:  PVE_TOTAL    >= 10   -> 50 CASH");
        console.log("    #2:  PVE_WINS     >= 10   -> 2 XTC");
        console.log("    #3:  PVE_TIES     >= 10   -> 2 XTC");
        console.log("    #4:  PVE_LOSSES   >= 10   -> 50 CASH");
        console.log("    #5:  PVE_DEAL     >= 10   -> 1 Shrooms");
        console.log("    #6:  PVE_THREATEN >= 10   -> 1 Shrooms");
        console.log("    #7:  PVE_BAIL     >= 10   -> 1 Shrooms");
        console.log("    #8:  PVP_WINS     >= 1    -> 10 REP");
        console.log("    #9:  PVP_ATTACK   >= 10   -> 1 General Goods");
        console.log("    #10: PVP_DEFEND   >= 10   -> 1 Shrooms");
        console.log("    #11: REP          >= 100  -> 20 Weed");
        console.log("  Tier milestones (12-20):");
        console.log("    #12: Associate    (50)    -> 50 CASH");
        console.log("    #13: Dealer       (150)   -> 150 CASH");
        console.log("    #14: Soldier      (300)   -> 300 CASH");
        console.log("    #15: Capo         (700)   -> 700 CASH");
        console.log("    #16: Consigliere  (1250)  -> 1250 CASH");
        console.log("    #17: Underboss    (1900)  -> 1900 CASH");
        console.log("    #18: Don          (2600)  -> 2600 CASH");
        console.log("    #19: Godfather    (3500)  -> 3500 CASH");
        console.log("    #20: Legend       (5000)  -> 5000 CASH");
        console.log("  Drug milestones:");
        console.log("    #21: REP >= 250          -> 1 Heroin");
        console.log("  PVP drug rewards (22-23):");
        console.log("    #22: PVP_WINS     >= 1    -> 1 General Goods");
        console.log("    #23: PVP_WINS     >= 10   -> 1 Contraband");
    }

    function _achievement(
        uint8 conditionType,
        uint256 conditionValue,
        uint256 threshold,
        uint8 rewardType,
        uint256 rewardId,
        uint256 rewardAmount
    ) internal pure returns (IClaimsContract.Achievement memory) {
        return IClaimsContract.Achievement({
            conditionType: conditionType,
            conditionValue: conditionValue,
            threshold: threshold,
            rewardType: rewardType,
            rewardId: rewardId,
            rewardAmount: rewardAmount,
            active: true
        });
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupClaims - Configure all achievements
 * @dev Usage:
 *   source .env && forge script script/setup/SetupClaims.s.sol:SetupClaims \
 *       --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *       --skip "RendererSVG" --skip "UploadTraits"
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
    uint8 constant CASH_BALANCE = 9;
    uint8 constant DRUG_BALANCE = 10;
    uint8 constant PVE_DEAL_CHOICES = 11;
    uint8 constant PVE_THREATEN_CHOICES = 12;
    uint8 constant PVE_BAIL_CHOICES = 13;
    uint8 constant HEIST_RUNS = 14;
    uint8 constant HEIST_STAGES_CLEARED = 15;
    uint8 constant HEIST_CASHOUTS = 16;
    uint8 constant HEIST_SETBACKS = 17;
    uint8 constant HEIST_BUSTS = 18;
    uint8 constant HEIST_JACKPOTS_WON = 19;

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
    uint256 constant OPIOIDS = 9;
    uint256 constant METH = 10;
    uint256 constant FENTANYL = 11;

    function run() external {
        _loadAddresses();
        _requireAddress(claims, "DEALERS_CLAIMS");

        IClaimsContract c = IClaimsContract(claims);

        console.log("Claims address:", claims);
        console.log("Current achievement count:", c.nextAchievementId());

        vm.startBroadcast();

        // =================================================================
        //                     EARLY GAME (IDs 0-11)
        // =================================================================

        // #0: First Deal - play one PVE round
        c.setAchievement(0, _achievement(PVE_TOTAL, 0, 1, REWARD_CASH, 0, 250));

        // #1: Grinder - play 10 PVE rounds
        c.setAchievement(1, _achievement(PVE_TOTAL, 0, 10, REWARD_CASH, 0, 1000));

        // #2: Winner - win 10 PVE rounds
        c.setAchievement(2, _achievement(PVE_WINS, 0, 10, REWARD_DRUG, XTC, 5));

        // #3: Stalemate King - tie 10 PVE rounds
        c.setAchievement(3, _achievement(PVE_TIES, 0, 10, REWARD_DRUG, XTC, 5));

        // #4: Hard Knocks - lose 10 PVE rounds
        c.setAchievement(4, _achievement(PVE_LOSSES, 0, 10, REWARD_CASH, 0, 1000));

        // #5: Dealer's Choice - choose Deal 10 times
        c.setAchievement(5, _achievement(PVE_DEAL_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 5));

        // #6: Intimidator - choose Threaten 10 times
        c.setAchievement(6, _achievement(PVE_THREATEN_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 5));

        // #7: Escape Artist - choose Bail 10 times
        c.setAchievement(7, _achievement(PVE_BAIL_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 5));

        // #8: First Blood - win a PVP fight (rep reward, pairs with #22 for drug)
        c.setAchievement(8, _achievement(PVP_TOTAL_WINS, 0, 1, REWARD_REP, 0, 25));

        // #9: Aggressor - win 10 PVP attacks
        c.setAchievement(9, _achievement(PVP_ATTACK_WINS, 0, 10, REWARD_DRUG, GENERAL_GOODS, 3));

        // #10: Fortress - win 10 PVP defenses
        c.setAchievement(10, _achievement(PVP_DEFEND_WINS, 0, 10, REWARD_DRUG, GENERAL_GOODS, 3));

        // #11: Made Man - reach 75 rep (stepping stone before Associate@100)
        c.setAchievement(11, _achievement(REPUTATION, 0, 75, REWARD_DRUG, WEED, 100));

        // =================================================================
        //         REPUTATION TIER MILESTONES (IDs 12-20)
        //         Aligned with the convex 2.2x ladder in SetupTiers
        // =================================================================

        c.setAchievement(12, _achievement(REPUTATION, 0, 100, REWARD_CASH, 0, 500)); // Associate
        c.setAchievement(13, _achievement(REPUTATION, 0, 250, REWARD_CASH, 0, 2000)); // Dealer
        c.setAchievement(14, _achievement(REPUTATION, 0, 600, REWARD_CASH, 0, 10000)); // Soldier
        c.setAchievement(15, _achievement(REPUTATION, 0, 1500, REWARD_CASH, 0, 25000)); // Capo
        c.setAchievement(16, _achievement(REPUTATION, 0, 3000, REWARD_CASH, 0, 75000)); // Consigliere
        c.setAchievement(17, _achievement(REPUTATION, 0, 5500, REWARD_CASH, 0, 200000)); // Underboss
        c.setAchievement(18, _achievement(REPUTATION, 0, 10000, REWARD_CASH, 0, 500000)); // Don
        c.setAchievement(19, _achievement(REPUTATION, 0, 22000, REWARD_CASH, 0, 1000000)); // Godfather
        c.setAchievement(20, _achievement(REPUTATION, 0, 50000, REWARD_CASH, 0, 2000000)); // Legend

        // =================================================================
        //                     EARLY DRUG MILESTONE (ID 21)
        // =================================================================

        c.setAchievement(21, _achievement(REPUTATION, 0, 400, REWARD_DRUG, HEROIN, 5));

        // =================================================================
        //                     PVP DRUG REWARDS (IDs 22-23)
        // =================================================================

        c.setAchievement(22, _achievement(PVP_TOTAL_WINS, 0, 1, REWARD_DRUG, GENERAL_GOODS, 3));
        c.setAchievement(23, _achievement(PVP_TOTAL_WINS, 0, 10, REWARD_DRUG, CONTRABAND, 3));

        // =================================================================
        //                NEW: CASH THRESHOLDS (IDs 24-27)
        // =================================================================

        c.setAchievement(24, _achievement(CASH_BALANCE, 0, 10000, REWARD_DRUG, XTC, 1)); // Pocket Lined
        c.setAchievement(25, _achievement(CASH_BALANCE, 0, 100000, REWARD_DRUG, COCAINE, 1)); // High Roller
        c.setAchievement(26, _achievement(CASH_BALANCE, 0, 500000, REWARD_DRUG, JEWELS, 1)); // Boss Money
        c.setAchievement(27, _achievement(CASH_BALANCE, 0, 2000000, REWARD_DRUG, JEWELS, 3)); // Cartel Cash

        // =================================================================
        //               NEW: DRUG STOCKPILES (IDs 28-29)
        // =================================================================

        c.setAchievement(28, _achievement(DRUG_BALANCE, FENTANYL, 1000, REWARD_CASH, 0, 25000)); // Drug Lord
        c.setAchievement(29, _achievement(DRUG_BALANCE, COCAINE, 5000, REWARD_CASH, 0, 100000)); // Cocaine King

        // =================================================================
        //               NEW: PVE / PVP LONG GRIND (IDs 30-32)
        // =================================================================

        c.setAchievement(30, _achievement(PVE_TOTAL, 0, 100, REWARD_CASH, 0, 5000)); // Hundred Hustles
        c.setAchievement(31, _achievement(PVE_TOTAL, 0, 1000, REWARD_CASH, 0, 50000)); // Thousand-Yard Dealer
        c.setAchievement(32, _achievement(PVP_TOTAL_WINS, 0, 100, REWARD_CASH, 0, 100000)); // Street Veteran II

        // =================================================================
        //         MID-TIER ACHIEVEMENTS (IDs 33-44)
        //         Targets Capo -> Underboss player journey
        // =================================================================

        // Block A: PvE grind ladder (fills 100 -> 1000 gap)
        c.setAchievement(33, _achievement(PVE_TOTAL, 0, 250, REWARD_CASH, 0, 10000)); // Hustle Streak
        c.setAchievement(34, _achievement(PVE_TOTAL, 0, 500, REWARD_CASH, 0, 25000)); // Career Hustler

        // Block B: PvE outcome mastery (100 specific outcomes ~ 200-500 plays)
        c.setAchievement(35, _achievement(PVE_WINS, 0, 100, REWARD_CASH, 0, 50000)); // Sharp Eye
        c.setAchievement(36, _achievement(PVE_TIES, 0, 100, REWARD_CASH, 0, 30000)); // Stalemate Champion
        c.setAchievement(37, _achievement(PVE_LOSSES, 0, 100, REWARD_CASH, 0, 30000)); // Hard Knocks II

        // Block C: Choice mastery (100 of one choice = 100+ committed plays)
        c.setAchievement(38, _achievement(PVE_DEAL_CHOICES, 0, 100, REWARD_CASH, 0, 15000)); // Dealer's Sense
        c.setAchievement(39, _achievement(PVE_THREATEN_CHOICES, 0, 100, REWARD_CASH, 0, 15000)); // Iron Fist
        c.setAchievement(40, _achievement(PVE_BAIL_CHOICES, 0, 100, REWARD_CASH, 0, 15000)); // Survivor

        // Block D: PvP mid-tier (fills 10 -> 100 gap)
        c.setAchievement(41, _achievement(PVP_TOTAL_WINS, 0, 25, REWARD_DRUG, CONTRABAND, 5)); // Brawler
        c.setAchievement(42, _achievement(PVP_TOTAL_WINS, 0, 50, REWARD_DRUG, JEWELS, 1)); // Enforcer

        // Block E: Drug stockpile coverage (mid-tier farmable drugs)
        c.setAchievement(43, _achievement(DRUG_BALANCE, HEROIN, 1000, REWARD_CASH, 0, 25000)); // Mule Master
        c.setAchievement(44, _achievement(DRUG_BALANCE, COCAINE, 1000, REWARD_CASH, 0, 25000)); // White Powder Pro

        // =================================================================
        //         HEIST ACHIEVEMENTS (IDs 45-51)
        //         Calibrated to difficulty gates: small (rep 0, 500 stake),
        //         big (rep 300, 2.5k stake), huge (rep 1250, 10k stake).
        //         Claims must be wired to Heists (setHeists) or these revert.
        // =================================================================

        if (heists != address(0)) {
            // setAchievement fails closed on unwired heists — wire it here so SetupClaims
            // works standalone on a fresh Claims deploy (idempotent, same as SetupWiring).
            if (c.heistsContract() != heists) {
                c.setHeists(heists);
                console.log("Claims -> Heists wired:", heists);
            }

            // Early (small heists, anyone): first run refunds the small stake; first
            // clean getaway pays rep like First Blood (#8).
            c.setAchievement(45, _achievement(HEIST_RUNS, 0, 1, REWARD_CASH, 0, 500)); // First Score
            c.setAchievement(46, _achievement(HEIST_CASHOUTS, 0, 1, REWARD_REP, 0, 25)); // Getaway Driver
            c.setAchievement(47, _achievement(HEIST_STAGES_CLEARED, 0, 25, REWARD_CASH, 0, 5000)); // Deep Run

            // Mid (Dealer -> Capo, big heists): real grind, mirrors 25k mid-tier scale.
            // Busts/setbacks pay consolation like Hard Knocks (#4/#37) so risk-takers aren't punished twice.
            c.setAchievement(48, _achievement(HEIST_CASHOUTS, 0, 25, REWARD_CASH, 0, 25000)); // Professional Crew
            c.setAchievement(49, _achievement(HEIST_BUSTS, 0, 10, REWARD_CASH, 0, 10000)); // Busted, Not Broken
            c.setAchievement(50, _achievement(HEIST_SETBACKS, 0, 10, REWARD_CASH, 0, 5000)); // Close Call

            // Jackpot (requires the ETH add-on): rare-ish flavor reward, matches #23/#41 scale.
            c.setAchievement(51, _achievement(HEIST_JACKPOTS_WON, 0, 1, REWARD_DRUG, CONTRABAND, 3)); // Lucky Roll
        } else {
            console.log("Heists not deployed -- skipping heist achievements (45-51); rerun once wired.");
        }

        vm.stopBroadcast();

        console.log("52 achievements configured:");
        console.log("  Early game (0-11):");
        console.log("    #0:  PVE_TOTAL    >= 1     -> 250 CASH");
        console.log("    #1:  PVE_TOTAL    >= 10    -> 1k CASH");
        console.log("    #2:  PVE_WINS     >= 10    -> 5 XTC");
        console.log("    #3:  PVE_TIES     >= 10    -> 5 XTC");
        console.log("    #4:  PVE_LOSSES   >= 10    -> 1k CASH");
        console.log("    #5:  PVE_DEAL     >= 10    -> 5 Shrooms");
        console.log("    #6:  PVE_THREATEN >= 10    -> 5 Shrooms");
        console.log("    #7:  PVE_BAIL     >= 10    -> 5 Shrooms");
        console.log("    #8:  PVP_WINS     >= 1     -> 25 REP");
        console.log("    #9:  PVP_ATTACK   >= 10    -> 3 General Goods");
        console.log("    #10: PVP_DEFEND   >= 10    -> 3 General Goods");
        console.log("    #11: REP          >= 75    -> 100 Weed");
        console.log("  Tier milestones (12-20, new convex ladder):");
        console.log("    #12: Associate    (100)    -> 500 CASH");
        console.log("    #13: Dealer       (250)    -> 2k CASH");
        console.log("    #14: Soldier      (600)    -> 10k CASH");
        console.log("    #15: Capo         (1,500)  -> 25k CASH");
        console.log("    #16: Consigliere  (3,000)  -> 75k CASH");
        console.log("    #17: Underboss    (5,500)  -> 200k CASH");
        console.log("    #18: Don          (10,000) -> 500k CASH");
        console.log("    #19: Godfather    (22,000) -> 1M CASH");
        console.log("    #20: Legend       (50,000) -> 2M CASH");
        console.log("  Drug + PvP rewards:");
        console.log("    #21: REP >= 400            -> 5 Heroin");
        console.log("    #22: PVP_WINS >= 1         -> 3 General Goods");
        console.log("    #23: PVP_WINS >= 10        -> 3 Contraband");
        console.log("  New: cash thresholds (24-27):");
        console.log("    #24: cash >= 10k           -> 1 XTC");
        console.log("    #25: cash >= 100k          -> 1 Cocaine");
        console.log("    #26: cash >= 500k          -> 1 Jewels");
        console.log("    #27: cash >= 2M            -> 3 Jewels");
        console.log("  New: drug stockpiles (28-29):");
        console.log("    #28: Fentanyl >= 1,000     -> 25k CASH");
        console.log("    #29: Cocaine  >= 5,000     -> 100k CASH");
        console.log("  New: long grind (30-32):");
        console.log("    #30: PVE_TOTAL >= 100      -> 5k CASH");
        console.log("    #31: PVE_TOTAL >= 1,000    -> 50k CASH");
        console.log("    #32: PVP_WINS  >= 100      -> 100k CASH");
        console.log("  Mid-tier additions (33-44):");
        console.log("    #33: PVE_TOTAL    >= 250   -> 10k CASH");
        console.log("    #34: PVE_TOTAL    >= 500   -> 25k CASH");
        console.log("    #35: PVE_WINS     >= 100   -> 50k CASH");
        console.log("    #36: PVE_TIES     >= 100   -> 30k CASH");
        console.log("    #37: PVE_LOSSES   >= 100   -> 30k CASH");
        console.log("    #38: PVE_DEAL     >= 100   -> 15k CASH");
        console.log("    #39: PVE_THREATEN >= 100   -> 15k CASH");
        console.log("    #40: PVE_BAIL     >= 100   -> 15k CASH");
        console.log("    #41: PVP_WINS     >= 25    -> 5 Contraband");
        console.log("    #42: PVP_WINS     >= 50    -> 1 Jewels");
        console.log("    #43: Heroin       >= 1,000 -> 25k CASH");
        console.log("    #44: Cocaine      >= 1,000 -> 25k CASH");
        console.log("  Heists (45-51):");
        console.log("    #45: HEIST_RUNS      >= 1  -> 500 CASH (refunds the small stake)");
        console.log("    #46: HEIST_CASHOUTS  >= 1  -> 25 REP");
        console.log("    #47: HEIST_STAGES    >= 25 -> 5k CASH");
        console.log("    #48: HEIST_CASHOUTS  >= 25 -> 25k CASH");
        console.log("    #49: HEIST_BUSTS     >= 10 -> 10k CASH");
        console.log("    #50: HEIST_SETBACKS  >= 10 -> 5k CASH");
        console.log("    #51: HEIST_JACKPOTS  >= 1  -> 3 Contraband");
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

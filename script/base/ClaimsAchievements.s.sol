// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./DrugIds.s.sol";

/**
 * @title ClaimsAchievements - Canonical achievement ladder (single source of truth)
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev The full 52-achievement ladder, sim-aligned with the reputation tiers in
 *      SetupTiers. Every Claims configurator — the standalone setup (SetupClaims) and the
 *      live corrective (FixAchievements) — drives the contract through
 *      _configureAchievements, so the ladder can no longer drift between paths. Reputation milestones (#11-21) track the tier thresholds 1:1; that
 *      coupling is the whole reason this lives in one place.
 * @author Berny0x
 */
abstract contract ClaimsAchievements is DrugIds {
    // =============================================================
    //                        CONDITION TYPES
    // =============================================================

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

    // =============================================================
    //                         REWARD TYPES
    // =============================================================

    uint8 constant REWARD_REP = 0;
    uint8 constant REWARD_CASH = 1;
    uint8 constant REWARD_DRUG = 2;

    // =============================================================
    //                  ACHIEVEMENT CONFIGURATION
    // =============================================================

    /**
     * @notice Apply the canonical 52-achievement ladder to a Claims contract.
     * @dev Idempotent: setAchievement overwrites achievement config only and never touches
     *      the per-(achievement,token) claimed mapping, so re-running over a live contract
     *      re-aligns thresholds without clawing back rewards already claimed. Achievements
     *      are set in ascending id order because Claims tracks nextAchievementId as the
     *      running max+1. Heist achievements (45-51) need a wired Heists module; this wires
     *      it first when heistsAddr is non-zero, and skips them entirely when it is zero
     *      (game-only deploy) — rerun once Heists exists to fill them in.
     * @param c The Claims contract to configure
     * @param heistsAddr The Heists module address, or address(0) to skip heist achievements
     */
    function _configureAchievements(IClaimsContract c, address heistsAddr) internal {
        // Early game (0-11)
        c.setAchievement(0, _achievement(PVE_TOTAL, 0, 1, REWARD_CASH, 0, 250));
        c.setAchievement(1, _achievement(PVE_TOTAL, 0, 10, REWARD_CASH, 0, 1000));
        c.setAchievement(2, _achievement(PVE_WINS, 0, 10, REWARD_DRUG, XTC, 5));
        c.setAchievement(3, _achievement(PVE_TIES, 0, 10, REWARD_DRUG, XTC, 5));
        c.setAchievement(4, _achievement(PVE_LOSSES, 0, 10, REWARD_CASH, 0, 1000));
        c.setAchievement(5, _achievement(PVE_DEAL_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 5));
        c.setAchievement(6, _achievement(PVE_THREATEN_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 5));
        c.setAchievement(7, _achievement(PVE_BAIL_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 5));
        c.setAchievement(8, _achievement(PVP_TOTAL_WINS, 0, 1, REWARD_REP, 0, 25));
        c.setAchievement(9, _achievement(PVP_ATTACK_WINS, 0, 10, REWARD_DRUG, GOODS, 3));
        c.setAchievement(10, _achievement(PVP_DEFEND_WINS, 0, 10, REWARD_DRUG, GOODS, 3));

        // #11 Made Man: stepping stone before Associate@100
        c.setAchievement(11, _achievement(REPUTATION, 0, 75, REWARD_DRUG, WEED, 100));

        // Reputation tier milestones (12-20) — mirror SetupTiers thresholds 1:1
        c.setAchievement(12, _achievement(REPUTATION, 0, 100, REWARD_CASH, 0, 500)); // Associate
        c.setAchievement(13, _achievement(REPUTATION, 0, 250, REWARD_CASH, 0, 2000)); // Dealer
        c.setAchievement(14, _achievement(REPUTATION, 0, 600, REWARD_CASH, 0, 10000)); // Soldier
        c.setAchievement(15, _achievement(REPUTATION, 0, 1500, REWARD_CASH, 0, 25000)); // Capo
        c.setAchievement(16, _achievement(REPUTATION, 0, 3000, REWARD_CASH, 0, 75000)); // Consigliere
        c.setAchievement(17, _achievement(REPUTATION, 0, 5500, REWARD_CASH, 0, 200000)); // Underboss
        c.setAchievement(18, _achievement(REPUTATION, 0, 10000, REWARD_CASH, 0, 500000)); // Don
        c.setAchievement(19, _achievement(REPUTATION, 0, 22000, REWARD_CASH, 0, 1000000)); // Godfather
        c.setAchievement(20, _achievement(REPUTATION, 0, 50000, REWARD_CASH, 0, 2000000)); // Legend

        // #21 early Heroin milestone (between Dealer@250 and Soldier@600)
        c.setAchievement(21, _achievement(REPUTATION, 0, 400, REWARD_DRUG, HEROIN, 5));

        // PvP drug rewards (22-23)
        c.setAchievement(22, _achievement(PVP_TOTAL_WINS, 0, 1, REWARD_DRUG, GOODS, 3));
        c.setAchievement(23, _achievement(PVP_TOTAL_WINS, 0, 10, REWARD_DRUG, CONTRABAND, 3));

        // Cash thresholds (24-27)
        c.setAchievement(24, _achievement(CASH_BALANCE, 0, 10000, REWARD_DRUG, XTC, 1));
        c.setAchievement(25, _achievement(CASH_BALANCE, 0, 100000, REWARD_DRUG, COCAINE, 1));
        c.setAchievement(26, _achievement(CASH_BALANCE, 0, 500000, REWARD_DRUG, JEWELS, 1));
        c.setAchievement(27, _achievement(CASH_BALANCE, 0, 2000000, REWARD_DRUG, JEWELS, 3));

        // Drug stockpiles (28-29)
        c.setAchievement(28, _achievement(DRUG_BALANCE, FENTANYL, 1000, REWARD_CASH, 0, 25000));
        c.setAchievement(29, _achievement(DRUG_BALANCE, COCAINE, 5000, REWARD_CASH, 0, 100000));

        // Long grind (30-32)
        c.setAchievement(30, _achievement(PVE_TOTAL, 0, 100, REWARD_CASH, 0, 5000));
        c.setAchievement(31, _achievement(PVE_TOTAL, 0, 1000, REWARD_CASH, 0, 50000));
        c.setAchievement(32, _achievement(PVP_TOTAL_WINS, 0, 100, REWARD_CASH, 0, 100000));

        // Mid-tier: PvE grind ladder (33-34)
        c.setAchievement(33, _achievement(PVE_TOTAL, 0, 250, REWARD_CASH, 0, 10000));
        c.setAchievement(34, _achievement(PVE_TOTAL, 0, 500, REWARD_CASH, 0, 25000));

        // Mid-tier: PvE outcome mastery (35-37)
        c.setAchievement(35, _achievement(PVE_WINS, 0, 100, REWARD_CASH, 0, 50000));
        c.setAchievement(36, _achievement(PVE_TIES, 0, 100, REWARD_CASH, 0, 30000));
        c.setAchievement(37, _achievement(PVE_LOSSES, 0, 100, REWARD_CASH, 0, 30000));

        // Mid-tier: choice mastery (38-40)
        c.setAchievement(38, _achievement(PVE_DEAL_CHOICES, 0, 100, REWARD_CASH, 0, 15000));
        c.setAchievement(39, _achievement(PVE_THREATEN_CHOICES, 0, 100, REWARD_CASH, 0, 15000));
        c.setAchievement(40, _achievement(PVE_BAIL_CHOICES, 0, 100, REWARD_CASH, 0, 15000));

        // Mid-tier: PvP (41-42)
        c.setAchievement(41, _achievement(PVP_TOTAL_WINS, 0, 25, REWARD_DRUG, CONTRABAND, 5));
        c.setAchievement(42, _achievement(PVP_TOTAL_WINS, 0, 50, REWARD_DRUG, JEWELS, 1));

        // Mid-tier: drug stockpile coverage (43-44)
        c.setAchievement(43, _achievement(DRUG_BALANCE, HEROIN, 1000, REWARD_CASH, 0, 25000));
        c.setAchievement(44, _achievement(DRUG_BALANCE, COCAINE, 1000, REWARD_CASH, 0, 25000));

        if (heistsAddr != address(0)) {
            if (c.heistsContract() != heistsAddr) {
                c.setHeists(heistsAddr);
                console.log("Claims -> Heists wired:", heistsAddr);
            }

            // Heist achievements (45-51) — gated on a wired Heists module
            c.setAchievement(45, _achievement(HEIST_RUNS, 0, 1, REWARD_CASH, 0, 500));
            c.setAchievement(46, _achievement(HEIST_CASHOUTS, 0, 1, REWARD_REP, 0, 25));
            c.setAchievement(47, _achievement(HEIST_STAGES_CLEARED, 0, 25, REWARD_CASH, 0, 5000));
            c.setAchievement(48, _achievement(HEIST_CASHOUTS, 0, 25, REWARD_CASH, 0, 25000));
            c.setAchievement(49, _achievement(HEIST_BUSTS, 0, 10, REWARD_CASH, 0, 10000));
            c.setAchievement(50, _achievement(HEIST_SETBACKS, 0, 10, REWARD_CASH, 0, 5000));
            c.setAchievement(51, _achievement(HEIST_JACKPOTS_WON, 0, 1, REWARD_DRUG, CONTRABAND, 3));

            console.log("Achievements configured: 52 (0-51, incl. heists 45-51)");
        } else {
            console.log("Achievements configured: 45 (0-44); heists 45-51 skipped (Heists unset)");
        }
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

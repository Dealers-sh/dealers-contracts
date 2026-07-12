// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./DeployBase.s.sol";

/**
 * @title TiersConfig - Canonical 10-tier reputation ladder (single source of truth)
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Sim-calibrated ladder (test/simulation/economy_sim.py). Thresholds are pinned to the
 *      heist gates (600/1500/5500) and achievement milestones, so only the per-tier repCaps
 *      carry the pacing. Every configurator — the all-in-one deploy (DeployAll), the standalone
 *      setup (SetupTiers) and the live corrective (FixTiers) — drives Core through
 *      _configureTiers, so the ladder can no longer drift between paths.
 *
 *      setReputationTiers replaces the whole array, so the same call serves a fresh deploy and a
 *      live re-tune; it touches only the tier config, never a dealer's stored reputation.
 * @author Berny0x
 */
abstract contract TiersConfig is DeployBase {
    uint256 constant MAX_REPUTATION = 75000;

    /**
     * @notice Apply the canonical reputation ladder + max reputation to a Core contract.
     * @dev Upper repCaps (Consigliere..Godfather = 56/62/70/78) set the late-game pace: an
     *      unboosted PvE grinder reaches Don ~day 105 and Godfather ~day 225; boosted play is
     *      ~2.5x faster via extra attempts (Kingpin Godfather ~day 90 — the ~100d design target).
     *      Trimmed from 72/80/90/100 (2026-07-12) after live play compressed the mid-game: the
     *      old caps put casual Kingpin at Godfather ~day 74, and dedicated daily play with
     *      attempt resets ran ~2-3x faster still. Caps are the binding throttle at high rep
     *      (cap-stake is only a few % of bankroll there). Outsider..Capo are left fast so a
     *      fresh wallet clears the 600-rep heist gate in ~4 days. Legend is the soft-bleed
     *      prestige tier (+4/+2/-10, repCap 8).
     * @param core The Core contract to configure
     */
    function _configureTiers(IDealersCore core) internal {
        ReputationTier[] memory tiers = new ReputationTier[](10);
        tiers[0] = _tier(0, 120, 60, -3, 120, "Outsider");
        tiers[1] = _tier(100, 90, 45, -4, 90, "Associate");
        tiers[2] = _tier(250, 60, 30, -4, 60, "Dealer");
        tiers[3] = _tier(600, 36, 18, -5, 40, "Soldier");
        tiers[4] = _tier(1500, 28, 14, -6, 40, "Capo");
        tiers[5] = _tier(3000, 22, 11, -6, 56, "Consigliere");
        tiers[6] = _tier(5500, 18, 9, -7, 62, "Underboss");
        tiers[7] = _tier(10000, 15, 7, -6, 70, "Don");
        tiers[8] = _tier(22000, 12, 6, -8, 78, "Godfather");
        tiers[9] = _tier(50000, 4, 2, -10, 8, "Legend");

        core.setReputationTiers(tiers);
        core.setMaxReputation(MAX_REPUTATION);
    }

    function _tier(uint256 minReputation, int16 winBonus, int16 tieBonus, int16 lossPenalty, int16 repCap, string memory tierName)
        private
        pure
        returns (ReputationTier memory)
    {
        return ReputationTier({
            minReputation: minReputation,
            winBonus: winBonus,
            tieBonus: tieBonus,
            lossPenalty: lossPenalty,
            repCap: repCap,
            tierName: tierName
        });
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/ClaimsAchievements.s.sol";

/**
 * @title FixAchievements - Re-sync a live Claims contract to the canonical ladder
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Both testnet and mainnet Claims were configured from the stale DeployAll ladder:
 *      eight reputation milestones sit a tier early (Soldier #14 unlocks at 500 rep instead
 *      of 600) and achievements 33-51 were never set (nextAchievementId == 33). This
 *      re-applies ClaimsAchievements._configureAchievements over the existing contract.
 *      setAchievement overwrites achievement config only — the per-(achievement,token)
 *      claimed mapping is untouched, so prior claims stand and nothing is clawed back;
 *      raising a threshold only re-gates future claims. The target network is auto-resolved
 *      from chainid, so the same script corrects both — run it once against each RPC.
 *
 *   Usage:
 *     source .env && forge script script/setup/FixAchievements.s.sol:FixAchievements \
 *         --rpc-url <abstract-testnet|abstract-mainnet> --account dealersKeystore \
 *         --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
 * @author Berny0x
 */
contract FixAchievements is ClaimsAchievements {
    function run() external {
        _loadAddresses();
        _requireAddress(claims, "DEALERS_CLAIMS");

        IClaimsContract c = IClaimsContract(claims);

        console.log("Network:", _getNetworkFolder());
        console.log("Claims:", claims);
        console.log("Achievements before:", c.nextAchievementId());

        vm.startBroadcast();
        _configureAchievements(c, heists);
        vm.stopBroadcast();

        _verify(c);
    }

    /**
     * @dev Post-apply self-check. Confirms the full ladder landed and spot-checks the
     *      reputation milestones that were wrong on-chain, so a partial broadcast aborts
     *      the run loudly instead of silently leaving the ladder half-fixed.
     */
    function _verify(IClaimsContract c) internal view {
        uint256 expectedCount = heists != address(0) ? 52 : 45;
        require(c.nextAchievementId() == expectedCount, "FixAchievements: wrong achievement count");

        _assertThreshold(c, 12, 100); // Associate
        _assertThreshold(c, 14, 600); // Soldier
        _assertThreshold(c, 21, 400); // Heroin milestone

        for (uint256 id; id < expectedCount;) {
            require(c.getAchievement(id).active, "FixAchievements: inactive achievement");
            unchecked {
                ++id;
            }
        }

        console.log("Verified: full ladder active, Soldier #14 re-gated to 600 rep");
    }

    function _assertThreshold(IClaimsContract c, uint256 id, uint256 expected) internal view {
        require(c.getAchievement(id).threshold == expected, "FixAchievements: threshold mismatch");
    }
}

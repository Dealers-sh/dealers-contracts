// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/ClaimsAchievements.s.sol";

/**
 * @title SetupClaims - Configure all achievements on an existing Claims contract
 * @dev Drives the canonical ladder in ClaimsAchievements. No idempotency guard: this
 *      overwrites, so it doubles as the re-sync path on a contract that was configured
 *      from an older ladder.
 *
 *   Usage:
 *     source .env && forge script script/setup/SetupClaims.s.sol:SetupClaims \
 *         --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *         --skip "RendererSVG" --skip "UploadTraits"
 * @author Berny0x
 */
contract SetupClaims is ClaimsAchievements {
    function run() external {
        _loadAddresses();
        _requireAddress(claims, "DEALERS_CLAIMS");

        IClaimsContract c = IClaimsContract(claims);

        console.log("Claims address:", claims);
        console.log("Achievements before:", c.nextAchievementId());

        vm.startBroadcast();
        _configureAchievements(c, heists);
        vm.stopBroadcast();

        console.log("Achievements after:", c.nextAchievementId());
    }
}

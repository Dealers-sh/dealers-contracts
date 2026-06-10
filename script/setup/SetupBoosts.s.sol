// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupBoosts - Retune Kingpin + Godfather boost perks
 * @dev Usage:
 *   source .env && forge script script/setup/SetupBoosts.s.sol:SetupBoosts \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Grinder + Hustler unchanged. Kingpin: +6 attempts (was +5), 1.25x rep (was 1.20).
 *   Godfather: 2.25x drug/cash (was 2.0), 1.35x rep (was 1.25).
 *   Prices and durations unchanged.
 */
contract SetupBoosts is DeployBase {
    uint64 constant DURATION_14_DAYS = 14 days;
    uint64 constant DURATION_30_DAYS = 30 days;

    function run() external {
        _loadAddresses();
        _requireAddress(boosts, "DEALERS_BOOSTS");

        IBoostsAdmin b = IBoostsAdmin(boosts);

        console.log("Boosts address:", boosts);
        console.log("Retuning Kingpin (tier 3) + Godfather (tier 4)");

        vm.startBroadcast();

        // Kingpin - 0.01 ETH, 14 days (price/duration unchanged)
        b.setBoostTier(
            3,
            IBoostsAdmin.BoostTier({
                price: 0.01 ether,
                duration: DURATION_14_DAYS,
                drugMultiplier: 175,
                repMultiplier: 125, // was 120 (1.20x -> 1.25x)
                extraAttempts: 6, // was 5 (5+5=10 -> 5+6=11)
                freeAreaMovement: true,
                cashMultiplier: 175,
                isActive: true
            })
        );

        // Godfather - 0.023 ETH, 30 days (price/duration unchanged)
        b.setBoostTier(
            4,
            IBoostsAdmin.BoostTier({
                price: 0.023 ether,
                duration: DURATION_30_DAYS,
                drugMultiplier: 225, // was 200 (2x -> 2.25x)
                repMultiplier: 135, // was 125 (1.25x -> 1.35x)
                extraAttempts: 7,
                freeAreaMovement: true,
                cashMultiplier: 225, // was 200 (2x -> 2.25x)
                isActive: true
            })
        );

        vm.stopBroadcast();

        console.log("Kingpin: +6 attempts, 1.25x rep");
        console.log("Godfather: 2.25x drug/cash, 1.35x rep, +7 attempts");
    }
}

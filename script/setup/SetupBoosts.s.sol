// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupBoosts - Sim-calibrated boost tiers (trimmed drug/cash multipliers)
 * @dev Usage:
 *   source .env && forge script script/setup/SetupBoosts.s.sol:SetupBoosts \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Drug/cash multipliers trimmed to 1.10/1.15/1.20/1.25x (constructor defaults are
 *   1.25/1.50/1.75/2.25x). With the rep-scaled max stake (DealersPVE.setStakeScaling)
 *   the allowed stakes grow with rank, so the old multipliers turn max-stake hustles
 *   into a $CASH faucet far above the ECONOMY_DESIGN 5.1 daily bands — sim-validated in
 *   docs/ECONOMY_BALANCE_SIM.md. Boost value concentrates in rep multiplier + extra
 *   attempts + free movement; prices, durations, and rep multipliers unchanged.
 */
contract SetupBoosts is DeployBase {
    uint64 constant DURATION_3_DAYS = 3 days;
    uint64 constant DURATION_7_DAYS = 7 days;
    uint64 constant DURATION_14_DAYS = 14 days;
    uint64 constant DURATION_30_DAYS = 30 days;

    function run() external {
        _loadAddresses();
        _requireAddress(boosts, "DEALERS_BOOSTS");

        IBoostsAdmin b = IBoostsAdmin(boosts);

        console.log("Boosts address:", boosts);
        console.log("Setting all 4 tiers (trimmed drug/cash multipliers)");

        vm.startBroadcast();

        // Grinder - 0.0025 ETH, 3 days
        b.setBoostTier(
            1,
            IBoostsAdmin.BoostTier({
                price: 0.0025 ether,
                duration: DURATION_3_DAYS,
                drugMultiplier: 110, // was 125
                repMultiplier: 110,
                extraAttempts: 2,
                freeAreaMovement: false,
                cashMultiplier: 110, // was 125
                isActive: true
            })
        );

        // Hustler - 0.005 ETH, 7 days
        b.setBoostTier(
            2,
            IBoostsAdmin.BoostTier({
                price: 0.005 ether,
                duration: DURATION_7_DAYS,
                drugMultiplier: 115, // was 150
                repMultiplier: 115,
                extraAttempts: 3,
                freeAreaMovement: false,
                cashMultiplier: 115, // was 150
                isActive: true
            })
        );

        // Kingpin - 0.01 ETH, 14 days
        b.setBoostTier(
            3,
            IBoostsAdmin.BoostTier({
                price: 0.01 ether,
                duration: DURATION_14_DAYS,
                drugMultiplier: 120, // was 175
                repMultiplier: 125,
                extraAttempts: 6,
                freeAreaMovement: true,
                cashMultiplier: 120, // was 175
                isActive: true
            })
        );

        // Godfather - 0.023 ETH, 30 days
        b.setBoostTier(
            4,
            IBoostsAdmin.BoostTier({
                price: 0.023 ether,
                duration: DURATION_30_DAYS,
                drugMultiplier: 125, // was 225
                repMultiplier: 135,
                extraAttempts: 7,
                freeAreaMovement: true,
                cashMultiplier: 125, // was 225
                isActive: true
            })
        );

        vm.stopBroadcast();

        console.log("Multipliers (drug/cash): Grinder 1.10x, Hustler 1.15x, Kingpin 1.20x, Godfather 1.25x");
        console.log("Rep multipliers / attempts / prices / durations unchanged");
    }
}

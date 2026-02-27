// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

struct CoreConfig {
    uint256 attemptResetFee;
    uint256 bribeCopFee;
    uint256 cashTopupPrice;
    uint256 cashTopupAmount;
    uint256 cashPurchaseThreshold;
    uint8 jailRepPenaltyPercent;
    uint256 jailRepPenaltyCap;
    uint8 wantedPosterSuccessChance;
    uint8 breakoutSuccessChance;
    uint8 jailDrugConfiscationPercent;
    uint256 starterCash;
    uint16 jailChancePerHeat;
}

interface ICoreConfig {
    function setCoreConfig(CoreConfig calldata _config) external;
    function config() external view returns (
        uint256 attemptResetFee,
        uint256 bribeCopFee,
        uint256 cashTopupPrice,
        uint256 cashTopupAmount,
        uint256 cashPurchaseThreshold,
        uint8 jailRepPenaltyPercent,
        uint256 jailRepPenaltyCap,
        uint8 wantedPosterSuccessChance,
        uint8 breakoutSuccessChance,
        uint8 jailDrugConfiscationPercent,
        uint256 starterCash,
        uint16 jailChancePerHeat
    );
}

interface IBoostsPricing {
    function setTierPrice(uint256 tierId, uint256 newPrice) external;
    function boostTiers(uint256 tierId) external view returns (
        uint256 price,
        uint256 duration,
        uint8 drugMultiplier,
        uint8 repMultiplier,
        uint8 extraAttempts,
        bool freeAreaMovement,
        bool doubleHeistEntries,
        uint8 cashMultiplier,
        bool isActive
    );
}

interface IAreaPricing {
    function updateMovementFee(uint8 areaId, uint256 newFee) external;
    function getMovementFee(uint8 areaId) external view returns (uint256);
    function getAreaCount() external view returns (uint8);
}

/**
 * @title SetupTestnetPricing - Set all ETH fees to 10x lower for testnet
 * @dev Reduces all payable fees across Core, Boosts, and AreaRegistry.
 *      NFT mint price is a constant and cannot be changed post-deploy.
 *
 * Usage:
 *   source .env && forge script script/setup/SetupTestnetPricing.s.sol:SetupTestnetPricing \
 *     --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore --broadcast --zksync \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 */
contract SetupTestnetPricing is DeployBase {
    uint256 constant DIVISOR = 10;

    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(boosts, "DEALERS_BOOSTS");
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        console.log("=== Testnet Pricing (1/%s of mainnet) ===", vm.toString(DIVISOR));
        console.log("");

        vm.startBroadcast();

        _updateCoreConfig();
        _updateBoostPrices();
        _updateMovementFees();

        vm.stopBroadcast();

        console.log("");
        console.log("Testnet pricing applied.");
    }

    function _updateCoreConfig() internal {
        console.log("Core fees:");

        ICoreConfig c = ICoreConfig(core);
        (
            uint256 attemptResetFee,
            uint256 bribeCopFee,
            uint256 cashTopupPrice,
            uint256 cashTopupAmount,
            uint256 cashPurchaseThreshold,
            uint8 jailRepPenaltyPercent,
            uint256 jailRepPenaltyCap,
            uint8 wantedPosterSuccessChance,
            uint8 breakoutSuccessChance,
            uint8 jailDrugConfiscationPercent,
            uint256 starterCash,
            uint16 jailChancePerHeat
        ) = c.config();

        uint256 newAttemptResetFee = attemptResetFee / DIVISOR;
        uint256 newBribeCopFee = bribeCopFee / DIVISOR;
        uint256 newCashTopupPrice = cashTopupPrice / DIVISOR;

        c.setCoreConfig(CoreConfig({
            attemptResetFee: newAttemptResetFee,
            bribeCopFee: newBribeCopFee,
            cashTopupPrice: newCashTopupPrice,
            cashTopupAmount: cashTopupAmount,
            cashPurchaseThreshold: cashPurchaseThreshold,
            jailRepPenaltyPercent: jailRepPenaltyPercent,
            jailRepPenaltyCap: jailRepPenaltyCap,
            wantedPosterSuccessChance: wantedPosterSuccessChance,
            breakoutSuccessChance: breakoutSuccessChance,
            jailDrugConfiscationPercent: jailDrugConfiscationPercent,
            starterCash: starterCash,
            jailChancePerHeat: jailChancePerHeat
        }));

        console.log("  attemptResetFee: %s wei", vm.toString(newAttemptResetFee));
        console.log("  bribeCopFee:     %s wei", vm.toString(newBribeCopFee));
        console.log("  cashTopupPrice:  %s wei", vm.toString(newCashTopupPrice));
    }

    function _updateBoostPrices() internal {
        console.log("Boost tier prices:");

        IBoostsPricing b = IBoostsPricing(boosts);

        for (uint256 tierId = 1; tierId <= 4; tierId++) {
            (uint256 price, , , , , , , , bool isActive) = b.boostTiers(tierId);
            if (!isActive) continue;

            uint256 newPrice = price / DIVISOR;
            if (newPrice == 0) newPrice = 1;

            b.setTierPrice(tierId, newPrice);
            console.log("  Tier %s: %s wei", vm.toString(tierId), vm.toString(newPrice));
        }
    }

    function _updateMovementFees() internal {
        console.log("Area movement fees:");

        IAreaPricing a = IAreaPricing(areaRegistry);
        uint8 areaCount = a.getAreaCount();

        // Regular areas (1 to areaCount)
        for (uint8 i = 1; i <= areaCount; i++) {
            _updateAreaFee(a, i);
        }

        // Jail (area 255) has a movement fee used as bail
        _updateAreaFee(a, 255);
    }

    function _updateAreaFee(IAreaPricing a, uint8 areaId) internal {
        uint256 currentFee = a.getMovementFee(areaId);
        if (currentFee == 0) return;

        uint256 newFee = currentFee / DIVISOR;
        if (newFee == 0) newFee = 1;

        a.updateMovementFee(areaId, newFee);
        console.log("  Area %s: %s wei", vm.toString(areaId), vm.toString(newFee));
    }
}

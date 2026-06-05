// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupAreas - Create all game areas and configure drug pricing
 * @dev Usage:
 *   source .env && forge script script/setup/SetupAreas.s.sol:SetupAreas \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 *
 *   Requires AREA_REGISTRY env var. Drugs must be registered first.
 */
contract SetupAreas is DeployBase {
    uint256 constant FREE = 0;
    uint256 constant MOVEMENT_FEE = 0.001 ether;
    uint256 constant PREMIUM_FEE = 0.002 ether;

    // PvP-loot drug IDs (Black Market sell-only inventory)
    uint256 constant GOODS = 1;
    uint256 constant CONTRABAND = 2;
    uint256 constant JEWELS = 3;

    // Drug IDs (must match SetupDrugs registration order)
    uint256 constant WEED = 4;
    uint256 constant XTC = 5;
    uint256 constant COCAINE = 6;
    uint256 constant SHROOMS = 7;
    uint256 constant HEROIN = 8;
    uint256 constant OPIOIDS = 9;
    uint256 constant METH = 10;
    uint256 constant FENTANYL = 11;

    // Black Market is auto-created in DealersAreaRegistry (area 254).
    uint8 constant BLACK_MARKET_AREA = 254;

    function run() external {
        _loadAddresses();
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        vm.startBroadcast();
        _setupAreas();
        vm.stopBroadcast();
    }

    function _setupAreas() internal {
        IAreaRegistry reg = IAreaRegistry(areaRegistry);

        if (reg.getTotalAreas() > 0) {
            console.log("Areas: already configured, skipping");
            return;
        }

        console.log("Creating 7 game areas (Manhattan/Amsterdam free, Dubai premium)...");

        // Area 1: Manhattan (starter, FREE movement - friction-free onboarding)
        reg.createArea("Manhattan", FREE, 0, false, false);
        _configureDrugs(reg, 1, _arr(WEED, XTC, COCAINE), _arr(1, 12, 120), _arr(1, 10, 100));

        // Area 2: Amsterdam (Associate entry, FREE movement - keeps F2P loop unblocked)
        reg.createArea("Amsterdam", FREE, 100, false, false);
        _configureDrugs(reg, 2, _arr(WEED, SHROOMS, HEROIN), _arr(3, 15, 180), _arr(2, 12, 150));

        // Area 3: Colombia (Dealer entry - first paid area, also PVP unlock)
        reg.createArea("Colombia", MOVEMENT_FEE, 250, false, false);
        _configureDrugs(reg, 3, _arr(WEED, COCAINE, HEROIN), _arr(1, 60, 90), _arr(1, 50, 75));

        // Area 4: Hong Kong (Soldier entry - premium heroin sink, heist gate)
        reg.createArea("Hong Kong", MOVEMENT_FEE, 600, false, false);
        _configureDrugs(reg, 4, _arr(OPIOIDS, METH, HEROIN), _arr(22, 30, 175), _arr(18, 25, 160));

        // Area 5: Seoul (Capo entry - Asian farm zone, cheap opioids/meth/fentanyl)
        reg.createArea("Seoul", MOVEMENT_FEE, 1500, false, false);
        _configureDrugs(reg, 5, _arr(OPIOIDS, METH, FENTANYL), _arr(8, 14, 90), _arr(7, 12, 75));

        // Area 6: Tokyo (Consigliere entry - premium sell destination)
        reg.createArea("Tokyo", MOVEMENT_FEE, 3000, false, false);
        _configureDrugs(reg, 6, _arr(OPIOIDS, METH, FENTANYL), _arr(24, 32, 200), _arr(20, 26, 160));

        // Area 7: Dubai (Underboss entry - premium sell zone, Gulf nightlife + Persian-Afghan route)
        // Asymmetric sell-heavy: buy ~1.3x Tokyo, sell ~2x Tokyo
        reg.createArea("Dubai", PREMIUM_FEE, 5500, false, false);
        _configureDrugs(reg, 7, _arr(XTC, COCAINE, HEROIN), _arr(14, 160, 200), _arr(20, 200, 240));

        console.log("  7 areas created with drug configs");

        // Update Black Market sell prices to 2x base value (sell-only by contract design;
        // PVE hustles are blocked here, and DealersActions.sellDrop is the only trade path).
        // Buy prices kept at base value as sentinels (never read).
        _configureDrugs(
            reg, BLACK_MARKET_AREA, _arr(GOODS, CONTRABAND, JEWELS), _arr(75, 500, 2500), _arr(150, 1200, 6500)
        );
        console.log("  Black Market sell prices set to 2x base (Goods 150, Contraband 1200, Jewels 6500)");
    }

    function _configureDrugs(
        IAreaRegistry reg,
        uint8 areaId,
        uint256[] memory drugIds,
        uint256[] memory buyPrices,
        uint256[] memory sellPrices
    ) private {
        reg.batchConfigureAreaDrugs(areaId, drugIds, buyPrices, sellPrices);
    }

    function _arr(uint256 a, uint256 b, uint256 c) private pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }
}

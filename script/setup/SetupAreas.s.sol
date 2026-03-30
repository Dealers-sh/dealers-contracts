// SPDX-License-Identifier: MIT
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
    uint256 constant MOVEMENT_FEE = 0.001 ether;

    // Drug IDs (must match SetupDrugs registration order)
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

        console.log("Creating 6 game areas...");

        // Area 1: Manhattan (starter)
        reg.createArea("Manhattan", MOVEMENT_FEE, 0, false, false);
        _configureDrugs(reg, 1,
            _arr(WEED, XTC, COCAINE),
            _arr(1, 12, 120),
            _arr(1, 10, 100)
        );

        // Area 2: Amsterdam (early unlock)
        reg.createArea("Amsterdam", MOVEMENT_FEE, 150, false, false);
        _configureDrugs(reg, 2,
            _arr(WEED, SHROOMS, HEROIN),
            _arr(3, 15, 180),
            _arr(2, 12, 150)
        );

        // Area 3: Colombia (mid-game farm zone)
        reg.createArea("Colombia", MOVEMENT_FEE, 250, false, false);
        _configureDrugs(reg, 3,
            _arr(WEED, COCAINE, HEROIN),
            _arr(1, 60, 90),
            _arr(1, 50, 75)
        );

        // Area 4: Hong Kong (mid-late, Western->Asian bridge via Heroin)
        reg.createArea("Hong Kong", MOVEMENT_FEE, 500, false, false);
        _configureDrugs(reg, 4,
            _arr(OPIOIDS, METH, HEROIN),
            _arr(18, 28, 140),
            _arr(15, 22, 110)
        );

        // Area 5: Seoul (Asian farm zone - cheap opioids/meth/fentanyl)
        reg.createArea("Seoul", MOVEMENT_FEE, 1000, false, false);
        _configureDrugs(reg, 5,
            _arr(OPIOIDS, METH, FENTANYL),
            _arr(8, 14, 90),
            _arr(7, 12, 75)
        );

        // Area 6: Tokyo (premium sell destination)
        reg.createArea("Tokyo", MOVEMENT_FEE, 1500, false, false);
        _configureDrugs(reg, 6,
            _arr(OPIOIDS, METH, FENTANYL),
            _arr(24, 32, 200),
            _arr(20, 26, 160)
        );

        console.log("  6 areas created with drug configs");
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

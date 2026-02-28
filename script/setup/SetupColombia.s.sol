// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

interface IAreaSetup {
    function createArea(
        string calldata name,
        uint256 movementFee,
        uint256 minReputation,
        bool isSafeHouseArea,
        bool isJailArea
    ) external returns (uint8 areaId);

    function batchConfigureAreaDrugs(
        uint8 areaId,
        uint256[] calldata drugIds,
        uint256[] calldata buyPrices,
        uint256[] calldata sellPrices
    ) external;

    function getTotalAreas() external view returns (uint8);
}

/**
 * @title SetupColombia - Add Colombia area to an existing AreaRegistry
 * @dev Usage:
 *   source .env && forge script script/setup/SetupColombia.s.sol:SetupColombia \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 *
 *   Requires AREA_REGISTRY env var.
 */
contract SetupColombia is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        IAreaSetup registry = IAreaSetup(areaRegistry);

        console.log("AreaRegistry:", areaRegistry);
        console.log("Current area count:", registry.getTotalAreas());

        vm.startBroadcast();

        uint8 colombiaId = registry.createArea("Colombia", 0.001 ether, 250, false, false);

        uint256[] memory drugIds = new uint256[](3);
        uint256[] memory buyPrices = new uint256[](3);
        uint256[] memory sellPrices = new uint256[](3);

        drugIds[0] = 1; // Weed
        buyPrices[0] = 1;
        sellPrices[0] = 1;

        drugIds[1] = 3; // Cocaine
        buyPrices[1] = 60;
        sellPrices[1] = 50;

        drugIds[2] = 5; // Heroin
        buyPrices[2] = 90;
        sellPrices[2] = 75;

        registry.batchConfigureAreaDrugs(colombiaId, drugIds, buyPrices, sellPrices);

        vm.stopBroadcast();

        console.log("Colombia created with area ID:", colombiaId);
        console.log("Drugs: Weed (1/1), Cocaine (60/50), Heroin (90/75)");
        console.log("Min reputation: 250");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/AreasConfig.s.sol";

/**
 * @title SetupAreas - Create all game areas and configure drug pricing
 * @dev Drives the canonical ladder in AreasConfig onto a freshly deployed AreaRegistry.
 *      Usage:
 *        source .env && forge script script/setup/SetupAreas.s.sol:SetupAreas \
 *          --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *          --skip "RendererSVG" --skip "UploadTraits"
 *
 *      Requires AREA_REGISTRY env var. Drugs must be registered first.
 * @author Berny0x
 */
contract SetupAreas is AreasConfig {
    function run() external {
        _loadAddresses();
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        vm.startBroadcast();
        _configureAreas(IAreaRegistry(areaRegistry));
        vm.stopBroadcast();
    }
}

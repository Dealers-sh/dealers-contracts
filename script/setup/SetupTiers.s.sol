// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/TiersConfig.s.sol";

/**
 * @title SetupTiers - Configure the 10-tier reputation ladder on an existing Core
 * @dev Drives the canonical ladder in TiersConfig onto a deployed Core.
 *      Usage:
 *        source .env && forge script script/setup/SetupTiers.s.sol:SetupTiers \
 *          --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *          --skip "RendererSVG" --skip "UploadTraits"
 *
 *      Requires DEALERS_CORE env var.
 * @author Berny0x
 */
contract SetupTiers is TiersConfig {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");

        console.log("Core address:", core);

        vm.startBroadcast();
        _configureTiers(IDealersCore(core));
        vm.stopBroadcast();

        console.log("10 tiers configured (sim-calibrated ladder): Outsider -> Legend");
        console.log("MAX_REPUTATION set to 75000");
    }
}

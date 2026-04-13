// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupDrugs - Register all drug types in the DrugRegistry
 * @dev Usage:
 *   source .env && forge script script/setup/SetupDrugs.s.sol:SetupDrugs \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 *
 *   Requires DRUG_REGISTRY env var.
 */
contract SetupDrugs is DeployBase {
    uint8 constant COMMON = 0;
    uint8 constant UNCOMMON = 1;
    uint8 constant RARE = 2;

    function run() external {
        _loadAddresses();
        _requireAddress(drugRegistry, "DRUG_REGISTRY");

        vm.startBroadcast();
        _setupDrugs();
        vm.stopBroadcast();
    }

    function _setupDrugs() internal {
        IDrugRegistry reg = IDrugRegistry(drugRegistry);

        if (reg.getTotalDrugs() > 0) {
            console.log("Drugs: already configured, skipping");
            return;
        }

        console.log("Registering 11 drugs...");

        reg.createDrug("Goods",      COMMON,   75);
        reg.createDrug("Contraband", UNCOMMON, 500);
        reg.createDrug("Jewels",     RARE,     2500);
        reg.createDrug("Weed",       COMMON,   1);
        reg.createDrug("XTC",        UNCOMMON, 10);
        reg.createDrug("Cocaine",    RARE,     100);
        reg.createDrug("Shrooms",    UNCOMMON, 12);
        reg.createDrug("Heroin",     RARE,     150);
        reg.createDrug("Opioids",    COMMON,   18);
        reg.createDrug("Meth",       UNCOMMON, 25);
        reg.createDrug("Fentanyl",   RARE,     200);

        console.log("  11 drugs registered");
    }
}

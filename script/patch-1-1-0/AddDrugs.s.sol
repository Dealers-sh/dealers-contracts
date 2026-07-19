// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title AddDrugs - Patch 1.1.0 one-shot: register Slivo + Krokodil on the live DrugRegistry
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev SetupDrugs guards on `getTotalDrugs() > 0` and skips a populated registry, so the three new
 *      drugs are added here instead. createDrug appends sequentially → Slivo = 12, Krokodil = 13,
 *      Speed = 14, matching the ids in DrugIds. Idempotent: no-op once 14 drugs exist. Run before
 *      AddAreas (which places Slivo/Speed/Krokodil).
 *
 *   Usage:
 *     source .env && forge script script/patch-1-1-0/AddDrugs.s.sol:AddDrugs \
 *         --rpc-url <abstract-testnet|abstract-mainnet> --account dealersKeystore \
 *         --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
 * @author Berny0x
 */
contract AddDrugs is DeployBase {
    uint8 constant COMMON = 0;
    uint8 constant UNCOMMON = 1;
    uint8 constant RARE = 2;

    function run() external {
        _loadAddresses();
        _requireAddress(drugRegistry, "DRUG_REGISTRY");

        IDrugRegistry reg = IDrugRegistry(drugRegistry);
        uint256 total = reg.getTotalDrugs();

        if (total >= 14) {
            console.log("AddDrugs: Slivo/Krokodil/Speed already registered, skipping");
            return;
        }
        require(total == 11, "AddDrugs: unexpected drug count (expected 11)");

        vm.startBroadcast();
        uint256 slivo = reg.createDrug("Slivo", COMMON, 8);
        uint256 krokodil = reg.createDrug("Krokodil", RARE, 500);
        uint256 speed = reg.createDrug("Speed", UNCOMMON, 30);
        vm.stopBroadcast();

        require(slivo == 12 && krokodil == 13 && speed == 14, "AddDrugs: unexpected drug ids");
        require(reg.getTotalDrugs() == 14, "AddDrugs: registry count mismatch");
        console.log("AddDrugs: Slivo=12, Krokodil=13, Speed=14 registered");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title SetupWiring - Re-assert the FULL cross-contract wiring graph
 * @dev Global drift check: runs every per-contract wire set in WiringBase (references,
 *      authorizations, Heists/BankHeist ref syncs). Idempotent — state is read before every
 *      setter, so a clean deployment broadcasts nothing and prints all "ok".
 *
 *      Individual redeploys do NOT need this — each Deploy<X> script wires its own edges.
 *      Run it after a multi-contract redeploy session, or any time you want proof nothing
 *      is stale.
 *
 * Usage:
 *   source .env && forge script script/setup/SetupWiring.s.sol:SetupWiring \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract SetupWiring is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(drugRegistry, "DRUG_REGISTRY");
        _requireAddress(areaRegistry, "AREA_REGISTRY");
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(paymentHandler, "PAYMENT_HANDLER");
        _requireAddress(randomness, "RANDOMNESS");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(boosts, "DEALERS_BOOSTS");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");

        vm.startBroadcast();

        _wireDrugRegistry();
        _wireAreaRegistry();
        _wireCore();
        _wirePaymentHandler();
        _wireRandomness();
        _wireNFT();
        _wireBoosts();
        _wirePVE();
        _wirePVP();
        _wireClaims();
        _wireActions();
        _wireMulticall();
        _wireChatFactory();
        _wireHeists();
        _wireBankHeist();

        vm.stopBroadcast();

        console.log("Wiring complete.");
    }
}

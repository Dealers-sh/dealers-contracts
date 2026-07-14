// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployHeists - Redeploy the daily heist module and re-wire every edge that touches it
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, RANDOMNESS, PAYMENT_HANDLER, DRUG_REGISTRY,
 *      plus the external Pyth Entropy contract (PYTH_ENTROPY, network-prefixed env).
 *      Wires (idempotent): Core auth, PaymentHandler auth, Randomness resolver, Actions jailer +
 *      Heists.setActions, Claims.setHeists, BankHeist ref sync.
 *
 *      STATE ABANDONED on redeploy: the ETH jackpot reserve (stays in the old contract), pending
 *      runs, and per-dealer lifetime heist stats — which feed Claims achievements and BankHeist
 *      zero-baseline season scoring. Migrate/drain the jackpot reserve before switching.
 *
 *      Mainnet requires CONFIRM=DealersHeists in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployHeists.s.sol:DeployHeists \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployHeists is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(randomness, "RANDOMNESS");
        _requireAddress(paymentHandler, "PAYMENT_HANDLER");
        _requireAddress(drugRegistry, "DRUG_REGISTRY");

        address entropy = _envAddrForNetwork("PYTH_ENTROPY");
        _requireAddress(entropy, "PYTH_ENTROPY");
        _guardMainnet("DealersHeists");

        console.log("WARNING: jackpot reserve ETH stays in the old contract; lifetime heist stats reset.");
        console.log("");

        vm.startBroadcast();
        heists = _zkCreate(
            abi.encodePacked(
                vm.getCode("DealersHeists.sol:DealersHeists"),
                abi.encode(core, nft, randomness, paymentHandler, drugRegistry, entropy)
            )
        );
        console.log("DealersHeists deployed:", heists);
        _wireHeists();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. SetupHeists.s.sol only if retuning (constructor ships the sim-tuned config)");
        console.log("  2. Fund/migrate the jackpot reserve if continuing the jackpot");
        console.log("  3. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}

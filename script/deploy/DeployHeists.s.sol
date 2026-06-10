// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployHeists - Deploy + wire the daily heist module (DealersHeists)
 *
 * @dev Standalone module deploy — intentionally NOT part of DeployAll. Deploys DealersHeists (daily
 *      push-your-luck supply/cash runs + optional ETH jackpot), persists its address, and wires it
 *      idempotently.
 *
 *      The community bank heist (DealersBankHeist) is NOT deployed here — it ships later via
 *      DeployBankHeist.s.sol. Until then the PaymentHandler bank-fee share keeps accruing to
 *      whatever address PaymentHandler was deployed with (BANK_VAULT — a treasury/multisig).
 *      That address must be able to receive ETH, or fee processing will revert.
 *
 *      Constructor deps (must already be deployed): core, nft, randomness, paymentHandler,
 *      drugRegistry. Plus the external Pyth Entropy contract (PYTH_ENTROPY).
 *
 *      Post-deploy wiring (idempotent, safe to re-run):
 *        Core.authorizeContract:           Heists   (mutates core state)
 *        PaymentHandler.authorizeContract: Heists   (calls processMarketplaceFee for the ETH add-on)
 *        Randomness.authorizeResolver:     Heists   (commit/reveal)
 *        Actions.authorizeJailer + Heists.setActions: Heists  (arrest-on-bust, if Actions deployed)
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployHeists.s.sol:DeployHeists \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Requires (besides the core addresses): TESTNET_PYTH_ENTROPY / MAINNET_PYTH_ENTROPY.
 *   Next: run SetupHeists.s.sol to configure difficulties + tuned tables.
 */
interface IHeistsWiring {
    function setActions(address _actions) external;
    function actions() external view returns (address);
}

contract DeployHeists is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(randomness, "RANDOMNESS");
        _requireAddress(paymentHandler, "PAYMENT_HANDLER");
        _requireAddress(drugRegistry, "DRUG_REGISTRY");

        address entropy = _envAddrForNetwork("PYTH_ENTROPY");
        _requireAddress(entropy, "PYTH_ENTROPY");

        vm.startBroadcast();

        heists = _zkCreate(
            abi.encodePacked(
                vm.getCode("DealersHeists.sol:DealersHeists"),
                abi.encode(core, nft, randomness, paymentHandler, drugRegistry, entropy)
            )
        );
        console.log("DealersHeists deployed:", heists);

        _wire();

        vm.stopBroadcast();

        _saveAddresses();

        console.log("");
        console.log("Bank heist NOT deployed; bank-fee share keeps accruing to PaymentHandler.bankVault.");
        console.log("Deploy it later via DeployBankHeist.s.sol when launching the community event.");
        console.log("Next: run SetupHeists.s.sol to set difficulties + tuned tables.");
    }

    function _wire() internal {
        console.log("Wiring DealersHeists:");

        IDealersCore c = IDealersCore(core);
        if (!c.authorizedContracts(heists)) {
            c.authorizeContract(heists, true);
            console.log("  Core -> Heists: AUTHORIZED");
        } else {
            console.log("  Core -> Heists: ok");
        }

        IPaymentHandler ph = IPaymentHandler(paymentHandler);
        if (!ph.authorizedContracts(heists)) {
            ph.authorizeContract(heists, true);
            console.log("  PaymentHandler -> Heists: AUTHORIZED");
        } else {
            console.log("  PaymentHandler -> Heists: ok");
        }

        IRandomness rng = IRandomness(randomness);
        if (!rng.isAuthorizedResolver(heists)) {
            rng.authorizeResolver(heists, true);
            console.log("  Randomness -> Heists: AUTHORIZED");
        } else {
            console.log("  Randomness -> Heists: ok");
        }

        // Optional arrest-on-bust integration.
        if (actions != address(0)) {
            if (IHeistsWiring(heists).actions() != actions) {
                IHeistsWiring(heists).setActions(actions);
                console.log("  Heists -> Actions: SET");
            } else {
                console.log("  Heists -> Actions: ok");
            }
            IActionsContract a = IActionsContract(actions);
            if (!a.authorizedJailers(heists)) {
                a.authorizeJailer(heists, true);
                console.log("  Actions.jailer -> Heists: AUTHORIZED");
            } else {
                console.log("  Actions.jailer -> Heists: ok");
            }
        }

        console.log("");
    }
}

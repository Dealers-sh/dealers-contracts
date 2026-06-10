// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployBankHeist - Deploy + wire the community bank-heist event (deferred launch step)
 *
 * @custom:status CONCEPT — OUT OF AUDIT SCOPE. Deploys the bank-heist concept module, which is not
 *      part of the audited mainnet rollout. Do not run against mainnet during the audited launch.
 *
 * @dev Run this only when launching the recurring community event — it is NOT part of the initial
 *      heist rollout (DeployHeists ships the daily module alone). Requires DealersHeists already
 *      deployed (the bank heist reads heistRuns for activity weighting).
 *
 *      Deploys DealersBankHeist, authorizes it on Core, repoints PaymentHandler.bankVault at it (so
 *      the 80% bank-fee share now accrues into the event vault instead of the launch treasury), and
 *      ships it PAUSED — entries are blocked until {unpause}, while ETH still accrues.
 *
 *      ETH already accrued at the previous bankVault (the launch treasury) stays there; migrate it
 *      into the new vault separately by sending to the contract's receive().
 *
 *      Constructor deps (must already be deployed): core, nft, pve, pvp, heists. Plus the external
 *      Pyth Entropy contract (PYTH_ENTROPY) and the prep-window length (BANK_HEIST_PREP_DURATION,
 *      default 7 days).
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployBankHeist.s.sol:DeployBankHeist \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Requires (besides the core addresses): TESTNET_PYTH_ENTROPY / MAINNET_PYTH_ENTROPY.
 */
interface IPaymentHandlerVault {
    function setBankVault(address _bankVault) external;
    function bankVault() external view returns (address);
}

interface IBankHeistWiring {
    function pause() external;
    function paused() external view returns (bool);
}

contract DeployBankHeist is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");
        _requireAddress(paymentHandler, "PAYMENT_HANDLER");
        _requireAddress(heists, "DEALERS_HEISTS"); // DealersHeists must be deployed first

        address entropy = _envAddrForNetwork("PYTH_ENTROPY");
        _requireAddress(entropy, "PYTH_ENTROPY");
        uint64 prepDuration = uint64(vm.envOr("BANK_HEIST_PREP_DURATION", uint256(7 days)));

        vm.startBroadcast();

        bankHeist = _zkCreate(
            abi.encodePacked(
                vm.getCode("DealersBankHeist.sol:DealersBankHeist"),
                abi.encode(core, nft, pve, pvp, heists, entropy, prepDuration)
            )
        );
        console.log("DealersBankHeist deployed:", bankHeist);

        IDealersCore c = IDealersCore(core);
        if (!c.authorizedContracts(bankHeist)) {
            c.authorizeContract(bankHeist, true);
            console.log("  Core -> BankHeist: AUTHORIZED");
        } else {
            console.log("  Core -> BankHeist: ok");
        }

        IPaymentHandlerVault ph = IPaymentHandlerVault(paymentHandler);
        if (ph.bankVault() != bankHeist) {
            ph.setBankVault(bankHeist);
            console.log("  PaymentHandler.bankVault -> BankHeist: SET");
        } else {
            console.log("  PaymentHandler.bankVault -> BankHeist: ok");
        }

        IBankHeistWiring bh = IBankHeistWiring(bankHeist);
        if (!bh.paused()) {
            bh.pause();
            console.log("  BankHeist: PAUSED");
        } else {
            console.log("  BankHeist: already paused");
        }

        vm.stopBroadcast();

        _saveAddresses();

        console.log("");
        console.log("Bank heist deployed PAUSED. Migrate any prior bankVault ETH, then unpause to launch.");
    }
}

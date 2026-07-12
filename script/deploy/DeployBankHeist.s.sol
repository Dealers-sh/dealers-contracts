// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployBankHeist - Deploy + wire the community bank-heist event (deferred launch step)
 *
 * @dev Requires DealersHeists already deployed (season scoring reads heistRuns). Deploys
 *      DealersBankHeist, authorizes it on Core, repoints PaymentHandler.bankVault at it (the 80%
 *      bank-fee share then accrues into the event vault), and ships it PAUSED — entries are
 *      blocked until {unpause}, while ETH still accrues. ETH already accrued at the previous
 *      bankVault stays there; migrate it separately by sending to the contract's receive().
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployBankHeist.s.sol:DeployBankHeist \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
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

        vm.startBroadcast();

        bankHeist = _zkCreate(
            abi.encodePacked(
                vm.getCode("DealersBankHeist.sol:DealersBankHeist"), abi.encode(core, nft, pve, pvp, heists)
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
        console.log("Bank heist deployed PAUSED. Migrate any prior bankVault ETH, then unpause + openSeason to launch.");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployBoosts
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, PAYMENT_HANDLER
 *      Post-deploy:
 *        - Core.authorizeContract(boosts, true)
 *        - PaymentHandler.authorizeContract(boosts, true)
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployBoosts.s.sol:DeployBoosts \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployBoosts is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(paymentHandler, "PAYMENT_HANDLER");

        vm.startBroadcast();
        boosts = _zkCreate(abi.encodePacked(
            vm.getCode("DealersExeBoosts.sol:DealersExeBoosts"),
            abi.encode(core, nft, paymentHandler)
        ));
        vm.stopBroadcast();

        _saveAddresses();

        console.log("DealersExeBoosts deployed:", boosts);
        console.log("");
        console.log("Next: run SetupWiring.s.sol");
    }
}

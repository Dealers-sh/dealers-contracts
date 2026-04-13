// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployCore
 * @dev Constructor deps: none
 *      Post-deploy wiring needed:
 *        - Core.set{DrugRegistry,AreaRegistry,NFTContract,PaymentHandler,Randomness}
 *        - Core.authorizeContract for PVE, PVP, Boosts, NFT
 *        - DrugRegistry.authorizeContract(core)
 *        - PaymentHandler.authorizeContract(core)
 *        - AreaRegistry.setCoreContract(core)
 *        - NFT.setDealersExeCore(core)
 *        - PVE.setDealersExeCore(core)
 *        - PVP.setDealersExeCore(core)
 *        - Boosts.setDealersExeCore(core)
 *        - SetupTiers.s.sol for reputation tiers
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployCore.s.sol:DeployCore \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployCore is DeployBase {
    function run() external {
        _loadAddresses();

        vm.startBroadcast();
        core = _zkCreate(vm.getCode("DealersExeCore.sol:DealersExeCore"));
        vm.stopBroadcast();

        _saveAddresses();

        console.log("DealersExeCore deployed:", core);
        console.log("");
        console.log("Next steps:");
        console.log("  1. Run SetupWiring.s.sol");
        console.log("  2. Run SetupTiers.s.sol");
    }
}

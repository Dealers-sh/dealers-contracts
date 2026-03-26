// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployClaims
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, DEALERS_PVE, DEALERS_PVP
 *      Post-deploy:
 *        - Core.authorizeContract(claims, true)
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployClaims.s.sol:DeployClaims \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployClaims is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");
        vm.startBroadcast();
        claims = _zkCreate(abi.encodePacked(
            vm.getCode("DealersExeClaims.sol:DealersExeClaims"),
            abi.encode(core, nft, pve, pvp)
        ));
        vm.stopBroadcast();

        _saveAddresses();

        console.log("DealersExeClaims deployed:", claims);
        console.log("");
        console.log("Next: run SetupWiring.s.sol");
    }
}

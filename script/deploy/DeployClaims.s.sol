// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployClaims
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, DEALERS_PVE, DEALERS_PVP
 *      Post-deploy wiring (idempotent):
 *        - Core.authorizeContract(claims, true)  (Claims grants rewards via Core)
 *        - Claims.setHeists                      (heist achievement conditions, if Heists deployed)
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployClaims.s.sol:DeployClaims \
 *       --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *       --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployClaims is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");
        vm.startBroadcast();
        claims =
            _zkCreate(abi.encodePacked(vm.getCode("DealersClaims.sol:DealersClaims"), abi.encode(core, nft, pve, pvp)));
        console.log("DealersClaims deployed:", claims);

        IDealersCore c = IDealersCore(core);
        if (!c.authorizedContracts(claims)) {
            c.authorizeContract(claims, true);
            console.log("Core -> Claims: AUTHORIZED");
        }

        if (heists != address(0)) {
            IClaimsContract cl = IClaimsContract(claims);
            if (cl.heistsContract() != heists) {
                cl.setHeists(heists);
                console.log("Claims -> Heists: SET");
            }
        }
        vm.stopBroadcast();

        _saveAddresses();

        console.log("");
        console.log("Next: run SetupClaims.s.sol to configure achievements.");
    }
}

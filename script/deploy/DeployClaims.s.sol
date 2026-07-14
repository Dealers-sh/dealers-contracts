// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployClaims - Redeploy the achievements module and re-wire every edge that touches it
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, DEALERS_PVE, DEALERS_PVP.
 *      Wires (idempotent): Core auth, Claims refs (heists).
 *
 *      STATE ABANDONED on redeploy: the achievement ladder (re-create via SetupClaims) AND all
 *      per-dealer claimed flags — every dealer can re-claim every achievement they already earned
 *      on the fresh contract. On mainnet that is free rep/cash inflation; plan for it.
 *
 *      Mainnet requires CONFIRM=DealersClaims in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployClaims.s.sol:DeployClaims \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployClaims is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");
        _guardMainnet("DealersClaims");

        console.log("WARNING: claimed flags reset - dealers can RE-CLAIM already-earned achievements.");
        console.log("");

        vm.startBroadcast();
        claims =
            _zkCreate(abi.encodePacked(vm.getCode("DealersClaims.sol:DealersClaims"), abi.encode(core, nft, pve, pvp)));
        console.log("DealersClaims deployed:", claims);
        _wireClaims();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. SetupClaims.s.sol (REQUIRED - configure the achievement ladder)");
        console.log("  2. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}

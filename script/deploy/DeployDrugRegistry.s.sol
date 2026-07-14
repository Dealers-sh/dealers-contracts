// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployDrugRegistry - Redeploy the drug registry and re-wire every edge that touches it
 * @dev Constructor deps: none.
 *      Wires (idempotent): Core, AreaRegistry, PVP, Multicall drugRegistry refs + Heists ref sync.
 *
 *      STATE ABANDONED on redeploy: all drug definitions. Dealer drug balances (Core) and area
 *      pricing (AreaRegistry) are keyed by drugId and survive — but ONLY if SetupDrugs re-registers
 *      the drugs in the exact original order so the ids line up. Run SetupDrugs immediately.
 *
 *      Mainnet requires CONFIRM=DealersDrugRegistry in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployDrugRegistry.s.sol:DeployDrugRegistry \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployDrugRegistry is WiringBase {
    function run() external {
        _loadAddresses();
        _guardMainnet("DealersDrugRegistry");

        console.log("WARNING: fresh registry has ZERO drugs until SetupDrugs runs (same order = same ids).");
        console.log("");

        vm.startBroadcast();
        drugRegistry = _zkCreate(vm.getCode("DealersDrugRegistry.sol:DealersDrugRegistry"));
        console.log("DealersDrugRegistry deployed:", drugRegistry);
        _wireDrugRegistry();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. SetupDrugs.s.sol (REQUIRED - re-register the 11 drugs in original order)");
        console.log("  2. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}

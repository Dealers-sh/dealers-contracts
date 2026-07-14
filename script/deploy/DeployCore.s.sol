// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployCore - Redeploy the central state hub and re-wire every edge that touches it
 * @dev Constructor deps: none.
 *      Wires (idempotent): Core's four refs, every module authorization on the new Core, the core
 *      pointer on NFT/Boosts/PVE/PVP/Claims/Multicall/AreaRegistry, PaymentHandler auth, and the
 *      Heists/BankHeist ref syncs.
 *
 *      STATE ABANDONED on redeploy: ALL dealer game state — reputation, cash, drug balances, heat,
 *      areas, attempts, jail/safe-house, boosts. There is no migration path; on mainnet this is a
 *      full game reset. Last resort only.
 *
 *      NOT re-wireable (constructor-only core reference):
 *        - DealersActions      -> redeploy via DeployActions.s.sol afterwards
 *        - DealersAreaChatGate -> deploy a new gate + ChatFactory.setRoomGate per area room
 *
 *      Mainnet requires CONFIRM=DealersCore in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployCore.s.sol:DeployCore \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployCore is WiringBase {
    function run() external {
        _loadAddresses();
        _guardMainnet("DealersCore");

        console.log("WARNING: a new Core starts with ZERO dealer state (rep/cash/drugs/heat/areas).");
        console.log("");

        vm.startBroadcast();
        core = _zkCreate(vm.getCode("DealersCore.sol:DealersCore"));
        console.log("DealersCore deployed:", core);
        _wireCore();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. SetupTiers.s.sol (REQUIRED - canonical reputation ladder; ctor ladder may be stale)");
        console.log("  2. SetupRebalance.s.sol (REQUIRED - CoreConfig jail/fees live on Core)");
        console.log("  3. DeployActions.s.sol (REQUIRED - Actions.core is constructor-only)");
        console.log("  4. New DealersAreaChatGate + ChatFactory.setRoomGate per area room (gate.core is ctor-only)");
        console.log("  5. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}

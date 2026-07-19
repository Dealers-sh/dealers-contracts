// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetFees - Patch 1.1.0 one-shot: trim bribe + bail to 0.0006 ETH
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Two different contracts hold the two fees: bribe is CoreConfig.bribeCopFee (read-modify-write
 *      so every other CoreConfig field is preserved), while bail is the jail area's movement fee —
 *      payBail reads areaRegistry.getMovementFee(255). Both go to 0.0006 ETH, matching the new
 *      default hop. Idempotent: rewriting values already correct is a harmless no-op.
 *
 *   Usage:
 *     source .env && forge script script/patch-1-1-0/SetFees.s.sol:SetFees \
 *         --rpc-url <abstract-testnet|abstract-mainnet> --account dealersKeystore \
 *         --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
 * @author Berny0x
 */
contract SetFees is DeployBase {
    uint256 constant NEW_FEE = 0.0006 ether;
    uint8 constant JAIL_AREA = 255;

    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        IDealersCore c = IDealersCore(core);
        IAreaRegistry reg = IAreaRegistry(areaRegistry);

        IDealersCore.CoreConfig memory cfg = c.config();
        cfg.bribeCopFee = NEW_FEE;

        vm.startBroadcast();
        c.setCoreConfig(cfg);
        reg.updateMovementFee(JAIL_AREA, NEW_FEE);
        vm.stopBroadcast();

        require(c.config().bribeCopFee == NEW_FEE, "SetFees: bribe not applied");
        require(reg.getMovementFee(JAIL_AREA) == NEW_FEE, "SetFees: bail not applied");
        console.log("SetFees: bribe + bail set to 0.0006 ETH");
    }
}

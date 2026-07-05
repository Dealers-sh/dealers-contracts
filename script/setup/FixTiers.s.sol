// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/TiersConfig.s.sol";

/**
 * @title FixTiers - Re-sync a live Core to the canonical reputation ladder
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Both testnet and mainnet shipped the old upper repCaps (Consigliere..Godfather =
 *      44/48/52/56), which left no-boost PvE stalling at Don. This re-applies TiersConfig over
 *      the existing Core via setReputationTiers (the upper caps become 72/80/90/100). The setter
 *      replaces the tier config only — a dealer's stored reputation is untouched, so nobody is
 *      demoted or reset; the raised caps simply let future hustles climb faster. Target network
 *      is auto-resolved from chainid, so the same script corrects both — run it once per RPC.
 *
 *   Usage:
 *     source .env && forge script script/setup/FixTiers.s.sol:FixTiers \
 *         --rpc-url <abstract-testnet|abstract-mainnet> --account dealersKeystore \
 *         --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
 * @author Berny0x
 */
contract FixTiers is TiersConfig {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");

        IDealersCore c = IDealersCore(core);

        console.log("Network:", _getNetworkFolder());
        console.log("Core:", core);

        vm.startBroadcast();
        _configureTiers(c);
        vm.stopBroadcast();

        _verify(c);
    }

    /**
     * @dev Post-apply self-check. Reads the upper-tier repCaps back and asserts they match the
     *      new ladder, so a partial broadcast aborts loudly instead of leaving caps half-raised.
     */
    function _verify(IDealersCore c) internal view {
        _assertCap(c, 5, 72); // Consigliere
        _assertCap(c, 6, 80); // Underboss
        _assertCap(c, 7, 90); // Don
        _assertCap(c, 8, 100); // Godfather
        console.log("Verified: upper repCaps re-synced to 72/80/90/100 (Consigliere..Godfather)");
    }

    function _assertCap(IDealersCore c, uint256 index, int16 expected) internal view {
        (,,,, int16 repCap,) = c.reputationTiers(index);
        require(repCap == expected, "FixTiers: repCap mismatch");
    }
}

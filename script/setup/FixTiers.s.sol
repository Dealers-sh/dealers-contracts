// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/TiersConfig.s.sol";

/**
 * @title FixTiers - Re-sync a live Core to the canonical reputation ladder
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Re-applies the canonical TiersConfig ladder over the existing Core via
 *      setReputationTiers. The setter replaces the tier config only — a dealer's stored
 *      reputation is untouched, so nobody is demoted or reset; new caps only change what future
 *      hustles can earn per play. Target network is auto-resolved from chainid, so the same
 *      script corrects both — run it once per RPC.
 *
 *      History: first run raised the upper repCaps 44/48/52/56 -> 72/80/90/100 (no-boost PvE
 *      stalled at Don). Second run (2026-07-12) trims them to 56/62/70/78 — live play showed the
 *      raised caps compressed the late game (casual Kingpin Godfather ~day 74 vs the ~100d
 *      target, dedicated grinders 2-3x faster still).
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
        _assertCap(c, 5, 56); // Consigliere
        _assertCap(c, 6, 62); // Underboss
        _assertCap(c, 7, 70); // Don
        _assertCap(c, 8, 78); // Godfather
        console.log("Verified: upper repCaps re-synced to 56/62/70/78 (Consigliere..Godfather)");
    }

    function _assertCap(IDealersCore c, uint256 index, int16 expected) internal view {
        (,,,, int16 repCap,) = c.reputationTiers(index);
        require(repCap == expected, "FixTiers: repCap mismatch");
    }
}

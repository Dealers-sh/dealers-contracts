// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";
import {IDealersBankHeist} from "../../src/core/IDealersBankHeist.sol";

/**
 * @title EndBankHeistSeason - Freeze scores and settle a closed bank-heist season
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Idempotent keeper for the post-close lifecycle: pages {freezeScores} until every entrant
 *      is frozen, then {settle} to reserve the pot and open claims. Both calls are permissionless,
 *      so this needs a funded signer but not the owner key.
 *
 *      Run WITHOUT --broadcast first to preview: the simulation logs the season phase and the
 *      outcome it would produce (pot, skip reason, or window-missed) without sending anything.
 *
 *   Preview (dry run — nothing is sent):
 *     source .env && forge script script/setup/EndBankHeistSeason.s.sol:EndBankHeistSeason \
 *       --rpc-url abstract-testnet --zksync --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Execute:
 *     source .env && forge script script/setup/EndBankHeistSeason.s.sol:EndBankHeistSeason \
 *       --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *       --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Targets the latest season by default; set SEASON=<id> to end an earlier one. Safe to re-run:
 *   a settled or skipped season short-circuits, and freezing resumes from wherever the cursor left
 *   off. Claims stay player-driven ({claim}); rolling the next season stays SetupBankHeistSeason.
 * @author Berny0x
 */
interface IBankHeistSettle {
    function seasonCount() external view returns (uint256);
    function getSeason(uint256 seasonId) external view returns (IDealersBankHeist.Season memory);
    function freezeScores(uint256 seasonId, uint256 maxCount) external;
    function settle(uint256 seasonId) external;
}

contract EndBankHeistSeason is DeployBase {
    /** @dev Entrants frozen per {freezeScores} tx — three cross-module staticcalls each, so keep
     *       pages modest to stay inside block gas on a large mainnet season. */
    uint256 internal constant FREEZE_PAGE = 250;

    function run() external {
        _loadAddresses();
        _requireAddress(bankHeist, "DEALERS_BANK_HEIST");

        IBankHeistSettle bh = IBankHeistSettle(bankHeist);
        uint256 count = bh.seasonCount();
        require(count != 0, "no seasons opened");
        uint256 sid = vm.envOr("SEASON", count - 1);
        require(sid < count, "SEASON out of range");

        IDealersBankHeist.Season memory s = bh.getSeason(sid);
        console.log("BankHeist:", bankHeist);
        console.log("Season:", sid);
        console.log("  entrants:", uint256(s.entryCount));
        console.log("  frozen so far:", uint256(s.scoreCursor));

        if (s.settled) {
            console.log("  ALREADY SETTLED | pot (wei):", s.pot);
            console.log("  totalScore:", s.totalScore);
            return;
        }
        if (s.skipped) {
            console.log("  SKIPPED/CANCELLED - refunds open via claimRefund");
            return;
        }
        if (block.timestamp < s.closesAt) {
            console.log("  NOT CLOSED yet | closesAt:", uint256(s.closesAt));
            console.log("  seconds remaining:", uint256(s.closesAt) - block.timestamp);
            return;
        }

        uint256 freezeDeadline = uint256(s.closesAt) + s.config.freezeWindow;
        uint256 settleDeadline = uint256(s.closesAt) + s.config.refundTimeout;
        bool aboveMin = s.entryCount >= s.config.minEntrants;

        vm.startBroadcast();

        if (s.scoreCursor < s.entryCount) {
            if (aboveMin && block.timestamp > freezeDeadline) {
                console.log("  FREEZE WINDOW CLOSED - season falls to refund-only");
                console.log("  freezeDeadline:", freezeDeadline);
                vm.stopBroadcast();
                return;
            }
            while (true) {
                bh.freezeScores(sid, FREEZE_PAGE);
                s = bh.getSeason(sid);
                if (s.skipped) {
                    console.log("  BELOW MIN ENTRANTS - skipped, refunds open");
                    vm.stopBroadcast();
                    return;
                }
                if (s.scoreCursor >= s.entryCount) break;
            }
            console.log("  scores frozen | totalScore:", s.totalScore);
        } else {
            console.log("  scores already frozen | totalScore:", s.totalScore);
        }

        if (block.timestamp > settleDeadline) {
            console.log("  SETTLE WINDOW CLOSED - refund-only; entrants use claimRefund");
            console.log("  settleDeadline:", settleDeadline);
            vm.stopBroadcast();
            return;
        }

        bh.settle(sid);
        s = bh.getSeason(sid);

        vm.stopBroadcast();

        if (s.skipped) {
            console.log("  totalScore 0 -> skipped, refunds open");
        } else {
            console.log("  SETTLED | pot (wei):", s.pot);
            console.log("  totalScore:", s.totalScore);
            console.log("  claim window (s):", uint256(s.config.claimWindow));
        }
    }
}

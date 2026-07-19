// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";
import {IDealersBankHeist} from "../../src/core/IDealersBankHeist.sol";

/**
 * @title SetupBankHeistSeason - Fund the vault, unpause, and open a bank-heist season
 * @dev Usage:
 *   source .env && forge script script/setup/SetupBankHeistSeason.s.sol:SetupBankHeistSeason \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Idempotent: vault funding is skipped once the balance covers VAULT_SEED, unpause is skipped
 *   when live, and openSeason is skipped while a season is in flight (re-run after settle/skip
 *   to roll the next one — flip ZERO_BASELINE off for post-genesis seasons).
 *
 *   Season 1 is the GENESIS season (zeroBaseline = true): entry keeps a zero baseline, so all
 *   lifetime PVE/PVP/heist play counts retroactively. Later seasons score delta-vs-entry.
 */
interface IBankHeistAdmin {
    function paused() external view returns (bool);
    function unpause() external;
    function seasonCount() external view returns (uint256);
    function getSeason(uint256 seasonId) external view returns (IDealersBankHeist.Season memory);
    function openSeason(IDealersBankHeist.SeasonConfig calldata cfg) external;
}

contract SetupBankHeistSeason is DeployBase {
    uint256 internal constant VAULT_SEED = 0.01 ether;
    bool internal constant ZERO_BASELINE = true; // genesis mode — set false for later seasons

    function run() external {
        _loadAddresses();
        _requireAddress(bankHeist, "DEALERS_BANK_HEIST");

        IBankHeistAdmin bh = IBankHeistAdmin(bankHeist);
        console.log("BankHeist address:", bankHeist);

        vm.startBroadcast();

        if (bankHeist.balance < VAULT_SEED) {
            (bool ok,) = bankHeist.call{value: VAULT_SEED - bankHeist.balance}("");
            require(ok, "vault seed transfer failed");
            console.log("  Vault seeded to:", VAULT_SEED);
        } else {
            console.log("  Vault balance ok:", bankHeist.balance);
        }

        if (bh.paused()) {
            bh.unpause();
            console.log("  BankHeist: UNPAUSED");
        } else {
            console.log("  BankHeist: already live");
        }

        uint256 count = bh.seasonCount();
        bool canOpen = count == 0;
        if (!canOpen) {
            IDealersBankHeist.Season memory prev = bh.getSeason(count - 1);
            canOpen = prev.settled || prev.skipped;
        }

        if (canOpen) {
            // Testnet genesis rehearsal: 200-rep entry gate, 500 CASH fee, score = games played
            // (PVE/PVP/heist), qualify with >=5 PVE and >=1 PVP, +5% score per daily focus check-in.
            IDealersBankHeist.SeasonConfig memory cfg = IDealersBankHeist.SeasonConfig({
                duration: 9 hours,
                entryFee: 500,
                entryRepGate: 200,
                minEntrants: 2,
                maxEntrants: 10000,
                potBps: 7500,
                claimWindow: 30 days,
                refundTimeout: 7 days,
                freezeWindow: 1 days,
                weights: [uint64(1), 1, 1, 0],
                minThresholds: [uint32(5), 1, 0, 0],
                focusBonusBps: 500,
                zeroBaseline: ZERO_BASELINE
            });
            bh.openSeason(cfg);
            console.log("  Season opened:", count);
            console.log("    duration 9h | fee 500 CASH | rep gate 200 | pot 75%% of vault | zeroBaseline:", ZERO_BASELINE);
        } else {
            console.log("  Season in flight - openSeason skipped (settle/cancel it first)");
        }

        vm.stopBroadcast();
    }
}

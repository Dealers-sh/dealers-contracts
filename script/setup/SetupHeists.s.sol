// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupHeists - Configure the DealersHeists module (difficulties + tuned tables)
 * @dev Usage:
 *   source .env && forge script script/setup/SetupHeists.s.sol:SetupHeists \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 *
 *   Requires DEALERS_HEISTS (deployment JSON `.heists` or env). This script is CONFIG ONLY —
 *   authorization (DealersCore.authorizeContract, DealersPaymentHandler.authorizeContract, and
 *   PaymentHandler.setBankVault for the bank heist) is wiring, handled separately.
 *
 *   Difficulty configs are REQUIRED: the contract ships with difficultyConfigs empty, so
 *   startHeist reverts (InvalidDifficulty) until set. The remaining tables are re-asserted to
 *   make this script the durable source of truth (stage odds / pot multipliers / supply mix
 *   match the constructor defaults; the jackpot table is the TUNED generous preset).
 *
 *   Values derived from the economy sim (test/simulation/HeistEconomySimulation.t.sol +
 *   heist_tuning.py) to fit ECONOMY_DESIGN 5.1 cash bands and keep the ETH jackpot reserve
 *   self-funding. See the constants below for rationale.
 */
interface IHeistsAdmin {
    struct DifficultyConfig {
        uint256 repGate; // totalReputation required to enter
        uint96 cashEntry; // $CASH stake (sizes the drug/$CASH pot)
        bool active;
    }

    struct JackpotStage {
        uint16 triggerPct; // 0-100, chance the jackpot triggers on a cleared stage
        uint32 minMultBps; // value floor as bps of the ETH add-on (non-zero; <10000 = partial refund)
        uint32 maxMultBps; // value ceiling as bps of the ETH add-on
    }

    function setDifficultyConfig(uint8 difficulty, DifficultyConfig calldata cfg) external;
    function setStageOdds(uint8[5] calldata cleanOdds, uint8[5] calldata setbackOdds, uint16[5] calldata setbackKeepBps)
        external;
    function setStageRewards(uint32[5] calldata potMinBps, uint32[5] calldata potMaxBps, uint16[5] calldata repReward)
        external;
    function setSupplyMix(uint8[3][5] calldata mix) external;
    function setJackpotConfig(JackpotStage[5] calldata cfg) external;
    function setEthAddOn(uint96 amount) external;
    function setJackpotReserveBps(uint16 bps) external;
    function setMinCashStage(uint8 stage) external;
    function setBustRepPenalty(uint16 penalty) external;
}

contract SetupHeists is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(heists, "DEALERS_HEISTS");

        IHeistsAdmin h = IHeistsAdmin(heists);
        console.log("Heists address:", heists);

        vm.startBroadcast();

        // -------------------------------------------------------------------
        // 1) Difficulty configs (REQUIRED — empty by default).
        //    Stake sizes the $CASH/drug pot (~1.43x EV at cash-out stage 3). Gated by rep so
        //    players can't stake above their tier. Tuned so split-play (~4 heist runs/day) lands
        //    in the 5.1 daily band of the gate tier; all-in whale stays under the 10M/30d ceiling.
        //      D0 Street Score : gate Soldier (Hong Kong heist gate)
        //      D1 Warehouse Job: gate Capo     (Seoul)
        //      D2 Cartel Heist : gate Underboss (Dubai); serves Underboss -> Godfather
        // -------------------------------------------------------------------
        h.setDifficultyConfig(0, IHeistsAdmin.DifficultyConfig({repGate: 600, cashEntry: 600, active: true}));
        h.setDifficultyConfig(1, IHeistsAdmin.DifficultyConfig({repGate: 1500, cashEntry: 2500, active: true}));
        h.setDifficultyConfig(2, IHeistsAdmin.DifficultyConfig({repGate: 5500, cashEntry: 12000, active: true}));

        // -------------------------------------------------------------------
        // 2) Stage odds (= constructor defaults; re-asserted as source of truth).
        //    clean = advance/cash; setback = end with partial pot; bust = lose all (remainder).
        // -------------------------------------------------------------------
        h.setStageOdds(
            [uint8(72), 62, 52, 42, 32], // clean odds per stage
            [uint8(20), 28, 33, 38, 40], // setback band (bust = 100 - clean - setback)
            [uint16(5000), 4500, 4000, 3500, 3000] // setback keeps this fraction of the pot (bps)
        );

        // -------------------------------------------------------------------
        // 3) Pot multipliers + rep reward (= constructor defaults). Pot rolled in [min,max] bps of
        //    stake per stage. NOT trimmed: trimming below ~70% turns heists -EV unboosted; the
        //    faucet is controlled by stake size instead.
        // -------------------------------------------------------------------
        h.setStageRewards(
            [uint32(10000), 18000, 30000, 52000, 100000], // pot min bps
            [uint32(14000), 28000, 46000, 78000, 160000], // pot max bps
            [uint16(0), 2, 4, 7, 12] // rep granted on payout per stage
        );

        // -------------------------------------------------------------------
        // 4) Supply-run rarity mix per stage (= constructor defaults): [common%, uncommon%, rare%].
        // -------------------------------------------------------------------
        uint8[3][5] memory mix;
        mix[0] = [uint8(100), 0, 0];
        mix[1] = [uint8(70), 30, 0];
        mix[2] = [uint8(40), 60, 0];
        mix[3] = [uint8(10), 50, 40];
        mix[4] = [uint8(0), 0, 100];
        h.setSupplyMix(mix);

        // -------------------------------------------------------------------
        // 5) Jackpot table — COMPENSATION model (surfaced to players as a partial refund, not a
        //    jackpot). Flat 25% trigger per cleared stage -> fires in ~31% (cash@3) / ~33% (ride@5)
        //    of eligible runs, paying back 0.7-0.9x the add-on. The 40% reserve cut nets +~128e-6
        //    ETH/bet after the ~24e-6 Pyth fee, so it self-funds with margin (depletes only above
        //    ~40% trigger). Escrow per fire is just 0.9x the add-on (vs 20x before) — no top-stage
        //    skips, cheap to seed.
        // -------------------------------------------------------------------
        IHeistsAdmin.JackpotStage[5] memory jc;
        jc[0] = IHeistsAdmin.JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
        jc[1] = IHeistsAdmin.JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
        jc[2] = IHeistsAdmin.JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
        jc[3] = IHeistsAdmin.JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
        jc[4] = IHeistsAdmin.JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
        h.setJackpotConfig(jc);

        // -------------------------------------------------------------------
        // 6) Scalars (= constructor defaults; re-asserted). ETH add-on 0.001, 40% to reserve,
        //    earliest voluntary cash-out at stage 2, small bust rep penalty.
        // -------------------------------------------------------------------
        h.setEthAddOn(0.001 ether);
        h.setJackpotReserveBps(4000);
        h.setMinCashStage(2);
        h.setBustRepPenalty(3);

        vm.stopBroadcast();

        console.log("Heists configured:");
        console.log("  D0 Street Score : gate 600  stake 600");
        console.log("  D1 Warehouse Job: gate 1500 stake 2500");
        console.log("  D2 Cartel Heist : gate 5500 stake 12000");
        console.log("  Compensation 25%% trigger, 0.7-0.9x add-on (reserve cut 40%%, self-funding)");
    }
}

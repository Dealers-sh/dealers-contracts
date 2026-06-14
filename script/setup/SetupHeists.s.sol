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
 *   match the constructor defaults; the jackpot table is the TUNED escalating-hybrid preset).
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
        // Stakes raised (D1 2500 -> 4000, D2 12000 -> 25000) alongside the trimmed boost
        // cash multipliers (SetupBoosts) so heists stay the best cash-per-attempt at every
        // rank vs max-stake PVE hustles (economy_sim.py HT3).
        h.setDifficultyConfig(0, IHeistsAdmin.DifficultyConfig({repGate: 600, cashEntry: 600, active: true}));
        h.setDifficultyConfig(1, IHeistsAdmin.DifficultyConfig({repGate: 1500, cashEntry: 4000, active: true}));
        h.setDifficultyConfig(2, IHeistsAdmin.DifficultyConfig({repGate: 5500, cashEntry: 25000, active: true}));

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
        // 3) Pot multipliers + rep reward. Pot rolled in [min,max] bps of stake per stage
        //    (= constructor defaults). NOT trimmed: trimming below ~70% turns heists -EV
        //    unboosted; the faucet is controlled by stake size instead.
        //    Rep rewards are 3x the constructor defaults (economy_sim.py): lets heist-leaning
        //    players climb to Consigliere and unlock D1/D2 stakes, while PVE stays ~7x the
        //    rep/attempt — heists remain the cash engine, not the rep farm.
        // -------------------------------------------------------------------
        h.setStageRewards(
            [uint32(10000), 18000, 30000, 52000, 100000], // pot min bps
            [uint32(14000), 28000, 46000, 78000, 160000], // pot max bps
            [uint16(0), 6, 12, 21, 36] // rep granted on payout per stage
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
        // 5) Jackpot table — ESCALATING HYBRID model (60% reserve cut). Every cleared stage
        //    rolls with an INCREASING payout band: stages 1-2 are consolation-ish (can pay
        //    under the add-on), stage 3+ is ALWAYS a net win (min >= 1x), stage 5 reaches
        //    1.5-20x. One fire per run latches — an early fire ends the chase, so surviving
        //    deep unfired is what earns the big band. Triggers are front-loaded (hot stage 1)
        //    so shallow cash@3 play consumes its reserve cut too, keeping the reserve LEAN
        //    instead of accumulating off conservative players.
        //    Sim-validated (heist_tuning.py [8] + test_staked_jackpot Monte Carlo, exact match):
        //    ~41% of staked runs win ETH; player return 48% (cash@3) to 56% (ride@5) of the
        //    add-on; ~1-in-350 ride@5 runs rolls >=10x. Reserve nets +~28e-6 ETH/bet after Pyth
        //    fees at MAX exposure (all riders), +~6 ETH per 100k games on a realistic strategy
        //    mix. Escrow per fire = stage ceiling (0.02 ETH at stage 5); an underfunded reserve
        //    SKIPS the fire but keeps the run eligible, so seed the reserve with >= ~0.05 ETH
        //    (fundReserve) before launch.
        // -------------------------------------------------------------------
        IHeistsAdmin.JackpotStage[5] memory jc;
        jc[0] = IHeistsAdmin.JackpotStage({triggerPct: 40, minMultBps: 7000, maxMultBps: 10000});
        jc[1] = IHeistsAdmin.JackpotStage({triggerPct: 34, minMultBps: 9000, maxMultBps: 23000});
        jc[2] = IHeistsAdmin.JackpotStage({triggerPct: 30, minMultBps: 10000, maxMultBps: 55000});
        jc[3] = IHeistsAdmin.JackpotStage({triggerPct: 32, minMultBps: 12000, maxMultBps: 120000});
        jc[4] = IHeistsAdmin.JackpotStage({triggerPct: 40, minMultBps: 15000, maxMultBps: 200000});
        h.setJackpotConfig(jc);

        // -------------------------------------------------------------------
        // 6) Scalars. ETH add-on 0.001; 60% to reserve (up from the 40% constructor default —
        //    funds the hybrid jackpot table above; bank/dev keep the remaining 32%/8%);
        //    earliest voluntary cash-out at stage 2, small bust rep penalty.
        // -------------------------------------------------------------------
        h.setEthAddOn(0.001 ether);
        h.setJackpotReserveBps(6000);
        h.setMinCashStage(2);
        h.setBustRepPenalty(3);

        vm.stopBroadcast();

        console.log("Heists configured:");
        console.log("  D0 Street Score : gate 600  stake 600");
        console.log("  D1 Warehouse Job: gate 1500 stake 4000");
        console.log("  D2 Cartel Heist : gate 5500 stake 25000");
        console.log("  Jackpot triggers 40/34/30/32/40%%, bands 0.7-1x up to 1.5-20x (reserve cut 60%%)");
    }
}

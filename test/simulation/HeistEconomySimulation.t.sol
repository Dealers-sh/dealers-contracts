// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

/**
 * @title HeistEconomySimulation - Monte-Carlo model of the heist module economy
 *
 * @dev Standalone economic model for DealersHeists (supply/cash runs + ETH jackpot add-on).
 *      It mirrors the on-chain stage math from src/core/DealersHeists.sol and the deployed
 *      economy config (the setup scripts are the source of truth, NOT the older
 *      ReputationSimulation.t.sol whose tier/boost tables predate the convex-ladder rebalance):
 *        - tiers       <- script/setup/SetupTiers.s.sol   (convex 2.2x ladder)
 *        - boosts      <- script/setup/SetupBoosts.s.sol   (Kingpin +6/1.25x, Godfather 2.25x/1.35x)
 *        - drugs/areas <- script/setup/SetupDrugs.s.sol + SetupAreas.s.sol
 *        - heist math  <- DealersHeists constructor defaults
 *
 *      Three tests:
 *        1. test_unstaked_ev          - $CASH/drug pot EV by difficulty x cash-out strategy x boost
 *        2. test_staked_jackpot       - ETH jackpot EV, house edge, reserve solvency trajectory
 *        3. test_multiday_growth      - cash / stash / rep / ETH growth by rep tier x boost over 30 days
 */
contract HeistEconomySimulation is Test {
    // =============================================================
    //                       HEIST MATH (from DealersHeists)
    // =============================================================

    uint16 constant BPS = 10000;
    uint8 constant STAGES = 5;

    uint8[5] stageWinOdds = [72, 62, 52, 42, 32];
    uint8[5] stageSetbackOdds = [20, 28, 33, 38, 40];
    uint16[5] stageSetbackKeepBps = [5000, 4500, 4000, 3500, 3000];
    uint32[5] stagePotMinBps = [10000, 18000, 30000, 52000, 100000];
    uint32[5] stagePotMaxBps = [14000, 28000, 46000, 78000, 160000];
    uint16[5] stageRepReward = [0, 2, 4, 7, 12];
    uint8[3][5] supplyMix = [
        [uint8(100), 0, 0],
        [uint8(70), 30, 0],
        [uint8(40), 60, 0],
        [uint8(10), 50, 40],
        [uint8(0), 0, 100]
    ];

    uint16[5] jackpotTriggerPct = [1, 2, 3, 4, 5];
    uint32[5] jackpotMinMultBps = [12000, 15000, 20000, 30000, 50000];
    uint32[5] jackpotMaxMultBps = [30000, 45000, 70000, 120000, 200000];

    uint256 constant ETH_ADD_ON = 0.001 ether;
    uint16 constant JACKPOT_RESERVE_BPS = 4000;
    uint8 constant MIN_CASH_STAGE = 2;
    uint16 constant BUST_REP_PENALTY = 3;

    // Pyth entropy fee per jackpot request (paid out of reserve). Estimate; tune if real fee known.
    uint256 constant ENTROPY_FEE = 0;

    // =============================================================
    //                    PROPOSED DIFFICULTY CONFIGS
    // =============================================================

    struct Difficulty {
        uint256 repGate;
        uint96 cashEntry;
        string name;
    }

    Difficulty[3] difficulties;

    // =============================================================
    //                    ECONOMY CONFIG (setup scripts)
    // =============================================================

    struct Tier { uint256 minRep; int256 win; int256 tie; int256 loss; int256 cap; string name; }
    Tier[10] tiers;

    struct Boost { uint16 drugMult; uint16 cashMult; uint16 repMult; uint8 extraAttempts; uint256 priceWei; uint8 durationDays; string name; }
    Boost[5] boostCfg; // 0=none,1=grinder,2=hustler,3=kingpin,4=godfather

    uint256[12] drugBaseValue;
    uint8[12] drugRarity; // 0=common,1=uncommon,2=rare
    uint256[3][8] areaDrugIds; // areaId 1..7 -> 3 drug ids
    uint256[3][8] areaDrugSell; // areaId 1..7 -> 3 sell prices (aligned with areaDrugIds)

    uint8 constant BASE_MAX_ATTEMPTS = 5;
    uint8 constant MAX_HEAT = 5;

    uint256 rng;

    /// @dev Tuning knob: scales every stage pot multiplier (10000 = 1.0x = ship defaults).
    ///      Lets a single test sweep "what if pots were trimmed N%" without rewriting tables.
    uint256 potScaleBps = 10000;

    /// @dev Tuning knob: scales every jackpot trigger probability (10000 = 1.0x = ship defaults).
    uint256 jackpotTriggerScaleBps = 10000;

    function setUp() public {
        // Tuned config (matches script/setup/SetupHeists.s.sol + heist_tuning.py)
        difficulties[0] = Difficulty({repGate: 600, cashEntry: 600, name: "Street Score   (D0)"});
        difficulties[1] = Difficulty({repGate: 1500, cashEntry: 2500, name: "Warehouse Job  (D1)"});
        difficulties[2] = Difficulty({repGate: 5500, cashEntry: 12000, name: "Cartel Heist   (D2)"});

        tiers[0] = Tier(0,     60, 25, -2, 35, "Outsider");
        tiers[1] = Tier(100,   35, 18, -3, 25, "Associate");
        tiers[2] = Tier(250,   20, 10, -3, 22, "Dealer");
        tiers[3] = Tier(600,   12, 5,  -4, 22, "Soldier");
        tiers[4] = Tier(1500,  9,  4,  -5, 24, "Capo");
        tiers[5] = Tier(3000,  7,  3,  -5, 26, "Consigliere");
        tiers[6] = Tier(5500,  6,  2,  -6, 28, "Underboss");
        tiers[7] = Tier(10000, 5,  2,  -6, 30, "Don");
        tiers[8] = Tier(22000, 4,  1,  -7, 32, "Godfather");
        tiers[9] = Tier(50000, 2,  1,  -8, 4,  "Legend");

        boostCfg[0] = Boost(100, 100, 100, 0, 0,            0,  "No Boost ");
        boostCfg[1] = Boost(125, 125, 110, 2, 0.0025 ether, 3,  "Grinder  ");
        boostCfg[2] = Boost(150, 150, 115, 3, 0.005 ether,  7,  "Hustler  ");
        boostCfg[3] = Boost(175, 175, 125, 6, 0.01 ether,   14, "Kingpin  ");
        boostCfg[4] = Boost(225, 225, 135, 7, 0.023 ether,  30, "Godfather");

        // Base cash values (SetupDrugs)
        drugBaseValue[1] = 75;   drugRarity[1] = 0; // Goods
        drugBaseValue[2] = 500;  drugRarity[2] = 1; // Contraband
        drugBaseValue[3] = 2500; drugRarity[3] = 2; // Jewels
        drugBaseValue[4] = 1;    drugRarity[4] = 0; // Weed
        drugBaseValue[5] = 10;   drugRarity[5] = 1; // XTC
        drugBaseValue[6] = 100;  drugRarity[6] = 2; // Cocaine
        drugBaseValue[7] = 12;   drugRarity[7] = 1; // Shrooms
        drugBaseValue[8] = 150;  drugRarity[8] = 2; // Heroin
        drugBaseValue[9] = 18;   drugRarity[9] = 0; // Opioids
        drugBaseValue[10] = 25;  drugRarity[10] = 1; // Meth
        drugBaseValue[11] = 200; drugRarity[11] = 2; // Fentanyl

        // Area drug ids (SetupAreas)
        areaDrugIds[1] = [uint256(4), 5, 6];   // Manhattan: Weed, XTC, Cocaine
        areaDrugIds[2] = [uint256(4), 7, 8];   // Amsterdam: Weed, Shrooms, Heroin
        areaDrugIds[3] = [uint256(4), 6, 8];   // Colombia: Weed, Cocaine, Heroin
        areaDrugIds[4] = [uint256(9), 10, 8];  // Hong Kong: Opioids, Meth, Heroin
        areaDrugIds[5] = [uint256(9), 10, 11]; // Seoul: Opioids, Meth, Fentanyl
        areaDrugIds[6] = [uint256(9), 10, 11]; // Tokyo: Opioids, Meth, Fentanyl
        areaDrugIds[7] = [uint256(5), 6, 8];   // Dubai: XTC, Cocaine, Heroin

        // Area sell prices (SetupAreas), aligned with areaDrugIds
        areaDrugSell[1] = [uint256(1), 10, 100];   // Manhattan
        areaDrugSell[2] = [uint256(2), 12, 150];   // Amsterdam
        areaDrugSell[3] = [uint256(1), 50, 75];    // Colombia
        areaDrugSell[4] = [uint256(18), 25, 160];  // Hong Kong: Opioids18, Meth25, Heroin160
        areaDrugSell[5] = [uint256(7), 12, 75];    // Seoul: Opioids7, Meth12, Fentanyl75
        areaDrugSell[6] = [uint256(20), 26, 160];  // Tokyo: Opioids20, Meth26, Fentanyl160
        areaDrugSell[7] = [uint256(20), 200, 240]; // Dubai: XTC20, Cocaine200, Heroin240

        rng = 0xDEADBEEF;
    }

    /// @dev Memory-free PRNG: hashes on scratch space (0x00) so the free-memory pointer never
    ///      grows. Critical for the multi-million-call Monte-Carlo loops (abi.encodePacked would
    ///      leak memory each call and trigger MemoryOOG).
    function _rand() private returns (uint256 result) {
        uint256 seed = rng;
        assembly {
            mstore(0x00, seed)
            result := keccak256(0x00, 0x20)
        }
        rng = result;
    }

    // =============================================================
    //                     SINGLE HEIST RUN
    // =============================================================

    /// @dev Shared stage engine. targetStage in [2..5]: cash out on the first clean win at >= target.
    ///      Mirrors DealersHeists.resolveStage / _setback / _bust. Returns the gross pot (pre-boost,
    ///      keep-adjusted on setback), the ending stage, the outcome (0 clean, 1 setback, 2 bust),
    ///      and any ETH jackpot won. Primitives only — zero memory per call for the hot loops.
    function _playRunCore(uint96 stake, uint8 targetStage, bool ethJackpot)
        private
        returns (uint256 grossPot, uint8 endStage, uint8 outcome, uint256 ethWon)
    {
        for (uint8 stage = 1; stage <= STAGES; stage++) {
            uint256 rand = _rand();
            uint256 roll = rand % 100;
            uint256 cleanOdds = stageWinOdds[stage - 1];
            uint256 stagePot = (uint256(stake) * _rollMult(stage, rand)) / BPS;

            if (roll < cleanOdds) {
                if (ethJackpot &&
                    (rand >> 16) % 10000 < (uint256(jackpotTriggerPct[stage - 1]) * jackpotTriggerScaleBps) / 100) {
                    ethWon += _rollJackpotValue(stage);
                }
                if (stage >= STAGES || stage >= targetStage) {
                    return (stagePot, stage, 0, ethWon);
                }
            } else if (roll < cleanOdds + stageSetbackOdds[stage - 1]) {
                return ((stagePot * stageSetbackKeepBps[stage - 1]) / BPS, stage, 1, ethWon);
            } else {
                return (0, stage, 2, ethWon);
            }
        }
    }

    /// @dev CASH-family run: pot paid as $CASH, boost cashMult applied.
    function _playRun(uint96 stake, uint8 targetStage, uint16 cashMult, bool ethJackpot)
        private
        returns (uint256 payout, int256 repDelta, bool busted, uint256 ethWon)
    {
        uint8 endStage;
        uint8 outcome;
        uint256 grossPot;
        (grossPot, endStage, outcome, ethWon) = _playRunCore(stake, targetStage, ethJackpot);
        payout = (grossPot * cashMult) / 100;
        if (outcome == 0) repDelta = int256(uint256(stageRepReward[endStage - 1]));
        else if (outcome == 2) { repDelta = -int256(uint256(BUST_REP_PENALTY)); busted = true; }
    }

    /// @dev SUPPLY-family run: pot converted to area drugs by the per-stage rarity mix (boost drugMult).
    ///      Returns stash value gained (sum units*baseValue) and residual $CASH (dust + missing rarities).
    function _playSupplyRun(uint96 stake, uint8 targetStage, uint16 drugMult, uint8 area, bool ethJackpot)
        private
        returns (uint256 stashAdded, uint256 cashResidual, int256 repDelta, bool busted, uint256 ethWon)
    {
        uint8 endStage;
        uint8 outcome;
        uint256 grossPot;
        (grossPot, endStage, outcome, ethWon) = _playRunCore(stake, targetStage, ethJackpot);
        if (outcome == 2) { repDelta = -int256(uint256(BUST_REP_PENALTY)); busted = true; return (0, 0, repDelta, true, ethWon); }
        (stashAdded, cashResidual) = _allocateSupply((grossPot * drugMult) / 100, endStage, area);
        if (outcome == 0) repDelta = int256(uint256(stageRepReward[endStage - 1]));
    }

    /// @dev Mirrors DealersHeists._allocateDrugs: split pot by stage rarity mix, convert each bucket
    ///      to whole drug units at base value from the area's drugs of that rarity. Missing rarity or
    ///      dust settles as $CASH.
    function _allocateSupply(uint256 amt, uint8 stage, uint8 area)
        private
        view
        returns (uint256 stashAdded, uint256 residualCash)
    {
        uint8[3] memory mix = supplyMix[stage - 1];
        for (uint256 r = 0; r < 3; r++) {
            uint8 pct = mix[r];
            if (pct == 0) continue;
            uint256 bucket = (amt * pct) / 100;
            if (bucket == 0) continue;
            uint256 baseVal = _areaDrugBaseOfRarity(area, uint8(r));
            if (baseVal == 0) { residualCash += bucket; continue; }
            uint256 units = bucket / baseVal;
            if (units == 0) { residualCash += bucket; continue; }
            stashAdded += units * baseVal;
            residualCash += bucket - units * baseVal;
        }
    }

    function _areaDrugBaseOfRarity(uint8 area, uint8 rarity) private view returns (uint256) {
        for (uint256 i = 0; i < 3; i++) {
            uint256 id = areaDrugIds[area][i];
            if (id != 0 && drugRarity[id] == rarity) return drugBaseValue[id];
        }
        return 0;
    }

    function _rollMult(uint8 stage, uint256 rand) private view returns (uint256) {
        uint256 lo = (uint256(stagePotMinBps[stage - 1]) * potScaleBps) / 10000;
        uint256 hi = (uint256(stagePotMaxBps[stage - 1]) * potScaleBps) / 10000;
        if (hi <= lo) return lo;
        return lo + ((rand >> 32) % (hi - lo + 1));
    }

    function _rollJackpotValue(uint8 stage) private returns (uint256) {
        uint256 range = uint256(jackpotMaxMultBps[stage - 1]) - uint256(jackpotMinMultBps[stage - 1]);
        uint256 mult = uint256(jackpotMinMultBps[stage - 1]) + (range == 0 ? 0 : _rand() % (range + 1));
        return (ETH_ADD_ON * mult) / BPS;
    }

    // =============================================================
    //              TEST 1 - UNSTAKED EV (cash/drug pot)
    // =============================================================

    function test_unstaked_ev() public {
        uint256 TRIALS = 20000;
        console.log("=================================================================");
        console.log("  TEST 1 - UNSTAKED HEIST EV  (pot multiple of $CASH stake)");
        console.log("  %d trials/scenario. Net = payout - stake.", TRIALS);
        console.log("=================================================================");

        uint8[3] memory boostIdx = [0, 3, 4]; // none, Kingpin, Godfather

        for (uint256 di = 0; di < 3; di++) {
            Difficulty memory d = difficulties[di];
            console.log("");
            console.log("--- %s  stake=%d $CASH ---", d.name, d.cashEntry);
            for (uint256 bi = 0; bi < 3; bi++) {
                uint16 cashMult = boostCfg[boostIdx[bi]].cashMult;
                console.log("  Boost: %s (cashMult %d%%)", boostCfg[boostIdx[bi]].name, cashMult);
                for (uint8 t = 2; t <= 5; t++) {
                    (uint256 avgPayout, uint256 bustPct) = _evRun(d.cashEntry, t, cashMult, TRIALS);
                    console.log("    target stage %d (5=ride to end):", t);
                    if (avgPayout >= d.cashEntry) {
                        console.log("      payout=%d  net=+%d  bust=%d%%", avgPayout, avgPayout - d.cashEntry, bustPct);
                    } else {
                        console.log("      payout=%d  net=-%d  bust=%d%%", avgPayout, d.cashEntry - avgPayout, bustPct);
                    }
                }
            }
        }
    }

    function _evRun(uint96 stake, uint8 target, uint16 cashMult, uint256 trials)
        private
        returns (uint256 avgPayout, uint256 bustPct)
    {
        uint256 sumPayout;
        uint256 busts;
        for (uint256 i = 0; i < trials; i++) {
            (uint256 payout,, bool busted,) = _playRun(stake, target, cashMult, false);
            sumPayout += payout;
            if (busted) busts++;
        }
        avgPayout = sumPayout / trials;
        bustPct = (busts * 100) / trials;
    }

    // =============================================================
    //              TEST 2 - STAKED JACKPOT ECONOMY (ETH)
    // =============================================================

    function test_staked_jackpot() public {
        uint256 TRIALS = 100000;
        console.log("=================================================================");
        console.log("  TEST 2 - STAKED JACKPOT ECONOMY  (ETH add-on = 0.001)");
        console.log("  %d add-on bets. Values in wei (1e15 = 0.001 ETH).", TRIALS);
        console.log("=================================================================");

        // reserve receives 40% of each add-on; jackpots paid from reserve
        uint256 reserve;
        uint256 totalWon;
        uint256 totalReserveIn;
        uint256 skips;
        uint256 fires;

        uint8[2] memory targets = [3, 5];
        for (uint256 ti = 0; ti < 2; ti++) {
            uint8 target = targets[ti];
            reserve = 0; totalWon = 0; totalReserveIn = 0; skips = 0; fires = 0;

            for (uint256 i = 0; i < TRIALS; i++) {
                uint256 toReserve = (ETH_ADD_ON * JACKPOT_RESERVE_BPS) / BPS;
                reserve += toReserve;
                totalReserveIn += toReserve;
                (uint256 won, uint256 fired, uint256 skipped) = _playJackpotBet(target, reserve);
                reserve = reserve - won - (fired * ENTROPY_FEE);
                totalWon += won;
                fires += fired;
                skips += skipped;
            }

            console.log("");
            console.log("  Strategy: %s", target == 5 ? "ride to stage 5 (max exposure)" : "cash out at stage 3");
            console.log("    avg ETH won / bet (wei) : %d", totalWon / TRIALS);
            console.log("    reserve in / bet (wei)  : %d", totalReserveIn / TRIALS);
            console.log("    net reserve accrual/bet : %d", (totalReserveIn - totalWon) / TRIALS);
            console.log("    player return on add-on : %d%% (of 0.001 ETH)", (totalWon * 100) / (TRIALS * ETH_ADD_ON));
            console.log("    final reserve (wei)     : %d", reserve);
            console.log("    jackpots fired / skipped: %d / %d", fires, skips);
        }

        console.log("");
        console.log("  Per-add-on split: 40%% reserve / 48%% bank vault / 12%% dev");
        console.log("  (handler bankFeePercent 8000 on the 60%% routed to it)");
    }

    function _playJackpotBet(uint8 target, uint256 reserve)
        private
        returns (uint256 won, uint256 fired, uint256 skipped)
    {
        for (uint8 stage = 1; stage <= STAGES; stage++) {
            uint256 rand = _rand();
            uint256 roll = rand % 100;
            uint256 cleanOdds = stageWinOdds[stage - 1];

            if (roll < cleanOdds) {
                if ((rand >> 16) % 10000 < (uint256(jackpotTriggerPct[stage - 1]) * jackpotTriggerScaleBps) / 100) {
                    uint256 maxVal = (ETH_ADD_ON * jackpotMaxMultBps[stage - 1]) / BPS;
                    if (reserve >= maxVal + ENTROPY_FEE) {
                        won += _rollJackpotValue(stage);
                        reserve -= (maxVal + ENTROPY_FEE); // escrow; unused returns but irrelevant to player EV
                        fired++;
                    } else {
                        skipped++;
                    }
                }
                if (stage >= STAGES || stage >= target) return (won, fired, skipped);
            } else {
                return (won, fired, skipped); // setback or bust ends the run
            }
        }
    }

    // =============================================================
    //          TEST 3 - MULTI-DAY GROWTH (cash / stash / rep / ETH)
    // =============================================================

    struct SimDealer {
        uint256 rep;
        uint256 cash;
        uint256 stashValue; // sum(units * baseValue), drug stash
        uint8 area;
        uint8 heat;
        uint256 jailCount;
        uint256 ethSpent;
        uint256 ethWon;
        uint256 runs;
        uint256 busts;
    }

    function test_multiday_growth() public {
        uint256 DAYS = 30;
        console.log("=================================================================");
        console.log("  TEST 3 - 30-DAY HEIST GROWTH  (CASH runs, cash@3, ETH add-on ON)");
        console.log("  All daily attempts spent on heists. Difficulty = highest unlocked.");
        console.log("=================================================================");

        // (startRep, area, startCash) representative dealers — startCash = §5.1 liquid-band midpoint
        uint256[6] memory startReps = [uint256(600), 1500, 3000, 5500, 10000, 22000];
        uint8[6] memory areas = [4, 5, 6, 7, 7, 7];
        uint256[6] memory startCash = [uint256(10000), 50000, 150000, 400000, 800000, 2000000];

        uint8[2] memory boostIdx = [3, 4]; // Kingpin, Godfather (the realistic heist grinders)

        for (uint256 bi = 0; bi < 2; bi++) {
            console.log("");
            console.log("############## BOOST: %s ##############", boostCfg[boostIdx[bi]].name);
            for (uint256 si = 0; si < 6; si++) {
                _runMultiday(startReps[si], areas[si], startCash[si], boostIdx[bi], DAYS);
            }
        }
    }

    function _pickDifficulty(uint256 rep) private view returns (uint256) {
        if (rep >= difficulties[2].repGate) return 2;
        if (rep >= difficulties[1].repGate) return 1;
        return 0; // assumes rep >= 600 (D0 gate) for all test dealers
    }

    function _runMultiday(uint256 startRep, uint8 area, uint256 startCash, uint8 boostIdx, uint256 numDays) private {
        SimDealer memory d;
        d.rep = startRep;
        d.cash = startCash;
        d.area = area;
        uint8 startTier = _tierIdx(startRep);

        Boost memory b = boostCfg[boostIdx];
        uint256 attemptsPerDay = uint256(BASE_MAX_ATTEMPTS) + b.extraAttempts;

        // boost cost amortized over its duration, charged across the sim window
        uint256 boostCycles = (numDays + b.durationDays - 1) / b.durationDays;
        d.ethSpent += boostCycles * b.priceWei;

        for (uint256 day = 0; day < numDays; day++) {
            uint8 variation = _dayVariation();
            uint256 attempts = variation == 0 ? 0 : (variation == 1 ? attemptsPerDay / 2 : attemptsPerDay);

            for (uint256 a = 0; a < attempts; a++) {
                uint256 di = _pickDifficulty(d.rep);
                uint96 stake = difficulties[di].cashEntry;
                if (d.cash < stake) { di = 0; stake = difficulties[0].cashEntry; }
                if (d.cash < stake) break; // broke

                d.cash -= stake;
                d.ethSpent += ETH_ADD_ON; // jackpot add-on on every run
                d.runs++;

                (uint256 payout, int256 repDelta, bool busted, uint256 ethWon) = _playRun(stake, 3, b.cashMult, true);
                d.cash += payout;
                d.ethWon += ethWon;
                if (busted) d.busts++;

                if (repDelta > 0) {
                    d.rep += (uint256(repDelta) * b.repMult) / 100;
                } else if (repDelta < 0) {
                    uint256 loss = uint256(-repDelta);
                    d.rep = loss >= d.rep ? 0 : d.rep - loss;
                }

                // heat + jail (heat * 0.5%/run; jail = -10% rep cap 50, reset heat)
                if (d.heat < MAX_HEAT) d.heat++;
                if (_rand() % 1000 < uint256(d.heat) * 5) {
                    uint256 pen = (d.rep * 10) / 100;
                    if (pen > 50) pen = 50;
                    d.rep -= pen > d.rep ? d.rep : pen;
                    d.heat = 0;
                    d.jailCount++;
                    d.ethSpent += 0.002 ether; // bail
                }
            }
            if (d.heat > 0) d.heat--; // mild overnight decay
        }

        uint8 endTier = _tierIdx(d.rep);
        console.log("  [%s] start, area %d:", tiers[startTier].name, area);
        console.log("    rep %d -> %d (%s)", startRep, d.rep, tiers[endTier].name);
        console.log("    cash: %d   runs: %d  busts: %d", d.cash, d.runs, d.busts);
        console.log("    ETH spent: %d wei   ETH won: %d wei", d.ethSpent, d.ethWon);
        int256 ethNet = int256(d.ethWon) - int256(d.ethSpent);
        if (ethNet >= 0) console.log("    ETH net: +%d wei", uint256(ethNet));
        else console.log("    ETH net: -%d wei", uint256(-ethNet));
    }

    function _dayVariation() private returns (uint8) {
        uint256 roll = _rand() % 100;
        if (roll < 70) return 2;
        if (roll < 90) return 1;
        return 0;
    }

    function _tierIdx(uint256 rep) private view returns (uint8) {
        for (uint8 i = 9; ; i--) {
            if (rep >= tiers[i].minRep) return i;
            if (i == 0) break;
        }
        return 0;
    }

    // =============================================================
    //         TUNING SWEEP A - CASH FAUCET vs ECONOMY_DESIGN 5.1
    // =============================================================

    function test_tuning_sweep_cash() public {
        console.log("=================================================================");
        console.log("  TUNING SWEEP - CASH FAUCET vs ECONOMY_DESIGN 5.1");
        console.log("  Godfather-tier dealer (start 2M), Godfather boost (cashMult 225%)");
        console.log("  5.1 Godfather: 1-5M typical / 10M whale; daily +100k-300k");
        console.log("  All-in = ~12 heist runs/day. Split = 5 runs/day (rest PVE/PVP).");
        console.log("=================================================================");

        uint16 gMult = boostCfg[4].cashMult; // 225
        uint96 stakeD2 = difficulties[2].cashEntry; // 40000

        console.log("");
        console.log("  -- Lever 1: trim pot multipliers (stake fixed 40000) --");
        uint256[3] memory scales = [uint256(10000), 8000, 6000];
        for (uint256 i = 0; i < 3; i++) {
            potScaleBps = scales[i];
            rng = 0x2222; (uint256 allIn, uint256 runsA) = _proj30dCash(2_000_000, stakeD2, gMult, 12);
            rng = 0x3333; (uint256 split,) = _proj30dCash(2_000_000, stakeD2, gMult, 5);
            console.log("    potScale %d%%:", scales[i] / 100);
            console.log("      net/run=%d  30d all-in(12/d)=%d", runsA == 0 ? 0 : (allIn - 2_000_000) / runsA, allIn);
            console.log("      30d split(5/d)=%d", split);
        }
        potScaleBps = 10000;

        console.log("");
        console.log("  -- Lever 2: lower stake (pot 100%) --");
        uint96[3] memory stakes = [uint96(40000), 20000, 10000];
        for (uint256 i = 0; i < 3; i++) {
            rng = 0x4444; (uint256 allIn, uint256 runsA) = _proj30dCash(2_000_000, stakes[i], gMult, 12);
            rng = 0x5555; (uint256 split,) = _proj30dCash(2_000_000, stakes[i], gMult, 5);
            console.log("    stake %d:", stakes[i]);
            console.log("      net/run=%d  30d all-in(12/d)=%d", runsA == 0 ? 0 : (allIn - 2_000_000) / runsA, allIn);
            console.log("      30d split(5/d)=%d", split);
        }
    }

    function _proj30dCash(uint256 startCash, uint96 stake, uint16 cashMult, uint256 runsPerDay)
        private
        returns (uint256 cash, uint256 runs)
    {
        cash = startCash;
        for (uint256 day = 0; day < 30; day++) {
            uint8 v = _dayVariation();
            uint256 att = v == 0 ? 0 : (v == 1 ? runsPerDay / 2 : runsPerDay);
            for (uint256 a = 0; a < att; a++) {
                if (cash < stake) break;
                cash -= stake;
                runs++;
                (uint256 payout,,,) = _playRun(stake, 3, cashMult, false);
                cash += payout;
            }
        }
    }

    // =============================================================
    //       TUNING SWEEP B - GENEROUS JACKPOT (solvency-bounded)
    // =============================================================

    function test_tuning_jackpot_generous() public {
        console.log("=================================================================");
        console.log("  TUNING - JACKPOT GENEROSITY vs RESERVE SOLVENCY");
        console.log("  Player ETH return must stay BELOW the reserve cut %% to self-fund.");
        console.log("  (return is reported for ride@5 = max exposure, and cash@3)");
        console.log("=================================================================");

        _reportJackpot(4000, 10000, "current : trigger x1.0, reserve cut 40%");
        _reportJackpot(4000, 20000, "option A: trigger x2.0, reserve cut 40%");
        _reportJackpot(4000, 25000, "option B: trigger x2.5, reserve cut 40%");
        _reportJackpot(6000, 35000, "option C: trigger x3.5, reserve cut 60%");
    }

    function _reportJackpot(uint256 reserveBps, uint256 trigScale, string memory label) private {
        jackpotTriggerScaleBps = trigScale;
        uint256 TRIALS = 80000;

        rng = 0x55AA;
        (uint256 won5, uint256 in5, uint256 fin5, uint256 fires5, uint256 skips5) = _runJackpotSim(5, reserveBps, TRIALS);
        rng = 0x55AA;
        (uint256 won3,,,,) = _runJackpotSim(3, reserveBps, TRIALS);

        console.log("");
        console.log("  %s", label);
        console.log("    return ride@5: %d%%   cash@3: %d%%",
            (won5 * 100) / (TRIALS * ETH_ADD_ON), (won3 * 100) / (TRIALS * ETH_ADD_ON));
        if (in5 >= won5) {
            console.log("    reserve SOLVENT: +%d wei/bet  (final %d after seed 1e18)", (in5 - won5) / TRIALS, fin5);
        } else {
            console.log("    reserve DEPLETING: -%d wei/bet  (final %d)", (won5 - in5) / TRIALS, fin5);
        }
        console.log("    ride@5 fired %d / skipped %d", fires5, skips5);
        jackpotTriggerScaleBps = 10000;
    }

    function _runJackpotSim(uint8 target, uint256 reserveBps, uint256 trials)
        private
        returns (uint256 totalWon, uint256 totalIn, uint256 reserve, uint256 fires, uint256 skips)
    {
        reserve = 1 ether; // seed so even big jackpots can pay; drift vs seed shows solvency
        for (uint256 i = 0; i < trials; i++) {
            uint256 toR = (ETH_ADD_ON * reserveBps) / BPS;
            reserve += toR;
            totalIn += toR;
            (uint256 won, uint256 fired, uint256 skipped) = _playJackpotBet(target, reserve);
            reserve = reserve - won - (fired * ENTROPY_FEE);
            totalWon += won;
            fires += fired;
            skips += skipped;
        }
    }

    // =============================================================
    //        SUPPLY-RUN / STASH GROWTH (drugs + stash-rep)
    // =============================================================

    function test_supply_stash_growth() public {
        console.log("=================================================================");
        console.log("  SUPPLY RUNS - 30d STASH GROWTH (Kingpin boost, drugMult 175%)");
        console.log("  Pot paid in area drugs (base value). Realizable = area sell price.");
        console.log("=================================================================");

        uint256[4] memory reps = [uint256(600), 1500, 3000, 5500];
        uint8[4] memory areas = [4, 5, 6, 7];
        string[4] memory areaNames = ["Hong Kong", "Seoul    ", "Tokyo    ", "Dubai    "];
        uint16 dMult = boostCfg[3].drugMult; // 175
        uint256 attemptsPerDay = uint256(BASE_MAX_ATTEMPTS) + boostCfg[3].extraAttempts; // 11

        for (uint256 i = 0; i < 4; i++) {
            uint8 area = areas[i];
            uint96 stake = difficulties[_pickDifficulty(reps[i])].cashEntry;

            rng = 0x9000 + i;
            uint256[12] memory units;
            uint256 stakeSpent;
            uint256 residual;
            uint256 runs;
            uint256 busts;

            for (uint256 day = 0; day < 30; day++) {
                uint8 v = _dayVariation();
                uint256 att = v == 0 ? 0 : (v == 1 ? attemptsPerDay / 2 : attemptsPerDay);
                for (uint256 a = 0; a < att; a++) {
                    stakeSpent += stake;
                    runs++;
                    (uint256 gross, uint8 es, uint8 oc,) = _playRunCore(stake, 3, false);
                    if (oc == 2) { busts++; continue; }
                    residual += _allocateSupplyUnits(units, (gross * dMult) / 100, es, area);
                }
            }

            uint256 baseVal = _stashBaseValue(units);
            uint256 sellVal = _stashSellValue(units, area);

            console.log("");
            console.log("  [%s] area %s, stake %d:", tiers[_tierIdx(reps[i])].name, areaNames[i], stake);
            console.log("    runs %d (busts %d)  $CASH staked %d", runs, busts, stakeSpent);
            console.log("    stash base value %d  + residual cash %d", baseVal, residual);
            console.log("    stash realizable (area sell) %d", sellVal);
            console.log("    stash-rep bonus (5.1 formula) %d", _stashBonus(baseVal));
        }
        console.log("");
        console.log("  Note: stash-rep uses base value; selling realizes the 'realizable' figure.");
        console.log("  Farm areas (Seoul) sell rares far below base -> stash overstates cash.");
    }

    function _allocateSupplyUnits(uint256[12] memory units, uint256 amt, uint8 stage, uint8 area)
        private
        view
        returns (uint256 residualCash)
    {
        uint8[3] memory mix = supplyMix[stage - 1];
        for (uint256 r = 0; r < 3; r++) {
            uint8 pct = mix[r];
            if (pct == 0) continue;
            uint256 bucket = (amt * pct) / 100;
            if (bucket == 0) continue;
            uint256 id = _areaDrugIdOfRarity(area, uint8(r));
            if (id == 0) { residualCash += bucket; continue; }
            uint256 u = bucket / drugBaseValue[id];
            if (u == 0) { residualCash += bucket; continue; }
            units[id] += u;
            residualCash += bucket - u * drugBaseValue[id];
        }
    }

    function _areaDrugIdOfRarity(uint8 area, uint8 rarity) private view returns (uint256) {
        for (uint256 i = 0; i < 3; i++) {
            uint256 id = areaDrugIds[area][i];
            if (id != 0 && drugRarity[id] == rarity) return id;
        }
        return 0;
    }

    function _stashBaseValue(uint256[12] memory units) private view returns (uint256 v) {
        for (uint256 id = 1; id <= 11; id++) v += units[id] * drugBaseValue[id];
    }

    function _stashSellValue(uint256[12] memory units, uint8 area) private view returns (uint256 v) {
        for (uint256 id = 1; id <= 11; id++) {
            if (units[id] == 0) continue;
            uint256 sell = _areaSellPrice(area, id);
            v += units[id] * (sell == 0 ? drugBaseValue[id] : sell);
        }
    }

    function _areaSellPrice(uint8 area, uint256 drugId) private view returns (uint256) {
        for (uint256 i = 0; i < 3; i++) {
            if (areaDrugIds[area][i] == drugId) return areaDrugSell[area][i];
        }
        return 0;
    }

    /// @dev ECONOMY_DESIGN 6 piecewise stash bonus (proposed Core upgrade). Doc samples are
    ///      internally inconsistent; this is the literal formula, reported as indicative only.
    function _stashBonus(uint256 stashValue) private pure returns (uint256) {
        if (stashValue < 10000) return stashValue / 100;
        if (stashValue < 100000) return 100 + (stashValue - 10000) / 250;
        return 460 + _intSqrt((stashValue - 100000) / 10);
    }

    function _intSqrt(uint256 x) private pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }
}

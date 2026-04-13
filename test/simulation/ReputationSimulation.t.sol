// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

contract ReputationSimulation is Test {
    // =============================================================
    //                          CONSTANTS
    // =============================================================

    uint256 constant REP_STAKE_DIVISOR = 50;
    uint256 constant BASE_MAX_ATTEMPTS = 5;
    uint256 constant MAX_HEAT = 5;
    uint256 constant JAIL_CHANCE_PER_HEAT = 5; // per 1000
    uint256 constant JAIL_REP_PENALTY_PERCENT = 10;
    uint256 constant JAIL_REP_PENALTY_CAP = 50;
    uint256 constant DRUG_CONFISCATION_PERCENT = 3;
    uint256 constant STARTER_CASH = 250;
    uint256 constant STARTER_WEED = 100;
    uint256 constant STARTER_XTC = 5;
    uint256 constant STARTER_COCAINE = 1;
    uint256 constant STARTING_REP = 25;
    uint256 constant MAX_REPUTATION = 6000;
    uint256 constant STASH_DIVISOR = 100;
    uint256 constant PVP_MIN_REPUTATION = 100;
    uint256 constant PVP_BASE_WIN_CHANCE = 50;
    uint256 constant PVP_DEFENDER_REP_BONUS = 2;
    uint256 constant CASH_TOPUP_PRICE_WEI = 0.001 ether;
    uint256 constant CASH_TOPUP_AMOUNT = 100;
    uint256 constant CASH_PURCHASE_THRESHOLD = 10;
    uint256 constant BAIL_FEE_WEI = 0.002 ether;
    uint256 constant BREAKOUT_CHANCE = 50;
    uint256 constant SIM_DAYS = 100;
    uint256 constant NUM_ARCHETYPES = 4;
    uint256 constant NUM_TIERS = 10;
    uint256 constant NUM_AREAS = 6;
    uint256 constant NUM_DRUGS = 11;

    // PVE outcome odds
    uint256 constant TIE_CHANCE = 50;
    uint256 constant WIN_CHANCE = 20;

    // =============================================================
    //                          STRUCTS
    // =============================================================

    struct TierConfig {
        uint256 minRep;
        int16 winBonus;
        int16 tieBonus;
        int16 lossPenalty;
        int16 repCap;
    }

    struct BoostConfig {
        uint256 priceWei;
        uint256 durationDays;
        uint16 drugMultiplier;
        uint16 repMultiplier;
        uint16 cashMultiplier;
        uint8 extraAttempts;
    }

    struct AreaDrug {
        uint256 drugId;
        uint256 buyPrice;
        uint256 sellPrice;
    }

    struct AreaConfig {
        uint256 minReputation;
        AreaDrug[3] drugs;
    }

    struct SimDealer {
        uint256 rep;
        uint256 cash;
        uint8 currentArea;
        uint8 heatLevel;
        bool inJail;
        uint256[12] drugBalances; // drugId 1-11
        uint8 boostTier;          // 0=none, 1-4
        uint256 boostExpiresDay;
        uint256 totalPveGames;
        uint256 pveWins;
        uint256 pveTies;
        uint256 pveLosses;
        uint256 pvpAttackWins;
        uint256 pvpAttackLosses;
        uint256 jailCount;
        uint256 ethSpent;
    }

    // =============================================================
    //                          STORAGE
    // =============================================================

    TierConfig[NUM_TIERS] tiers;
    BoostConfig[5] boosts; // index 1-4
    uint256[12] drugBaseCashValues; // drugId 1-11
    uint256[7] areaMinRep; // areaId 1-6

    // Area drug configs: areaId => array of 3 AreaDrug
    // Stored flat: areaId 1-6
    AreaDrug[3][7] areaDrugs;

    SimDealer[NUM_ARCHETYPES] dealers;

    uint256 rngState;

    // =============================================================
    //                       INITIALIZATION
    // =============================================================

    function _initConfig() private {
        // Tiers from SetupTiers.s.sol (deployment source of truth)
        tiers[0] = TierConfig({minRep: 0,    winBonus: 50, tieBonus: 25, lossPenalty: -2, repCap: 25});
        tiers[1] = TierConfig({minRep: 50,   winBonus: 40, tieBonus: 20, lossPenalty: -3, repCap: 22});
        tiers[2] = TierConfig({minRep: 150,  winBonus: 15, tieBonus: 8,  lossPenalty: -3, repCap: 18});
        tiers[3] = TierConfig({minRep: 300,  winBonus: 9,  tieBonus: 3,  lossPenalty: -4, repCap: 17});
        tiers[4] = TierConfig({minRep: 700,  winBonus: 8,  tieBonus: 3,  lossPenalty: -4, repCap: 21});
        tiers[5] = TierConfig({minRep: 1250, winBonus: 7,  tieBonus: 3,  lossPenalty: -5, repCap: 24});
        tiers[6] = TierConfig({minRep: 1900, winBonus: 6,  tieBonus: 2,  lossPenalty: -5, repCap: 25});
        tiers[7] = TierConfig({minRep: 2600, winBonus: 5,  tieBonus: 2,  lossPenalty: -6, repCap: 28});
        tiers[8] = TierConfig({minRep: 3500, winBonus: 4,  tieBonus: 2,  lossPenalty: -6, repCap: 30});
        tiers[9] = TierConfig({minRep: 5000, winBonus: 3,  tieBonus: 1,  lossPenalty: -7, repCap: 24});

        // Boosts from COMMANDS.md (post-deployment setBoostTier values)
        boosts[1] = BoostConfig({priceWei: 0.0025 ether, durationDays: 3,  drugMultiplier: 125, repMultiplier: 110, cashMultiplier: 125, extraAttempts: 2});
        boosts[2] = BoostConfig({priceWei: 0.005 ether,  durationDays: 7,  drugMultiplier: 150, repMultiplier: 115, cashMultiplier: 150, extraAttempts: 3});
        boosts[3] = BoostConfig({priceWei: 0.01 ether,   durationDays: 14, drugMultiplier: 175, repMultiplier: 120, cashMultiplier: 175, extraAttempts: 5});
        boosts[4] = BoostConfig({priceWei: 0.023 ether,  durationDays: 30, drugMultiplier: 200, repMultiplier: 125, cashMultiplier: 200, extraAttempts: 7});

        // Drug base cash values (drugId 1-11) from SetupDrugs.s.sol
        drugBaseCashValues[1]  = 75;   // Goods
        drugBaseCashValues[2]  = 500;  // Contraband
        drugBaseCashValues[3]  = 2500; // Jewels
        drugBaseCashValues[4]  = 1;    // Weed
        drugBaseCashValues[5]  = 10;   // XTC
        drugBaseCashValues[6]  = 100;  // Cocaine
        drugBaseCashValues[7]  = 12;   // Shrooms
        drugBaseCashValues[8]  = 150;  // Heroin
        drugBaseCashValues[9]  = 18;   // Opioids
        drugBaseCashValues[10] = 25;   // Meth
        drugBaseCashValues[11] = 200;  // Fentanyl

        // Area min reputation
        areaMinRep[1] = 0;    // Manhattan
        areaMinRep[2] = 150;  // Amsterdam
        areaMinRep[3] = 250;  // Colombia
        areaMinRep[4] = 500;  // Hong Kong
        areaMinRep[5] = 1000; // Seoul
        areaMinRep[6] = 1500; // Tokyo

        // Area drug configs from SetupAreas.s.sol
        // Manhattan: Weed 1/1, XTC 12/10, Cocaine 120/100
        areaDrugs[1][0] = AreaDrug({drugId: 4, buyPrice: 1,   sellPrice: 1});
        areaDrugs[1][1] = AreaDrug({drugId: 5, buyPrice: 12,  sellPrice: 10});
        areaDrugs[1][2] = AreaDrug({drugId: 6, buyPrice: 120, sellPrice: 100});

        // Amsterdam: Weed 3/2, Shrooms 15/12, Heroin 180/150
        areaDrugs[2][0] = AreaDrug({drugId: 4, buyPrice: 3,   sellPrice: 2});
        areaDrugs[2][1] = AreaDrug({drugId: 7, buyPrice: 15,  sellPrice: 12});
        areaDrugs[2][2] = AreaDrug({drugId: 8, buyPrice: 180, sellPrice: 150});

        // Colombia: Weed 1/1, Cocaine 60/50, Heroin 90/75
        areaDrugs[3][0] = AreaDrug({drugId: 4, buyPrice: 1,   sellPrice: 1});
        areaDrugs[3][1] = AreaDrug({drugId: 6, buyPrice: 60,  sellPrice: 50});
        areaDrugs[3][2] = AreaDrug({drugId: 8, buyPrice: 90,  sellPrice: 75});

        // Hong Kong: Opioids 18/15, Meth 28/22, Heroin 140/110
        areaDrugs[4][0] = AreaDrug({drugId: 9,  buyPrice: 18,  sellPrice: 15});
        areaDrugs[4][1] = AreaDrug({drugId: 10, buyPrice: 28,  sellPrice: 22});
        areaDrugs[4][2] = AreaDrug({drugId: 8,  buyPrice: 140, sellPrice: 110});

        // Seoul: Opioids 8/7, Meth 14/12, Fentanyl 90/75
        areaDrugs[5][0] = AreaDrug({drugId: 9,  buyPrice: 8,  sellPrice: 7});
        areaDrugs[5][1] = AreaDrug({drugId: 10, buyPrice: 14, sellPrice: 12});
        areaDrugs[5][2] = AreaDrug({drugId: 11, buyPrice: 90, sellPrice: 75});

        // Tokyo: Opioids 24/20, Meth 32/26, Fentanyl 200/160
        areaDrugs[6][0] = AreaDrug({drugId: 9,  buyPrice: 24,  sellPrice: 20});
        areaDrugs[6][1] = AreaDrug({drugId: 10, buyPrice: 32,  sellPrice: 26});
        areaDrugs[6][2] = AreaDrug({drugId: 11, buyPrice: 200, sellPrice: 160});
    }

    function _initDealer(uint256 idx) private {
        dealers[idx].rep = STARTING_REP;
        dealers[idx].cash = STARTER_CASH;
        dealers[idx].currentArea = 1; // Manhattan
        dealers[idx].drugBalances[4] = STARTER_WEED;
        dealers[idx].drugBalances[5] = STARTER_XTC;
        dealers[idx].drugBalances[6] = STARTER_COCAINE;
    }

    // =============================================================
    //                           PRNG
    // =============================================================

    function _initRng(uint256 seed) private {
        rngState = seed;
    }

    function _nextRng() private returns (uint256) {
        rngState = uint256(keccak256(abi.encodePacked(rngState)));
        return rngState;
    }

    function _rollPveOutcome() private returns (uint8) {
        uint256 roll = _nextRng() % 100;
        if (roll < TIE_CHANCE) return 1;                    // 0-49: TIE (50%)
        if (roll < TIE_CHANCE + WIN_CHANCE) return 0;       // 50-69: WIN (20%)
        return 2;                                            // 70-99: LOSS (30%)
    }

    function _rollPvpWin(uint256 winChance) private returns (bool) {
        return (_nextRng() % 100) < winChance;
    }

    function _rollJailCheck(uint8 heatLevel) private returns (bool) {
        if (heatLevel == 0) return false;
        uint256 jailChance = uint256(heatLevel) * JAIL_CHANCE_PER_HEAT;
        return (_nextRng() % 1000) < jailChance;
    }

    function _rollDayVariation() private returns (uint8) {
        uint256 roll = _nextRng() % 100;
        if (roll < 70) return 2;  // full play
        if (roll < 90) return 1;  // half play
        return 0;                 // skip
    }

    // =============================================================
    //                     CORE GAME MATH
    // =============================================================

    function _getTierIndex(uint256 rep) private view returns (uint8) {
        uint8 idx = 0;
        for (uint8 i = uint8(NUM_TIERS); i > 0; ) {
            unchecked { --i; }
            if (rep >= tiers[i].minRep) {
                idx = i;
                break;
            }
        }
        return idx;
    }

    function _getStashBonus(uint256 dealerIdx) private view returns (uint256) {
        uint256 totalValue;
        for (uint256 d = 1; d <= NUM_DRUGS; d++) {
            uint256 bal = dealers[dealerIdx].drugBalances[d];
            if (bal > 0) {
                totalValue += bal * drugBaseCashValues[d];
            }
        }
        return totalValue / STASH_DIVISOR;
    }

    function _getTotalReputation(uint256 dealerIdx) private view returns (uint256) {
        return dealers[dealerIdx].rep + _getStashBonus(dealerIdx);
    }

    function _getBestArea(uint256 rep) private view returns (uint8) {
        uint8 best = 1;
        for (uint8 a = 6; a >= 1; a--) {
            if (rep >= areaMinRep[a]) {
                best = a;
                break;
            }
        }
        return best;
    }

    function _getMaxAttempts(uint256 dealerIdx) private view returns (uint256) {
        uint8 bt = dealers[dealerIdx].boostTier;
        if (bt > 0 && dealers[dealerIdx].boostExpiresDay > 0) {
            return BASE_MAX_ATTEMPTS + boosts[bt].extraAttempts;
        }
        return BASE_MAX_ATTEMPTS;
    }

    function _getRepMultiplier(uint256 dealerIdx) private view returns (uint16) {
        uint8 bt = dealers[dealerIdx].boostTier;
        if (bt > 0 && dealers[dealerIdx].boostExpiresDay > 0) {
            return boosts[bt].repMultiplier;
        }
        return 100;
    }

    function _getDrugMultiplier(uint256 dealerIdx) private view returns (uint16) {
        uint8 bt = dealers[dealerIdx].boostTier;
        if (bt > 0 && dealers[dealerIdx].boostExpiresDay > 0) {
            return boosts[bt].drugMultiplier;
        }
        return 100;
    }

    function _getCashMultiplier(uint256 dealerIdx) private view returns (uint16) {
        uint8 bt = dealers[dealerIdx].boostTier;
        if (bt > 0 && dealers[dealerIdx].boostExpiresDay > 0) {
            return boosts[bt].cashMultiplier;
        }
        return 100;
    }

    function _calculatePveRepChange(
        uint8 tierIdx,
        uint8 outcome,
        uint256 stakeValue,
        uint16 repMultiplier
    ) private view returns (int256) {
        TierConfig memory t = tiers[tierIdx];
        int16 baseRep;
        if (outcome == 0) baseRep = t.winBonus;
        else if (outcome == 1) baseRep = t.tieBonus;
        else baseRep = t.lossPenalty;

        int256 scaled = (int256(baseRep) * int256(stakeValue)) / int256(REP_STAKE_DIVISOR);

        if (outcome <= 1) {
            scaled = (scaled * int256(uint256(repMultiplier))) / 100;
        }

        if (scaled > int256(t.repCap)) return int256(t.repCap);
        if (scaled < -int256(t.repCap)) return -int256(t.repCap);
        return scaled;
    }

    function _pvpAttackerRepChange(uint8 tierIdx, uint16 repMultiplier, bool won) private view returns (int256) {
        TierConfig memory t = tiers[tierIdx];
        if (won) {
            int256 result = (int256(t.winBonus) * int256(uint256(repMultiplier))) / 100;
            return result;
        }
        return int256(t.lossPenalty);
    }

    function _applyRepChange(uint256 dealerIdx, int256 delta) private {
        if (delta >= 0) {
            dealers[dealerIdx].rep += uint256(delta);
            if (dealers[dealerIdx].rep > MAX_REPUTATION) {
                dealers[dealerIdx].rep = MAX_REPUTATION;
            }
        } else {
            uint256 loss = uint256(-delta);
            if (loss >= dealers[dealerIdx].rep) {
                dealers[dealerIdx].rep = 0;
            } else {
                dealers[dealerIdx].rep -= loss;
            }
        }
    }

    function _processJail(uint256 dealerIdx) private {
        SimDealer storage d = dealers[dealerIdx];
        uint256 percentLoss = (d.rep * JAIL_REP_PENALTY_PERCENT) / 100;
        uint256 repLoss = percentLoss > JAIL_REP_PENALTY_CAP ? JAIL_REP_PENALTY_CAP : percentLoss;

        if (repLoss >= d.rep) {
            d.rep = 0;
        } else {
            d.rep -= repLoss;
        }

        // Confiscate 3% of a random held drug
        for (uint256 drugId = 1; drugId <= NUM_DRUGS; drugId++) {
            if (d.drugBalances[drugId] > 0) {
                uint256 confiscated = (d.drugBalances[drugId] * DRUG_CONFISCATION_PERCENT) / 100;
                if (confiscated == 0) confiscated = 1;
                d.drugBalances[drugId] -= confiscated;
                break;
            }
        }

        d.inJail = true;
        d.jailCount++;
    }

    // =============================================================
    //                     PVE SIMULATION
    // =============================================================

    function _findBestSellDrug(uint256 dealerIdx) private view returns (uint256 drugId, uint256 sellPrice, uint256 maxAmount) {
        uint8 area = dealers[dealerIdx].currentArea;
        uint256 bestValue;

        for (uint256 i = 0; i < 3; i++) {
            AreaDrug memory ad = areaDrugs[area][i];
            uint256 bal = dealers[dealerIdx].drugBalances[ad.drugId];
            if (bal > 0 && ad.sellPrice > bestValue) {
                bestValue = ad.sellPrice;
                drugId = ad.drugId;
                sellPrice = ad.sellPrice;
                maxAmount = bal;
            }
        }
    }

    function _findBestBuyDrug(uint256 dealerIdx) private view returns (uint256 drugId, uint256 buyPrice, uint256 sellPrice, uint256 maxAmount) {
        uint8 area = dealers[dealerIdx].currentArea;
        uint256 cash = dealers[dealerIdx].cash;
        uint256 bestSellPrice;

        for (uint256 i = 0; i < 3; i++) {
            AreaDrug memory ad = areaDrugs[area][i];
            if (ad.buyPrice > 0 && cash >= ad.buyPrice && ad.sellPrice > bestSellPrice) {
                bestSellPrice = ad.sellPrice;
                drugId = ad.drugId;
                buyPrice = ad.buyPrice;
                sellPrice = ad.sellPrice;
                maxAmount = cash / ad.buyPrice;
            }
        }
    }

    function _playPveAttempt(uint256 dealerIdx) private {
        SimDealer storage d = dealers[dealerIdx];
        uint8 tierIdx = _getTierIndex(d.rep);
        uint16 repMult = _getRepMultiplier(dealerIdx);
        uint16 drugMult = _getDrugMultiplier(dealerIdx);
        uint16 cashMult = _getCashMultiplier(dealerIdx);

        // Try to sell first (highest value drug), fallback to buy
        (uint256 sellDrugId, uint256 sellPrice, uint256 sellMax) = _findBestSellDrug(dealerIdx);

        if (sellDrugId > 0 && sellMax > 0) {
            // Sell strategy: sell enough to hit rep cap if possible
            uint256 amount = sellMax > 10 ? 10 : sellMax;
            uint256 stakeValue = amount * sellPrice;
            uint8 outcome = _rollPveOutcome();

            int256 repChange = _calculatePveRepChange(tierIdx, outcome, stakeValue, repMult);
            _applyRepChange(dealerIdx, repChange);

            if (outcome == 0) {
                // WIN: keep drugs, get cash
                uint256 boostedCash = (stakeValue * uint256(cashMult)) / 100;
                d.cash += boostedCash;
            } else if (outcome == 1) {
                // TIE: lose drugs, get cash
                d.drugBalances[sellDrugId] -= amount;
                uint256 boostedCash = (stakeValue * uint256(cashMult)) / 100;
                d.cash += boostedCash;
            } else {
                // LOSS: lose drugs, no cash
                d.drugBalances[sellDrugId] -= amount;
            }

            d.totalPveGames++;
            if (outcome == 0) d.pveWins++;
            else if (outcome == 1) d.pveTies++;
            else d.pveLosses++;
        } else {
            // Try to buy drugs
            (uint256 buyDrugId, uint256 buyPrice, uint256 buySellPrice, uint256 buyMax) = _findBestBuyDrug(dealerIdx);

            if (buyDrugId > 0 && buyMax > 0) {
                uint256 amount = buyMax > 10 ? 10 : buyMax;
                uint256 cashCost = amount * buyPrice;
                uint8 outcome = _rollPveOutcome();

                int256 repChange = _calculatePveRepChange(tierIdx, outcome, cashCost, repMult);
                _applyRepChange(dealerIdx, repChange);

                if (outcome == 0) {
                    // WIN: keep cash, get drugs
                    uint256 boostedAmount = (amount * uint256(drugMult)) / 100;
                    d.drugBalances[buyDrugId] += boostedAmount;
                } else if (outcome == 1) {
                    // TIE: lose cash, get drugs
                    d.cash -= cashCost;
                    uint256 boostedAmount = (amount * uint256(drugMult)) / 100;
                    d.drugBalances[buyDrugId] += boostedAmount;
                } else {
                    // LOSS: lose cash, no drugs
                    d.cash -= cashCost;
                }

                d.totalPveGames++;
                if (outcome == 0) d.pveWins++;
                else if (outcome == 1) d.pveTies++;
                else d.pveLosses++;

                // Use buySellPrice to suppress unused variable warning
                buySellPrice;
            } else {
                // No drugs to sell and can't afford to buy — need cash topup
                d.cash += CASH_TOPUP_AMOUNT;
                d.ethSpent += CASH_TOPUP_PRICE_WEI;
            }
        }

        // Heat increment
        if (d.heatLevel < MAX_HEAT) {
            d.heatLevel++;
        }

        // Jail check
        if (_rollJailCheck(d.heatLevel)) {
            _processJail(dealerIdx);
        }
    }

    // =============================================================
    //                     PVP SIMULATION
    // =============================================================

    function _playPvpAttempt(uint256 dealerIdx) private {
        SimDealer storage d = dealers[dealerIdx];
        uint8 tierIdx = _getTierIndex(d.rep);
        uint16 repMult = _getRepMultiplier(dealerIdx);

        bool won = _rollPvpWin(PVP_BASE_WIN_CHANCE);

        int256 repChange = _pvpAttackerRepChange(tierIdx, repMult, won);
        _applyRepChange(dealerIdx, repChange);

        if (won) {
            d.pvpAttackWins++;
        } else {
            d.pvpAttackLosses++;
        }

        // Heat increment on PVP too
        if (d.heatLevel < MAX_HEAT) {
            d.heatLevel++;
        }

        if (_rollJailCheck(d.heatLevel)) {
            _processJail(dealerIdx);
        }
    }

    // =============================================================
    //                   ARCHETYPE STRATEGIES
    // =============================================================

    function _playDayPveOnly(uint256 dealerIdx, uint256 day) private {
        SimDealer storage d = dealers[dealerIdx];

        // No boost for PVE-Only archetype
        _updateArea(dealerIdx);
        _handleJailStart(dealerIdx, day);
        if (d.inJail) return;

        uint256 attempts = _getDayAttempts(dealerIdx);
        for (uint256 a = 0; a < attempts; a++) {
            if (d.inJail) break;
            _playPveAttempt(dealerIdx);
        }
    }

    function _playDayPvpOnly(uint256 dealerIdx, uint256 day) private {
        SimDealer storage d = dealers[dealerIdx];

        _updateArea(dealerIdx);
        _handleJailStart(dealerIdx, day);
        if (d.inJail) return;

        uint256 attempts = _getDayAttempts(dealerIdx);
        bool canPvp = d.rep >= PVP_MIN_REPUTATION;

        for (uint256 a = 0; a < attempts; a++) {
            if (d.inJail) break;
            if (canPvp) {
                _playPvpAttempt(dealerIdx);
            } else {
                _playPveAttempt(dealerIdx);
                canPvp = d.rep >= PVP_MIN_REPUTATION;
            }
        }
    }

    function _playDayHybrid(uint256 dealerIdx, uint256 day) private {
        SimDealer storage d = dealers[dealerIdx];

        _updateArea(dealerIdx);
        _handleJailStart(dealerIdx, day);
        if (d.inJail) return;

        uint256 attempts = _getDayAttempts(dealerIdx);
        bool canPvp = d.rep >= PVP_MIN_REPUTATION;

        for (uint256 a = 0; a < attempts; a++) {
            if (d.inJail) break;

            bool doPvp = canPvp && (_nextRng() % 100) < 40; // 40% PVP when eligible
            if (doPvp) {
                _playPvpAttempt(dealerIdx);
            } else {
                _playPveAttempt(dealerIdx);
                canPvp = d.rep >= PVP_MIN_REPUTATION;
            }
        }
    }

    function _playDayWhale(uint256 dealerIdx, uint256 day) private {
        SimDealer storage d = dealers[dealerIdx];

        // Godfather boost always active
        if (d.boostExpiresDay <= day) {
            d.boostTier = 4;
            d.boostExpiresDay = day + boosts[4].durationDays;
            d.ethSpent += boosts[4].priceWei;
        }

        _updateArea(dealerIdx);
        _handleJailStart(dealerIdx, day);
        if (d.inJail) return;

        uint256 attempts = _getDayAttempts(dealerIdx);
        bool canPvp = d.rep >= PVP_MIN_REPUTATION;

        for (uint256 a = 0; a < attempts; a++) {
            if (d.inJail) break;

            bool doPvp = canPvp && (_nextRng() % 100) < 40;
            if (doPvp) {
                _playPvpAttempt(dealerIdx);
            } else {
                _playPveAttempt(dealerIdx);
                canPvp = d.rep >= PVP_MIN_REPUTATION;
            }
        }
    }

    // =============================================================
    //                      HELPER FUNCTIONS
    // =============================================================

    function _updateArea(uint256 dealerIdx) private {
        uint8 bestArea = _getBestArea(_getTotalReputation(dealerIdx));
        if (bestArea > dealers[dealerIdx].currentArea) {
            dealers[dealerIdx].currentArea = bestArea;
        }
    }

    function _handleJailStart(uint256 dealerIdx, uint256 /* day */) private {
        SimDealer storage d = dealers[dealerIdx];
        if (!d.inJail) return;

        // Pay bail to get out
        d.inJail = false;
        d.ethSpent += BAIL_FEE_WEI;
        d.heatLevel = 0;
    }

    function _getDayAttempts(uint256 dealerIdx) private returns (uint256) {
        uint8 variation = _rollDayVariation();
        uint256 maxAttempts = _getMaxAttempts(dealerIdx);

        if (variation == 0) return 0;         // skip day
        if (variation == 1) return maxAttempts / 2; // half day
        return maxAttempts;                    // full day
    }

    // =============================================================
    //                    LOGGING HELPERS
    // =============================================================

    function _tierName(uint8 tierIdx) private pure returns (string memory) {
        if (tierIdx == 0) return "Outsider";
        if (tierIdx == 1) return "Associate";
        if (tierIdx == 2) return "Dealer";
        if (tierIdx == 3) return "Soldier";
        if (tierIdx == 4) return "Capo";
        if (tierIdx == 5) return "Consigliere";
        if (tierIdx == 6) return "Underboss";
        if (tierIdx == 7) return "Don";
        if (tierIdx == 8) return "Godfather";
        return "Legend";
    }

    function _archetypeName(uint256 idx) private pure returns (string memory) {
        if (idx == 0) return "PVE_ONLY ";
        if (idx == 1) return "PVP_ONLY ";
        if (idx == 2) return "HYBRID   ";
        return "WHALE    ";
    }

    function _logSnapshot(uint256 day) private view {
        console.log("=== DAY %d ===", day);
        for (uint256 i = 0; i < NUM_ARCHETYPES; i++) {
            uint8 tierIdx = _getTierIndex(dealers[i].rep);
            console.log("  %s  rep=%d  tier=%s", _archetypeName(i), dealers[i].rep, _tierName(tierIdx));
        }
    }

    function _logSummary() private view {
        console.log("");
        console.log("============================================================");
        console.log("               100-DAY SIMULATION SUMMARY");
        console.log("============================================================");
        console.log("");

        for (uint256 i = 0; i < NUM_ARCHETYPES; i++) {
            SimDealer storage d = dealers[i];
            uint8 tierIdx = _getTierIndex(d.rep);

            console.log("--- %s ---", _archetypeName(i));
            console.log("  Final Rep: %d (%s)", d.rep, _tierName(tierIdx));
            console.log("  Total Rep (+ stash): %d", _getTotalReputation(i));
            console.log("  Cash: %d", d.cash);
            console.log("  PVE: %d W / %d T / %d L", d.pveWins, d.pveTies, d.pveLosses);
            console.log("  PVP: %d wins / %d losses", d.pvpAttackWins, d.pvpAttackLosses);
            console.log("  Jailed: %d times", d.jailCount);
            console.log("  ETH Spent: %d wei", d.ethSpent);
            console.log("");
        }
    }

    // =============================================================
    //                    MAIN SIMULATION TESTS
    // =============================================================

    function test_100day_archetype_simulation() public {
        _initConfig();
        _initRng(42);

        for (uint256 i = 0; i < NUM_ARCHETYPES; i++) {
            _initDealer(i);
        }

        for (uint256 day = 1; day <= SIM_DAYS; day++) {
            // Expire boosts
            for (uint256 i = 0; i < NUM_ARCHETYPES; i++) {
                if (dealers[i].boostExpiresDay > 0 && dealers[i].boostExpiresDay <= day) {
                    dealers[i].boostTier = 0;
                    dealers[i].boostExpiresDay = 0;
                }
            }

            // Each archetype plays their strategy
            _playDayPveOnly(0, day);
            _playDayPvpOnly(1, day);
            _playDayHybrid(2, day);
            _playDayWhale(3, day);

            // Heat decay: simplified — reduce by 1 if no games played today
            // (In practice heat decays after 7-day grace. For sim we let it accumulate
            //  during play days and reset on skip days.)

            // Log every 10 days
            if (day % 10 == 0) {
                _logSnapshot(day);
            }
        }

        _logSummary();
    }

    // =============================================================
    //                BOOST COMPARISON (PVE-ONLY)
    // =============================================================

    SimDealer[5] boostDealers;

    function _initBoostDealer(uint256 idx) private {
        boostDealers[idx].rep = STARTING_REP;
        boostDealers[idx].cash = STARTER_CASH;
        boostDealers[idx].currentArea = 1;
        boostDealers[idx].drugBalances[4] = STARTER_WEED;
        boostDealers[idx].drugBalances[5] = STARTER_XTC;
        boostDealers[idx].drugBalances[6] = STARTER_COCAINE;
    }

    function _getBoostMaxAttempts(uint256 idx) private view returns (uint256) {
        uint8 bt = boostDealers[idx].boostTier;
        if (bt > 0 && boostDealers[idx].boostExpiresDay > 0) {
            return BASE_MAX_ATTEMPTS + boosts[bt].extraAttempts;
        }
        return BASE_MAX_ATTEMPTS;
    }

    function _getBoostRepMultiplier(uint256 idx) private view returns (uint16) {
        uint8 bt = boostDealers[idx].boostTier;
        if (bt > 0 && boostDealers[idx].boostExpiresDay > 0) {
            return boosts[bt].repMultiplier;
        }
        return 100;
    }

    function _getBoostDrugMultiplier(uint256 idx) private view returns (uint16) {
        uint8 bt = boostDealers[idx].boostTier;
        if (bt > 0 && boostDealers[idx].boostExpiresDay > 0) {
            return boosts[bt].drugMultiplier;
        }
        return 100;
    }

    function _getBoostCashMultiplier(uint256 idx) private view returns (uint16) {
        uint8 bt = boostDealers[idx].boostTier;
        if (bt > 0 && boostDealers[idx].boostExpiresDay > 0) {
            return boosts[bt].cashMultiplier;
        }
        return 100;
    }

    function _getBoostStashBonus(uint256 idx) private view returns (uint256) {
        uint256 totalValue;
        for (uint256 d = 1; d <= NUM_DRUGS; d++) {
            uint256 bal = boostDealers[idx].drugBalances[d];
            if (bal > 0) {
                totalValue += bal * drugBaseCashValues[d];
            }
        }
        return totalValue / STASH_DIVISOR;
    }

    function _getBoostTotalRep(uint256 idx) private view returns (uint256) {
        return boostDealers[idx].rep + _getBoostStashBonus(idx);
    }

    function _getBoostBestArea(uint256 idx) private view returns (uint8) {
        uint256 totalRep = _getBoostTotalRep(idx);
        uint8 best = 1;
        for (uint8 a = 6; a >= 1; a--) {
            if (totalRep >= areaMinRep[a]) {
                best = a;
                break;
            }
        }
        return best;
    }

    function _findBoostBestSellDrug(uint256 idx) private view returns (uint256 drugId, uint256 sellPrice, uint256 maxAmount) {
        uint8 area = boostDealers[idx].currentArea;
        uint256 bestValue;
        for (uint256 i = 0; i < 3; i++) {
            AreaDrug memory ad = areaDrugs[area][i];
            uint256 bal = boostDealers[idx].drugBalances[ad.drugId];
            if (bal > 0 && ad.sellPrice > bestValue) {
                bestValue = ad.sellPrice;
                drugId = ad.drugId;
                sellPrice = ad.sellPrice;
                maxAmount = bal;
            }
        }
    }

    function _findBoostBestBuyDrug(uint256 idx) private view returns (uint256 drugId, uint256 buyPrice, uint256 maxAmount) {
        uint8 area = boostDealers[idx].currentArea;
        uint256 cash = boostDealers[idx].cash;
        uint256 bestSellPrice;
        for (uint256 i = 0; i < 3; i++) {
            AreaDrug memory ad = areaDrugs[area][i];
            if (ad.buyPrice > 0 && cash >= ad.buyPrice && ad.sellPrice > bestSellPrice) {
                bestSellPrice = ad.sellPrice;
                drugId = ad.drugId;
                buyPrice = ad.buyPrice;
                maxAmount = cash / ad.buyPrice;
            }
        }
    }

    function _playBoostPveAttempt(uint256 idx) private {
        SimDealer storage d = boostDealers[idx];
        uint8 tierIdx = _getTierIndex(d.rep);
        uint16 repMult = _getBoostRepMultiplier(idx);
        uint16 drugMult = _getBoostDrugMultiplier(idx);
        uint16 cashMult = _getBoostCashMultiplier(idx);

        (uint256 sellDrugId, uint256 sellPrice, uint256 sellMax) = _findBoostBestSellDrug(idx);

        if (sellDrugId > 0 && sellMax > 0) {
            uint256 amount = sellMax > 10 ? 10 : sellMax;
            uint256 stakeValue = amount * sellPrice;
            uint8 outcome = _rollPveOutcome();

            int256 repChange = _calculatePveRepChange(tierIdx, outcome, stakeValue, repMult);

            // Apply rep
            if (repChange >= 0) {
                d.rep += uint256(repChange);
                if (d.rep > MAX_REPUTATION) d.rep = MAX_REPUTATION;
            } else {
                uint256 loss = uint256(-repChange);
                d.rep = loss >= d.rep ? 0 : d.rep - loss;
            }

            if (outcome == 0) {
                uint256 boostedCash = (stakeValue * uint256(cashMult)) / 100;
                d.cash += boostedCash;
            } else if (outcome == 1) {
                d.drugBalances[sellDrugId] -= amount;
                uint256 boostedCash = (stakeValue * uint256(cashMult)) / 100;
                d.cash += boostedCash;
            } else {
                d.drugBalances[sellDrugId] -= amount;
            }

            d.totalPveGames++;
            if (outcome == 0) d.pveWins++;
            else if (outcome == 1) d.pveTies++;
            else d.pveLosses++;
        } else {
            (uint256 buyDrugId, uint256 buyPrice, uint256 buyMax) = _findBoostBestBuyDrug(idx);

            if (buyDrugId > 0 && buyMax > 0) {
                uint256 amount = buyMax > 10 ? 10 : buyMax;
                uint256 cashCost = amount * buyPrice;
                uint8 outcome = _rollPveOutcome();

                int256 repChange = _calculatePveRepChange(tierIdx, outcome, cashCost, repMult);

                if (repChange >= 0) {
                    d.rep += uint256(repChange);
                    if (d.rep > MAX_REPUTATION) d.rep = MAX_REPUTATION;
                } else {
                    uint256 loss = uint256(-repChange);
                    d.rep = loss >= d.rep ? 0 : d.rep - loss;
                }

                if (outcome == 0) {
                    uint256 boostedAmount = (amount * uint256(drugMult)) / 100;
                    d.drugBalances[buyDrugId] += boostedAmount;
                } else if (outcome == 1) {
                    d.cash -= cashCost;
                    uint256 boostedAmount = (amount * uint256(drugMult)) / 100;
                    d.drugBalances[buyDrugId] += boostedAmount;
                } else {
                    d.cash -= cashCost;
                }

                d.totalPveGames++;
                if (outcome == 0) d.pveWins++;
                else if (outcome == 1) d.pveTies++;
                else d.pveLosses++;
            } else {
                d.cash += CASH_TOPUP_AMOUNT;
                d.ethSpent += CASH_TOPUP_PRICE_WEI;
            }
        }

        if (d.heatLevel < MAX_HEAT) {
            d.heatLevel++;
        }

        if (_rollJailCheck(d.heatLevel)) {
            uint256 percentLoss = (d.rep * JAIL_REP_PENALTY_PERCENT) / 100;
            uint256 repLoss = percentLoss > JAIL_REP_PENALTY_CAP ? JAIL_REP_PENALTY_CAP : percentLoss;
            d.rep = repLoss >= d.rep ? 0 : d.rep - repLoss;
            for (uint256 drugId = 1; drugId <= NUM_DRUGS; drugId++) {
                if (d.drugBalances[drugId] > 0) {
                    uint256 confiscated = (d.drugBalances[drugId] * DRUG_CONFISCATION_PERCENT) / 100;
                    if (confiscated == 0) confiscated = 1;
                    d.drugBalances[drugId] -= confiscated;
                    break;
                }
            }
            d.inJail = true;
            d.jailCount++;
        }
    }

    function test_boost_comparison_pve() public {
        _initConfig();
        _initRng(123);

        string[5] memory boostNames = ["No Boost  ", "Grinder   ", "Hustler   ", "Kingpin   ", "Godfather "];
        uint8[5] memory boostTierIds = [0, 1, 2, 3, 4];

        for (uint256 i = 0; i < 5; i++) {
            _initBoostDealer(i);
        }

        for (uint256 day = 1; day <= SIM_DAYS; day++) {
            for (uint256 i = 0; i < 5; i++) {
                SimDealer storage d = boostDealers[i];

                // Expire boosts
                if (d.boostExpiresDay > 0 && d.boostExpiresDay <= day) {
                    d.boostTier = 0;
                    d.boostExpiresDay = 0;
                }

                // Renew boost if applicable (skip index 0 = no boost)
                if (boostTierIds[i] > 0 && d.boostExpiresDay <= day) {
                    d.boostTier = boostTierIds[i];
                    d.boostExpiresDay = day + boosts[boostTierIds[i]].durationDays;
                    d.ethSpent += boosts[boostTierIds[i]].priceWei;
                }

                // Handle jail
                if (d.inJail) {
                    d.inJail = false;
                    d.ethSpent += BAIL_FEE_WEI;
                    d.heatLevel = 0;
                    continue;
                }

                // Update area
                uint8 bestArea = _getBoostBestArea(i);
                if (bestArea > d.currentArea) {
                    d.currentArea = bestArea;
                }

                // Day variation
                uint8 variation = _rollDayVariation();
                uint256 maxAttempts = _getBoostMaxAttempts(i);
                uint256 attempts;
                if (variation == 0) attempts = 0;
                else if (variation == 1) attempts = maxAttempts / 2;
                else attempts = maxAttempts;

                for (uint256 a = 0; a < attempts; a++) {
                    if (d.inJail) break;
                    _playBoostPveAttempt(i);
                }
            }

            if (day % 25 == 0) {
                console.log("=== BOOST COMPARISON DAY %d ===", day);
                for (uint256 i = 0; i < 5; i++) {
                    uint8 tierIdx = _getTierIndex(boostDealers[i].rep);
                    console.log("  %s  rep=%d  tier=%s", boostNames[i], boostDealers[i].rep, _tierName(tierIdx));
                }
            }
        }

        console.log("");
        console.log("============================================================");
        console.log("          BOOST COMPARISON SUMMARY (PVE-ONLY, 100 DAYS)");
        console.log("============================================================");
        console.log("");

        for (uint256 i = 0; i < 5; i++) {
            SimDealer storage d = boostDealers[i];
            uint8 tierIdx = _getTierIndex(d.rep);
            console.log("--- %s ---", boostNames[i]);
            console.log("  Final Rep: %d (%s)", d.rep, _tierName(tierIdx));
            console.log("  PVE: %d W / %d T / %d L", d.pveWins, d.pveTies, d.pveLosses);
            console.log("  Jailed: %d times", d.jailCount);
            console.log("  ETH Spent: %d wei", d.ethSpent);
            console.log("");
        }
    }
}

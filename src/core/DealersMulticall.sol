// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {IDealersCore} from "./IDealersCore.sol";
import {IDealersPVE} from "./IDealersPVE.sol";
import {IDealersPVP} from "./IDealersPVP.sol";
import {IDealersBankHeist} from "./IDealersBankHeist.sol";
import {DealersBoosts} from "./DealersBoosts.sol";
import {IAreaRegistry} from "../utils/IAreaRegistry.sol";
import {IDrugRegistry} from "../utils/IDrugRegistry.sol";

/**
 * @title DealersMulticall - Read-Only Aggregator
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Batches multiple read calls into single responses for the frontend.
 *      Returns full dealer state, area economies, and drug balances in one call.
 * @author Berny0x
 */
contract DealersMulticall is Ownable {
    error ZeroAddress(string param);
    error DealerNotInitialized(uint256 tokenId);
    error InvalidAddress();

    /**
     * @notice A dealer's balance for a single drug type
     */
    struct DrugBalance {
        uint256 drugId;
        string name;
        uint256 balance;
        IDrugRegistry.DrugRarity rarity;
    }

    /**
     * @notice Complete snapshot of a dealer's game state, stats, and boost info
     */
    struct FullDealerState {
        uint256 reputation;
        uint256 stashBonusRep;
        uint8 currentArea;
        uint8 previousArea;
        uint8 heatLevel;
        uint8 dailyAttemptsRemaining;
        uint8 maxAttempts;
        uint8 threat;
        uint8 armor;
        bool isInitialized;
        bool isJailed;
        bool isInSafeHouse;
        uint16 jailChance;
        string reputationTitle;
        uint256 cashBalance;
        DrugBalance[] drugBalances;
        bool boostActive;
        uint64 boostExpiry;
        uint8 drugMultiplier;
        uint8 cashMultiplier;
        uint8 repMultiplier;
        bool freeAreaMovement;
        uint32 pveWins;
        uint32 pveLosses;
        uint32 pveTies;
        uint32 pvpAttackWins;
        uint32 pvpAttackLosses;
        uint32 pvpDefendWins;
        uint32 pvpDefendLosses;
        uint32 lastBreakoutAttempt;
        bool canBreakoutToday;
        uint8 attacksReceivedToday;
        uint8 maxAttacksPerDay;
        uint256 infamy;
    }

    /**
     * @notice Drug availability and pricing within a specific area
     */
    struct AreaDrug {
        uint256 drugId;
        string name;
        IDrugRegistry.DrugRarity rarity;
        uint256 buyPrice;
        uint256 sellPrice;
        bool isAvailable;
    }

    /**
     * @notice Full economic snapshot of an area including metadata, fees, and drug market
     */
    struct AreaEconomy {
        uint8 areaId;
        string areaName;
        uint256 movementFee;
        uint256 minReputation;
        bool isActive;
        bool isSafeHouse;
        bool isJail;
        uint256 dealerCount;
        AreaDrug[] drugs;
    }

    /**
     * @notice An attackable dealer with stats and win chances (PVP target browser)
     */
    struct PVPTarget {
        uint256 tokenId;
        uint256 reputation;
        uint8 threat;
        uint8 armor;
        uint8 attemptsRemaining;
        uint256 winChance;
        uint256 lossChance;
        bool canAttackNow;
        uint256 infamy;
    }

    /**
     * @notice One entrant's live standing in a bank-heist season (unsorted; rank is client-side)
     */
    struct HeistEntry {
        uint256 tokenId;
        uint256 pendingScore;
        uint32 focus;
    }

    /**
     * @notice A single dealer's full bank-heist season status (season-card view)
     */
    struct HeistDealerStatus {
        bool entered;
        uint256 pendingScore;
        uint256 frozenScore;
        uint32 focus;
        bool checkedInToday;
        bool claimed;
        bool refunded;
        uint256 claimableETH;
        uint96 refundableCash;
    }

    IDealersCore public core;
    IDealersPVE public pve;
    IDealersPVP public pvp;
    IAreaRegistry public areaRegistry;
    IDrugRegistry public drugRegistry;
    DealersBoosts public boosts;
    IDealersBankHeist public bankHeist;

    uint256 internal constant BPS = 10000;
    uint256 internal constant MAX_SETTLE_FEE_BPS = 100;

    constructor(address _core, address _pve, address _pvp, address _areaRegistry, address _drugRegistry) {
        if (_core == address(0)) revert ZeroAddress("core");
        if (_pve == address(0)) revert ZeroAddress("pve");
        if (_pvp == address(0)) revert ZeroAddress("pvp");
        if (_areaRegistry == address(0)) revert ZeroAddress("areaRegistry");
        if (_drugRegistry == address(0)) revert ZeroAddress("drugRegistry");

        _initializeOwner(msg.sender);

        core = IDealersCore(_core);
        pve = IDealersPVE(_pve);
        pvp = IDealersPVP(_pvp);
        areaRegistry = IAreaRegistry(_areaRegistry);
        drugRegistry = IDrugRegistry(_drugRegistry);
    }

    /**
     * @notice Set the core state contract
     * @param _core Address of the DealersCore contract
     */
    function setCore(address _core) external onlyOwner {
        if (_core == address(0)) revert InvalidAddress();
        core = IDealersCore(_core);
    }

    /**
     * @notice Set the PVE game module contract
     * @param _pve Address of the DealersPVE contract
     */
    function setPVE(address _pve) external onlyOwner {
        if (_pve == address(0)) revert InvalidAddress();
        pve = IDealersPVE(_pve);
    }

    /**
     * @notice Set the PVP battle module contract
     * @param _pvp Address of the DealersPVP contract
     */
    function setPVP(address _pvp) external onlyOwner {
        if (_pvp == address(0)) revert InvalidAddress();
        pvp = IDealersPVP(_pvp);
    }

    /**
     * @notice Set the area registry contract
     * @param _areaRegistry Address of the DealersAreaRegistry contract
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert InvalidAddress();
        areaRegistry = IAreaRegistry(_areaRegistry);
    }

    /**
     * @notice Set the drug registry contract
     * @param _drugRegistry Address of the DealersDrugRegistry contract
     */
    function setDrugRegistry(address _drugRegistry) external onlyOwner {
        if (_drugRegistry == address(0)) revert InvalidAddress();
        drugRegistry = IDrugRegistry(_drugRegistry);
    }

    /**
     * @notice Set the boosts module contract
     * @param _boosts Address of the DealersBoosts contract
     */
    function setBoosts(address _boosts) external onlyOwner {
        if (_boosts == address(0)) revert InvalidAddress();
        boosts = DealersBoosts(_boosts);
    }

    /**
     * @notice Set the bank-heist season contract
     * @param _bankHeist Address of the DealersBankHeist contract
     */
    function setBankHeist(address _bankHeist) external onlyOwner {
        if (_bankHeist == address(0)) revert InvalidAddress();
        bankHeist = IDealersBankHeist(_bankHeist);
    }

    /**
     * @notice Aggregate a dealer's full game state into a single call
     * @param tokenId The dealer NFT token ID
     * @return state Complete dealer state including stats, drugs, boosts, and PVE/PVP records
     */
    function getFullDealerState(uint256 tokenId) external view returns (FullDealerState memory state) {
        IDealersCore.GameState memory gs = core.getGameState(tokenId);

        if (!gs.isInitialized) revert DealerNotInitialized(tokenId);

        state.reputation = gs.totalReputation;
        state.stashBonusRep = gs.totalReputation - gs.reputation;
        state.currentArea = gs.currentArea;
        state.previousArea = gs.previousArea;
        state.heatLevel = core.getEffectiveHeat(tokenId);
        state.dailyAttemptsRemaining = gs.dailyAttemptsRemaining;
        state.maxAttempts = core.BASE_MAX_ATTEMPTS() + (gs.boostActive ? gs.extraAttempts : 0);
        state.isInitialized = true;
        state.isJailed = gs.isJailed;
        state.isInSafeHouse = gs.isInSafeHouse;
        state.jailChance = gs.jailChance;
        state.reputationTitle = core.getReputationTitle(gs.totalReputation);

        state.threat = gs.threat;
        state.armor = gs.armor;

        state.cashBalance = gs.cashBalance;

        uint256[] memory drugIds = drugRegistry.getAllDrugIds();
        uint256[] memory balances = core.getAreaDrugBalances(tokenId, drugIds);
        state.drugBalances = new DrugBalance[](drugIds.length);
        for (uint256 i = 0; i < drugIds.length;) {
            IDrugRegistry.DrugInfo memory info = drugRegistry.getDrugInfo(drugIds[i]);
            state.drugBalances[i] =
                DrugBalance({drugId: drugIds[i], name: info.name, balance: balances[i], rarity: info.rarity});
            unchecked {
                ++i;
            }
        }

        state.boostActive = gs.boostActive;
        if (gs.boostActive) {
            state.boostExpiry = gs.boostExpiresAt;
            state.drugMultiplier = gs.drugMultiplier;
            state.cashMultiplier = gs.cashMultiplier;
            state.repMultiplier = gs.repMultiplier;
            state.freeAreaMovement = gs.freeAreaMovement;
        }

        IDealersPVE.PveStats memory pveStats = pve.getDealerPveStats(tokenId);
        state.pveWins = pveStats.wins;
        state.pveLosses = pveStats.losses;
        state.pveTies = pveStats.ties;

        IDealersPVP.PvpStats memory pvpStats = pvp.getDealerPvpStats(tokenId);
        state.pvpAttackWins = pvpStats.attackWins;
        state.pvpAttackLosses = pvpStats.attackLosses;
        state.pvpDefendWins = pvpStats.defendWins;
        state.pvpDefendLosses = pvpStats.defendLosses;

        state.lastBreakoutAttempt = gs.lastBreakoutAttempt;
        uint256 dayStart = (block.timestamp / 1 days) * 1 days;
        state.canBreakoutToday = gs.lastBreakoutAttempt == 0 || gs.lastBreakoutAttempt < uint32(dayStart);

        state.infamy = core.getInfamy(tokenId);

        uint256 currentDay = block.timestamp / 1 days;
        state.maxAttacksPerDay = pvp.config().maxAttacksPerDay;
        if (pvp.lastAttackDay(tokenId) == currentDay) {
            uint256 received = pvp.attacksReceivedToday(tokenId);
            state.attacksReceivedToday = received > type(uint8).max ? type(uint8).max : uint8(received);
        }
    }

    /**
     * @notice Get the full economic state of a single area
     * @param areaId The area to query
     * @return Economy snapshot including drug market and dealer count
     */
    function getAreaEconomy(uint8 areaId) external view returns (AreaEconomy memory) {
        return _buildAreaEconomy(areaId);
    }

    /**
     * @notice Get economic snapshots for all areas (including safe house, jail, and black market)
     * @return economies Array of area economies ordered by area ID
     */
    function getAllAreas() external view returns (AreaEconomy[] memory economies) {
        uint8 totalAreas = areaRegistry.getTotalAreas();
        economies = new AreaEconomy[](totalAreas + 3);

        economies[0] = _buildAreaEconomy(0);
        for (uint8 i = 0; i < totalAreas;) {
            economies[i + 1] = _buildAreaEconomy(i + 1);
            unchecked {
                ++i;
            }
        }
        economies[totalAreas + 1] = _buildAreaEconomy(areaRegistry.BLACK_MARKET_AREA());
        economies[totalAreas + 2] = _buildAreaEconomy(areaRegistry.JAIL_AREA());
    }

    function _buildAreaEconomy(uint8 areaId) internal view returns (AreaEconomy memory economy) {
        IAreaRegistry.AreaInfo memory info = areaRegistry.getAreaInfo(areaId);

        economy.areaId = areaId;
        economy.areaName = info.name;
        economy.movementFee = info.movementFee;
        economy.minReputation = info.minReputation;
        economy.isActive = info.isActive;
        economy.isSafeHouse = info.isSafeHouse;
        economy.isJail = info.isJail;
        economy.dealerCount = areaRegistry.getDealerCountInArea(areaId);

        uint256[] memory drugIds = areaRegistry.getAreaDrugIds(areaId);
        economy.drugs = new AreaDrug[](drugIds.length);
        for (uint256 i = 0; i < drugIds.length;) {
            IAreaRegistry.AreaDrugConfig memory drugConfig = areaRegistry.getAreaDrugConfig(areaId, drugIds[i]);
            IDrugRegistry.DrugInfo memory drugInfo = drugRegistry.getDrugInfo(drugIds[i]);
            economy.drugs[i] = AreaDrug({
                drugId: drugIds[i],
                name: drugInfo.name,
                rarity: drugInfo.rarity,
                buyPrice: drugConfig.buyPrice,
                sellPrice: drugConfig.sellPrice,
                isAvailable: drugConfig.isAvailable
            });
            unchecked {
                ++i;
            }
        }
    }

    // =============================================================
    //                  PVE PREVIEW HELPERS
    // =============================================================

    /**
     * @notice Check whether a dealer can play a hustle round
     * @param tokenId The dealer NFT token ID
     * @return isPlayable True if the dealer can play
     * @return reason 0 = playable, 1 = not initialized, 2 = jailed, 3 = safe house, 4 = no attempts
     */
    function canPlay(uint256 tokenId) external view returns (bool isPlayable, uint8 reason) {
        IDealersCore.GameState memory state = core.getGameState(tokenId);
        if (!state.isInitialized) return (false, 1);
        if (state.isJailed) return (false, 2);
        if (state.isInSafeHouse) return (false, 3);
        if (state.dailyAttemptsRemaining == 0) return (false, 4);
        return (true, 0);
    }

    /**
     * @notice Preview reputation and cash outcomes for a potential hustle
     * @param tokenId The dealer NFT token ID
     * @param drugId The drug to preview
     * @param amount Quantity to preview
     * @return winRep Reputation gained on win
     * @return tieRep Reputation gained on tie
     * @return lossRep Reputation lost on loss (negative)
     * @return cashValueOnSell Cash earned if selling this amount
     * @return cashCostOnBuy Cash spent if buying this amount
     */
    function previewHustle(uint256 tokenId, uint256 drugId, uint256 amount)
        external
        view
        returns (int16 winRep, int16 tieRep, int16 lossRep, uint256 cashValueOnSell, uint256 cashCostOnBuy)
    {
        IDealersCore.GameState memory state = core.getGameState(tokenId);

        winRep = state.repWinBonus;
        tieRep = state.repTieBonus;
        lossRep = state.repLossPenalty;

        if (areaRegistry.isDrugAvailableInArea(state.currentArea, drugId)) {
            (uint256 buyPrice, uint256 sellPrice) = areaRegistry.getDrugPricing(state.currentArea, drugId);
            cashValueOnSell = amount * sellPrice;
            cashCostOnBuy = amount * buyPrice;
        }
    }

    // =============================================================
    //                  PVP PREVIEW HELPERS
    // =============================================================

    /**
     * @notice Calculate the attacker's win probability against a defender
     * @dev Mirrors DealersPVP._calcWinChance via pvp.config().
     * @param attackerId The attacker's dealer NFT token ID
     * @param defenderId The defender's dealer NFT token ID
     * @return Win chance as a percentage (25-75)
     */
    function calculateWinChance(uint256 attackerId, uint256 defenderId) public view returns (uint256) {
        (uint8 attackerThreat,) = core.getDealerStats(attackerId);
        (, uint8 defenderArmor) = core.getDealerStats(defenderId);

        return _calcWinChance(pvp.config(), attackerThreat, defenderArmor);
    }

    /**
     * @notice Check whether an attack is possible between two dealers
     * @dev Mirrors DealersPVP._validateCommitAttack — the module re-validates at commit.
     * @param attackerId The attacker's dealer NFT token ID
     * @param defenderId The defender's dealer NFT token ID
     * @return canFight True if the attack can proceed
     * @return reason 0 = can attack, 1-12 = specific blocker (same dealer, not init, jailed, etc.)
     */
    function canAttack(uint256 attackerId, uint256 defenderId) external view returns (bool canFight, uint8 reason) {
        if (attackerId == defenderId) return (false, 1);

        (IDealersCore.GameState memory atkState, IDealersCore.GameState memory defState) =
            core.getBothGameStates(attackerId, defenderId);

        if (!atkState.isInitialized) return (false, 2);
        if (!defState.isInitialized) return (false, 3);

        if (atkState.isJailed) return (false, 4);
        if (atkState.isInSafeHouse) return (false, 5);
        if (defState.isJailed) return (false, 6);
        if (defState.isInSafeHouse) return (false, 7);

        if (atkState.currentArea != defState.currentArea) return (false, 8);

        if (atkState.dailyAttemptsRemaining == 0) return (false, 9);

        IDealersPVP.PVPConfig memory cfg = pvp.config();

        if (!_isDefenderAvailable(defenderId, cfg.maxAttacksPerDay)) return (false, 10);

        if (!_isInRepRange(cfg, atkState.totalReputation, defState.totalReputation)) return (false, 11);

        if (cfg.minReputation > 0) {
            if (atkState.totalReputation < cfg.minReputation || defState.totalReputation < cfg.minReputation) {
                return (false, 12);
            }
        }

        return (true, 0);
    }

    /**
     * @notice Get paginated list of valid PVP targets in the attacker's current area
     * @param attackerId The attacker's dealer NFT token ID
     * @param offset Number of matches to skip (for pagination)
     * @param limit Maximum number of targets to return
     * @return targets Array of attackable dealers with stats and win chances
     * @return totalInArea Total dealers in the area (before filtering)
     */
    function getPotentialTargets(uint256 attackerId, uint256 offset, uint256 limit)
        external
        view
        returns (PVPTarget[] memory targets, uint256 totalInArea)
    {
        IDealersCore.GameState memory atkState = core.getGameState(attackerId);
        if (!atkState.isInitialized) return (new PVPTarget[](0), 0);

        (uint256[] memory dealersInArea, uint256 total) =
            areaRegistry.getDealersInArea(atkState.currentArea, 0, type(uint256).max);
        totalInArea = total;

        if (total == 0 || limit == 0) return (new PVPTarget[](0), total);

        IDealersPVP.PVPConfig memory cfg = pvp.config();
        PVPTarget[] memory tempTargets = new PVPTarget[](total);
        uint256 matchCount = 0;

        for (uint256 i = 0; i < dealersInArea.length;) {
            uint256 tokenId = dealersInArea[i];

            if (tokenId == attackerId) {
                unchecked {
                    ++i;
                }
                continue;
            }

            IDealersCore.GameState memory candState = core.getGameState(tokenId);

            if (!candState.isInitialized || candState.isJailed || candState.isInSafeHouse) {
                unchecked {
                    ++i;
                }
                continue;
            }

            if (cfg.minReputation > 0 && candState.totalReputation < cfg.minReputation) {
                unchecked {
                    ++i;
                }
                continue;
            }

            if (!_isInRepRange(cfg, atkState.totalReputation, candState.totalReputation)) {
                unchecked {
                    ++i;
                }
                continue;
            }

            uint256 winChancePct = _calcWinChance(cfg, atkState.threat, candState.armor);

            tempTargets[matchCount] = PVPTarget({
                tokenId: tokenId,
                reputation: candState.totalReputation,
                threat: candState.threat,
                armor: candState.armor,
                attemptsRemaining: candState.dailyAttemptsRemaining,
                winChance: winChancePct,
                lossChance: 100 - winChancePct,
                canAttackNow: _isDefenderAvailable(tokenId, cfg.maxAttacksPerDay),
                infamy: candState.infamy
            });

            unchecked {
                ++matchCount;
            }
            unchecked {
                ++i;
            }
        }

        if (matchCount == 0) return (new PVPTarget[](0), total);

        if (offset >= matchCount) return (new PVPTarget[](0), total);

        uint256 end = offset + limit;
        if (end > matchCount) end = matchCount;
        uint256 resultLength = end - offset;

        targets = new PVPTarget[](resultLength);
        for (uint256 i = 0; i < resultLength;) {
            targets[i] = tempTargets[offset + i];
            unchecked {
                ++i;
            }
        }

        return (targets, total);
    }

    function _calcWinChance(IDealersPVP.PVPConfig memory cfg, uint8 attackerThreat, uint8 defenderArmor)
        private
        pure
        returns (uint256)
    {
        int256 statModifier = int256(uint256(attackerThreat)) - int256(uint256(defenderArmor));
        int256 finalChance = int256(uint256(cfg.baseWinChance)) + statModifier;
        if (finalChance < int256(uint256(cfg.minWinChance))) return cfg.minWinChance;
        if (finalChance > int256(uint256(cfg.maxWinChance))) return cfg.maxWinChance;
        return uint256(finalChance);
    }

    function _isInRepRange(IDealersPVP.PVPConfig memory cfg, uint256 attackerRep, uint256 defenderRep)
        private
        pure
        returns (bool)
    {
        uint256 threshold = cfg.repRangeThreshold;
        if (threshold > 0 && attackerRep >= threshold && defenderRep >= threshold) {
            return true;
        }

        uint256 range = attackerRep * cfg.repRangePercent / 100;
        uint256 minRep = attackerRep > range ? attackerRep - range : 0;
        uint256 maxRep = (threshold > 0 && attackerRep >= threshold) ? type(uint256).max : attackerRep + range;
        return defenderRep >= minRep && defenderRep <= maxRep;
    }

    function _isDefenderAvailable(uint256 defenderId, uint8 maxAttacksPerDay) private view returns (bool) {
        uint256 currentDay = block.timestamp / 1 days;
        if (pvp.lastAttackDay(defenderId) == currentDay && pvp.attacksReceivedToday(defenderId) >= maxAttacksPerDay) {
            return false;
        }
        return true;
    }

    // =============================================================
    //                  BOOST PREVIEW HELPERS
    // =============================================================

    /**
     * @notice Get all active boost tiers
     * @return tiers Array of all active boost tiers
     * @return tierIds Array of tier IDs corresponding to the tiers
     */
    function getActiveTiers()
        external
        view
        returns (DealersBoosts.BoostTier[] memory tiers, uint256[] memory tierIds)
    {
        uint256 totalTiers = boosts.totalTiers();

        uint256 activeCount = 0;
        for (uint256 i = 1; i <= totalTiers;) {
            if (boosts.getBoostTier(i).isActive) {
                unchecked {
                    ++activeCount;
                }
            }
            unchecked {
                ++i;
            }
        }

        tiers = new DealersBoosts.BoostTier[](activeCount);
        tierIds = new uint256[](activeCount);

        uint256 index = 0;
        for (uint256 i = 1; i <= totalTiers;) {
            DealersBoosts.BoostTier memory tier = boosts.getBoostTier(i);
            if (tier.isActive) {
                tiers[index] = tier;
                tierIds[index] = i;
                unchecked {
                    ++index;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Check if a dealer currently has an active boost
     * @param dealerId The dealer ID to check
     * @return hasBoost Whether the dealer has an active boost
     * @return expiresAt When the boost expires (0 if no boost)
     */
    function checkBoostStatus(uint256 dealerId) external view returns (bool hasBoost, uint64 expiresAt) {
        hasBoost = core.hasActiveBoost(dealerId);
        if (hasBoost) {
            IDealersCore.BoostData memory boost = core.getBoost(dealerId);
            expiresAt = boost.expiresAt;
        }
    }

    /**
     * @notice Calculate total cost for a batch boost purchase
     * @param dealerCount Number of dealers to boost
     * @param tierId The tier to purchase
     * @return totalCost Total ETH required
     */
    function calculateBatchCost(uint256 dealerCount, uint256 tierId) external view returns (uint256 totalCost) {
        return boosts.getBoostTier(tierId).price * dealerCount;
    }

    // =============================================================
    //                  BANK HEIST SEASON VIEWS
    // =============================================================

    /**
     * @notice Paginated live standings for a bank-heist season, in entry order (unsorted).
     * @dev Rank and cut are client-side: page until start >= entryCount, sort by pendingScore
     *      descending, cut = pendingScore / sum(all pages) x estPot. Each entry costs three
     *      cross-module staticcalls, so keep pages in the low hundreds to stay inside RPC
     *      eth_call gas caps.
     * @param seasonId The season identifier
     * @param start First entry index (entry order)
     * @param count Max entries to return
     * @return entries Entrants [start, min(start + count, entryCount))
     * @return entryCount Total entrants in the season
     * @return sumPending Sum of pendingScore over the returned page only
     * @return estPot Projected pot (live estimate until settle, then the reserved pot)
     */
    function getHeistStandings(uint256 seasonId, uint256 start, uint256 count)
        external
        view
        returns (HeistEntry[] memory entries, uint256 entryCount, uint256 sumPending, uint256 estPot)
    {
        IDealersBankHeist.Season memory s = bankHeist.getSeason(seasonId);
        entryCount = s.entryCount;
        estPot = _estimatedPot(s);

        if (start >= entryCount || count == 0) return (new HeistEntry[](0), entryCount, 0, estPot);
        uint256 remaining = entryCount - start;
        uint256 end = start + (count > remaining ? remaining : count);

        entries = new HeistEntry[](end - start);
        for (uint256 i = start; i < end;) {
            uint256 tokenId = bankHeist.entryAt(seasonId, i);
            uint256 score = bankHeist.pendingScore(seasonId, tokenId);
            (uint32 focus,,) = bankHeist.focusState(seasonId, tokenId);
            entries[i - start] = HeistEntry({tokenId: tokenId, pendingScore: score, focus: focus});
            sumPending += score;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice A dealer's full status for a bank-heist season in one read: live and frozen score,
     *         focus, check-in state, and what is claimable or refundable right now.
     * @dev claimableETH / refundableCash mirror the guards in BankHeist {claim} / {claimRefund},
     *      so a non-zero value means the corresponding call would succeed for the dealer owner.
     */
    function getHeistDealerStatus(uint256 seasonId, uint256 tokenId)
        external
        view
        returns (HeistDealerStatus memory status)
    {
        status.entered = bankHeist.entered(seasonId, tokenId);
        if (!status.entered) return status;

        IDealersBankHeist.Season memory s = bankHeist.getSeason(seasonId);

        status.pendingScore = bankHeist.pendingScore(seasonId, tokenId);
        status.frozenScore = bankHeist.scoreOf(seasonId, tokenId);
        (uint32 focus, uint32 lastDay,) = bankHeist.focusState(seasonId, tokenId);
        status.focus = focus;
        status.checkedInToday = lastDay == uint32(block.timestamp / 1 days);
        status.claimed = bankHeist.claimed(seasonId, tokenId);
        status.refunded = bankHeist.refunded(seasonId, tokenId);

        if (
            s.settled && !status.claimed && status.frozenScore != 0
                && block.timestamp <= uint256(s.settledAt) + s.config.claimWindow
        ) {
            status.claimableETH = (s.pot * status.frozenScore) / s.totalScore;
        }

        bool abandoned = !s.settled && block.timestamp > uint256(s.closesAt) + s.config.refundTimeout;
        if (!status.refunded && (s.skipped || abandoned)) {
            status.refundableCash = s.config.entryFee;
        }
    }

    /** @dev Mirrors BankHeist {settle}: pot = (avail - tip) x potBps / BPS with the tip capped at
     *       1% of avail. A settled season returns its reserved pot; a skipped one returns 0. */
    function _estimatedPot(IDealersBankHeist.Season memory s) private view returns (uint256) {
        if (s.settled) return s.pot;
        if (s.skipped) return 0;
        uint256 avail = bankHeist.availableVault();
        uint256 maxFee = (avail * MAX_SETTLE_FEE_BPS) / BPS;
        uint256 fee = bankHeist.settleFee();
        if (fee > maxFee) fee = maxFee;
        return ((avail - fee) * s.config.potBps) / BPS;
    }
}

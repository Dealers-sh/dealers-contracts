// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDealersExeCore} from "./IDealersExeCore.sol";
import {IDealersExePVE} from "./IDealersExePVE.sol";
import {IDealersExePVP} from "./IDealersExePVP.sol";
import {IAreaRegistry} from "../utils/IAreaRegistry.sol";
import {IDrugRegistry} from "../utils/IDrugRegistry.sol";

contract DealersExeMulticall {
    error ZeroAddress(string param);
    error DealerNotInitialized(uint256 tokenId);

    struct DrugBalance {
        uint256 drugId;
        string name;
        uint256 balance;
        IDrugRegistry.DrugRarity rarity;
    }

    struct FullDealerState {
        uint256 reputation;
        uint256 stashBonusRep;
        uint8 currentArea;
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
    }

    struct AreaDrug {
        uint256 drugId;
        string name;
        IDrugRegistry.DrugRarity rarity;
        uint256 buyPrice;
        uint256 sellPrice;
        uint256 globalSupply;
        bool isAvailable;
    }

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

    IDealersExeCore public immutable core;
    IDealersExePVE public immutable pve;
    IDealersExePVP public immutable pvp;
    IAreaRegistry public immutable areaRegistry;
    IDrugRegistry public immutable drugRegistry;

    constructor(
        address _core,
        address _pve,
        address _pvp,
        address _areaRegistry,
        address _drugRegistry
    ) {
        if (_core == address(0)) revert ZeroAddress("core");
        if (_pve == address(0)) revert ZeroAddress("pve");
        if (_pvp == address(0)) revert ZeroAddress("pvp");
        if (_areaRegistry == address(0)) revert ZeroAddress("areaRegistry");
        if (_drugRegistry == address(0)) revert ZeroAddress("drugRegistry");

        core = IDealersExeCore(_core);
        pve = IDealersExePVE(_pve);
        pvp = IDealersExePVP(_pvp);
        areaRegistry = IAreaRegistry(_areaRegistry);
        drugRegistry = IDrugRegistry(_drugRegistry);
    }

    function getFullDealerState(uint256 tokenId) external view returns (FullDealerState memory state) {
        (
            uint8 currentArea,
            uint256 reputation,
            uint8 dailyAttemptsRemaining,
            uint8 heatLevel,
            ,
            bool isInitialized
        ) = core.getDealerData(tokenId);

        if (!isInitialized) revert DealerNotInitialized(tokenId);

        state.stashBonusRep = core.getStashBonus(tokenId);
        state.reputation = reputation + state.stashBonusRep;
        state.currentArea = currentArea;
        state.heatLevel = heatLevel;
        state.dailyAttemptsRemaining = dailyAttemptsRemaining;
        state.maxAttempts = core.getMaxAttempts(tokenId);
        state.isInitialized = true;
        state.isJailed = core.isInJail(tokenId);
        state.isInSafeHouse = core.isInSafeHouse(tokenId);
        state.jailChance = core.getJailChance(tokenId);
        state.reputationTitle = core.getReputationTitle(state.reputation);

        (uint8 threat, uint8 armor) = core.getDealerStats(tokenId);
        state.threat = threat;
        state.armor = armor;

        state.cashBalance = core.getCashBalance(tokenId);

        uint256[] memory drugIds = drugRegistry.getAllDrugIds();
        state.drugBalances = new DrugBalance[](drugIds.length);
        for (uint256 i = 0; i < drugIds.length;) {
            IDrugRegistry.DrugInfo memory info = drugRegistry.getDrugInfo(drugIds[i]);
            state.drugBalances[i] = DrugBalance({
                drugId: drugIds[i],
                name: info.name,
                balance: core.getDrugBalance(tokenId, drugIds[i]),
                rarity: info.rarity
            });
            unchecked { ++i; }
        }

        state.boostActive = core.hasActiveBoost(tokenId);
        if (state.boostActive) {
            IDealersExeCore.BoostData memory boost = core.getBoost(tokenId);
            state.boostExpiry = boost.expiresAt;
            state.drugMultiplier = boost.drugMultiplier;
            state.cashMultiplier = boost.cashMultiplier;
            state.repMultiplier = boost.repMultiplier;
            state.freeAreaMovement = boost.freeAreaMovement;
        }

        IDealersExePVE.PveStats memory pveStats = pve.getDealerPveStats(tokenId);
        state.pveWins = pveStats.wins;
        state.pveLosses = pveStats.losses;
        state.pveTies = pveStats.ties;

        IDealersExePVP.PvpStats memory pvpStats = pvp.getDealerPvpStats(tokenId);
        state.pvpAttackWins = pvpStats.attackWins;
        state.pvpAttackLosses = pvpStats.attackLosses;
        state.pvpDefendWins = pvpStats.defendWins;
        state.pvpDefendLosses = pvpStats.defendLosses;

        (,, uint32 lastBreakout,,,,,) = core.dealers(tokenId);
        state.lastBreakoutAttempt = lastBreakout;
        uint256 dayStart = (block.timestamp / 1 days) * 1 days;
        state.canBreakoutToday = lastBreakout == 0 || lastBreakout < uint32(dayStart);

        uint256 currentDay = block.timestamp / 1 days;
        (,,,,uint8 maxAttacksPerDay,,,,,,,) = pvp.config();
        state.maxAttacksPerDay = maxAttacksPerDay;
        if (pvp.lastAttackDay(tokenId) == currentDay) {
            uint256 received = pvp.attacksReceivedToday(tokenId);
            state.attacksReceivedToday = uint8(received);
        }
    }

    function getAreaEconomy(uint8 areaId) external view returns (AreaEconomy memory) {
        return _buildAreaEconomy(areaId);
    }

    function getAllAreas() external view returns (AreaEconomy[] memory economies) {
        uint8 totalAreas = areaRegistry.getTotalAreas();
        economies = new AreaEconomy[](totalAreas + 2);

        economies[0] = _buildAreaEconomy(0);
        for (uint8 i = 0; i < totalAreas;) {
            economies[i + 1] = _buildAreaEconomy(i + 1);
            unchecked { ++i; }
        }
        economies[totalAreas + 1] = _buildAreaEconomy(255);
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
                globalSupply: drugInfo.totalSupply,
                isAvailable: drugConfig.isAvailable
            });
            unchecked { ++i; }
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {IDealersCore} from "./IDealersCore.sol";
import {IDealersPVE} from "./IDealersPVE.sol";
import {IDealersPVP} from "./IDealersPVP.sol";
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

    IDealersCore public core;
    IDealersPVE public pve;
    IDealersPVP public pvp;
    IAreaRegistry public areaRegistry;
    IDrugRegistry public drugRegistry;

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
}

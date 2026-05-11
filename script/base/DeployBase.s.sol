// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

// =============================================================================
//                            SHARED STRUCTS
// =============================================================================

struct ReputationTier {
    uint256 minReputation;
    int16 winBonus;
    int16 tieBonus;
    int16 lossPenalty;
    int16 repCap;
    string tierName;
}

// =============================================================================
//                          INTERFACE DEFINITIONS
// =============================================================================

interface IDealersCore {
    function authorizeContract(address contractAddress, bool authorized) external;
    function setNFTContract(address _nftContract) external;
    function setPaymentHandler(address _paymentHandler) external;
    function setDrugRegistry(address _drugRegistry) external;
    function setAreaRegistry(address _areaRegistry) external;
    function setReputationTiers(ReputationTier[] calldata _tiers) external;
    function setMaxReputation(uint256 newMax) external;
    function drugRegistry() external view returns (address);
    function areaRegistry() external view returns (address);
    function nftContract() external view returns (address);
    function paymentHandler() external view returns (address);
    function authorizedContracts(address) external view returns (bool);
    function initializeDealer(uint256 tokenId) external;
    function updateReputation(uint256 tokenId, int256 change) external;
    function updateInfamy(uint256 tokenId, int256 delta) external;
    function reputationTiers(uint256 index) external view returns (
        uint256 minReputation, int16 winBonus, int16 tieBonus, int16 lossPenalty, int16 repCap, string memory tierName
    );
}

interface IDealersNFT {
    function setDealersCore(address _core) external;
    function dealersCore() external view returns (address);
}

interface IDrugRegistry {
    function authorizeContract(address contractAddress, bool authorized) external;
    function authorizedContracts(address) external view returns (bool);
    function createDrug(string calldata name, uint8 rarity, uint256 baseCashValue) external returns (uint256);
    function getTotalDrugs() external view returns (uint256);
}

interface IPaymentHandler {
    function authorizeContract(address contractAddress, bool authorized) external;
    function authorizedContracts(address) external view returns (bool);
}

interface IAreaRegistry {
    function setCoreContract(address _coreContract) external;
    function coreContract() external view returns (address);
    function createArea(string calldata name, uint256 movementFee, uint256 minReputation, bool isSafeHouseArea, bool isJailArea) external returns (uint8);
    function batchConfigureAreaDrugs(uint8 areaId, uint256[] calldata drugIds, uint256[] calldata buyPrices, uint256[] calldata sellPrices) external;
    function getTotalAreas() external view returns (uint8);
}

interface IPVPContract {
    function setCore(address _core) external;
    function setDrugRegistry(address _drugRegistry) external;
    function setAreaRegistry(address _areaRegistry) external;
    function setRandomness(address _randomness) external;
    function setActions(address _actions) external;
    function core() external view returns (address);
    function drugRegistry() external view returns (address);
    function areaRegistry() external view returns (address);
    function randomness() external view returns (address);
    function actions() external view returns (address);
}

interface IPVEContract {
    function setDealersCore(address _core) external;
    function setAreaRegistry(address _areaRegistry) external;
    function setRandomness(address _randomness) external;
    function setActions(address _actions) external;
    function dealersCore() external view returns (address);
    function areaRegistry() external view returns (address);
    function randomness() external view returns (address);
    function actions() external view returns (address);
}

interface IRandomness {
    function authorizeResolver(address resolver, bool authorized) external;
    function isAuthorizedResolver(address resolver) external view returns (bool);
}

interface IBoostsContract {
    function setDealersCore(address _core) external;
    function setDealersNFT(address _nft) external;
    function setPaymentHandler(address _handler) external;
    function dealersCore() external view returns (address);
    function dealersNFT() external view returns (address);
    function paymentHandler() external view returns (address);
}

interface IClaimsContract {
    struct Achievement {
        uint8 conditionType;
        uint256 conditionValue;
        uint256 threshold;
        uint8 rewardType;
        uint256 rewardId;
        uint256 rewardAmount;
        bool active;
    }
    function setAchievement(uint256 achievementId, Achievement calldata achievement) external;
    function setDealersCore(address _core) external;
    function setDealersNFT(address _nft) external;
    function setPVE(address _pve) external;
    function setPVP(address _pvp) external;
    function dealersCore() external view returns (address);
    function dealersNFT() external view returns (address);
    function pveContract() external view returns (address);
    function pvpContract() external view returns (address);
    function achievementCount() external view returns (uint256);
}

interface IActionsContract {
    function setPaymentHandler(address _handler) external;
    function setRandomness(address _randomness) external;
    function setAreaRegistry(address _areaRegistry) external;
    function authorizeJailer(address module, bool authorized) external;
    function paymentHandler() external view returns (address);
    function randomness() external view returns (address);
    function areaRegistry() external view returns (address);
    function authorizedJailers(address) external view returns (bool);
}

interface IMulticallContract {
    function setCore(address _core) external;
    function setPVE(address _pve) external;
    function setPVP(address _pvp) external;
    function setAreaRegistry(address _areaRegistry) external;
    function setDrugRegistry(address _drugRegistry) external;
    function core() external view returns (address);
    function pve() external view returns (address);
    function pvp() external view returns (address);
    function areaRegistry() external view returns (address);
    function drugRegistry() external view returns (address);
}

interface IChatFactory {
    enum RoomType { WORLD, AREA, GANG, DM }
    function createRoom(RoomType roomType, uint8 id, address gate) external returns (address room);
    function getRoomInfo(bytes32 roomKey) external view returns (address room, address gate, uint8 roomId);
    function roomKey(RoomType roomType, uint8 id) external pure returns (bytes32);
}

// =============================================================================
//                              BASE CONTRACT
// =============================================================================

abstract contract DeployBase is Script {
    // Contract addresses
    address public drugRegistry;
    address public areaRegistry;
    address public core;
    address public paymentHandler;
    address public randomness;
    address public nft;
    address public boosts;
    address public pve;
    address public pvp;
    address public claims;
    address public actions;
    address public rendererSvg;
    address public rendererHtml;
    address public multicall;
    address public chatFactory;

    // Config values
    string public gzipFilename;

    // Wallet addresses
    address public devWallet;
    address public bankVault;
    address public royaltyReceiver;

    // =========================================================================
    //                         ADDRESS PERSISTENCE
    // =========================================================================

    function _getDeploymentPath() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 11124) return "script/data/deployments/testnet.json";
        if (chainId == 2741) return "script/data/deployments/mainnet.json";
        return "script/data/deployments/local.json";
    }

    function _loadAddresses() internal {
        string memory path = _getDeploymentPath();
        try vm.readFile(path) returns (string memory json) {
            drugRegistry = _jsonAddrOr(json, ".drugRegistry", "DRUG_REGISTRY");
            areaRegistry = _jsonAddrOr(json, ".areaRegistry", "AREA_REGISTRY");
            core = _jsonAddrOr(json, ".core", "DEALERS_CORE");
            paymentHandler = _jsonAddrOr(json, ".paymentHandler", "PAYMENT_HANDLER");
            randomness = _jsonAddrOr(json, ".randomness", "RANDOMNESS");
            nft = _jsonAddrOr(json, ".nft", "DEALERS_NFT");
            boosts = _jsonAddrOr(json, ".boosts", "DEALERS_BOOSTS");
            pve = _jsonAddrOr(json, ".pve", "DEALERS_PVE");
            pvp = _jsonAddrOr(json, ".pvp", "DEALERS_PVP");
            claims = _jsonAddrOr(json, ".claims", "DEALERS_CLAIMS");
            actions = _jsonAddrOr(json, ".actions", "DEALERS_ACTIONS");
            rendererSvg = _jsonAddrOr(json, ".rendererSvg", "RENDERER_SVG");
            rendererHtml = _jsonAddrOr(json, ".rendererHtml", "RENDERER_HTML");
            multicall = _jsonAddrOr(json, ".multicall", "DEALER_MULTICALL");
            chatFactory = _jsonAddrOr(json, ".chatFactory", "CHAT_FACTORY");
            try vm.parseJsonString(json, ".gzipFilename") returns (string memory val) {
                gzipFilename = val;
            } catch {}
        } catch {
            drugRegistry = vm.envOr("DRUG_REGISTRY", address(0));
            areaRegistry = vm.envOr("AREA_REGISTRY", address(0));
            core = vm.envOr("DEALERS_CORE", address(0));
            paymentHandler = vm.envOr("PAYMENT_HANDLER", address(0));
            randomness = vm.envOr("RANDOMNESS", address(0));
            nft = vm.envOr("DEALERS_NFT", address(0));
            boosts = vm.envOr("DEALERS_BOOSTS", address(0));
            pve = vm.envOr("DEALERS_PVE", address(0));
            pvp = vm.envOr("DEALERS_PVP", address(0));
            claims = vm.envOr("DEALERS_CLAIMS", address(0));
            actions = vm.envOr("DEALERS_ACTIONS", address(0));
            rendererSvg = vm.envOr("RENDERER_SVG", address(0));
            rendererHtml = vm.envOr("RENDERER_HTML", address(0));
            multicall = vm.envOr("DEALER_MULTICALL", address(0));
            chatFactory = vm.envOr("CHAT_FACTORY", address(0));
        }

        devWallet = vm.envOr("DEV_WALLET", address(0));
        bankVault = vm.envOr("BANK_VAULT", address(0));
        royaltyReceiver = vm.envOr("ROYALTY_RECEIVER", address(0));
    }

    function _jsonAddrOr(string memory json, string memory key, string memory envKey) internal returns (address) {
        try vm.parseJsonAddress(json, key) returns (address val) {
            if (val != address(0)) return val;
        } catch {}
        return vm.envOr(envKey, address(0));
    }

    function _saveAddresses() internal {
        _mergeExistingAddresses();

        string memory obj = "deploy";
        vm.serializeAddress(obj, "drugRegistry", drugRegistry);
        vm.serializeAddress(obj, "areaRegistry", areaRegistry);
        vm.serializeAddress(obj, "core", core);
        vm.serializeAddress(obj, "paymentHandler", paymentHandler);
        vm.serializeAddress(obj, "randomness", randomness);
        vm.serializeAddress(obj, "nft", nft);
        vm.serializeAddress(obj, "boosts", boosts);
        vm.serializeAddress(obj, "pve", pve);
        vm.serializeAddress(obj, "pvp", pvp);
        vm.serializeAddress(obj, "claims", claims);
        vm.serializeAddress(obj, "actions", actions);
        vm.serializeAddress(obj, "rendererSvg", rendererSvg);
        vm.serializeAddress(obj, "rendererHtml", rendererHtml);
        vm.serializeAddress(obj, "multicall", multicall);
        if (bytes(gzipFilename).length > 0) {
            vm.serializeString(obj, "gzipFilename", gzipFilename);
        }
        string memory json = vm.serializeAddress(obj, "chatFactory", chatFactory);

        string memory path = _getDeploymentPath();
        vm.writeJson(json, path);
        console.log("Addresses saved to:", path);
    }

    function _mergeExistingAddresses() internal {
        string memory path = _getDeploymentPath();
        try vm.readFile(path) returns (string memory json) {
            if (drugRegistry == address(0)) drugRegistry = _jsonAddr(json, ".drugRegistry");
            if (areaRegistry == address(0)) areaRegistry = _jsonAddr(json, ".areaRegistry");
            if (core == address(0)) core = _jsonAddr(json, ".core");
            if (paymentHandler == address(0)) paymentHandler = _jsonAddr(json, ".paymentHandler");
            if (randomness == address(0)) randomness = _jsonAddr(json, ".randomness");
            if (nft == address(0)) nft = _jsonAddr(json, ".nft");
            if (boosts == address(0)) boosts = _jsonAddr(json, ".boosts");
            if (pve == address(0)) pve = _jsonAddr(json, ".pve");
            if (pvp == address(0)) pvp = _jsonAddr(json, ".pvp");
            if (claims == address(0)) claims = _jsonAddr(json, ".claims");
            if (actions == address(0)) actions = _jsonAddr(json, ".actions");
            if (rendererSvg == address(0)) rendererSvg = _jsonAddr(json, ".rendererSvg");
            if (rendererHtml == address(0)) rendererHtml = _jsonAddr(json, ".rendererHtml");
            if (multicall == address(0)) multicall = _jsonAddr(json, ".multicall");
            if (chatFactory == address(0)) chatFactory = _jsonAddr(json, ".chatFactory");
        } catch {}
    }

    function _jsonAddr(string memory json, string memory key) internal returns (address) {
        try vm.parseJsonAddress(json, key) returns (address val) {
            return val;
        } catch {
            return address(0);
        }
    }

    // =========================================================================
    //                            UTILITIES
    // =========================================================================

    function _requireAddress(address addr, string memory name) internal pure {
        require(addr != address(0), string.concat(name, " not set"));
    }

    function _zkCreate(bytes memory bytecode) internal returns (address deployed) {
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "Deployment failed");
    }
}

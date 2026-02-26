// SPDX-License-Identifier: MIT
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

interface IDealersExeCore {
    function authorizeContract(address contractAddress, bool authorized) external;
    function setNFTContract(address _nftContract) external;
    function setPaymentHandler(address _paymentHandler) external;
    function setDrugRegistry(address _drugRegistry) external;
    function setAreaRegistry(address _areaRegistry) external;
    function setRandomness(address _randomness) external;
    function setReputationTiers(ReputationTier[] calldata _tiers) external;
    function setMaxReputation(uint256 newMax) external;
    function drugRegistry() external view returns (address);
    function areaRegistry() external view returns (address);
    function nftContract() external view returns (address);
    function paymentHandler() external view returns (address);
    function randomness() external view returns (address);
    function authorizedContracts(address) external view returns (bool);
    function getTierCount() external view returns (uint256);
}

interface IDealersExeNFT {
    function setDealersExeCore(address _core) external;
    function dealersExeCore() external view returns (address);
}

interface IDrugRegistry {
    function authorizeContract(address contractAddress, bool authorized) external;
    function authorizedContracts(address) external view returns (bool);
}

interface IPaymentHandler {
    function authorizeContract(address contractAddress, bool authorized) external;
    function authorizedContracts(address) external view returns (bool);
}

interface IAreaRegistry {
    function setCoreContract(address _coreContract) external;
    function coreContract() external view returns (address);
}

interface IPVPContract {
    function setCore(address _core) external;
    function setDrugRegistry(address _drugRegistry) external;
    function setRandomness(address _randomness) external;
    function core() external view returns (address);
    function drugRegistry() external view returns (address);
    function randomness() external view returns (address);
}

interface IPVEContract {
    function setDealersExeCore(address _core) external;
    function setRandomness(address _randomness) external;
    function dealersExeCore() external view returns (address);
    function randomness() external view returns (address);
}

interface IRandomness {
    function authorizeResolver(address resolver, bool authorized) external;
    function isAuthorizedResolver(address resolver) external view returns (bool);
}

interface IBoostsContract {
    function setDealersExeCore(address _core) external;
    function setDealersExeNFT(address _nft) external;
    function setPaymentHandler(address _handler) external;
    function dealersExeCore() external view returns (address);
    function dealersExeNFT() external view returns (address);
    function paymentHandler() external view returns (address);
}

interface IClaimsContract {
    function setDealersExeCore(address _core) external;
    function setDealersExeNFT(address _nft) external;
    function setPVE(address _pve) external;
    function setPVP(address _pvp) external;
    function dealersExeCore() external view returns (address);
    function dealersExeNFT() external view returns (address);
    function pveContract() external view returns (address);
    function pvpContract() external view returns (address);
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

    // Wallet addresses
    address public devWallet;
    address public bankVault;
    address public royaltyReceiver;

    function _loadAddresses() internal {
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
        devWallet = vm.envOr("DEV_WALLET", address(0));
        bankVault = vm.envOr("BANK_VAULT", address(0));
        royaltyReceiver = vm.envOr("ROYALTY_RECEIVER", address(0));
    }

    function _requireAddress(address addr, string memory name) internal pure {
        require(addr != address(0), string.concat(name, " not set in .env"));
    }

    function _zkCreate(bytes memory bytecode) internal returns (address deployed) {
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "Deployment failed");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

/**
 * @title SetupAuthorization - Phase 1 Post-Deployment Authorization Script
 * @notice Foundry script to configure all contract authorizations for Phase 1 launch
 * @dev Run this script after deploying all Phase 1 contracts
 *
 * ============================================================================
 *                           PHASE 1 CONTRACTS
 * ============================================================================
 *
 * This script handles authorization for the initial launch:
 * - DealersExeCore (central state hub)
 * - DealersExeNFT (dealer NFTs)
 * - DealersExePVE (player vs environment gameplay)
 * - DealersExePVP (player vs player combat)
 * - DealersExeBoosts (premium boost purchases)
 * - DEDrugRegistry (global drug definitions)
 * - DEAreaRegistry (area & pricing config)
 * - DEPaymentHandler (ETH fee distribution)
 *
 * Phase 2 contracts (Items, Heist, Gangs) will be added later and have their
 * own authorization script when deployed.
 *
 * ============================================================================
 *                        AUTHORIZATION OVERVIEW
 * ============================================================================
 *
 * AUTHORIZATION FLOW:
 *
 *   1. DealersExeCore.authorizeContract() - Game modules that modify dealer state:
 *      - DealersExePVE    -> updates reputation, drugs, heat, jail, attempts, cash
 *      - DealersExePVP    -> updates reputation, drugs, stats, heat, jail
 *      - DealersExeBoosts -> applies boosts (multipliers, extra attempts)
 *
 *   2. DrugRegistry.authorizeContract() - Contracts that track drug supply:
 *      - DealersExeCore -> increments/decrements supply when drugs change
 *
 *   3. DEPaymentHandler.authorizeContract() - Contracts that process payments:
 *      - DealersExeCore   -> bail, attempt resets, cop bribes, cash purchases
 *      - DealersExeBoosts -> boost purchases
 *
 *   4. DealersExeCore setter functions:
 *      - setDrugRegistry()    -> for drug validation and supply tracking
 *      - setAreaRegistry()    -> for area validation and movement
 *      - setNFTContract()     -> for ownership verification
 *      - setPaymentHandler()  -> for ETH fee processing
 *
 *   5. DealersExeNFT setter functions:
 *      - setDealersExeCore()  -> to initialize dealers on mint
 *
 * ============================================================================
 *                          USAGE INSTRUCTIONS
 * ============================================================================
 *
 * 1. Set environment variables with deployed contract addresses:
 *    export DEALERS_CORE=0x...
 *    export DEALERS_NFT=0x...
 *    export DEALERS_PVE=0x...
 *    export DEALERS_PVP=0x...
 *    export DEALERS_BOOSTS=0x...
 *    export DRUG_REGISTRY=0x...
 *    export AREA_REGISTRY=0x...
 *    export PAYMENT_HANDLER=0x...
 *
 * 2. Run the script (testnet):
 *    forge script script/SetupAuthorization.s.sol:SetupAuthorization \
 *      --rpc-url https://api.testnet.abs.xyz \
 *      --account dealersKeystore \
 *      --sender <YOUR_ADDRESS> \
 *      --broadcast \
 *      --zksync
 *
 * 3. Run the script (mainnet):
 *    forge script script/SetupAuthorization.s.sol:SetupAuthorization \
 *      --rpc-url https://api.mainnet.abs.xyz \
 *      --account dealersKeystore \
 *      --sender <YOUR_ADDRESS> \
 *      --broadcast \
 *      --zksync
 *
 * @author Dealers.Exe Team
 */

// =============================================================================
//                            INTERFACE DEFINITIONS
// =============================================================================

/**
 * @dev Minimal interface for DealersExeCore authorization and setup
 */
interface IDealersExeCore {
    function authorizeContract(address contractAddress, bool authorized) external;
    function authorizedContracts(address) external view returns (bool);
    function setDrugRegistry(address _drugRegistry) external;
    function setAreaRegistry(address _areaRegistry) external;
    function setNFTContract(address _nftContract) external;
    function setPaymentHandler(address _paymentHandler) external;
    function drugRegistry() external view returns (address);
    function areaRegistry() external view returns (address);
    function nftContract() external view returns (address);
    function paymentHandler() external view returns (address);
    function owner() external view returns (address);
}

/**
 * @dev Minimal interface for DEDrugRegistry authorization
 */
interface IDrugRegistry {
    function authorizeContract(address contractAddress, bool authorized) external;
    function authorizedContracts(address) external view returns (bool);
    function owner() external view returns (address);
}

/**
 * @dev Minimal interface for DEPaymentHandler authorization
 */
interface IPaymentHandler {
    function authorizeContract(address contractAddress, bool authorized) external;
    function authorizedContracts(address) external view returns (bool);
    function owner() external view returns (address);
}

/**
 * @dev Minimal interface for DealersExeNFT setup
 */
interface IDealersExeNFT {
    function setDealersExeCore(address _dealersExeCore) external;
    function dealersExeCore() external view returns (address);
    function owner() external view returns (address);
}

// =============================================================================
//                              MAIN SCRIPT
// =============================================================================

contract SetupAuthorization is Script {
    // Contract addresses - loaded from environment variables
    address public dealersCore;
    address public dealersNFT;
    address public dealersPVE;
    address public dealersPVP;
    address public dealersBoosts;
    address public drugRegistry;
    address public areaRegistry;
    address public paymentHandler;

    /**
     * @notice Load contract addresses from environment variables
     * @dev Reverts if any required address is not set
     */
    function loadAddresses() internal {
        dealersCore = vm.envAddress("DEALERS_CORE");
        dealersNFT = vm.envAddress("DEALERS_NFT");
        dealersPVE = vm.envAddress("DEALERS_PVE");
        dealersPVP = vm.envAddress("DEALERS_PVP");
        dealersBoosts = vm.envAddress("DEALERS_BOOSTS");
        drugRegistry = vm.envAddress("DRUG_REGISTRY");
        areaRegistry = vm.envAddress("AREA_REGISTRY");
        paymentHandler = vm.envAddress("PAYMENT_HANDLER");

        // Validate all addresses are set (non-zero)
        require(dealersCore != address(0), "DEALERS_CORE not set");
        require(dealersNFT != address(0), "DEALERS_NFT not set");
        require(dealersPVE != address(0), "DEALERS_PVE not set");
        require(dealersPVP != address(0), "DEALERS_PVP not set");
        require(dealersBoosts != address(0), "DEALERS_BOOSTS not set");
        require(drugRegistry != address(0), "DRUG_REGISTRY not set");
        require(areaRegistry != address(0), "AREA_REGISTRY not set");
        require(paymentHandler != address(0), "PAYMENT_HANDLER not set");
    }

    /**
     * @notice Main entry point for the script
     */
    function run() external {
        // Load addresses from environment
        loadAddresses();

        // Start broadcasting transactions
        vm.startBroadcast();

        console.log("==============================================");
        console.log("   Dealers.Exe Phase 1 Authorization Setup");
        console.log("==============================================");
        console.log("");

        // Step 1: Setup Core contract references
        _setupCoreReferences();

        // Step 2: Authorize game modules in DealersExeCore
        _authorizeGameModulesInCore();

        // Step 3: Authorize DealersExeCore in DrugRegistry
        _authorizeCoreInDrugRegistry();

        // Step 4: Authorize contracts in PaymentHandler
        _authorizeInPaymentHandler();

        // Step 5: Setup NFT to Core reference
        _setupNFTReference();

        console.log("");
        console.log("==============================================");
        console.log("   Phase 1 Authorization Setup Complete!");
        console.log("==============================================");

        vm.stopBroadcast();
    }

    /**
     * @notice Step 1: Setup Core contract references
     * @dev Core needs references to registries, NFT, and payment handler
     */
    function _setupCoreReferences() internal {
        console.log("Step 1: Setting up DealersExeCore references...");
        console.log("  Core address:", dealersCore);
        console.log("");

        IDealersExeCore core = IDealersExeCore(dealersCore);

        // 1a. Set DrugRegistry
        if (core.drugRegistry() != drugRegistry) {
            console.log("  Setting DrugRegistry...");
            console.log("    Address:", drugRegistry);
            core.setDrugRegistry(drugRegistry);
            console.log("    Status: SET");
        } else {
            console.log("  DrugRegistry already set, skipping.");
        }

        // 1b. Set AreaRegistry
        if (core.areaRegistry() != areaRegistry) {
            console.log("  Setting AreaRegistry...");
            console.log("    Address:", areaRegistry);
            core.setAreaRegistry(areaRegistry);
            console.log("    Status: SET");
        } else {
            console.log("  AreaRegistry already set, skipping.");
        }

        // 1c. Set NFT Contract
        if (core.nftContract() != dealersNFT) {
            console.log("  Setting NFT Contract...");
            console.log("    Address:", dealersNFT);
            core.setNFTContract(dealersNFT);
            console.log("    Status: SET");
        } else {
            console.log("  NFT Contract already set, skipping.");
        }

        // 1d. Set Payment Handler
        if (core.paymentHandler() != paymentHandler) {
            console.log("  Setting Payment Handler...");
            console.log("    Address:", paymentHandler);
            core.setPaymentHandler(paymentHandler);
            console.log("    Status: SET");
        } else {
            console.log("  Payment Handler already set, skipping.");
        }

        console.log("");
        console.log("  Step 1 complete: Core references configured.");
    }

    /**
     * @notice Step 2: Authorize all game modules in DealersExeCore
     * @dev These modules need authorization to call state-modifying functions
     */
    function _authorizeGameModulesInCore() internal {
        console.log("");
        console.log("Step 2: Authorizing game modules in DealersExeCore...");
        console.log("");

        IDealersExeCore core = IDealersExeCore(dealersCore);

        // 2a. Authorize DealersExePVE
        if (!core.authorizedContracts(dealersPVE)) {
            console.log("  Authorizing DealersExePVE...");
            console.log("    Address:", dealersPVE);
            console.log("    Purpose: PVE game - updates rep, drugs, heat, jail, attempts, cash");
            core.authorizeContract(dealersPVE, true);
            console.log("    Status: AUTHORIZED");
        } else {
            console.log("  DealersExePVE already authorized, skipping.");
        }
        console.log("");

        // 2b. Authorize DealersExePVP
        if (!core.authorizedContracts(dealersPVP)) {
            console.log("  Authorizing DealersExePVP...");
            console.log("    Address:", dealersPVP);
            console.log("    Purpose: PVP combat - updates rep, transfers drugs, heat, jail");
            core.authorizeContract(dealersPVP, true);
            console.log("    Status: AUTHORIZED");
        } else {
            console.log("  DealersExePVP already authorized, skipping.");
        }
        console.log("");

        // 2c. Authorize DealersExeBoosts
        if (!core.authorizedContracts(dealersBoosts)) {
            console.log("  Authorizing DealersExeBoosts...");
            console.log("    Address:", dealersBoosts);
            console.log("    Purpose: Boost purchases - applies boost multipliers and perks");
            core.authorizeContract(dealersBoosts, true);
            console.log("    Status: AUTHORIZED");
        } else {
            console.log("  DealersExeBoosts already authorized, skipping.");
        }
        console.log("");

        console.log("  Step 2 complete: Game modules authorized in Core.");
    }

    /**
     * @notice Step 3: Authorize DealersExeCore in DrugRegistry
     * @dev Core needs authorization to track global drug supply
     */
    function _authorizeCoreInDrugRegistry() internal {
        console.log("");
        console.log("Step 3: Authorizing DealersExeCore in DrugRegistry...");
        console.log("  DrugRegistry address:", drugRegistry);
        console.log("");

        IDrugRegistry registry = IDrugRegistry(drugRegistry);

        if (!registry.authorizedContracts(dealersCore)) {
            console.log("  Authorizing DealersExeCore...");
            console.log("    Address:", dealersCore);
            console.log("    Purpose: Supply tracking - increment/decrement drug supply");
            registry.authorizeContract(dealersCore, true);
            console.log("    Status: AUTHORIZED");
        } else {
            console.log("  DealersExeCore already authorized in DrugRegistry, skipping.");
        }
        console.log("");

        console.log("  Step 3 complete: Core authorized for supply tracking.");
    }

    /**
     * @notice Step 4: Authorize contracts in DEPaymentHandler
     * @dev Core and Boosts need authorization to process payments
     */
    function _authorizeInPaymentHandler() internal {
        console.log("");
        console.log("Step 4: Authorizing contracts in DEPaymentHandler...");
        console.log("  PaymentHandler address:", paymentHandler);
        console.log("");

        IPaymentHandler handler = IPaymentHandler(paymentHandler);

        // 4a. Authorize Core
        if (!handler.authorizedContracts(dealersCore)) {
            console.log("  Authorizing DealersExeCore...");
            console.log("    Address:", dealersCore);
            console.log("    Purpose: Process bail, attempt resets, bribes, cash purchases");
            handler.authorizeContract(dealersCore, true);
            console.log("    Status: AUTHORIZED");
        } else {
            console.log("  DealersExeCore already authorized, skipping.");
        }
        console.log("");

        // 4b. Authorize Boosts
        if (!handler.authorizedContracts(dealersBoosts)) {
            console.log("  Authorizing DealersExeBoosts...");
            console.log("    Address:", dealersBoosts);
            console.log("    Purpose: Process boost purchase payments");
            handler.authorizeContract(dealersBoosts, true);
            console.log("    Status: AUTHORIZED");
        } else {
            console.log("  DealersExeBoosts already authorized, skipping.");
        }
        console.log("");

        console.log("  Step 4 complete: Contracts authorized in PaymentHandler.");
    }

    /**
     * @notice Step 5: Setup NFT to Core reference
     * @dev NFT needs Core reference to initialize dealers on mint
     */
    function _setupNFTReference() internal {
        console.log("");
        console.log("Step 5: Setting up DealersExeNFT -> Core reference...");
        console.log("  NFT address:", dealersNFT);
        console.log("");

        IDealersExeNFT nft = IDealersExeNFT(dealersNFT);

        if (nft.dealersExeCore() != dealersCore) {
            console.log("  Setting DealersExeCore reference...");
            console.log("    Address:", dealersCore);
            console.log("    Purpose: Initialize dealers automatically on mint");
            nft.setDealersExeCore(dealersCore);
            console.log("    Status: SET");
        } else {
            console.log("  Core reference already set in NFT, skipping.");
        }
        console.log("");

        console.log("  Step 5 complete: NFT configured to initialize dealers.");
    }

    /**
     * @notice Verify all authorizations are correctly set
     * @dev Call this function separately to verify the setup without making changes
     *      Usage: forge script script/SetupAuthorization.s.sol:SetupAuthorization --sig "verify()" --rpc-url <RPC>
     */
    function verify() external view {
        console.log("==============================================");
        console.log("   Verifying Phase 1 Authorization Config");
        console.log("==============================================");
        console.log("");

        address _core = vm.envAddress("DEALERS_CORE");
        address _nft = vm.envAddress("DEALERS_NFT");
        address _pve = vm.envAddress("DEALERS_PVE");
        address _pvp = vm.envAddress("DEALERS_PVP");
        address _boosts = vm.envAddress("DEALERS_BOOSTS");
        address _drugReg = vm.envAddress("DRUG_REGISTRY");
        address _areaReg = vm.envAddress("AREA_REGISTRY");
        address _payHandler = vm.envAddress("PAYMENT_HANDLER");

        IDealersExeCore core = IDealersExeCore(_core);
        IDrugRegistry drugReg = IDrugRegistry(_drugReg);
        IPaymentHandler payHandler = IPaymentHandler(_payHandler);
        IDealersExeNFT nft = IDealersExeNFT(_nft);

        console.log("Core Contract References:");
        console.log("  DrugRegistry:", core.drugRegistry());
        console.log("    Expected:", _drugReg);
        console.log("    Match:", core.drugRegistry() == _drugReg);
        console.log("  AreaRegistry:", core.areaRegistry());
        console.log("    Expected:", _areaReg);
        console.log("    Match:", core.areaRegistry() == _areaReg);
        console.log("  NFT Contract:", core.nftContract());
        console.log("    Expected:", _nft);
        console.log("    Match:", core.nftContract() == _nft);
        console.log("  PaymentHandler:", core.paymentHandler());
        console.log("    Expected:", _payHandler);
        console.log("    Match:", core.paymentHandler() == _payHandler);
        console.log("");

        console.log("Core Authorization Status:");
        console.log("  PVE authorized:", core.authorizedContracts(_pve));
        console.log("  PVP authorized:", core.authorizedContracts(_pvp));
        console.log("  Boosts authorized:", core.authorizedContracts(_boosts));
        console.log("");

        console.log("DrugRegistry Authorization:");
        console.log("  Core authorized:", drugReg.authorizedContracts(_core));
        console.log("");

        console.log("PaymentHandler Authorization:");
        console.log("  Core authorized:", payHandler.authorizedContracts(_core));
        console.log("  Boosts authorized:", payHandler.authorizedContracts(_boosts));
        console.log("");

        console.log("NFT Configuration:");
        console.log("  Core reference:", nft.dealersExeCore());
        console.log("    Expected:", _core);
        console.log("    Match:", nft.dealersExeCore() == _core);
        console.log("");

        console.log("==============================================");
        console.log("   Verification Complete");
        console.log("==============================================");
    }
}

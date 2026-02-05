// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

/**
 * @title DeployGame - Deploy All Game Contracts for Native zkSync
 * @notice Foundry script to deploy all game contracts as native zkSync bytecode
 * @dev Run with --zksync flag for native zkSync deployment on Abstract Chain
 *
 * ============================================================================
 *                           DEPLOYMENT ORDER
 * ============================================================================
 *
 * This script deploys contracts in dependency order:
 *   1. DEDrugRegistry     - Drug definitions (no dependencies)
 *   2. DEAreaRegistry     - Area config (depends on DrugRegistry)
 *   3. DealersExeCore     - Central state management (no dependencies)
 *   4. DEPaymentHandler   - Payment/fee handling (no dependencies)
 *   5. DealersExeNFT      - NFT contract (no dependencies, renderers set later)
 *   6. DealersExeBoosts   - Boost system (depends on Core, NFT, PaymentHandler)
 *   7. DealersExePVE      - PvE game module (depends on Core, NFT, AreaRegistry)
 *   8. DealersExePVP      - PvP game module (depends on Core, NFT, AreaRegistry)
 *
 * After deployment, run SetupAuthorization.s.sol to configure all references.
 *
 * ============================================================================
 *                        ENVIRONMENT VARIABLES
 * ============================================================================
 *
 * Required (for new deployments):
 *   DEV_WALLET       - Address for dev fee distribution
 *   BANK_VAULT       - Address for bank vault fee distribution
 *   ROYALTY_RECEIVER - Address for NFT royalty payments
 *
 * Optional (to skip deployment of already-deployed contracts):
 *   DRUG_REGISTRY    - Skip DrugRegistry deployment, use this address
 *   AREA_REGISTRY    - Skip AreaRegistry deployment, use this address
 *   DEALERS_CORE     - Skip Core deployment, use this address
 *   PAYMENT_HANDLER  - Skip PaymentHandler deployment, use this address
 *   DEALERS_NFT      - Skip NFT deployment, use this address
 *   DEALERS_BOOSTS   - Skip Boosts deployment, use this address
 *   DEALERS_PVE      - Skip PVE deployment, use this address
 *   DEALERS_PVP      - Skip PVP deployment, use this address
 *
 * ============================================================================
 *                            USAGE INSTRUCTIONS
 * ============================================================================
 *
 * 1. Create .env file in project root:
 *    # Required
 *    DEV_WALLET=0x...
 *    BANK_VAULT=0x...
 *    ROYALTY_RECEIVER=0x...
 *
 *    # Optional - set these to skip deployment of existing contracts
 *    # DRUG_REGISTRY=0x...
 *    # AREA_REGISTRY=0x...
 *
 * 2. Source the .env file:
 *    source .env
 *
 * 3. Build with zkSync support (skip renderer contracts):
 *    forge build --zksync --skip "DealerRenderer" --skip "DeployRenderers"
 *
 * 4. Deploy to Abstract Testnet (with verification):
 *    forge script script/DeployGame.s.sol:DeployGame \
 *      --rpc-url https://api.testnet.abs.xyz \
 *      --account dealersKeystore \
 *      --sender $DEPLOYER_ADDRESS \
 *      --broadcast \
 *      --zksync \
 *      --verify \
 *      --verifier etherscan \
 *      --verifier-url "https://api.etherscan.io/v2/api?chainid=11124" \
 *      --etherscan-api-key P5U7KEVRI6WKS9J2UKCDI8HW61SUD5X8VF \
 *      --skip "DealerRenderer" --skip "DeployRenderers"
 *
 * @author Dealers.Exe Team
 */

// =============================================================================
//                            INTERFACE DEFINITIONS
// =============================================================================

interface IDealersExeCore {
    function authorizeContract(address contractAddress, bool authorized) external;
    function setNFTContract(address _nftContract) external;
    function setPaymentHandler(address _paymentHandler) external;
    function setDrugRegistry(address _drugRegistry) external;
    function setAreaRegistry(address _areaRegistry) external;
    function drugRegistry() external view returns (address);
    function areaRegistry() external view returns (address);
    function nftContract() external view returns (address);
    function paymentHandler() external view returns (address);
    function authorizedContracts(address) external view returns (bool);
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
    function setDrugRegistry(address _drugRegistry) external;
    function drugRegistry() external view returns (address);
}

// =============================================================================
//                              MAIN SCRIPT
// =============================================================================

contract DeployGame is Script {
    // Deployed contract addresses
    address public drugRegistry;
    address public areaRegistry;
    address public core;
    address public paymentHandler;
    address public nft;
    address public boosts;
    address public pve;
    address public pvp;

    // Configuration from environment
    address public devWallet;
    address public bankVault;
    address public royaltyReceiver;

    function run() external {
        _loadConfig();
        _loadExistingAddresses();
        _validateConfig();

        vm.startBroadcast();

        console.log("==============================================");
        console.log("   Dealers.Exe Game Contracts Deployment");
        console.log("   Network: Native zkSync (Abstract Chain)");
        console.log("==============================================");
        console.log("");

        // Deploy contracts in dependency order (skip if address already set)
        _deployDrugRegistry();
        _deployAreaRegistry();
        _deployCore();
        _deployPaymentHandler();
        _deployNFT();
        _deployBoosts();
        _deployPVE();
        _deployPVP();

        // Configure contract relationships
        _setupCoreReferences();
        _authorizeGameModulesInCore();
        _setupRegistryAuthorizations();
        _setupModuleReferences();

        vm.stopBroadcast();

        _printDeploymentSummary();
    }

    function _loadConfig() internal {
        devWallet = vm.envAddress("DEV_WALLET");
        bankVault = vm.envAddress("BANK_VAULT");
        royaltyReceiver = vm.envAddress("ROYALTY_RECEIVER");
    }

    function _loadExistingAddresses() internal {
        // Try to load existing addresses - use address(0) as default if not set
        drugRegistry = vm.envOr("DRUG_REGISTRY", address(0));
        areaRegistry = vm.envOr("AREA_REGISTRY", address(0));
        core = vm.envOr("DEALERS_CORE", address(0));
        paymentHandler = vm.envOr("PAYMENT_HANDLER", address(0));
        nft = vm.envOr("DEALERS_NFT", address(0));
        boosts = vm.envOr("DEALERS_BOOSTS", address(0));
        pve = vm.envOr("DEALERS_PVE", address(0));
        pvp = vm.envOr("DEALERS_PVP", address(0));

        // Log which addresses are pre-configured
        if (drugRegistry != address(0)) console.log("Using existing DRUG_REGISTRY:", drugRegistry);
        if (areaRegistry != address(0)) console.log("Using existing AREA_REGISTRY:", areaRegistry);
        if (core != address(0)) console.log("Using existing DEALERS_CORE:", core);
        if (paymentHandler != address(0)) console.log("Using existing PAYMENT_HANDLER:", paymentHandler);
        if (nft != address(0)) console.log("Using existing DEALERS_NFT:", nft);
        if (boosts != address(0)) console.log("Using existing DEALERS_BOOSTS:", boosts);
        if (pve != address(0)) console.log("Using existing DEALERS_PVE:", pve);
        if (pvp != address(0)) console.log("Using existing DEALERS_PVP:", pvp);
        console.log("");
    }

    function _validateConfig() internal view {
        require(devWallet != address(0), "DEV_WALLET not set");
        require(bankVault != address(0), "BANK_VAULT not set");
        require(royaltyReceiver != address(0), "ROYALTY_RECEIVER not set");

        console.log("Configuration loaded:");
        console.log("  DEV_WALLET:", devWallet);
        console.log("  BANK_VAULT:", bankVault);
        console.log("  ROYALTY_RECEIVER:", royaltyReceiver);
        console.log("");
    }

    // =========================================================================
    //                           DEPLOYMENT FUNCTIONS
    // =========================================================================

    function _deployDrugRegistry() internal {
        if (drugRegistry != address(0)) {
            console.log("Skipping DEDrugRegistry (already deployed)");
            console.log("");
            return;
        }

        console.log("Deploying DEDrugRegistry...");

        bytes memory bytecode = vm.getCode("DEDrugRegistry.sol:DEDrugRegistry");
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DEDrugRegistry deployment failed");
        drugRegistry = deployed;

        console.log("  DEDrugRegistry deployed at:", drugRegistry);
        console.log("");
    }

    function _deployAreaRegistry() internal {
        if (areaRegistry != address(0)) {
            console.log("Skipping DEAreaRegistry (already deployed)");
            console.log("");
            return;
        }

        require(drugRegistry != address(0), "DrugRegistry must be deployed first");

        console.log("Deploying DEAreaRegistry...");

        bytes memory bytecode = abi.encodePacked(
            vm.getCode("DEAreaRegistry.sol:DEAreaRegistry"),
            abi.encode(drugRegistry)
        );
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DEAreaRegistry deployment failed");
        areaRegistry = deployed;

        console.log("  DEAreaRegistry deployed at:", areaRegistry);
        console.log("    DrugRegistry:", drugRegistry);
        console.log("");
    }

    function _deployCore() internal {
        if (core != address(0)) {
            console.log("Skipping DealersExeCore (already deployed)");
            console.log("");
            return;
        }

        console.log("Deploying DealersExeCore...");

        bytes memory bytecode = vm.getCode("DealersExeCore.sol:DealersExeCore");
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DealersExeCore deployment failed");
        core = deployed;

        console.log("  DealersExeCore deployed at:", core);
        console.log("");
    }

    function _deployPaymentHandler() internal {
        if (paymentHandler != address(0)) {
            console.log("Skipping DEPaymentHandler (already deployed)");
            console.log("");
            return;
        }

        console.log("Deploying DEPaymentHandler...");

        bytes memory bytecode = abi.encodePacked(
            vm.getCode("DEPaymentHandler.sol:DEPaymentHandler"),
            abi.encode(devWallet, bankVault)
        );
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DEPaymentHandler deployment failed");
        paymentHandler = deployed;

        console.log("  DEPaymentHandler deployed at:", paymentHandler);
        console.log("    Dev Wallet:", devWallet);
        console.log("    Bank Vault:", bankVault);
        console.log("");
    }

    function _deployNFT() internal {
        if (nft != address(0)) {
            console.log("Skipping DealersExeNFT (already deployed)");
            console.log("");
            return;
        }

        console.log("Deploying DealersExeNFT...");

        bytes memory bytecode = abi.encodePacked(
            vm.getCode("DealersExeNFT.sol:DealersExeNFT"),
            abi.encode(royaltyReceiver)
        );
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DealersExeNFT deployment failed");
        nft = deployed;

        console.log("  DealersExeNFT deployed at:", nft);
        console.log("    Royalty Receiver:", royaltyReceiver);
        console.log("    Note: Renderers will be set separately via setContractRendererSVG/HTML");
        console.log("");
    }

    function _deployBoosts() internal {
        if (boosts != address(0)) {
            console.log("Skipping DealersExeBoosts (already deployed)");
            console.log("");
            return;
        }

        require(core != address(0), "Core must be deployed first");
        require(nft != address(0), "NFT must be deployed first");
        require(paymentHandler != address(0), "PaymentHandler must be deployed first");

        console.log("Deploying DealersExeBoosts...");

        bytes memory bytecode = abi.encodePacked(
            vm.getCode("DealersExeBoosts.sol:DealersExeBoosts"),
            abi.encode(core, nft, paymentHandler)
        );
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DealersExeBoosts deployment failed");
        boosts = deployed;

        console.log("  DealersExeBoosts deployed at:", boosts);
        console.log("");
    }

    function _deployPVE() internal {
        if (pve != address(0)) {
            console.log("Skipping DealersExePVE (already deployed)");
            console.log("");
            return;
        }

        require(core != address(0), "Core must be deployed first");
        require(nft != address(0), "NFT must be deployed first");
        require(areaRegistry != address(0), "AreaRegistry must be deployed first");

        console.log("Deploying DealersExePVE...");

        bytes memory bytecode = abi.encodePacked(
            vm.getCode("DealersExePVE.sol:DealersExePVE"),
            abi.encode(core, nft, areaRegistry)
        );
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DealersExePVE deployment failed");
        pve = deployed;

        console.log("  DealersExePVE deployed at:", pve);
        console.log("");
    }

    function _deployPVP() internal {
        if (pvp != address(0)) {
            console.log("Skipping DealersExePVP (already deployed)");
            console.log("");
            return;
        }

        require(core != address(0), "Core must be deployed first");
        require(nft != address(0), "NFT must be deployed first");
        require(areaRegistry != address(0), "AreaRegistry must be deployed first");

        console.log("Deploying DealersExePVP...");

        bytes memory bytecode = abi.encodePacked(
            vm.getCode("DealersExePVP.sol:DealersExePVP"),
            abi.encode(core, nft, areaRegistry)
        );
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DealersExePVP deployment failed");
        pvp = deployed;

        console.log("  DealersExePVP deployed at:", pvp);
        console.log("");
    }

    // =========================================================================
    //                         CONFIGURATION FUNCTIONS
    // =========================================================================

    function _setupCoreReferences() internal {
        console.log("Setting up DealersExeCore references...");

        IDealersExeCore coreContract = IDealersExeCore(core);

        if (coreContract.drugRegistry() != drugRegistry) {
            coreContract.setDrugRegistry(drugRegistry);
            console.log("  Core -> DrugRegistry: SET");
        } else {
            console.log("  Core -> DrugRegistry: already set");
        }

        if (coreContract.areaRegistry() != areaRegistry) {
            coreContract.setAreaRegistry(areaRegistry);
            console.log("  Core -> AreaRegistry: SET");
        } else {
            console.log("  Core -> AreaRegistry: already set");
        }

        if (coreContract.nftContract() != nft) {
            coreContract.setNFTContract(nft);
            console.log("  Core -> NFT: SET");
        } else {
            console.log("  Core -> NFT: already set");
        }

        if (coreContract.paymentHandler() != paymentHandler) {
            coreContract.setPaymentHandler(paymentHandler);
            console.log("  Core -> PaymentHandler: SET");
        } else {
            console.log("  Core -> PaymentHandler: already set");
        }

        console.log("");
    }

    function _authorizeGameModulesInCore() internal {
        console.log("Authorizing game modules in DealersExeCore...");

        IDealersExeCore coreContract = IDealersExeCore(core);

        if (!coreContract.authorizedContracts(pve)) {
            coreContract.authorizeContract(pve, true);
            console.log("  PVE authorized: YES");
        } else {
            console.log("  PVE: already authorized");
        }

        if (!coreContract.authorizedContracts(pvp)) {
            coreContract.authorizeContract(pvp, true);
            console.log("  PVP authorized: YES");
        } else {
            console.log("  PVP: already authorized");
        }

        if (!coreContract.authorizedContracts(boosts)) {
            coreContract.authorizeContract(boosts, true);
            console.log("  Boosts authorized: YES");
        } else {
            console.log("  Boosts: already authorized");
        }

        if (!coreContract.authorizedContracts(nft)) {
            coreContract.authorizeContract(nft, true);
            console.log("  NFT authorized: YES (for initializeDealer on mint)");
        } else {
            console.log("  NFT: already authorized");
        }

        console.log("");
    }

    function _setupRegistryAuthorizations() internal {
        console.log("Setting up registry authorizations...");

        // Authorize Core in DrugRegistry
        IDrugRegistry drugReg = IDrugRegistry(drugRegistry);
        if (!drugReg.authorizedContracts(core)) {
            drugReg.authorizeContract(core, true);
            console.log("  DrugRegistry -> Core: AUTHORIZED");
        } else {
            console.log("  DrugRegistry -> Core: already authorized");
        }

        // Authorize Core and Boosts in PaymentHandler
        IPaymentHandler payHandler = IPaymentHandler(paymentHandler);
        if (!payHandler.authorizedContracts(core)) {
            payHandler.authorizeContract(core, true);
            console.log("  PaymentHandler -> Core: AUTHORIZED");
        } else {
            console.log("  PaymentHandler -> Core: already authorized");
        }

        if (!payHandler.authorizedContracts(boosts)) {
            payHandler.authorizeContract(boosts, true);
            console.log("  PaymentHandler -> Boosts: AUTHORIZED");
        } else {
            console.log("  PaymentHandler -> Boosts: already authorized");
        }

        // Set Core in AreaRegistry
        IAreaRegistry areaReg = IAreaRegistry(areaRegistry);
        if (areaReg.coreContract() != core) {
            areaReg.setCoreContract(core);
            console.log("  AreaRegistry -> Core: SET");
        } else {
            console.log("  AreaRegistry -> Core: already set");
        }

        console.log("");
    }

    function _setupModuleReferences() internal {
        console.log("Setting up module references...");

        // NFT -> Core
        IDealersExeNFT nftContract = IDealersExeNFT(nft);
        if (nftContract.dealersExeCore() != core) {
            nftContract.setDealersExeCore(core);
            console.log("  NFT -> Core: SET");
        } else {
            console.log("  NFT -> Core: already set");
        }

        // PVP -> DrugRegistry
        IPVPContract pvpContract = IPVPContract(pvp);
        if (pvpContract.drugRegistry() != drugRegistry) {
            pvpContract.setDrugRegistry(drugRegistry);
            console.log("  PVP -> DrugRegistry: SET");
        } else {
            console.log("  PVP -> DrugRegistry: already set");
        }

        console.log("");
    }

    // =========================================================================
    //                            SUMMARY OUTPUT
    // =========================================================================

    function _printDeploymentSummary() internal view {
        console.log("==============================================");
        console.log("   Deployment Complete!");
        console.log("==============================================");
        console.log("");
        console.log("Deployed Contract Addresses:");
        console.log("  DEDrugRegistry:", drugRegistry);
        console.log("  DEAreaRegistry:", areaRegistry);
        console.log("  DealersExeCore:", core);
        console.log("  DEPaymentHandler:", paymentHandler);
        console.log("  DealersExeNFT:", nft);
        console.log("  DealersExeBoosts:", boosts);
        console.log("  DealersExePVE:", pve);
        console.log("  DealersExePVP:", pvp);
        console.log("");
        console.log("Add to your .env file:");
        console.log("----------------------------------------");
        console.log("DRUG_REGISTRY=", drugRegistry);
        console.log("AREA_REGISTRY=", areaRegistry);
        console.log("DEALERS_CORE=", core);
        console.log("PAYMENT_HANDLER=", paymentHandler);
        console.log("DEALERS_NFT=", nft);
        console.log("DEALERS_BOOSTS=", boosts);
        console.log("DEALERS_PVE=", pve);
        console.log("DEALERS_PVP=", pvp);
        console.log("----------------------------------------");
        console.log("");
        console.log("==============================================");
        console.log("   REMAINING SETUP REQUIRED:");
        console.log("==============================================");
        console.log("");
        console.log("1. Deploy renderers (via EVM mode - no --zksync flag):");
        console.log("   forge script script/DeployRenderers.s.sol:DeployRenderers \\");
        console.log("     --rpc-url https://api.testnet.abs.xyz \\");
        console.log("     --account dealersKeystore --sender <YOUR_ADDRESS> --broadcast");
        console.log("");
        console.log("2. Set renderers in NFT:");
        console.log("   cast send $DEALERS_NFT \"setContractRendererSVG(address)\" <SVG_ADDRESS>");
        console.log("   cast send $DEALERS_NFT \"setContractRendererHTML(address)\" <HTML_ADDRESS>");
        console.log("");
        console.log("3. Set reputation tiers in Core:");
        console.log("   cast send $DEALERS_CORE \"setReputationTiers(...)\"");
        console.log("");
        console.log("4. Enable minting:");
        console.log("   cast send $DEALERS_NFT \"setMintStatus(uint8)\" 3  # PUBLIC");
        console.log("");
        console.log("==============================================");
    }
}

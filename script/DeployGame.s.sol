// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
 *   1. DealersExeCore       - Central state management (no dependencies)
 *   2. DEPaymentHandler     - Payment/fee handling (no dependencies)
 *   3. DealersExeNFT        - NFT contract (renderers set later via setRenderers)
 *   4. DealersExeBoosts     - Boost system (depends on Core, NFT, PaymentHandler)
 *   5. DealersExePVE        - PvE game module (depends on Core, NFT, AreaRegistry)
 *   6. DealersExePVP        - PvP game module (depends on Core, NFT, AreaRegistry)
 *
 * After deployment, the script:
 *   - Authorizes game modules (PVE, PVP, Boosts) in DealersExeCore
 *   - Sets the core contract in NFT, PVE, PVP, Boosts contracts
 *
 * ============================================================================
 *                        REQUIRED ENVIRONMENT VARIABLES
 * ============================================================================
 *
 *   DEV_WALLET       - Address for dev fee distribution
 *   BANK_VAULT       - Address for bank vault fee distribution
 *   SIGNER_ADDRESS   - Address for NFT mint signature verification
 *   ROYALTY_RECEIVER - Address for NFT royalty payments
 *   AREA_REGISTRY    - Address of deployed AreaRegistry (for PVE/PVP)
 *
 * ============================================================================
 *                            USAGE INSTRUCTIONS
 * ============================================================================
 *
 * 1. Set required environment variables:
 *    export DEV_WALLET=0x...
 *    export BANK_VAULT=0x...
 *    export SIGNER_ADDRESS=0x...
 *    export ROYALTY_RECEIVER=0x...
 *    export AREA_REGISTRY=0x...
 *
 * 2. Build with zkSync support (skip renderer contracts):
 *    forge build --zksync --skip "DealerRenderer" --skip "DeployRenderers"
 *
 * 3. Deploy to Abstract Testnet:
 *    forge script script/DeployGame.s.sol:DeployGame \
 *      --rpc-url https://api.testnet.abs.xyz \
 *      --account dealersKeystore \
 *      --sender <YOUR_ADDRESS> \
 *      --broadcast \
 *      --zksync \
 *      --skip "DealerRenderer" --skip "DeployRenderers"
 *
 * 4. Deploy to Abstract Mainnet:
 *    forge script script/DeployGame.s.sol:DeployGame \
 *      --rpc-url https://api.mainnet.abs.xyz \
 *      --account dealersKeystore \
 *      --sender <YOUR_ADDRESS> \
 *      --broadcast \
 *      --zksync \
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
}

interface IDealersExeNFT {
    function setDealersExeCore(address _core) external;
}

// =============================================================================
//                              MAIN SCRIPT
// =============================================================================

contract DeployGame is Script {
    // Deployed contract addresses
    address public core;
    address public paymentHandler;
    address public nft;
    address public boosts;
    address public pve;
    address public pvp;

    // Configuration from environment
    address public devWallet;
    address public bankVault;
    address public signerAddress;
    address public royaltyReceiver;
    address public areaRegistry;

    function run() external {
        _loadConfig();
        _validateConfig();

        vm.startBroadcast();

        console.log("==============================================");
        console.log("   Dealers.Exe Game Contracts Deployment");
        console.log("   Network: Native zkSync (Abstract Chain)");
        console.log("==============================================");
        console.log("");

        // Deploy contracts in dependency order
        _deployCore();
        _deployPaymentHandler();
        _deployNFT();
        _deployBoosts();
        _deployPVE();
        _deployPVP();

        // Configure contract relationships
        _setupCoreReferences();
        _authorizeGameModulesInCore();
        _setupModuleReferences();

        vm.stopBroadcast();

        _printDeploymentSummary();
    }

    function _loadConfig() internal {
        devWallet = vm.envAddress("DEV_WALLET");
        bankVault = vm.envAddress("BANK_VAULT");
        signerAddress = vm.envAddress("SIGNER_ADDRESS");
        royaltyReceiver = vm.envAddress("ROYALTY_RECEIVER");
        areaRegistry = vm.envAddress("AREA_REGISTRY");
    }

    function _validateConfig() internal view {
        require(devWallet != address(0), "DEV_WALLET not set");
        require(bankVault != address(0), "BANK_VAULT not set");
        require(signerAddress != address(0), "SIGNER_ADDRESS not set");
        require(royaltyReceiver != address(0), "ROYALTY_RECEIVER not set");
        require(areaRegistry != address(0), "AREA_REGISTRY not set");

        console.log("Configuration loaded:");
        console.log("  DEV_WALLET:", devWallet);
        console.log("  BANK_VAULT:", bankVault);
        console.log("  SIGNER_ADDRESS:", signerAddress);
        console.log("  ROYALTY_RECEIVER:", royaltyReceiver);
        console.log("  AREA_REGISTRY:", areaRegistry);
        console.log("");
    }

    // =========================================================================
    //                           DEPLOYMENT FUNCTIONS
    // =========================================================================

    function _deployCore() internal {
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
        console.log("Deploying DealersExeNFT...");

        bytes memory bytecode = abi.encodePacked(
            vm.getCode("DealersExeNFT.sol:DealersExeNFT"),
            abi.encode(signerAddress, royaltyReceiver)
        );
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DealersExeNFT deployment failed");
        nft = deployed;

        console.log("  DealersExeNFT deployed at:", nft);
        console.log("    Signer Address:", signerAddress);
        console.log("    Royalty Receiver:", royaltyReceiver);
        console.log("    Note: Renderers will be set separately via setContractRendererSVG/HTML");
        console.log("");
    }

    function _deployBoosts() internal {
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

        IDealersExeCore(core).setNFTContract(nft);
        console.log("  Core -> NFT: SET");

        IDealersExeCore(core).setPaymentHandler(paymentHandler);
        console.log("  Core -> PaymentHandler: SET");

        console.log("  Note: DrugRegistry and AreaRegistry must be set separately");
        console.log("");
    }

    function _authorizeGameModulesInCore() internal {
        console.log("Authorizing game modules in DealersExeCore...");

        IDealersExeCore(core).authorizeContract(pve, true);
        console.log("  PVE authorized: YES");

        IDealersExeCore(core).authorizeContract(pvp, true);
        console.log("  PVP authorized: YES");

        IDealersExeCore(core).authorizeContract(boosts, true);
        console.log("  Boosts authorized: YES");

        IDealersExeCore(core).authorizeContract(nft, true);
        console.log("  NFT authorized: YES (for initializeDealer on mint)");

        console.log("");
    }

    function _setupModuleReferences() internal {
        console.log("Setting up module references...");

        IDealersExeNFT(nft).setDealersExeCore(core);
        console.log("  NFT -> Core: SET");

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
        console.log("  DealersExeCore:", core);
        console.log("  DEPaymentHandler:", paymentHandler);
        console.log("  DealersExeNFT:", nft);
        console.log("  DealersExeBoosts:", boosts);
        console.log("  DealersExePVE:", pve);
        console.log("  DealersExePVP:", pvp);
        console.log("");
        console.log("Environment Variables for SetupAuthorization script:");
        console.log("  export DEALERS_CORE=", core);
        console.log("  export DEALERS_NFT=", nft);
        console.log("  export DEALERS_PVE=", pve);
        console.log("  export DEALERS_PVP=", pvp);
        console.log("  export DEALERS_BOOSTS=", boosts);
        console.log("  export PAYMENT_HANDLER=", paymentHandler);
        console.log("");
        console.log("==============================================");
        console.log("   REMAINING SETUP REQUIRED:");
        console.log("==============================================");
        console.log("");
        console.log("1. Deploy DrugRegistry and AreaRegistry (if not already deployed)");
        console.log("2. Set DrugRegistry in Core: core.setDrugRegistry(address)");
        console.log("3. Set AreaRegistry in Core: core.setAreaRegistry(address)");
        console.log("4. Authorize Core in DrugRegistry: drugRegistry.authorizeContract(core, true)");
        console.log("5. Authorize Core in PaymentHandler: paymentHandler.authorizeContract(core, true)");
        console.log("6. Authorize Boosts in PaymentHandler: paymentHandler.authorizeContract(boosts, true)");
        console.log("7. Deploy renderers (via EVM mode - no --zksync flag)");
        console.log("8. Set renderers in NFT: nft.setContractRendererSVG/HTML(address)");
        console.log("9. Set reputation tiers in Core: core.setReputationTiers(...)");
        console.log("");
        console.log("Run SetupAuthorization.s.sol for complete authorization setup.");
        console.log("==============================================");
    }
}

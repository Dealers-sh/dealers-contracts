// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployAll - Deploy all game contracts + wire + setup tiers
 * @dev Deploys in dependency order, skipping contracts that already have an address in .env.
 *      After deploying, runs SetupWiring logic and reputation tier setup.
 *
 * Required env vars: DEV_WALLET, BANK_VAULT, ROYALTY_RECEIVER
 * Optional env vars: DRUG_REGISTRY, AREA_REGISTRY, DEALERS_CORE, PAYMENT_HANDLER,
 *                    RANDOMNESS, DEALERS_NFT, DEALERS_BOOSTS, DEALERS_PVE, DEALERS_PVP,
 *                    DEALERS_CLAIMS (set these to skip deployment of already-deployed contracts)
 *
 * Usage:
 *   source .env && forge script script/DeployAll.s.sol:DeployAll \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 */
contract DeployAll is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(devWallet, "DEV_WALLET");
        _requireAddress(bankVault, "BANK_VAULT");
        _requireAddress(royaltyReceiver, "ROYALTY_RECEIVER");

        console.log("==============================================");
        console.log("   Dealers.Exe - Deploy All");
        console.log("==============================================");
        console.log("");

        vm.startBroadcast();

        // 1. Deploy contracts in dependency order
        _deployIfNeeded();

        // 2. Wire references + authorizations
        _wireAll();

        // 3. Setup reputation tiers
        _setupTiers();

        vm.stopBroadcast();

        _printSummary();
    }

    // =========================================================================
    //                           DEPLOYMENTS
    // =========================================================================

    function _deployIfNeeded() internal {
        if (drugRegistry == address(0)) {
            drugRegistry = _zkCreate(vm.getCode("DEDrugRegistry.sol:DEDrugRegistry"));
            console.log("DEDrugRegistry deployed:", drugRegistry);
        } else {
            console.log("DEDrugRegistry: skipped (exists)");
        }

        if (areaRegistry == address(0)) {
            _requireAddress(drugRegistry, "DRUG_REGISTRY");
            areaRegistry = _zkCreate(abi.encodePacked(
                vm.getCode("DEAreaRegistry.sol:DEAreaRegistry"),
                abi.encode(drugRegistry)
            ));
            console.log("DEAreaRegistry deployed:", areaRegistry);
        } else {
            console.log("DEAreaRegistry: skipped (exists)");
        }

        if (core == address(0)) {
            core = _zkCreate(vm.getCode("DealersExeCore.sol:DealersExeCore"));
            console.log("DealersExeCore deployed:", core);
        } else {
            console.log("DealersExeCore: skipped (exists)");
        }

        if (paymentHandler == address(0)) {
            paymentHandler = _zkCreate(abi.encodePacked(
                vm.getCode("DEPaymentHandler.sol:DEPaymentHandler"),
                abi.encode(devWallet, bankVault)
            ));
            console.log("DEPaymentHandler deployed:", paymentHandler);
        } else {
            console.log("DEPaymentHandler: skipped (exists)");
        }

        if (randomness == address(0)) {
            randomness = _zkCreate(vm.getCode("DERandomness.sol:DERandomness"));
            console.log("DERandomness deployed:", randomness);
        } else {
            console.log("DERandomness: skipped (exists)");
        }

        if (nft == address(0)) {
            nft = _zkCreate(abi.encodePacked(
                vm.getCode("DealersExeNFT.sol:DealersExeNFT"),
                abi.encode(royaltyReceiver)
            ));
            console.log("DealersExeNFT deployed:", nft);
        } else {
            console.log("DealersExeNFT: skipped (exists)");
        }

        if (boosts == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(paymentHandler, "PAYMENT_HANDLER");
            boosts = _zkCreate(abi.encodePacked(
                vm.getCode("DealersExeBoosts.sol:DealersExeBoosts"),
                abi.encode(core, nft, paymentHandler)
            ));
            console.log("DealersExeBoosts deployed:", boosts);
        } else {
            console.log("DealersExeBoosts: skipped (exists)");
        }

        if (pve == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(areaRegistry, "AREA_REGISTRY");
            pve = _zkCreate(abi.encodePacked(
                vm.getCode("DealersExePVE.sol:DealersExePVE"),
                abi.encode(core, nft, areaRegistry)
            ));
            console.log("DealersExePVE deployed:", pve);
        } else {
            console.log("DealersExePVE: skipped (exists)");
        }

        if (pvp == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(areaRegistry, "AREA_REGISTRY");
            pvp = _zkCreate(abi.encodePacked(
                vm.getCode("DealersExePVP.sol:DealersExePVP"),
                abi.encode(core, nft, areaRegistry)
            ));
            console.log("DealersExePVP deployed:", pvp);
        } else {
            console.log("DealersExePVP: skipped (exists)");
        }

        if (claims == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(pve, "DEALERS_PVE");
            _requireAddress(pvp, "DEALERS_PVP");
            _requireAddress(devWallet, "DEV_WALLET");
            claims = _zkCreate(abi.encodePacked(
                vm.getCode("DealersExeClaims.sol:DealersExeClaims"),
                abi.encode(core, nft, pve, pvp, devWallet)
            ));
            console.log("DealersExeClaims deployed:", claims);
        } else {
            console.log("DealersExeClaims: skipped (exists)");
        }

        console.log("");
    }

    // =========================================================================
    //                           WIRING
    // =========================================================================

    function _wireAll() internal {
        console.log("Wiring references + authorizations...");

        IDealersExeCore c = IDealersExeCore(core);

        // Core references
        _setIfDifferent(c.drugRegistry(), drugRegistry, c.setDrugRegistry);
        _setIfDifferent(c.areaRegistry(), areaRegistry, c.setAreaRegistry);
        _setIfDifferent(c.nftContract(), nft, c.setNFTContract);
        _setIfDifferent(c.paymentHandler(), paymentHandler, c.setPaymentHandler);
        _setIfDifferent(c.randomness(), randomness, c.setRandomness);

        // Core authorizations
        _authorizeIfNeeded(c, pve);
        _authorizeIfNeeded(c, pvp);
        _authorizeIfNeeded(c, boosts);
        _authorizeIfNeeded(c, nft);
        if (claims != address(0)) _authorizeIfNeeded(c, claims);

        // DrugRegistry auth
        IDrugRegistry drugReg = IDrugRegistry(drugRegistry);
        if (!drugReg.authorizedContracts(core)) drugReg.authorizeContract(core, true);

        // PaymentHandler auth
        IPaymentHandler payHandler = IPaymentHandler(paymentHandler);
        if (!payHandler.authorizedContracts(core)) payHandler.authorizeContract(core, true);
        if (!payHandler.authorizedContracts(boosts)) payHandler.authorizeContract(boosts, true);

        // AreaRegistry -> Core
        IAreaRegistry areaReg = IAreaRegistry(areaRegistry);
        if (areaReg.coreContract() != core) areaReg.setCoreContract(core);

        // Module references
        IDealersExeNFT nftC = IDealersExeNFT(nft);
        _setIfDifferent(nftC.dealersExeCore(), core, nftC.setDealersExeCore);

        IBoostsContract boostsC = IBoostsContract(boosts);
        _setIfDifferent(boostsC.dealersExeCore(), core, boostsC.setDealersExeCore);
        _setIfDifferent(boostsC.dealersExeNFT(), nft, boostsC.setDealersExeNFT);
        _setIfDifferent(boostsC.paymentHandler(), paymentHandler, boostsC.setPaymentHandler);

        IPVEContract pveC = IPVEContract(pve);
        _setIfDifferent(pveC.dealersExeCore(), core, pveC.setDealersExeCore);
        _setIfDifferent(pveC.randomness(), randomness, pveC.setRandomness);

        IPVPContract pvpC = IPVPContract(pvp);
        _setIfDifferent(pvpC.core(), core, pvpC.setCore);
        _setIfDifferent(pvpC.drugRegistry(), drugRegistry, pvpC.setDrugRegistry);
        _setIfDifferent(pvpC.randomness(), randomness, pvpC.setRandomness);

        if (claims != address(0)) {
            IClaimsContract claimsC = IClaimsContract(claims);
            _setIfDifferent(claimsC.dealersExeCore(), core, claimsC.setDealersExeCore);
            _setIfDifferent(claimsC.dealersExeNFT(), nft, claimsC.setDealersExeNFT);
            _setIfDifferent(address(claimsC.pveContract()), pve, claimsC.setPVE);
            _setIfDifferent(address(claimsC.pvpContract()), pvp, claimsC.setPVP);
        }

        console.log("  Done.");
        console.log("");
    }

    function _setIfDifferent(address current, address target, function(address) external setter) internal {
        if (current != target) setter(target);
    }

    function _authorizeIfNeeded(IDealersExeCore c, address module) internal {
        if (!c.authorizedContracts(module)) c.authorizeContract(module, true);
    }

    // =========================================================================
    //                        REPUTATION TIERS
    // =========================================================================

    function _setupTiers() internal {
        IDealersExeCore c = IDealersExeCore(core);
        if (c.getTierCount() > 0) {
            console.log("Reputation tiers: already configured");
            return;
        }

        console.log("Setting up 10-tier reputation system...");

        ReputationTier[] memory tiers = new ReputationTier[](10);
        tiers[0] = ReputationTier({minReputation: 0, winBonus: 50, tieBonus: 25, lossPenalty: -2, repCap: 25, tierName: "Outsider"});
        tiers[1] = ReputationTier({minReputation: 50, winBonus: 40, tieBonus: 20, lossPenalty: -3, repCap: 22, tierName: "Associate"});
        tiers[2] = ReputationTier({minReputation: 150, winBonus: 15, tieBonus: 8, lossPenalty: -3, repCap: 18, tierName: "Dealer"});
        tiers[3] = ReputationTier({minReputation: 300, winBonus: 9, tieBonus: 3, lossPenalty: -4, repCap: 17, tierName: "Soldier"});
        tiers[4] = ReputationTier({minReputation: 700, winBonus: 8, tieBonus: 3, lossPenalty: -4, repCap: 16, tierName: "Capo"});
        tiers[5] = ReputationTier({minReputation: 1250, winBonus: 7, tieBonus: 3, lossPenalty: -5, repCap: 14, tierName: "Consigliere"});
        tiers[6] = ReputationTier({minReputation: 1900, winBonus: 6, tieBonus: 2, lossPenalty: -5, repCap: 12, tierName: "Underboss"});
        tiers[7] = ReputationTier({minReputation: 2600, winBonus: 5, tieBonus: 2, lossPenalty: -6, repCap: 12, tierName: "Don"});
        tiers[8] = ReputationTier({minReputation: 3500, winBonus: 4, tieBonus: 2, lossPenalty: -6, repCap: 10, tierName: "Godfather"});
        tiers[9] = ReputationTier({minReputation: 5000, winBonus: 3, tieBonus: 1, lossPenalty: -7, repCap: 8, tierName: "Legend"});

        c.setReputationTiers(tiers);
        c.setMaxReputation(6000);
        console.log("  10 tiers + MAX_REPUTATION=6000");
        console.log("");
    }

    // =========================================================================
    //                           SUMMARY
    // =========================================================================

    function _printSummary() internal view {
        console.log("==============================================");
        console.log("   Deployment Complete!");
        console.log("==============================================");
        console.log("");
        console.log("DRUG_REGISTRY=", drugRegistry);
        console.log("AREA_REGISTRY=", areaRegistry);
        console.log("DEALERS_CORE=", core);
        console.log("PAYMENT_HANDLER=", paymentHandler);
        console.log("RANDOMNESS=", randomness);
        console.log("DEALERS_NFT=", nft);
        console.log("DEALERS_BOOSTS=", boosts);
        console.log("DEALERS_PVE=", pve);
        console.log("DEALERS_PVP=", pvp);
        console.log("DEALERS_CLAIMS=", claims);
        console.log("");
        console.log("Remaining:");
        console.log("  1. Deploy renderers (EVM mode, no --zksync)");
        console.log("  2. Set renderers on NFT");
        console.log("  3. Enable minting: cast send $DEALERS_NFT \"setMintStatus(uint8)\" 3");
    }
}

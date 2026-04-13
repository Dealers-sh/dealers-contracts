// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupWiring - Configure all cross-contract references and authorizations
 * @dev Idempotent — safe to re-run. Checks current state before calling setters.
 *      Requires all 9 contract addresses set in .env.
 *
 * What this configures:
 *
 *   REFERENCES (setters):
 *     Core ← drugRegistry, areaRegistry, nft, paymentHandler, randomness
 *     NFT ← core
 *     AreaRegistry ← core
 *     PVP ← drugRegistry, randomness
 *     PVE ← randomness
 *     Claims ← core, nft, pve, pvp (optional)
 *     Actions ← paymentHandler, randomness (optional)
 *
 *   AUTHORIZATIONS:
 *     Core.authorizeContract:           PVE, PVP, Boosts, NFT, Claims (optional), Actions (optional)
 *     DrugRegistry.authorizeContract:   Core
 *     PaymentHandler.authorizeContract: Core, Boosts, Actions (optional)
 *     Randomness.authorizeResolver:     Core, PVE, PVP, Actions (optional)
 *
 * Usage:
 *   source .env && forge script script/SetupWiring.s.sol:SetupWiring \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract SetupWiring is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(drugRegistry, "DRUG_REGISTRY");
        _requireAddress(areaRegistry, "AREA_REGISTRY");
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(paymentHandler, "PAYMENT_HANDLER");
        _requireAddress(randomness, "RANDOMNESS");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(boosts, "DEALERS_BOOSTS");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");

        vm.startBroadcast();

        _setupCoreReferences();
        _authorizeModulesInCore();
        _setupRegistryAuthorizations();
        _setupModuleReferences();

        vm.stopBroadcast();

        console.log("Wiring complete.");
    }

    // =========================================================================
    //                        CORE REFERENCES
    // =========================================================================

    function _setupCoreReferences() internal {
        console.log("Core references:");
        IDealersExeCore c = IDealersExeCore(core);

        if (c.drugRegistry() != drugRegistry) {
            c.setDrugRegistry(drugRegistry);
            console.log("  DrugRegistry: SET");
        } else {
            console.log("  DrugRegistry: ok");
        }

        if (c.areaRegistry() != areaRegistry) {
            c.setAreaRegistry(areaRegistry);
            console.log("  AreaRegistry: SET");
        } else {
            console.log("  AreaRegistry: ok");
        }

        if (c.nftContract() != nft) {
            c.setNFTContract(nft);
            console.log("  NFT: SET");
        } else {
            console.log("  NFT: ok");
        }

        if (c.paymentHandler() != paymentHandler) {
            c.setPaymentHandler(paymentHandler);
            console.log("  PaymentHandler: SET");
        } else {
            console.log("  PaymentHandler: ok");
        }

        if (c.randomness() != randomness) {
            c.setRandomness(randomness);
            console.log("  Randomness: SET");
        } else {
            console.log("  Randomness: ok");
        }
        console.log("");
    }

    // =========================================================================
    //                     CORE AUTHORIZATIONS
    // =========================================================================

    function _authorizeModulesInCore() internal {
        console.log("Core authorizations:");
        IDealersExeCore c = IDealersExeCore(core);

        _authorizeIfNeeded(c, pve, "PVE");
        _authorizeIfNeeded(c, pvp, "PVP");
        _authorizeIfNeeded(c, boosts, "Boosts");
        _authorizeIfNeeded(c, nft, "NFT");
        if (claims != address(0)) _authorizeIfNeeded(c, claims, "Claims");
        if (actions != address(0)) _authorizeIfNeeded(c, actions, "Actions");
        console.log("");
    }

    function _authorizeIfNeeded(IDealersExeCore c, address module, string memory name) internal {
        if (!c.authorizedContracts(module)) {
            c.authorizeContract(module, true);
            console.log(string.concat("  ", name, ": AUTHORIZED"));
        } else {
            console.log(string.concat("  ", name, ": ok"));
        }
    }

    // =========================================================================
    //                    REGISTRY AUTHORIZATIONS
    // =========================================================================

    function _setupRegistryAuthorizations() internal {
        console.log("Registry authorizations:");

        IDrugRegistry drugReg = IDrugRegistry(drugRegistry);
        if (!drugReg.authorizedContracts(core)) {
            drugReg.authorizeContract(core, true);
            console.log("  DrugRegistry -> Core: AUTHORIZED");
        } else {
            console.log("  DrugRegistry -> Core: ok");
        }

        IPaymentHandler payHandler = IPaymentHandler(paymentHandler);
        if (!payHandler.authorizedContracts(core)) {
            payHandler.authorizeContract(core, true);
            console.log("  PaymentHandler -> Core: AUTHORIZED");
        } else {
            console.log("  PaymentHandler -> Core: ok");
        }
        if (!payHandler.authorizedContracts(boosts)) {
            payHandler.authorizeContract(boosts, true);
            console.log("  PaymentHandler -> Boosts: AUTHORIZED");
        } else {
            console.log("  PaymentHandler -> Boosts: ok");
        }
        if (actions != address(0)) {
            if (!payHandler.authorizedContracts(actions)) {
                payHandler.authorizeContract(actions, true);
                console.log("  PaymentHandler -> Actions: AUTHORIZED");
            } else {
                console.log("  PaymentHandler -> Actions: ok");
            }
        }

        IAreaRegistry areaReg = IAreaRegistry(areaRegistry);
        if (areaReg.coreContract() != core) {
            areaReg.setCoreContract(core);
            console.log("  AreaRegistry -> Core: SET");
        } else {
            console.log("  AreaRegistry -> Core: ok");
        }

        IRandomness rng = IRandomness(randomness);
        _authorizeResolverIfNeeded(rng, core, "Randomness -> Core");
        _authorizeResolverIfNeeded(rng, pve, "Randomness -> PVE");
        _authorizeResolverIfNeeded(rng, pvp, "Randomness -> PVP");
        if (actions != address(0)) _authorizeResolverIfNeeded(rng, actions, "Randomness -> Actions");

        console.log("");
    }

    // =========================================================================
    //                      MODULE REFERENCES
    // =========================================================================

    function _setupModuleReferences() internal {
        console.log("Module references:");

        IDealersExeNFT nftContract = IDealersExeNFT(nft);
        _setIfNeeded(nftContract.dealersExeCore(), core, "NFT -> Core", nftContract.setDealersExeCore);

        IBoostsContract boostsContract = IBoostsContract(boosts);
        _setIfNeeded(boostsContract.dealersExeCore(), core, "Boosts -> Core", boostsContract.setDealersExeCore);
        _setIfNeeded(boostsContract.dealersExeNFT(), nft, "Boosts -> NFT", boostsContract.setDealersExeNFT);
        _setIfNeeded(boostsContract.paymentHandler(), paymentHandler, "Boosts -> PaymentHandler", boostsContract.setPaymentHandler);

        IPVEContract pveContract = IPVEContract(pve);
        _setIfNeeded(pveContract.dealersExeCore(), core, "PVE -> Core", pveContract.setDealersExeCore);
        _setIfNeeded(pveContract.randomness(), randomness, "PVE -> Randomness", pveContract.setRandomness);

        IPVPContract pvpContract = IPVPContract(pvp);
        _setIfNeeded(pvpContract.core(), core, "PVP -> Core", pvpContract.setCore);
        _setIfNeeded(pvpContract.drugRegistry(), drugRegistry, "PVP -> DrugRegistry", pvpContract.setDrugRegistry);
        _setIfNeeded(pvpContract.randomness(), randomness, "PVP -> Randomness", pvpContract.setRandomness);

        if (claims != address(0)) {
            IClaimsContract claimsContract = IClaimsContract(claims);
            _setIfNeeded(claimsContract.dealersExeCore(), core, "Claims -> Core", claimsContract.setDealersExeCore);
            _setIfNeeded(claimsContract.dealersExeNFT(), nft, "Claims -> NFT", claimsContract.setDealersExeNFT);
            _setIfNeeded(address(claimsContract.pveContract()), pve, "Claims -> PVE", claimsContract.setPVE);
            _setIfNeeded(address(claimsContract.pvpContract()), pvp, "Claims -> PVP", claimsContract.setPVP);
        }

        if (actions != address(0)) {
            IActionsContract actionsContract = IActionsContract(actions);
            _setIfNeeded(actionsContract.paymentHandler(), paymentHandler, "Actions -> PaymentHandler", actionsContract.setPaymentHandler);
            _setIfNeeded(actionsContract.randomness(), randomness, "Actions -> Randomness", actionsContract.setRandomness);
        }

        console.log("");
    }

    function _authorizeResolverIfNeeded(IRandomness rng, address resolver, string memory label) internal {
        if (!rng.isAuthorizedResolver(resolver)) {
            rng.authorizeResolver(resolver, true);
            console.log(string.concat("  ", label, ": AUTHORIZED"));
        } else {
            console.log(string.concat("  ", label, ": ok"));
        }
    }

    function _setIfNeeded(address current, address target, string memory label, function(address) external setter) internal {
        if (current != target) {
            setter(target);
            console.log(string.concat("  ", label, ": SET"));
        } else {
            console.log(string.concat("  ", label, ": ok"));
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/ClaimsAchievements.s.sol";
import "../base/AreasConfig.s.sol";
import "../base/TiersConfig.s.sol";

/**
 * @title DeployAll - Deploy all game contracts + full setup
 * @dev Deploys in dependency order, skipping contracts that already have an address in .env.
 *      After deploying: drugs, areas, wiring, tiers, claims, chat rooms.
 *
 * Required env vars: DEV_WALLET, BANK_VAULT, ROYALTY_RECEIVER, PYTH_ENTROPY (network-prefixed)
 * Optional env vars: DRUG_REGISTRY, AREA_REGISTRY, DEALERS_CORE, PAYMENT_HANDLER,
 *                    RANDOMNESS, DEALERS_NFT, DEALERS_BOOSTS, DEALERS_PVE, DEALERS_PVP,
 *                    DEALERS_CLAIMS, DEALERS_HEISTS (set these to skip deployment of already-deployed contracts)
 *
 * Usage:
 *     source .env && forge script script/deploy/DeployAll.s.sol:DeployAll \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
interface IHeistsWiring {
    function setActions(address _actions) external;
    function actions() external view returns (address);
}

contract DeployAll is ClaimsAchievements, AreasConfig, TiersConfig {
    bool internal skipNFT;

    function run() external {
        _runImpl();
    }

    /**
     * @notice Deploy every game contract EXCEPT DealersNFT (and renderers, which live in separate scripts).
     * @dev Use when you need stable game-contract addresses (e.g. session-key approval) before locking in
     *      NFT/GTM details. Boosts/PVE/PVP/Claims/Actions/ChatFactory are constructed with `devWallet` as a
     *      placeholder NFT and re-pointed later via SetupWiring once the real NFT is deployed.
     *      NFT-touching Core wiring (setNFTContract, authorize NFT, NFT.setDealersCore) is skipped here and
     *      picked up idempotently by SetupWiring on the follow-up run.
     */
    function runGameOnly() external {
        skipNFT = true;
        _runImpl();
    }

    function _runImpl() internal {
        _loadAddresses();
        _requireAddress(devWallet, "DEV_WALLET");
        _requireAddress(bankVault, "BANK_VAULT");
        if (!skipNFT) _requireAddress(royaltyReceiver, "ROYALTY_RECEIVER");

        console.log("==============================================");
        if (skipNFT) {
            console.log("   Dealers.sh - Deploy Game Only (NFT skipped)");
        } else {
            console.log("   Dealers.sh - Deploy All");
        }
        console.log("==============================================");
        console.log("");

        vm.startBroadcast();

        // 1. Deploy contracts in dependency order
        _deployIfNeeded();

        // 2. Register drugs + create game areas (must run before wiring)
        _setupDrugs();
        _setupAreas();

        // 3. Wire references + authorizations
        _wireAll();

        // 4. Setup reputation tiers
        _setupTiers();

        // 5. Retune Kingpin + Godfather boost perks (constructor sets defaults)
        _setupBoosts();

        // 5b. Economy rebalance setters (PVE odds, jail chance, PVP cash steal)
        _setupRebalance();

        // 6. Setup achievements
        _setupClaims();

        // 7. Setup chat rooms
        _setupChat();

        vm.stopBroadcast();

        _saveAddresses();
        _printSummary();
    }

    /**
     * @dev Returns the NFT address to embed in module constructors.
     *      In skipNFT mode the real NFT doesn't exist yet, so we use devWallet as a non-zero
     *      placeholder that satisfies the ctor's `address(0)` check without granting any privileges.
     *      Subsequent SetupWiring run replaces it with the real NFT via the modules' setters.
     *      The chosen address is persisted to deployments JSON as `nftCtor` so verify-source.sh
     *      can re-encode constructor args correctly when verifying on Etherscan.
     */
    function _nftForCtor() internal returns (address) {
        if (skipNFT) {
            nftCtor = devWallet;
            return devWallet;
        }
        return nft;
    }

    // =========================================================================
    //                           DEPLOYMENTS
    // =========================================================================

    function _deployIfNeeded() internal {
        if (drugRegistry == address(0)) {
            drugRegistry = _zkCreate(vm.getCode("DealersDrugRegistry.sol:DealersDrugRegistry"));
            console.log("DealersDrugRegistry deployed:", drugRegistry);
        } else {
            console.log("DealersDrugRegistry: skipped (exists)");
        }

        // WARNING: Redeploying AreaRegistry resets the dealer-in-area reverse index.
        // Dealer locations in Core are unaffected. Index re-populates as dealers move.
        // On mainnet, prefer admin functions on the existing registry instead.
        if (areaRegistry == address(0)) {
            _requireAddress(drugRegistry, "DRUG_REGISTRY");
            areaRegistry = _zkCreate(
                abi.encodePacked(vm.getCode("DealersAreaRegistry.sol:DealersAreaRegistry"), abi.encode(drugRegistry))
            );
            console.log("DealersAreaRegistry deployed:", areaRegistry);
        } else {
            console.log("DealersAreaRegistry: skipped (exists)");
        }

        if (core == address(0)) {
            core = _zkCreate(vm.getCode("DealersCore.sol:DealersCore"));
            console.log("DealersCore deployed:", core);
        } else {
            console.log("DealersCore: skipped (exists)");
        }

        if (paymentHandler == address(0)) {
            paymentHandler = _zkCreate(
                abi.encodePacked(
                    vm.getCode("DealersPaymentHandler.sol:DealersPaymentHandler"), abi.encode(devWallet, bankVault)
                )
            );
            console.log("DealersPaymentHandler deployed:", paymentHandler);
        } else {
            console.log("DealersPaymentHandler: skipped (exists)");
        }

        if (randomness == address(0)) {
            randomness = _zkCreate(vm.getCode("DealersRandomness.sol:DealersRandomness"));
            console.log("DealersRandomness deployed:", randomness);
        } else {
            console.log("DealersRandomness: skipped (exists)");
        }

        if (skipNFT) {
            console.log("DealersNFT: skipped (game-only mode, placeholder=devWallet)");
        } else if (nft == address(0)) {
            nft = _zkCreate(abi.encodePacked(vm.getCode("DealersNFT.sol:DealersNFT"), abi.encode(royaltyReceiver)));
            console.log("DealersNFT deployed:", nft);
        } else {
            console.log("DealersNFT: skipped (exists)");
        }

        address nftCtor = _nftForCtor();

        if (boosts == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nftCtor, "DEALERS_NFT or DEV_WALLET (game-only)");
            _requireAddress(paymentHandler, "PAYMENT_HANDLER");
            boosts = _zkCreate(
                abi.encodePacked(
                    vm.getCode("DealersBoosts.sol:DealersBoosts"), abi.encode(core, nftCtor, paymentHandler)
                )
            );
            console.log("DealersBoosts deployed:", boosts);
        } else {
            console.log("DealersBoosts: skipped (exists)");
        }

        if (pve == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nftCtor, "DEALERS_NFT or DEV_WALLET (game-only)");
            _requireAddress(areaRegistry, "AREA_REGISTRY");
            pve = _zkCreate(
                abi.encodePacked(vm.getCode("DealersPVE.sol:DealersPVE"), abi.encode(core, nftCtor, areaRegistry))
            );
            console.log("DealersPVE deployed:", pve);
        } else {
            console.log("DealersPVE: skipped (exists)");
        }

        if (pvp == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nftCtor, "DEALERS_NFT or DEV_WALLET (game-only)");
            _requireAddress(areaRegistry, "AREA_REGISTRY");
            pvp = _zkCreate(
                abi.encodePacked(vm.getCode("DealersPVP.sol:DealersPVP"), abi.encode(core, nftCtor, areaRegistry))
            );
            console.log("DealersPVP deployed:", pvp);
        } else {
            console.log("DealersPVP: skipped (exists)");
        }

        if (claims == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nftCtor, "DEALERS_NFT or DEV_WALLET (game-only)");
            _requireAddress(pve, "DEALERS_PVE");
            _requireAddress(pvp, "DEALERS_PVP");
            claims = _zkCreate(
                abi.encodePacked(vm.getCode("DealersClaims.sol:DealersClaims"), abi.encode(core, nftCtor, pve, pvp))
            );
            console.log("DealersClaims deployed:", claims);
        } else {
            console.log("DealersClaims: skipped (exists)");
        }

        if (actions == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nftCtor, "DEALERS_NFT or DEV_WALLET (game-only)");
            _requireAddress(areaRegistry, "AREA_REGISTRY");
            actions = _zkCreate(
                abi.encodePacked(
                    vm.getCode("DealersActions.sol:DealersActions"), abi.encode(core, nftCtor, areaRegistry)
                )
            );
            console.log("DealersActions deployed:", actions);
        } else {
            console.log("DealersActions: skipped (exists)");
        }

        if (multicall == address(0)) {
            multicall = _zkCreate(
                abi.encodePacked(
                    vm.getCode("DealersMulticall.sol:DealersMulticall"),
                    abi.encode(core, pve, pvp, areaRegistry, drugRegistry)
                )
            );
            console.log("DealersMulticall deployed:", multicall);
        } else {
            console.log("DealersMulticall: skipped (exists)");
        }

        if (chatFactory == address(0)) {
            _requireAddress(nftCtor, "DEALERS_NFT or DEV_WALLET (game-only)");
            chatFactory = _zkCreate(
                abi.encodePacked(vm.getCode("DealersChatFactory.sol:DealersChatFactory"), abi.encode(nftCtor))
            );
            console.log("DealersChatFactory deployed:", chatFactory);
        } else {
            console.log("DealersChatFactory: skipped (exists)");
        }

        if (skipNFT) {
            console.log("DealersHeists: skipped (game-only mode; needs real NFT)");
        } else if (heists == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(randomness, "RANDOMNESS");
            _requireAddress(paymentHandler, "PAYMENT_HANDLER");
            _requireAddress(drugRegistry, "DRUG_REGISTRY");
            address entropy = _envAddrForNetwork("PYTH_ENTROPY");
            _requireAddress(entropy, "PYTH_ENTROPY");
            heists = _zkCreate(
                abi.encodePacked(
                    vm.getCode("DealersHeists.sol:DealersHeists"),
                    abi.encode(core, nft, randomness, paymentHandler, drugRegistry, entropy)
                )
            );
            console.log("DealersHeists deployed:", heists);
        } else {
            console.log("DealersHeists: skipped (exists)");
        }

        console.log("");
    }

    // =========================================================================
    //                           WIRING
    // =========================================================================

    function _wireAll() internal {
        console.log("Wiring references + authorizations...");

        IDealersCore c = IDealersCore(core);

        // Core references
        _setIfDifferent(c.drugRegistry(), drugRegistry, c.setDrugRegistry);
        _setIfDifferent(c.areaRegistry(), areaRegistry, c.setAreaRegistry);
        if (!skipNFT) _setIfDifferent(c.nftContract(), nft, c.setNFTContract);
        _setIfDifferent(c.paymentHandler(), paymentHandler, c.setPaymentHandler);

        // Core authorizations
        _authorizeIfNeeded(c, pve);
        _authorizeIfNeeded(c, pvp);
        _authorizeIfNeeded(c, boosts);
        if (!skipNFT) _authorizeIfNeeded(c, nft);
        if (claims != address(0)) _authorizeIfNeeded(c, claims);
        if (actions != address(0)) _authorizeIfNeeded(c, actions);

        // PaymentHandler auth
        IPaymentHandler payHandler = IPaymentHandler(paymentHandler);
        if (!payHandler.authorizedContracts(core)) payHandler.authorizeContract(core, true);
        if (!payHandler.authorizedContracts(boosts)) payHandler.authorizeContract(boosts, true);
        if (actions != address(0) && !payHandler.authorizedContracts(actions)) {
            payHandler.authorizeContract(actions, true);
        }

        // AreaRegistry -> Core
        IAreaRegistry areaReg = IAreaRegistry(areaRegistry);
        if (areaReg.coreContract() != core) areaReg.setCoreContract(core);

        // Randomness authorizations (Core no longer consumes randomness)
        IRandomness rng = IRandomness(randomness);
        if (!rng.isAuthorizedResolver(pve)) rng.authorizeResolver(pve, true);
        if (!rng.isAuthorizedResolver(pvp)) rng.authorizeResolver(pvp, true);
        if (actions != address(0) && !rng.isAuthorizedResolver(actions)) rng.authorizeResolver(actions, true);

        // DealersActions jailer authorizations (centralized arrest policy)
        if (actions != address(0)) {
            IActionsContract actionsAuth = IActionsContract(actions);
            if (!actionsAuth.authorizedJailers(pve)) actionsAuth.authorizeJailer(pve, true);
            if (!actionsAuth.authorizedJailers(pvp)) actionsAuth.authorizeJailer(pvp, true);
        }

        // Heists (daily heist module) auth + wiring. Claims.setHeists is handled in the Claims block.
        if (heists != address(0)) {
            _authorizeIfNeeded(c, heists);
            if (!payHandler.authorizedContracts(heists)) payHandler.authorizeContract(heists, true);
            if (!rng.isAuthorizedResolver(heists)) rng.authorizeResolver(heists, true);
            if (actions != address(0)) {
                if (IHeistsWiring(heists).actions() != actions) IHeistsWiring(heists).setActions(actions);
                if (!IActionsContract(actions).authorizedJailers(heists)) {
                    IActionsContract(actions).authorizeJailer(heists, true);
                }
            }
        }

        // Module references
        if (!skipNFT) {
            IDealersNFT nftC = IDealersNFT(nft);
            _setIfDifferent(nftC.dealersCore(), core, nftC.setDealersCore);
        }

        IBoostsContract boostsC = IBoostsContract(boosts);
        _setIfDifferent(boostsC.dealersCore(), core, boostsC.setDealersCore);
        if (!skipNFT) _setIfDifferent(boostsC.dealersNFT(), nft, boostsC.setDealersNFT);
        _setIfDifferent(boostsC.paymentHandler(), paymentHandler, boostsC.setPaymentHandler);

        IPVEContract pveC = IPVEContract(pve);
        _setIfDifferent(pveC.dealersCore(), core, pveC.setDealersCore);
        _setIfDifferent(pveC.areaRegistry(), areaRegistry, pveC.setAreaRegistry);
        _setIfDifferent(pveC.randomness(), randomness, pveC.setRandomness);
        if (actions != address(0)) {
            _setIfDifferent(pveC.actions(), actions, pveC.setActions);
        }

        IPVPContract pvpC = IPVPContract(pvp);
        _setIfDifferent(pvpC.core(), core, pvpC.setCore);
        _setIfDifferent(pvpC.areaRegistry(), areaRegistry, pvpC.setAreaRegistry);
        _setIfDifferent(pvpC.drugRegistry(), drugRegistry, pvpC.setDrugRegistry);
        _setIfDifferent(pvpC.randomness(), randomness, pvpC.setRandomness);
        if (actions != address(0)) {
            _setIfDifferent(pvpC.actions(), actions, pvpC.setActions);
        }

        if (claims != address(0)) {
            IClaimsContract claimsC = IClaimsContract(claims);
            _setIfDifferent(claimsC.dealersCore(), core, claimsC.setDealersCore);
            if (!skipNFT) _setIfDifferent(claimsC.dealersNFT(), nft, claimsC.setDealersNFT);
            _setIfDifferent(address(claimsC.pveContract()), pve, claimsC.setPVE);
            _setIfDifferent(address(claimsC.pvpContract()), pvp, claimsC.setPVP);
            if (heists != address(0)) {
                _setIfDifferent(claimsC.heistsContract(), heists, claimsC.setHeists);
            }
        }

        if (actions != address(0)) {
            IActionsContract actionsC = IActionsContract(actions);
            _setIfDifferent(actionsC.paymentHandler(), paymentHandler, actionsC.setPaymentHandler);
            _setIfDifferent(actionsC.areaRegistry(), areaRegistry, actionsC.setAreaRegistry);
            _setIfDifferent(actionsC.randomness(), randomness, actionsC.setRandomness);
        }

        if (multicall != address(0)) {
            IMulticallContract mc = IMulticallContract(multicall);
            _setIfDifferent(mc.core(), core, mc.setCore);
            _setIfDifferent(mc.pve(), pve, mc.setPVE);
            _setIfDifferent(mc.pvp(), pvp, mc.setPVP);
            _setIfDifferent(mc.areaRegistry(), areaRegistry, mc.setAreaRegistry);
            _setIfDifferent(mc.drugRegistry(), drugRegistry, mc.setDrugRegistry);
            _setIfDifferent(mc.boosts(), boosts, mc.setBoosts);
        }

        console.log("  Done.");
        console.log("");
    }

    function _setIfDifferent(address current, address target, function(address) external setter) internal {
        if (current != target) setter(target);
    }

    function _authorizeIfNeeded(IDealersCore c, address module) internal {
        if (!c.authorizedContracts(module)) c.authorizeContract(module, true);
    }

    // =========================================================================
    //                        DRUG & AREA SETUP
    // =========================================================================

    function _setupDrugs() internal {
        IDrugRegistry reg = IDrugRegistry(drugRegistry);

        if (reg.getTotalDrugs() > 0) {
            console.log("Drugs: already configured");
            return;
        }

        console.log("Registering 11 drugs...");
        reg.createDrug("Goods", 0, 75);
        reg.createDrug("Contraband", 1, 500);
        reg.createDrug("Jewels", 2, 2500);
        reg.createDrug("Weed", 0, 1);
        reg.createDrug("XTC", 1, 10);
        reg.createDrug("Cocaine", 2, 100);
        reg.createDrug("Shrooms", 1, 12);
        reg.createDrug("Heroin", 2, 150);
        reg.createDrug("Opioids", 0, 18);
        reg.createDrug("Meth", 1, 25);
        reg.createDrug("Fentanyl", 2, 200);
        console.log("  11 drugs registered");
        console.log("");
    }

    function _setupAreas() internal {
        _configureAreas(IAreaRegistry(areaRegistry));
        console.log("");
    }

    // =========================================================================
    //                        REPUTATION TIERS
    // =========================================================================

    function _setupTiers() internal {
        // Core's constructor seeds a default ladder, so always re-apply the canonical caps
        // (setReputationTiers overwrites) instead of skipping when tiers already exist —
        // otherwise a fresh deploy would keep the constructor's stale upper caps.
        _configureTiers(IDealersCore(core));
        console.log("  10 tiers + MAX_REPUTATION=75000 (Legend is soft-bleed +4/+2/-10 repCap=8)");
        console.log("");
    }

    // =========================================================================
    //                        ECONOMY REBALANCE
    // =========================================================================

    /**
     * @dev Mirrors SetupRebalance.s.sol so fresh deploys carry the sim-calibrated economy
     *      out-of-the-box (constructor defaults are stale). Keep both in sync.
     */
    function _setupRebalance() internal {
        console.log("Applying economy rebalance (PVE odds 25/50/25, stake scaling, jail 0.7%%/heat, cash steal 2%%)...");

        IPVEContract(pve).setOutcomeOdds(50, 25);
        IPVEContract(pve).setStakeScaling(2500, 10000);

        IDealersCore(core).setCoreConfig(
            IDealersCore.CoreConfig({
                attemptResetFee: 0.001 ether,
                bribeCopFee: 0.001 ether,
                cashTopupPrice: 0.001 ether,
                cashTopupAmount: 100,
                cashPurchaseThreshold: 10,
                jailRepPenaltyPercent: 10,
                jailRepPenaltyCap: 50,
                wantedPosterSuccessChance: 50,
                breakoutSuccessChance: 50,
                jailDrugConfiscationPercent: 3,
                starterCash: 250,
                jailChancePerHeat: 7
            })
        );

        IPVPContract(pvp).setPVPConfig(
            IPVPContract.PVPConfig({
                minReputation: 200,
                baseWinChance: 50,
                minWinChance: 25,
                maxWinChance: 75,
                maxAttacksPerDay: 3,
                drugStealPercent: 2,
                cashStealPercent: 2,
                rarityWeightCommon: 75,
                rarityWeightUncommon: 20,
                rarityWeightRare: 5,
                repRangePercent: 25,
                defenderRepBonus: 2,
                repRangeThreshold: 22000
            })
        );

        console.log("");
    }

    // =========================================================================
    //                           BOOSTS RETUNE
    // =========================================================================

    /**
     * @dev Mirrors SetupBoosts.s.sol: drug/cash multipliers trimmed to 1.10-1.25x so
     *      max-stake hustles under the rep-scaled stake ceiling stay inside the 5.1 daily
     *      cash bands. Keep both in sync.
     */
    function _setupBoosts() internal {
        IBoostsAdmin b = IBoostsAdmin(boosts);

        console.log("Setting boost tiers (trimmed drug/cash multipliers)...");

        b.setBoostTier(
            1,
            IBoostsAdmin.BoostTier({
                price: 0.0025 ether,
                duration: 3 days,
                drugMultiplier: 110,
                repMultiplier: 110,
                extraAttempts: 2,
                freeAreaMovement: false,
                cashMultiplier: 110,
                isActive: true
            })
        );

        b.setBoostTier(
            2,
            IBoostsAdmin.BoostTier({
                price: 0.005 ether,
                duration: 7 days,
                drugMultiplier: 115,
                repMultiplier: 115,
                extraAttempts: 3,
                freeAreaMovement: false,
                cashMultiplier: 115,
                isActive: true
            })
        );

        b.setBoostTier(
            3,
            IBoostsAdmin.BoostTier({
                price: 0.01 ether,
                duration: 14 days,
                drugMultiplier: 120,
                repMultiplier: 125,
                extraAttempts: 6,
                freeAreaMovement: true,
                cashMultiplier: 120,
                isActive: true
            })
        );

        b.setBoostTier(
            4,
            IBoostsAdmin.BoostTier({
                price: 0.023 ether,
                duration: 30 days,
                drugMultiplier: 125,
                repMultiplier: 135,
                extraAttempts: 7,
                freeAreaMovement: true,
                cashMultiplier: 125,
                isActive: true
            })
        );

        console.log("  Drug/cash mult: 1.10/1.15/1.20/1.25x | rep mult + attempts unchanged");
        console.log("");
    }

    // =========================================================================
    //                           CLAIMS
    // =========================================================================

    function _setupClaims() internal {
        IClaimsContract c = IClaimsContract(claims);

        if (c.nextAchievementId() > 0) {
            console.log("Claims: already configured");
            return;
        }

        _configureAchievements(c, heists);
    }

    // =========================================================================
    //                           CHAT ROOMS
    // =========================================================================

    function _setupChat() internal {
        IChatFactory factory = IChatFactory(chatFactory);

        bytes32 worldKey = factory.roomKey(IChatFactory.RoomType.WORLD, 0);
        (address existingWorld,,) = factory.getRoomInfo(worldKey);

        if (existingWorld != address(0)) {
            console.log("Chat rooms: already configured");
            return;
        }

        console.log("Setting up chat rooms...");

        address worldRoom = factory.createRoom(IChatFactory.RoomType.WORLD, 0, address(0));
        console.log("  WORLD room:", worldRoom);

        address gate =
            _zkCreate(abi.encodePacked(vm.getCode("DealersAreaChatGate.sol:DealersAreaChatGate"), abi.encode(core)));
        console.log("  AreaChatGate:", gate);

        uint8[9] memory areas = [uint8(1), 2, 3, 4, 5, 6, 7, 254, 255];
        for (uint256 i = 0; i < areas.length; ++i) {
            factory.createRoom(IChatFactory.RoomType.AREA, areas[i], gate);
            console.log("  Area", areas[i], "room: created");
        }

        console.log("");
    }

    // =========================================================================
    //                           SUMMARY
    // =========================================================================

    function _printSummary() internal view {
        console.log("==============================================");
        if (skipNFT) {
            console.log("   Game-only Deployment Complete!");
        } else {
            console.log("   Deployment Complete!");
        }
        console.log("==============================================");
        console.log("");
        console.log("DRUG_REGISTRY=", drugRegistry);
        console.log("AREA_REGISTRY=", areaRegistry);
        console.log("DEALERS_CORE=", core);
        console.log("PAYMENT_HANDLER=", paymentHandler);
        console.log("RANDOMNESS=", randomness);
        if (skipNFT) {
            console.log("DEALERS_NFT= <DEFERRED - placeholder=devWallet in module ctors>");
        } else {
            console.log("DEALERS_NFT=", nft);
        }
        console.log("DEALERS_BOOSTS=", boosts);
        console.log("DEALERS_PVE=", pve);
        console.log("DEALERS_PVP=", pvp);
        console.log("DEALERS_CLAIMS=", claims);
        console.log("DEALERS_ACTIONS=", actions);
        console.log("DEALER_MULTICALL=", multicall);
        console.log("CHAT_FACTORY=", chatFactory);
        if (!skipNFT) console.log("DEALERS_HEISTS=", heists);
        console.log("");
        if (skipNFT) {
            console.log("Game-only mode notes:");
            console.log("  - NFT NOT deployed; nft saved as 0x0 in deployments JSON.");
            console.log("  - Boosts/PVE/PVP/Claims/Actions/ChatFactory hold devWallet as placeholder NFT.");
            console.log("  - Core.nftContract NOT set; NFT NOT authorized on Core.");
            console.log("");
            console.log("To finish later:");
            console.log("  1. Deploy NFT:    forge script ... DeployNFT.s.sol --broadcast --zksync");
            console.log("  2. Re-wire:       forge script ... SetupWiring.s.sol --broadcast --zksync");
            console.log("                    (idempotent; points every module's NFT ref at the real NFT)");
            console.log("  3. Deploy SVG renderer (EVM mode, no --zksync)");
            console.log("  4. Deploy HTML renderer (--zksync)");
            console.log("  5. Upload gzip JS + set gzip filename on HTML renderer");
            console.log("  6. Enable minting: cast send $DEALERS_NFT \"setMintOpen(bool)\" true");
        } else {
            console.log("Remaining:");
            console.log("  1. Deploy SVG renderer (EVM mode, no --zksync)");
            console.log("  2. Deploy HTML renderer (--zksync)");
            console.log("  3. Upload gzip JS + set gzip filename on HTML renderer");
            console.log("  4. Enable minting: cast send $DEALERS_NFT \"setMintOpen(bool)\" true");
        }
    }
}

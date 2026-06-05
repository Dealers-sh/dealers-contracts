// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployAll - Deploy all game contracts + full setup
 * @dev Deploys in dependency order, skipping contracts that already have an address in .env.
 *      After deploying: drugs, areas, wiring, tiers, claims, chat rooms.
 *
 * Required env vars: DEV_WALLET, BANK_VAULT, ROYALTY_RECEIVER
 * Optional env vars: DRUG_REGISTRY, AREA_REGISTRY, DEALERS_CORE, PAYMENT_HANDLER,
 *                    RANDOMNESS, DEALERS_NFT, DEALERS_BOOSTS, DEALERS_PVE, DEALERS_PVP,
 *                    DEALERS_CLAIMS (set these to skip deployment of already-deployed contracts)
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployAll.s.sol:DeployAll \
 *       --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *       --skip "RendererSVG"
 */
contract DeployAll is DeployBase {
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
        IAreaRegistry reg = IAreaRegistry(areaRegistry);

        if (reg.getTotalAreas() > 0) {
            console.log("Areas: already configured");
            return;
        }

        console.log("Creating 7 game areas (Manhattan/Amsterdam free, Dubai premium)...");

        // Manhattan: starter, FREE movement
        reg.createArea("Manhattan", 0, 0, false, false);
        reg.batchConfigureAreaDrugs(1, _d(4, 5, 6), _d(1, 12, 120), _d(1, 10, 100));

        // Amsterdam: Associate entry, FREE movement
        reg.createArea("Amsterdam", 0, 75, false, false);
        reg.batchConfigureAreaDrugs(2, _d(4, 7, 8), _d(3, 15, 180), _d(2, 12, 150));

        // Colombia: Dealer entry, first paid area (0.001 ETH), also PVP unlock
        reg.createArea("Colombia", 0.001 ether, 200, false, false);
        reg.batchConfigureAreaDrugs(3, _d(4, 6, 8), _d(1, 60, 90), _d(1, 50, 75));

        // Hong Kong: Soldier entry
        reg.createArea("Hong Kong", 0.001 ether, 500, false, false);
        reg.batchConfigureAreaDrugs(4, _d(9, 10, 8), _d(18, 28, 140), _d(15, 22, 110));

        // Seoul: Capo entry
        reg.createArea("Seoul", 0.001 ether, 1200, false, false);
        reg.batchConfigureAreaDrugs(5, _d(9, 10, 11), _d(8, 14, 90), _d(7, 12, 75));

        // Tokyo: Consigliere entry, premium sell destination
        reg.createArea("Tokyo", 0.001 ether, 2500, false, false);
        reg.batchConfigureAreaDrugs(6, _d(9, 10, 11), _d(24, 32, 200), _d(20, 26, 160));

        // Dubai: Don entry, endgame teaser (XTC/Cocaine/Heroin, asymmetric sell-heavy pricing)
        reg.createArea("Dubai", 0.002 ether, 10000, false, false);
        reg.batchConfigureAreaDrugs(7, _d(5, 6, 8), _d(14, 160, 200), _d(20, 200, 240));

        // Black Market sell prices to 2x base (sell-only by contract design)
        reg.batchConfigureAreaDrugs(254, _d(1, 2, 3), _d(75, 500, 2500), _d(150, 1200, 6500));

        console.log("  7 areas created + Black Market sell premium configured");
        console.log("");
    }

    function _d(uint256 a, uint256 b, uint256 c) private pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    // =========================================================================
    //                        REPUTATION TIERS
    // =========================================================================

    function _setupTiers() internal {
        IDealersCore c = IDealersCore(core);
        try c.reputationTiers(0) returns (uint256, int16, int16, int16, int16, string memory) {
            console.log("Reputation tiers: already configured");
            return;
        } catch {}

        console.log("Setting up 10-tier reputation system (convex 2.2x ladder)...");

        ReputationTier[] memory tiers = new ReputationTier[](10);
        tiers[0] = ReputationTier({
            minReputation: 0,
            winBonus: 60,
            tieBonus: 25,
            lossPenalty: -2,
            repCap: 35,
            tierName: "Outsider"
        });
        tiers[1] = ReputationTier({
            minReputation: 100,
            winBonus: 35,
            tieBonus: 18,
            lossPenalty: -3,
            repCap: 25,
            tierName: "Associate"
        });
        tiers[2] = ReputationTier({
            minReputation: 250,
            winBonus: 20,
            tieBonus: 10,
            lossPenalty: -3,
            repCap: 22,
            tierName: "Dealer"
        });
        tiers[3] = ReputationTier({
            minReputation: 600,
            winBonus: 12,
            tieBonus: 5,
            lossPenalty: -4,
            repCap: 22,
            tierName: "Soldier"
        });
        tiers[4] = ReputationTier({
            minReputation: 1500,
            winBonus: 9,
            tieBonus: 4,
            lossPenalty: -5,
            repCap: 24,
            tierName: "Capo"
        });
        tiers[5] = ReputationTier({
            minReputation: 3000,
            winBonus: 7,
            tieBonus: 3,
            lossPenalty: -5,
            repCap: 26,
            tierName: "Consigliere"
        });
        tiers[6] = ReputationTier({
            minReputation: 5500,
            winBonus: 6,
            tieBonus: 2,
            lossPenalty: -6,
            repCap: 28,
            tierName: "Underboss"
        });
        tiers[7] = ReputationTier({
            minReputation: 10000,
            winBonus: 5,
            tieBonus: 2,
            lossPenalty: -6,
            repCap: 30,
            tierName: "Don"
        });
        tiers[8] = ReputationTier({
            minReputation: 22000,
            winBonus: 4,
            tieBonus: 1,
            lossPenalty: -7,
            repCap: 32,
            tierName: "Godfather"
        });
        tiers[9] = ReputationTier({
            minReputation: 50000,
            winBonus: 2,
            tieBonus: 1,
            lossPenalty: -8,
            repCap: 4,
            tierName: "Legend"
        });

        c.setReputationTiers(tiers);
        c.setMaxReputation(75000);
        console.log("  10 tiers + MAX_REPUTATION=75000 (Legend is soft-bleed +2/+1/-8 repCap=4)");
        console.log("");
    }

    // =========================================================================
    //                           BOOSTS RETUNE
    // =========================================================================

    function _setupBoosts() internal {
        IBoostsAdmin b = IBoostsAdmin(boosts);

        console.log("Retuning Kingpin + Godfather boost perks...");

        // Kingpin (tier 3) - +6 attempts (was +5), 1.25x rep (was 1.20)
        b.setBoostTier(
            3,
            IBoostsAdmin.BoostTier({
                price: 0.01 ether,
                duration: 14 days,
                drugMultiplier: 175,
                repMultiplier: 125,
                extraAttempts: 6,
                freeAreaMovement: true,
                cashMultiplier: 175,
                isActive: true
            })
        );

        // Godfather (tier 4) - 2.25x drug/cash (was 2x), 1.35x rep (was 1.25)
        b.setBoostTier(
            4,
            IBoostsAdmin.BoostTier({
                price: 0.023 ether,
                duration: 30 days,
                drugMultiplier: 225,
                repMultiplier: 135,
                extraAttempts: 7,
                freeAreaMovement: true,
                cashMultiplier: 225,
                isActive: true
            })
        );

        console.log("  Kingpin: +6 attempts, 1.25x rep | Godfather: 2.25x drug/cash, 1.35x rep");
        console.log("");
    }

    // =========================================================================
    //                           CLAIMS
    // =========================================================================

    uint8 constant PVE_WINS = 1;
    uint8 constant PVE_LOSSES = 2;
    uint8 constant PVE_TIES = 3;
    uint8 constant PVE_TOTAL = 4;
    uint8 constant PVP_ATTACK_WINS = 5;
    uint8 constant PVP_DEFEND_WINS = 6;
    uint8 constant PVP_TOTAL_WINS = 7;
    uint8 constant REPUTATION = 8;
    uint8 constant CASH_BALANCE = 9;
    uint8 constant DRUG_BALANCE = 10;
    uint8 constant PVE_DEAL_CHOICES = 11;
    uint8 constant PVE_THREATEN_CHOICES = 12;
    uint8 constant PVE_BAIL_CHOICES = 13;

    uint8 constant REWARD_REP = 0;
    uint8 constant REWARD_CASH = 1;
    uint8 constant REWARD_DRUG = 2;

    // Drug IDs (must match SetupDrugs registration order)
    uint256 constant GENERAL_GOODS = 1;
    uint256 constant CONTRABAND = 2;
    uint256 constant JEWELS = 3;
    uint256 constant WEED = 4;
    uint256 constant XTC = 5;
    uint256 constant COCAINE = 6;
    uint256 constant SHROOMS = 7;
    uint256 constant HEROIN = 8;
    uint256 constant FENTANYL = 11;

    function _setupClaims() internal {
        IClaimsContract c = IClaimsContract(claims);

        if (c.nextAchievementId() > 0) {
            console.log("Claims: already configured");
            return;
        }

        console.log("Configuring 33 achievements (rebalanced for new ladder)...");

        // Early game (0-11)
        c.setAchievement(0, _ach(PVE_TOTAL, 0, 1, REWARD_CASH, 0, 250));
        c.setAchievement(1, _ach(PVE_TOTAL, 0, 10, REWARD_CASH, 0, 1000));
        c.setAchievement(2, _ach(PVE_WINS, 0, 10, REWARD_DRUG, XTC, 5));
        c.setAchievement(3, _ach(PVE_TIES, 0, 10, REWARD_DRUG, XTC, 5));
        c.setAchievement(4, _ach(PVE_LOSSES, 0, 10, REWARD_CASH, 0, 1000));
        c.setAchievement(5, _ach(PVE_DEAL_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 5));
        c.setAchievement(6, _ach(PVE_THREATEN_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 5));
        c.setAchievement(7, _ach(PVE_BAIL_CHOICES, 0, 10, REWARD_DRUG, SHROOMS, 5));
        c.setAchievement(8, _ach(PVP_TOTAL_WINS, 0, 1, REWARD_REP, 0, 25));
        c.setAchievement(9, _ach(PVP_ATTACK_WINS, 0, 10, REWARD_DRUG, GENERAL_GOODS, 3));
        c.setAchievement(10, _ach(PVP_DEFEND_WINS, 0, 10, REWARD_DRUG, GENERAL_GOODS, 3));
        c.setAchievement(11, _ach(REPUTATION, 0, 100, REWARD_DRUG, WEED, 100));

        // Tier milestones (12-20) aligned with new convex ladder
        c.setAchievement(12, _ach(REPUTATION, 0, 75, REWARD_CASH, 0, 500)); // Associate
        c.setAchievement(13, _ach(REPUTATION, 0, 200, REWARD_CASH, 0, 2000)); // Dealer
        c.setAchievement(14, _ach(REPUTATION, 0, 500, REWARD_CASH, 0, 10000)); // Soldier
        c.setAchievement(15, _ach(REPUTATION, 0, 1200, REWARD_CASH, 0, 25000)); // Capo
        c.setAchievement(16, _ach(REPUTATION, 0, 2500, REWARD_CASH, 0, 75000)); // Consigliere
        c.setAchievement(17, _ach(REPUTATION, 0, 5000, REWARD_CASH, 0, 200000)); // Underboss
        c.setAchievement(18, _ach(REPUTATION, 0, 10000, REWARD_CASH, 0, 500000)); // Don
        c.setAchievement(19, _ach(REPUTATION, 0, 22000, REWARD_CASH, 0, 1000000)); // Godfather
        c.setAchievement(20, _ach(REPUTATION, 0, 50000, REWARD_CASH, 0, 2000000)); // Legend

        // Drug + PvP rewards (21-23)
        c.setAchievement(21, _ach(REPUTATION, 0, 250, REWARD_DRUG, HEROIN, 5));
        c.setAchievement(22, _ach(PVP_TOTAL_WINS, 0, 1, REWARD_DRUG, GENERAL_GOODS, 3));
        c.setAchievement(23, _ach(PVP_TOTAL_WINS, 0, 10, REWARD_DRUG, CONTRABAND, 3));

        // Cash thresholds (24-27)
        c.setAchievement(24, _ach(CASH_BALANCE, 0, 10000, REWARD_DRUG, XTC, 1));
        c.setAchievement(25, _ach(CASH_BALANCE, 0, 100000, REWARD_DRUG, COCAINE, 1));
        c.setAchievement(26, _ach(CASH_BALANCE, 0, 500000, REWARD_DRUG, JEWELS, 1));
        c.setAchievement(27, _ach(CASH_BALANCE, 0, 2000000, REWARD_DRUG, JEWELS, 3));

        // Drug stockpiles (28-29)
        c.setAchievement(28, _ach(DRUG_BALANCE, FENTANYL, 1000, REWARD_CASH, 0, 25000));
        c.setAchievement(29, _ach(DRUG_BALANCE, COCAINE, 5000, REWARD_CASH, 0, 100000));

        // Long grind (30-32)
        c.setAchievement(30, _ach(PVE_TOTAL, 0, 100, REWARD_CASH, 0, 5000));
        c.setAchievement(31, _ach(PVE_TOTAL, 0, 1000, REWARD_CASH, 0, 50000));
        c.setAchievement(32, _ach(PVP_TOTAL_WINS, 0, 100, REWARD_CASH, 0, 100000));

        console.log("  33 achievements configured");
        console.log("");
    }

    function _ach(
        uint8 conditionType,
        uint256 conditionValue,
        uint256 threshold,
        uint8 rewardType,
        uint256 rewardId,
        uint256 rewardAmount
    ) private pure returns (IClaimsContract.Achievement memory) {
        return IClaimsContract.Achievement({
            conditionType: conditionType,
            conditionValue: conditionValue,
            threshold: threshold,
            rewardType: rewardType,
            rewardId: rewardId,
            rewardAmount: rewardAmount,
            active: true
        });
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
            console.log("  6. Enable minting: cast send $DEALERS_NFT \"setMintStatus(uint8)\" 3");
        } else {
            console.log("Remaining:");
            console.log("  1. Deploy SVG renderer (EVM mode, no --zksync)");
            console.log("  2. Deploy HTML renderer (--zksync)");
            console.log("  3. Upload gzip JS + set gzip filename on HTML renderer");
            console.log("  4. Enable minting: cast send $DEALERS_NFT \"setMintStatus(uint8)\" 3");
        }
    }
}

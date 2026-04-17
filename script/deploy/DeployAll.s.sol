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
      --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
      --skip "RendererSVG"
 */
contract DeployAll is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(devWallet, "DEV_WALLET");
        _requireAddress(bankVault, "BANK_VAULT");
        _requireAddress(royaltyReceiver, "ROYALTY_RECEIVER");

        console.log("==============================================");
        console.log("   Dealers.sh - Deploy All");
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

        // 5. Setup achievements
        _setupClaims();

        // 6. Setup chat rooms
        _setupChat();

        vm.stopBroadcast();

        _saveAddresses();
        _printSummary();
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
            areaRegistry = _zkCreate(abi.encodePacked(
                vm.getCode("DealersAreaRegistry.sol:DealersAreaRegistry"),
                abi.encode(drugRegistry)
            ));
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
            paymentHandler = _zkCreate(abi.encodePacked(
                vm.getCode("DealersPaymentHandler.sol:DealersPaymentHandler"),
                abi.encode(devWallet, bankVault)
            ));
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

        if (nft == address(0)) {
            nft = _zkCreate(abi.encodePacked(
                vm.getCode("DealersNFT.sol:DealersNFT"),
                abi.encode(royaltyReceiver)
            ));
            console.log("DealersNFT deployed:", nft);
        } else {
            console.log("DealersNFT: skipped (exists)");
        }

        if (boosts == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(paymentHandler, "PAYMENT_HANDLER");
            boosts = _zkCreate(abi.encodePacked(
                vm.getCode("DealersBoosts.sol:DealersBoosts"),
                abi.encode(core, nft, paymentHandler)
            ));
            console.log("DealersBoosts deployed:", boosts);
        } else {
            console.log("DealersBoosts: skipped (exists)");
        }

        if (pve == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(areaRegistry, "AREA_REGISTRY");
            pve = _zkCreate(abi.encodePacked(
                vm.getCode("DealersPVE.sol:DealersPVE"),
                abi.encode(core, nft, areaRegistry)
            ));
            console.log("DealersPVE deployed:", pve);
        } else {
            console.log("DealersPVE: skipped (exists)");
        }

        if (pvp == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(areaRegistry, "AREA_REGISTRY");
            pvp = _zkCreate(abi.encodePacked(
                vm.getCode("DealersPVP.sol:DealersPVP"),
                abi.encode(core, nft, areaRegistry)
            ));
            console.log("DealersPVP deployed:", pvp);
        } else {
            console.log("DealersPVP: skipped (exists)");
        }

        if (claims == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(pve, "DEALERS_PVE");
            _requireAddress(pvp, "DEALERS_PVP");
            claims = _zkCreate(abi.encodePacked(
                vm.getCode("DealersClaims.sol:DealersClaims"),
                abi.encode(core, nft, pve, pvp)
            ));
            console.log("DealersClaims deployed:", claims);
        } else {
            console.log("DealersClaims: skipped (exists)");
        }

        if (actions == address(0)) {
            _requireAddress(core, "DEALERS_CORE");
            _requireAddress(nft, "DEALERS_NFT");
            _requireAddress(areaRegistry, "AREA_REGISTRY");
            actions = _zkCreate(abi.encodePacked(
                vm.getCode("DealersActions.sol:DealersActions"),
                abi.encode(core, nft, areaRegistry)
            ));
            console.log("DealersActions deployed:", actions);
        } else {
            console.log("DealersActions: skipped (exists)");
        }

        if (multicall == address(0)) {
            multicall = _zkCreate(abi.encodePacked(
                vm.getCode("DealersMulticall.sol:DealersMulticall"),
                abi.encode(core, pve, pvp, areaRegistry, drugRegistry)
            ));
            console.log("DealersMulticall deployed:", multicall);
        } else {
            console.log("DealersMulticall: skipped (exists)");
        }

        if (chatFactory == address(0)) {
            _requireAddress(nft, "DEALERS_NFT");
            chatFactory = _zkCreate(abi.encodePacked(
                vm.getCode("DealersChatFactory.sol:DealersChatFactory"),
                abi.encode(nft)
            ));
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
        _setIfDifferent(c.nftContract(), nft, c.setNFTContract);
        _setIfDifferent(c.paymentHandler(), paymentHandler, c.setPaymentHandler);
        _setIfDifferent(c.randomness(), randomness, c.setRandomness);

        // Core authorizations
        _authorizeIfNeeded(c, pve);
        _authorizeIfNeeded(c, pvp);
        _authorizeIfNeeded(c, boosts);
        _authorizeIfNeeded(c, nft);
        if (claims != address(0)) _authorizeIfNeeded(c, claims);
        if (actions != address(0)) _authorizeIfNeeded(c, actions);

        // DrugRegistry auth
        IDrugRegistry drugReg = IDrugRegistry(drugRegistry);
        if (!drugReg.authorizedContracts(core)) drugReg.authorizeContract(core, true);

        // PaymentHandler auth
        IPaymentHandler payHandler = IPaymentHandler(paymentHandler);
        if (!payHandler.authorizedContracts(core)) payHandler.authorizeContract(core, true);
        if (!payHandler.authorizedContracts(boosts)) payHandler.authorizeContract(boosts, true);
        if (actions != address(0) && !payHandler.authorizedContracts(actions)) payHandler.authorizeContract(actions, true);

        // AreaRegistry -> Core
        IAreaRegistry areaReg = IAreaRegistry(areaRegistry);
        if (areaReg.coreContract() != core) areaReg.setCoreContract(core);

        // Randomness authorizations
        IRandomness rng = IRandomness(randomness);
        if (!rng.isAuthorizedResolver(core)) rng.authorizeResolver(core, true);
        if (!rng.isAuthorizedResolver(pve)) rng.authorizeResolver(pve, true);
        if (!rng.isAuthorizedResolver(pvp)) rng.authorizeResolver(pvp, true);
        if (actions != address(0) && !rng.isAuthorizedResolver(actions)) rng.authorizeResolver(actions, true);

        // Module references
        IDealersNFT nftC = IDealersNFT(nft);
        _setIfDifferent(nftC.dealersCore(), core, nftC.setDealersCore);

        IBoostsContract boostsC = IBoostsContract(boosts);
        _setIfDifferent(boostsC.dealersCore(), core, boostsC.setDealersCore);
        _setIfDifferent(boostsC.dealersNFT(), nft, boostsC.setDealersNFT);
        _setIfDifferent(boostsC.paymentHandler(), paymentHandler, boostsC.setPaymentHandler);

        IPVEContract pveC = IPVEContract(pve);
        _setIfDifferent(pveC.dealersCore(), core, pveC.setDealersCore);
        _setIfDifferent(pveC.areaRegistry(), areaRegistry, pveC.setAreaRegistry);
        _setIfDifferent(pveC.randomness(), randomness, pveC.setRandomness);

        IPVPContract pvpC = IPVPContract(pvp);
        _setIfDifferent(pvpC.core(), core, pvpC.setCore);
        _setIfDifferent(pvpC.areaRegistry(), areaRegistry, pvpC.setAreaRegistry);
        _setIfDifferent(pvpC.drugRegistry(), drugRegistry, pvpC.setDrugRegistry);
        _setIfDifferent(pvpC.randomness(), randomness, pvpC.setRandomness);

        if (claims != address(0)) {
            IClaimsContract claimsC = IClaimsContract(claims);
            _setIfDifferent(claimsC.dealersCore(), core, claimsC.setDealersCore);
            _setIfDifferent(claimsC.dealersNFT(), nft, claimsC.setDealersNFT);
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
        reg.createDrug("Goods",      0, 75);
        reg.createDrug("Contraband", 1, 500);
        reg.createDrug("Jewels",     2, 2500);
        reg.createDrug("Weed",       0, 1);
        reg.createDrug("XTC",        1, 10);
        reg.createDrug("Cocaine",    2, 100);
        reg.createDrug("Shrooms",    1, 12);
        reg.createDrug("Heroin",     2, 150);
        reg.createDrug("Opioids",    0, 18);
        reg.createDrug("Meth",       1, 25);
        reg.createDrug("Fentanyl",   2, 200);
        console.log("  11 drugs registered");
        console.log("");
    }

    function _setupAreas() internal {
        IAreaRegistry reg = IAreaRegistry(areaRegistry);

        if (reg.getTotalAreas() > 0) {
            console.log("Areas: already configured");
            return;
        }

        console.log("Creating 6 game areas...");

        reg.createArea("Manhattan", 0.001 ether, 0, false, false);
        reg.batchConfigureAreaDrugs(1, _d(4, 5, 6), _d(1, 12, 120), _d(1, 10, 100));

        reg.createArea("Amsterdam", 0.001 ether, 150, false, false);
        reg.batchConfigureAreaDrugs(2, _d(4, 7, 8), _d(3, 15, 180), _d(2, 12, 150));

        reg.createArea("Colombia", 0.001 ether, 250, false, false);
        reg.batchConfigureAreaDrugs(3, _d(4, 6, 8), _d(1, 60, 90), _d(1, 50, 75));

        reg.createArea("Hong Kong", 0.001 ether, 500, false, false);
        reg.batchConfigureAreaDrugs(4, _d(9, 10, 8), _d(18, 28, 140), _d(15, 22, 110));

        reg.createArea("Seoul", 0.001 ether, 1000, false, false);
        reg.batchConfigureAreaDrugs(5, _d(9, 10, 11), _d(8, 14, 90), _d(7, 12, 75));

        reg.createArea("Tokyo", 0.001 ether, 1500, false, false);
        reg.batchConfigureAreaDrugs(6, _d(9, 10, 11), _d(24, 32, 200), _d(20, 26, 160));

        console.log("  6 areas created");
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

        console.log("Setting up 10-tier reputation system...");

        ReputationTier[] memory tiers = new ReputationTier[](10);
        tiers[0] = ReputationTier({minReputation: 0, winBonus: 50, tieBonus: 25, lossPenalty: -2, repCap: 25, tierName: "Outsider"});
        tiers[1] = ReputationTier({minReputation: 50, winBonus: 40, tieBonus: 20, lossPenalty: -3, repCap: 22, tierName: "Associate"});
        tiers[2] = ReputationTier({minReputation: 150, winBonus: 15, tieBonus: 8, lossPenalty: -3, repCap: 18, tierName: "Dealer"});
        tiers[3] = ReputationTier({minReputation: 300, winBonus: 9, tieBonus: 3, lossPenalty: -4, repCap: 17, tierName: "Soldier"});
        tiers[4] = ReputationTier({minReputation: 700, winBonus: 8, tieBonus: 3, lossPenalty: -4, repCap: 21, tierName: "Capo"});
        tiers[5] = ReputationTier({minReputation: 1250, winBonus: 7, tieBonus: 3, lossPenalty: -5, repCap: 24, tierName: "Consigliere"});
        tiers[6] = ReputationTier({minReputation: 1900, winBonus: 6, tieBonus: 2, lossPenalty: -5, repCap: 25, tierName: "Underboss"});
        tiers[7] = ReputationTier({minReputation: 2600, winBonus: 5, tieBonus: 2, lossPenalty: -6, repCap: 28, tierName: "Don"});
        tiers[8] = ReputationTier({minReputation: 3500, winBonus: 4, tieBonus: 2, lossPenalty: -6, repCap: 30, tierName: "Godfather"});
        tiers[9] = ReputationTier({minReputation: 5000, winBonus: 3, tieBonus: 1, lossPenalty: -7, repCap: 24, tierName: "Legend"});

        c.setReputationTiers(tiers);
        c.setMaxReputation(6000);
        console.log("  10 tiers + MAX_REPUTATION=6000");
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
    uint8 constant PVE_DEAL_CHOICES = 11;
    uint8 constant PVE_THREATEN_CHOICES = 12;
    uint8 constant PVE_BAIL_CHOICES = 13;

    uint8 constant REWARD_REP = 0;
    uint8 constant REWARD_CASH = 1;
    uint8 constant REWARD_DRUG = 2;

    function _setupClaims() internal {
        IClaimsContract c = IClaimsContract(claims);

        if (c.achievementCount() > 0) {
            console.log("Claims: already configured");
            return;
        }

        console.log("Configuring 24 achievements...");

        c.setAchievement(0, _ach(PVE_TOTAL, 0, 1, REWARD_CASH, 0, 25));
        c.setAchievement(1, _ach(PVE_TOTAL, 0, 10, REWARD_CASH, 0, 50));
        c.setAchievement(2, _ach(PVE_WINS, 0, 10, REWARD_DRUG, 5, 2));
        c.setAchievement(3, _ach(PVE_TIES, 0, 10, REWARD_DRUG, 5, 2));
        c.setAchievement(4, _ach(PVE_LOSSES, 0, 10, REWARD_CASH, 0, 50));
        c.setAchievement(5, _ach(PVE_DEAL_CHOICES, 0, 10, REWARD_DRUG, 7, 1));
        c.setAchievement(6, _ach(PVE_THREATEN_CHOICES, 0, 10, REWARD_DRUG, 7, 1));
        c.setAchievement(7, _ach(PVE_BAIL_CHOICES, 0, 10, REWARD_DRUG, 7, 1));
        c.setAchievement(8, _ach(PVP_TOTAL_WINS, 0, 1, REWARD_REP, 0, 10));
        c.setAchievement(9, _ach(PVP_ATTACK_WINS, 0, 10, REWARD_DRUG, 1, 1));
        c.setAchievement(10, _ach(PVP_DEFEND_WINS, 0, 10, REWARD_DRUG, 1, 1));
        c.setAchievement(11, _ach(REPUTATION, 0, 100, REWARD_DRUG, 4, 20));
        c.setAchievement(12, _ach(REPUTATION, 0, 50, REWARD_CASH, 0, 50));
        c.setAchievement(13, _ach(REPUTATION, 0, 150, REWARD_CASH, 0, 150));
        c.setAchievement(14, _ach(REPUTATION, 0, 300, REWARD_CASH, 0, 300));
        c.setAchievement(15, _ach(REPUTATION, 0, 700, REWARD_CASH, 0, 700));
        c.setAchievement(16, _ach(REPUTATION, 0, 1250, REWARD_CASH, 0, 1250));
        c.setAchievement(17, _ach(REPUTATION, 0, 1900, REWARD_CASH, 0, 1900));
        c.setAchievement(18, _ach(REPUTATION, 0, 2600, REWARD_CASH, 0, 2600));
        c.setAchievement(19, _ach(REPUTATION, 0, 3500, REWARD_CASH, 0, 3500));
        c.setAchievement(20, _ach(REPUTATION, 0, 5000, REWARD_CASH, 0, 5000));
        c.setAchievement(21, _ach(REPUTATION, 0, 250, REWARD_DRUG, 8, 1));
        c.setAchievement(22, _ach(PVP_TOTAL_WINS, 0, 1, REWARD_DRUG, 1, 1));
        c.setAchievement(23, _ach(PVP_TOTAL_WINS, 0, 10, REWARD_DRUG, 2, 1));

        console.log("  24 achievements configured");
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

        address gate = _zkCreate(abi.encodePacked(
            vm.getCode("DealersAreaChatGate.sol:DealersAreaChatGate"),
            abi.encode(core)
        ));
        console.log("  AreaChatGate:", gate);

        uint8[8] memory areas = [uint8(1), 2, 3, 4, 5, 6, 254, 255];
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
        console.log("DEALERS_ACTIONS=", actions);
        console.log("DEALER_MULTICALL=", multicall);
        console.log("CHAT_FACTORY=", chatFactory);
        console.log("");
        console.log("Remaining:");
        console.log("  1. Deploy SVG renderer (EVM mode, no --zksync)");
        console.log("  2. Deploy HTML renderer (--zksync)");
        console.log("  3. Upload gzip JS + set gzip filename on HTML renderer");
        console.log("  4. Enable minting: cast send $DEALERS_NFT \"setMintStatus(uint8)\" 3");
    }
}

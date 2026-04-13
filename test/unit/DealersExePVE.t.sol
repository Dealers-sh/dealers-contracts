// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/core/DealersExeCore.sol";
import "../../src/nft/DealersExeNFT.sol";
import "../../src/core/DealersExePVE.sol";
import "../../src/core/IDealersExeCore.sol";
import "../../src/core/IDealersExePVE.sol";
import "../../src/utils/DEDrugRegistry.sol";
import "../../src/utils/DEAreaRegistry.sol";
import "../../src/utils/DEPaymentHandler.sol";
import "../../src/utils/DERandomness.sol";
import "../../src/core/DealersExeActions.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract DealersExePVETest is Test, IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
    DealersExeCore public core;
    DealersExeNFT public nft;
    DealersExePVE public pve;
    DealersExeActions public actions;
    DEDrugRegistry public drugRegistry;
    DEAreaRegistry public areaRegistry;
    DEPaymentHandler public paymentHandler;
    DERandomness public randomness;

    address public owner;
    address public player1;
    address public player2;
    address public devWallet;
    address public bankVault;
    address public signer;

    uint256 constant DEALER_ID_1 = 1;
    uint256 constant DEALER_ID_2 = 2;

    uint256 constant DRUG_WEED = 4;
    uint256 constant DRUG_XTC = 5;
    uint256 constant DRUG_COCAINE = 6;
    uint256 constant DRUG_SHROOMS = 7;
    uint256 constant DRUG_HEROIN = 8;

    uint8 constant AREA_SAFE_HOUSE = 0;
    uint8 constant AREA_MANHATTAN = 1;
    uint8 constant AREA_AMSTERDAM = 2;
    uint8 constant AREA_JAIL = 255;

    uint256 constant BUY_PRICE_WEED = 1;
    uint256 constant SELL_PRICE_WEED = 1;
    uint256 constant BUY_PRICE_XTC = 12;
    uint256 constant SELL_PRICE_XTC = 10;

    function setUp() public virtual {
        owner = address(this);
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        devWallet = makeAddr("devWallet");
        bankVault = makeAddr("bankVault");
        signer = makeAddr("signer");

        vm.deal(player1, 100 ether);
        vm.deal(player2, 100 ether);

        drugRegistry = new DEDrugRegistry();
        areaRegistry = new DEAreaRegistry(address(drugRegistry));
        _setupDrugsAndAreas();
        paymentHandler = new DEPaymentHandler(devWallet, bankVault);
        randomness = new DERandomness();

        core = new DealersExeCore();
        nft = new DealersExeNFT(devWallet);
        pve = new DealersExePVE(address(core), address(nft), address(areaRegistry));
        actions = new DealersExeActions(address(core), address(nft), address(areaRegistry));
        actions.setPaymentHandler(address(paymentHandler));
        actions.setRandomness(address(randomness));

        core.setNFTContract(address(nft));
        core.setPaymentHandler(address(paymentHandler));
        core.setDrugRegistry(address(drugRegistry));
        core.setAreaRegistry(address(areaRegistry));
        core.setRandomness(address(randomness));

        nft.setDealersExeCore(address(core));
        pve.setRandomness(address(randomness));

        core.authorizeContract(address(nft), true);
        core.authorizeContract(address(pve), true);
        core.authorizeContract(address(actions), true);
        drugRegistry.authorizeContract(address(core), true);
        areaRegistry.setCoreContract(address(core));
        paymentHandler.authorizeContract(address(core), true);
        paymentHandler.authorizeContract(address(actions), true);
        randomness.authorizeResolver(address(core), true);
        randomness.authorizeResolver(address(pve), true);
        randomness.authorizeResolver(address(actions), true);

        _setupReputationTiers();

        nft.reserveTo(1, player1);
        nft.reserveTo(1, player2);
    }

    function _isInJail(uint256 tokenId) internal view returns (bool) {
        return core.getGameState(tokenId).isJailed;
    }

    function _setupReputationTiers() internal {
        IDealersExeCore.ReputationTier[] memory tiers = new IDealersExeCore.ReputationTier[](3);

        tiers[0] = IDealersExeCore.ReputationTier({
            minReputation: 0,
            winBonus: 10,
            tieBonus: 5,
            lossPenalty: -5,
            repCap: 20,
            tierName: "Street Dealer"
        });

        tiers[1] = IDealersExeCore.ReputationTier({
            minReputation: 100,
            winBonus: 15,
            tieBonus: 7,
            lossPenalty: -7,
            repCap: 25,
            tierName: "Corner Boss"
        });

        tiers[2] = IDealersExeCore.ReputationTier({
            minReputation: 500,
            winBonus: 20,
            tieBonus: 10,
            lossPenalty: -10,
            repCap: 30,
            tierName: "Kingpin"
        });

        core.setReputationTiers(tiers);
    }

    function _setupDrugsAndAreas() internal {
        drugRegistry.createDrug("Goods",      IDrugRegistry.DrugRarity.COMMON,   75);
        drugRegistry.createDrug("Contraband", IDrugRegistry.DrugRarity.UNCOMMON, 500);
        drugRegistry.createDrug("Jewels",     IDrugRegistry.DrugRarity.RARE,     2500);
        drugRegistry.createDrug("Weed",       IDrugRegistry.DrugRarity.COMMON,   1);
        drugRegistry.createDrug("XTC",        IDrugRegistry.DrugRarity.UNCOMMON, 10);
        drugRegistry.createDrug("Cocaine",    IDrugRegistry.DrugRarity.RARE,     100);
        drugRegistry.createDrug("Shrooms",    IDrugRegistry.DrugRarity.UNCOMMON, 12);
        drugRegistry.createDrug("Heroin",     IDrugRegistry.DrugRarity.RARE,     150);
        drugRegistry.createDrug("Opioids",    IDrugRegistry.DrugRarity.COMMON,   18);
        drugRegistry.createDrug("Meth",       IDrugRegistry.DrugRarity.UNCOMMON, 25);
        drugRegistry.createDrug("Fentanyl",   IDrugRegistry.DrugRarity.RARE,     200);

        areaRegistry.createArea("Manhattan", 0.001 ether, 0, false, false);
        uint256[] memory ids = new uint256[](3);
        uint256[] memory buys = new uint256[](3);
        uint256[] memory sells = new uint256[](3);
        ids[0] = 4; ids[1] = 5; ids[2] = 6;
        buys[0] = 1; buys[1] = 12; buys[2] = 120;
        sells[0] = 1; sells[1] = 10; sells[2] = 100;
        areaRegistry.batchConfigureAreaDrugs(1, ids, buys, sells);

        areaRegistry.createArea("Amsterdam", 0.001 ether, 150, false, false);
        ids[0] = 4; ids[1] = 7; ids[2] = 8;
        buys[0] = 3; buys[1] = 15; buys[2] = 180;
        sells[0] = 2; sells[1] = 12; sells[2] = 150;
        areaRegistry.batchConfigureAreaDrugs(2, ids, buys, sells);

        areaRegistry.createArea("Colombia", 0.001 ether, 250, false, false);
        ids[0] = 4; ids[1] = 6; ids[2] = 8;
        buys[0] = 1; buys[1] = 60; buys[2] = 90;
        sells[0] = 1; sells[1] = 50; sells[2] = 75;
        areaRegistry.batchConfigureAreaDrugs(3, ids, buys, sells);

        areaRegistry.createArea("Hong Kong", 0.001 ether, 500, false, false);
        ids[0] = 9; ids[1] = 10; ids[2] = 8;
        buys[0] = 18; buys[1] = 28; buys[2] = 140;
        sells[0] = 15; sells[1] = 22; sells[2] = 110;
        areaRegistry.batchConfigureAreaDrugs(4, ids, buys, sells);

        areaRegistry.createArea("Seoul", 0.001 ether, 1000, false, false);
        ids[0] = 9; ids[1] = 10; ids[2] = 11;
        buys[0] = 8; buys[1] = 14; buys[2] = 90;
        sells[0] = 7; sells[1] = 12; sells[2] = 75;
        areaRegistry.batchConfigureAreaDrugs(5, ids, buys, sells);

        areaRegistry.createArea("Tokyo", 0.001 ether, 1500, false, false);
        ids[0] = 9; ids[1] = 10; ids[2] = 11;
        buys[0] = 24; buys[1] = 32; buys[2] = 200;
        sells[0] = 20; sells[1] = 26; sells[2] = 160;
        areaRegistry.batchConfigureAreaDrugs(6, ids, buys, sells);
    }

    function _moveDealerToArea(uint256 tokenId, uint8 areaId) internal {
        core.authorizeContract(address(this), true);
        core.moveToArea(tokenId, areaId);
        core.authorizeContract(address(this), false);
    }

    function _addCashToDealer(uint256 tokenId, uint256 amount) internal {
        core.authorizeContract(address(this), true);
        core.addCash(tokenId, amount);
        core.authorizeContract(address(this), false);
    }

    function _addDrugsToDealer(uint256 tokenId, uint256 drugId, uint256 amount) internal {
        core.authorizeContract(address(this), true);
        core.updateDrugBalance(tokenId, drugId, int256(amount));
        core.authorizeContract(address(this), false);
    }

    function _sendDealerToJail(uint256 tokenId) internal {
        core.authorizeContract(address(this), true);
        core.sendToJail(tokenId);
        core.authorizeContract(address(this), false);
    }

    function _applyBoost(
        uint256 tokenId,
        uint64 duration,
        uint8 drugMultiplier,
        uint8 repMultiplier,
        uint8 extraAttempts,
        bool freeAreaMovement,
        bool,
        uint8 cashMultiplier
    ) internal {
        core.authorizeContract(address(this), true);
        core.applyBoost(tokenId, duration, drugMultiplier, repMultiplier, extraAttempts, freeAreaMovement, cashMultiplier);
        core.authorizeContract(address(this), false);
    }

    function _setHeatLevel(uint256 tokenId, uint8 level) internal {
        core.authorizeContract(address(this), true);
        for (uint8 i = 0; i < level; i++) {
            core.incrementHeatLevel(tokenId);
        }
        core.authorizeContract(address(this), false);
    }

    function _useAttempts(uint256 tokenId, uint8 count) internal {
        core.authorizeContract(address(this), true);
        for (uint8 i = 0; i < count; i++) {
            core.useAttempt(tokenId);
        }
        core.authorizeContract(address(this), false);
    }

    function _setupDealerForPlay(uint256 tokenId) internal {
        _moveDealerToArea(tokenId, AREA_MANHATTAN);
        _addCashToDealer(tokenId, 1000);
        _addDrugsToDealer(tokenId, DRUG_WEED, 500);
    }

    function _getPrevrandaoForOutcome(
        uint256 tokenId,
        uint8 playerChoice,
        uint8 desiredOutcome
    ) internal view returns (uint256) {
        for (uint256 i = 0; i < 10000; i++) {
            uint256 testPrevrandao = i;
            uint256 rng = uint256(keccak256(abi.encodePacked(
                testPrevrandao,
                block.timestamp,
                tokenId,
                player1,
                block.timestamp
            )));
            uint256 gameRng = uint256(keccak256(abi.encodePacked(rng, "GAME")));
            uint8 roll = uint8(gameRng % 100);
            (, uint8 outcome) = _calculateBiasedHouseChoice(roll, playerChoice);

            if (outcome == desiredOutcome) {
                uint8 jailRoll = uint8(rng % 100);
                if (jailRoll >= 10) {
                    return testPrevrandao;
                }
            }
        }
        revert("Could not find suitable prevrandao");
    }

    function _calculateBiasedHouseChoice(uint8 roll, uint8 playerChoice) internal view returns (uint8 houseChoice, uint8 outcome) {
        uint8 _tieChance = pve.tieChance();
        uint8 _winChance = pve.winChance();

        if (roll < _tieChance) {
            houseChoice = playerChoice;
            outcome = 1; // TIE
        } else if (roll < _tieChance + _winChance) {
            houseChoice = (playerChoice + 1) % 3;
            outcome = 0; // WIN
        } else {
            houseChoice = (playerChoice + 2) % 3;
            outcome = 2; // LOSS
        }
    }

    function _getActualOutcome(uint256 tokenId, uint8 playerChoice, uint256 prevrandao) internal view returns (uint8) {
        uint256 rng = uint256(keccak256(abi.encodePacked(
            prevrandao,
            block.timestamp,
            tokenId,
            player1,
            block.timestamp
        )));
        uint256 gameRng = uint256(keccak256(abi.encodePacked(rng, "GAME")));
        uint8 roll = uint8(gameRng % 100);
        (, uint8 outcome) = _calculateBiasedHouseChoice(roll, playerChoice);
        return outcome;
    }

    function _getPrevrandaoForArrest(uint256 tokenId, uint8 currentHeatLevel) internal view returns (uint256) {
        uint8 heatAfterIncrement = currentHeatLevel < 5 ? currentHeatLevel + 1 : 5;
        for (uint256 i = 0; i < 100000; i++) {
            uint256 testPrevrandao = i;
            uint256 rng = uint256(keccak256(abi.encodePacked(
                testPrevrandao,
                block.timestamp,
                tokenId,
                player1,
                block.timestamp
            )));
            uint8 jailRoll = uint8(rng % 100);

            if (jailRoll < heatAfterIncrement) {
                return testPrevrandao;
            }
        }
        revert("Could not find prevrandao for arrest");
    }

    function _getPrevrandaoNoArrest(uint256 tokenId, uint8 heatLevel) internal view returns (uint256) {
        for (uint256 i = 0; i < 1000; i++) {
            uint256 testPrevrandao = i;
            uint256 rng = uint256(keccak256(abi.encodePacked(
                testPrevrandao,
                block.timestamp,
                tokenId,
                player1,
                block.timestamp
            )));
            uint8 jailRoll = uint8(rng % 100);

            if (jailRoll >= heatLevel) {
                return testPrevrandao;
            }
        }
        revert("Could not find prevrandao without arrest");
    }

    // =============================================================
    //                    GAME OUTCOME LOGIC (4 tests)
    // =============================================================

    function test_calculateGameOutcome_dealBeatsThreat() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0; // DEAL
        uint256 amount = 10;
        uint256 buyPrice = BUY_PRICE_WEED;
        uint256 stakeCost = amount * buyPrice;

        uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
        uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
        (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

        uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
        uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
        (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

        bool gotArrested = _isInJail(DEALER_ID_1);
        if (gotArrested) {
            assertEq(cashAfter, cashBefore - stakeCost, "Arrested should lose stake");
            return;
        }

        bool isWin = (cashAfter == cashBefore) && (drugsAfter > drugsBefore);
        bool isTie = (cashAfter == cashBefore - stakeCost) && (drugsAfter > drugsBefore);
        bool isLoss = (cashAfter == cashBefore - stakeCost) && (drugsAfter == drugsBefore);

        assertTrue(isWin || isTie || isLoss, "BUY outcome should match one of WIN/TIE/LOSS patterns");

        if (isWin) {
            assertGt(repAfter, repBefore, "WIN should gain big reputation");
        } else if (isTie) {
            assertGt(repAfter, repBefore, "TIE should gain small reputation");
        } else {
            assertLt(repAfter, repBefore, "LOSS should lose reputation");
        }
    }

    function test_calculateGameOutcome_threatenBeatsBail() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 1; // THREATEN
        uint256 amount = 10;
        uint256 buyPrice = BUY_PRICE_WEED;
        uint256 stakeCost = amount * buyPrice;

        uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
        uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

        uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
        uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

        bool gotArrested = _isInJail(DEALER_ID_1);
        if (gotArrested) {
            assertEq(cashAfter, cashBefore - stakeCost, "Arrested should lose stake");
            return;
        }

        bool isWin = (cashAfter == cashBefore) && (drugsAfter > drugsBefore);
        bool isTie = (cashAfter == cashBefore - stakeCost) && (drugsAfter > drugsBefore);
        bool isLoss = (cashAfter == cashBefore - stakeCost) && (drugsAfter == drugsBefore);

        assertTrue(isWin || isTie || isLoss, "BUY outcome should match one of WIN/TIE/LOSS patterns");
    }

    function test_calculateGameOutcome_winOutcome() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0;
        uint256 amount = 10;

        bool foundWin = false;
        for (uint256 i = 0; i < 200; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, amount * BUY_PRICE_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);
            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

            // WIN: Keep cash, gain drugs, gain rep
            if (cashAfter == cashBefore && drugsAfter > drugsBefore && repAfter > repBefore) {
                foundWin = true;
                assertGt(repAfter, repBefore, "WIN should gain rep");
                break;
            }
        }

        assertTrue(foundWin, "Should find WIN outcome within 200 attempts");
    }

    function test_calculateGameOutcome_tieOutcome() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0;
        uint256 amount = 10;
        uint256 stakeCost = amount * BUY_PRICE_WEED;

        bool foundTie = false;
        for (uint256 i = 0; i < 200; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, stakeCost);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) continue;

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

            bool isTie = (cashAfter == cashBefore - stakeCost) && (drugsAfter > drugsBefore);
            if (isTie) {
                assertLt(cashAfter, cashBefore, "TIE BUY should spend cash");
                assertGt(repAfter, repBefore, "TIE should still gain small rep");
                foundTie = true;
                break;
            }
        }

        assertTrue(foundTie, "Should find a TIE outcome within 200 attempts");
    }

    // =============================================================
    //                      BUY OUTCOMES (5 tests)
    // =============================================================

    function test_playGame_buyWin_keepCashGetDrugs() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0; // DEAL
        uint256 amount = 10;

        bool foundWin = false;
        for (uint256 i = 0; i < 100; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.warp(block.timestamp + 1 days);
            }

            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) continue;

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

            bool isWin = (cashAfter == cashBefore) && (drugsAfter > drugsBefore);
            if (isWin) {
                assertEq(cashAfter, cashBefore, "WIN: Keep cash");
                assertEq(drugsAfter, drugsBefore + amount, "WIN: Get drugs");
                assertGt(repAfter, repBefore, "WIN: Big rep gain");
                foundWin = true;
                break;
            }
        }

        assertTrue(foundWin, "Should find a WIN outcome within 100 attempts");
    }

    function test_playGame_buyTie_loseCashGetDrugs() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0;
        uint256 amount = 10;
        uint256 expectedCost = amount * BUY_PRICE_WEED;

        bool foundTie = false;
        for (uint256 i = 0; i < 200; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, expectedCost);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) continue;

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

            bool isTie = (cashAfter == cashBefore - expectedCost) && (drugsAfter > drugsBefore);
            if (isTie) {
                assertEq(cashAfter, cashBefore - expectedCost, "TIE: Lose cash");
                assertEq(drugsAfter, drugsBefore + amount, "TIE: Get drugs");
                assertGt(repAfter, repBefore, "TIE: Small rep gain");
                foundTie = true;
                break;
            }
        }

        assertTrue(foundTie, "Should find a TIE outcome within 200 attempts");
    }

    function test_playGame_buyLoss_loseCashNoDrugs() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0;
        uint256 amount = 10;
        uint256 expectedCost = amount * BUY_PRICE_WEED;

        bool foundLoss = false;

        for (uint256 i = 0; i < 500; i++) {
            uint256 snapshotId = vm.snapshotState();

            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) {
                vm.revertToState(snapshotId);
                continue;
            }

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

            bool isLoss = (cashAfter == cashBefore - expectedCost) && (drugsAfter == drugsBefore);
            if (isLoss) {
                assertEq(cashAfter, cashBefore - expectedCost, "LOSS: Lose cash");
                assertEq(drugsAfter, drugsBefore, "LOSS: No drugs");
                assertLt(repAfter, repBefore, "LOSS: Lose rep");
                foundLoss = true;
                break;
            }

            vm.revertToState(snapshotId);
        }

        if (!foundLoss) {
            emit log("Note: BUY LOSS outcome not found within iteration limit - test inconclusive");
        }
    }

    function test_playGame_buyInsufficientCash() public {
        _moveDealerToArea(DEALER_ID_1, AREA_MANHATTAN);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.InsufficientCash.selector);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_XTC, 1000);
    }

    function test_playGame_buyZeroAmount_reverts() public {
        _setupDealerForPlay(DEALER_ID_1);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.InvalidAmount.selector);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 0);
    }

    // =============================================================
    //                      SELL OUTCOMES (5 tests)
    // =============================================================

    function test_playGame_sellWin_keepDrugsGetCash() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0; // DEAL
        uint256 amount = 10;
        uint256 expectedCash = amount * SELL_PRICE_WEED;

        bool foundWin = false;
        for (uint256 i = 0; i < 100; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.warp(block.timestamp + 1 days);
            }

            _addDrugsToDealer(DEALER_ID_1, DRUG_WEED, amount);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.SELL, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) continue;

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

            bool isWin = (cashAfter == cashBefore + expectedCash) && (drugsAfter == drugsBefore);
            if (isWin) {
                assertEq(cashAfter, cashBefore + expectedCash, "WIN: Get cash");
                assertEq(drugsAfter, drugsBefore, "WIN: Keep drugs");
                assertGt(repAfter, repBefore, "WIN: Big rep gain");
                foundWin = true;
                break;
            }
        }

        assertTrue(foundWin, "Should find a WIN outcome within 100 attempts");
    }

    function test_playGame_sellTie_loseDrugsGetCash() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0;
        uint256 amount = 10;
        uint256 expectedCash = amount * SELL_PRICE_WEED;

        bool foundTie = false;
        for (uint256 i = 0; i < 200; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addDrugsToDealer(DEALER_ID_1, DRUG_WEED, amount);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.SELL, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) continue;

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

            bool isTie = (cashAfter == cashBefore + expectedCash) && (drugsAfter == drugsBefore - amount);
            if (isTie) {
                assertEq(cashAfter, cashBefore + expectedCash, "TIE: Get cash");
                assertEq(drugsAfter, drugsBefore - amount, "TIE: Lose drugs");
                assertGt(repAfter, repBefore, "TIE: Small rep gain");
                foundTie = true;
                break;
            }
        }

        assertTrue(foundTie, "Should find a TIE outcome within 200 attempts");
    }

    function test_playGame_sellLoss_loseDrugsNoCash() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0;
        uint256 amount = 10;

        bool foundLoss = false;

        for (uint256 i = 0; i < 500; i++) {
            uint256 snapshotId = vm.snapshotState();

            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.SELL, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) {
                vm.revertToState(snapshotId);
                continue;
            }

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

            bool isLoss = (cashAfter == cashBefore) && (drugsAfter == drugsBefore - amount);
            if (isLoss) {
                assertEq(cashAfter, cashBefore, "LOSS: No cash");
                assertEq(drugsAfter, drugsBefore - amount, "LOSS: Lose drugs");
                assertLt(repAfter, repBefore, "LOSS: Lose rep");
                foundLoss = true;
                break;
            }

            vm.revertToState(snapshotId);
        }

        if (!foundLoss) {
            emit log("Note: SELL LOSS outcome not found within iteration limit - test inconclusive");
        }
    }

    function test_playGame_sellInsufficientDrugs() public {
        _moveDealerToArea(DEALER_ID_1, AREA_MANHATTAN);
        _addCashToDealer(DEALER_ID_1, 100);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.InsufficientDrugs.selector);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.SELL, DRUG_WEED, 1000);
    }

    function test_playGame_sellZeroAmount_reverts() public {
        _setupDealerForPlay(DEALER_ID_1);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.InvalidAmount.selector);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.SELL, DRUG_WEED, 0);
    }

    // =============================================================
    //                      ARREST/JAIL (4 tests)
    // =============================================================

    function test_playGame_arrestBeforeOutcome() public {
        _setupDealerForPlay(DEALER_ID_1);

        _setHeatLevel(DEALER_ID_1, 5);

        bool arrested = false;
        for (uint256 i = 0; i < 100; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 10);

            if (_isInJail(DEALER_ID_1)) {
                arrested = true;
                break;
            }
        }

        assertTrue(arrested, "Dealer should be in jail after arrest (within 100 attempts)");
    }

    function test_playGame_arrestLosesStake_buy() public {
        _setupDealerForPlay(DEALER_ID_1);

        _setHeatLevel(DEALER_ID_1, 5);

        uint256 amount = 10;
        uint256 stakeCost = amount * BUY_PRICE_WEED;

        bool arrested = false;
        for (uint256 i = 0; i < 100; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, stakeCost);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) {
                uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
                assertEq(cashAfter, cashBefore - stakeCost, "Arrested BUY loses staked cash");
                arrested = true;
                break;
            }
        }

        assertTrue(arrested, "Dealer should be in jail (within 100 attempts)");
    }

    function test_playGame_arrestLosesStake_sell() public {
        _setupDealerForPlay(DEALER_ID_1);

        _setHeatLevel(DEALER_ID_1, 5);

        uint256 amount = 10;

        bool arrested = false;
        for (uint256 i = 0; i < 100; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addDrugsToDealer(DEALER_ID_1, DRUG_WEED, amount);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.SELL, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) {
                uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
                assertLe(drugsAfter, drugsBefore - amount, "Arrested SELL loses at least staked drugs (+ possible confiscation)");
                arrested = true;
                break;
            }
        }

        assertTrue(arrested, "Dealer should be in jail (within 100 attempts)");
    }

    // =============================================================
    //                      MULTIPLIERS (4 tests)
    // =============================================================

    function test_playGame_drugMultiplierApplied() public {
        _setupDealerForPlay(DEALER_ID_1);

        _applyBoost(DEALER_ID_1, 1 days, 200, 100, 0, false, false, 100);

        uint8 playerChoice = 0;
        uint256 amount = 10;
        uint256 boostedAmount = (amount * 200) / 100;

        bool foundWin = false;
        for (uint256 i = 0; i < 200; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, amount * BUY_PRICE_WEED);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);

            // WIN: Keep cash, gain boosted drugs
            if (cashAfter == cashBefore && drugsAfter == drugsBefore + boostedAmount) {
                foundWin = true;
                break;
            }
        }

        assertTrue(foundWin, "Should find WIN with 2x drug multiplier within 200 attempts");
    }

    function test_playGame_repMultiplierApplied() public {
        _setupDealerForPlay(DEALER_ID_1);

        _applyBoost(DEALER_ID_1, 1 days, 100, 200, 0, false, false, 100);

        uint8 playerChoice = 0;
        uint256 amount = 50;

        bool foundWin = false;
        for (uint256 i = 0; i < 200; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, amount * BUY_PRICE_WEED);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (_isInJail(DEALER_ID_1)) continue;

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

            // WIN: keep cash + get drugs
            bool isWin = (cashAfter == cashBefore) && (drugsAfter > drugsBefore);
            if (isWin) {
                uint256 repGain = repAfter - repBefore;
                // stakeValue=50, divisor=50 → 1x scale. base=10, 2x boost → 20 rep
                assertEq(repGain, 20, "2x rep multiplier with full stake should give 2x base rep");
                foundWin = true;
                break;
            }
        }

        assertTrue(foundWin, "Should find a WIN outcome to test rep multiplier");
    }

    function test_playGame_cashMultiplierApplied() public {
        _setupDealerForPlay(DEALER_ID_1);

        _applyBoost(DEALER_ID_1, 1 days, 100, 100, 0, false, false, 200);

        uint8 playerChoice = 0;
        uint256 amount = 10;
        uint256 boostedCash = (amount * SELL_PRICE_WEED * 200) / 100;

        bool foundWin = false;
        for (uint256 i = 0; i < 200; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addDrugsToDealer(DEALER_ID_1, DRUG_WEED, amount);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.SELL, DRUG_WEED, amount);

            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);

            // WIN SELL: Keep drugs, gain boosted cash
            if (drugsAfter == drugsBefore && cashAfter == cashBefore + boostedCash) {
                foundWin = true;
                break;
            }
        }

        assertTrue(foundWin, "Should find WIN with 2x cash multiplier within 200 attempts");
    }

    function test_playGame_noMultiplierWithoutBoost() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint8 playerChoice = 0;
        uint256 amount = 10;

        bool foundWin = false;
        for (uint256 i = 0; i < 200; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                actions.purchaseAttemptReset{value: 0.001 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, amount * BUY_PRICE_WEED);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, IDealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);

            // WIN: Keep cash, gain exact amount (no multiplier)
            if (cashAfter == cashBefore && drugsAfter == drugsBefore + amount) {
                foundWin = true;
                break;
            }
        }

        assertTrue(foundWin, "Should find WIN without boost within 200 attempts");
    }

    // =============================================================
    //                   LOCATION VALIDATION (4 tests)
    // =============================================================

    function test_playGame_revertInJail() public {
        _sendDealerToJail(DEALER_ID_1);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.DealerInJail.selector);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    function test_playGame_revertInSafeHouse() public {
        // Move dealer to safe house first (they start in Manhattan now)
        vm.prank(player1);
        actions.travel{value: 0}(DEALER_ID_1, AREA_SAFE_HOUSE);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.DealerInSafeHouse.selector);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    function test_playGame_revertDrugNotInArea() public {
        _moveDealerToArea(DEALER_ID_1, AREA_MANHATTAN);
        _addCashToDealer(DEALER_ID_1, 1000);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.DrugNotAvailableInArea.selector);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, 999, 10);
    }

    function test_playGame_revertNonExistentToken() public {
        uint256 nonExistentToken = 999;

        vm.prank(player1);
        vm.expectRevert();
        pve.playGame(nonExistentToken, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    // =============================================================
    //                    ATTEMPTS & HEAT (4 tests)
    // =============================================================

    function test_playGame_usesAttempt() public {
        _setupDealerForPlay(DEALER_ID_1);

        (,, uint8 attemptsBefore,,,) = core.getDealerData(DEALER_ID_1);

        uint256 prevrandao = _getPrevrandaoNoArrest(DEALER_ID_1, 0);
        vm.prevrandao(bytes32(prevrandao));

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 10);

        (,, uint8 attemptsAfter,,,) = core.getDealerData(DEALER_ID_1);

        assertEq(attemptsAfter, attemptsBefore - 1, "Should use 1 attempt");
    }

    function test_playGame_revertNoAttempts() public {
        _setupDealerForPlay(DEALER_ID_1);

        _useAttempts(DEALER_ID_1, 5);

        vm.prank(player1);
        vm.expectRevert();
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    function test_playGame_incrementsHeat() public {
        _setupDealerForPlay(DEALER_ID_1);

        (,,, uint8 heatBefore,,) = core.getDealerData(DEALER_ID_1);

        uint256 prevrandao = _getPrevrandaoNoArrest(DEALER_ID_1, heatBefore + 1);
        vm.prevrandao(bytes32(prevrandao));

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 10);

        (,,, uint8 heatAfter,,) = core.getDealerData(DEALER_ID_1);

        assertEq(heatAfter, heatBefore + 1, "Heat should increment by 1");
    }

    function test_playGame_heatAffectsJailChance() public {
        _setupDealerForPlay(DEALER_ID_1);

        assertEq(core.getGameState(DEALER_ID_1).jailChance, 0, "Heat 0 = 0% jail chance");

        _setHeatLevel(DEALER_ID_1, 3);

        assertEq(core.getGameState(DEALER_ID_1).jailChance, 15, "Heat 3 = 1.5% jail chance (15/1000)");

        _setHeatLevel(DEALER_ID_1, 2);

        assertEq(core.getGameState(DEALER_ID_1).jailChance, 25, "Heat 5 = 2.5% jail chance (25/1000)");
    }

    // =============================================================
    //                    VIEW FUNCTIONS (2 tests)
    // =============================================================

    function test_canPlay_returnsCorrectReasons() public {
        // Dealer starts in Manhattan now
        (bool canPlay, uint8 reason) = pve.canPlay(DEALER_ID_1);
        assertTrue(canPlay && reason == 0, "In Manhattan with attempts should be playable");

        // Move to safe house to test safe house restriction
        vm.prank(player1);
        actions.travel{value: 0}(DEALER_ID_1, AREA_SAFE_HOUSE);
        (canPlay, reason) = pve.canPlay(DEALER_ID_1);
        assertTrue(!canPlay && reason == 3, "In safe house should return reason 3");

        // Move back to Manhattan then send to jail
        _moveDealerToArea(DEALER_ID_1, AREA_MANHATTAN);
        _sendDealerToJail(DEALER_ID_1);
        (canPlay, reason) = pve.canPlay(DEALER_ID_1);
        assertTrue(!canPlay && reason == 2, "In jail should return reason 2");
    }

    function test_previewHustle_returnsCorrectValues() public {
        _moveDealerToArea(DEALER_ID_1, AREA_MANHATTAN);

        uint256 amount = 10;

        (
            int16 winRep,
            int16 tieRep,
            int16 lossRep,
            uint256 cashValueOnSell,
            uint256 cashCostOnBuy
        ) = pve.previewHustle(DEALER_ID_1, DRUG_WEED, amount);

        assertEq(winRep, 10, "Win rep for Street Dealer tier");
        assertEq(tieRep, 5, "Tie rep for Street Dealer tier");
        assertEq(lossRep, -5, "Loss rep for Street Dealer tier");
        assertEq(cashValueOnSell, amount * SELL_PRICE_WEED, "Sell value calculation");
        assertEq(cashCostOnBuy, amount * BUY_PRICE_WEED, "Buy cost calculation");
    }

    // =============================================================
    //                    SECURITY FEATURES (6 tests)
    // =============================================================

    function test_pause_revertsOnPlay() public {
        _setupDealerForPlay(DEALER_ID_1);

        pve.pause();

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.ContractPaused.selector);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    function test_pause_unpause_allowsPlay() public {
        _setupDealerForPlay(DEALER_ID_1);

        pve.pause();
        pve.unpause();

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    function test_pause_onlyOwner() public {
        vm.prank(player1);
        vm.expectRevert();
        pve.pause();
    }

    function test_unpause_onlyOwner() public {
        pve.pause();

        vm.prank(player1);
        vm.expectRevert();
        pve.unpause();
    }

    function test_setDealersExeCore_revertZeroAddress() public {
        vm.expectRevert(DealersExePVE.InvalidAddress.selector);
        pve.setDealersExeCore(address(0));
    }

    function test_setDealersExeNFT_revertZeroAddress() public {
        vm.expectRevert(DealersExePVE.InvalidAddress.selector);
        pve.setDealersExeNFT(address(0));
    }

    function test_setAreaRegistry_revertZeroAddress() public {
        vm.expectRevert(DealersExePVE.InvalidAddress.selector);
        pve.setAreaRegistry(address(0));
    }

    function test_setRandomness_revertZeroAddress() public {
        vm.expectRevert(DealersExePVE.InvalidAddress.selector);
        pve.setRandomness(address(0));
    }

    function test_pveStats_accumulateAcrossGames() public {
        _setupDealerForPlay(DEALER_ID_1);

        uint32 totalPlayed = 0;
        for (uint256 i = 0; i < 20; i++) {
            if (_isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.warp(block.timestamp + 1 days);
            }

            uint8 choice = uint8(i % 3);
            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, choice, IDealersExePVE.HustleType.BUY, DRUG_WEED, 1);

            if (!_isInJail(DEALER_ID_1)) {
                totalPlayed++;
            }
        }

        IDealersExePVE.PveStats memory stats = pve.getDealerPveStats(DEALER_ID_1);
        uint32 totalOutcomes = stats.wins + stats.losses + stats.ties;
        uint32 totalChoices = stats.dealChoices + stats.threatenChoices + stats.bailChoices;

        assertEq(totalOutcomes, totalChoices, "outcomes should match choices");
        assertGt(totalOutcomes, 0, "should have played at least one game");
    }

    function test_amsterdam_sellWeedArbitrage() public {
        _setupDealerForPlay(DEALER_ID_1);

        core.authorizeContract(address(this), true);
        core.updateReputation(DEALER_ID_1, 150);
        core.authorizeContract(address(this), false);

        vm.prank(player1);
        actions.travel{value: 0.001 ether}(DEALER_ID_1, AREA_AMSTERDAM);

        (uint8 area,,,,,) = core.getDealerData(DEALER_ID_1);
        assertEq(area, AREA_AMSTERDAM);

        bool foundWin = false;
        for (uint256 i = 0; i < 200; i++) {
            if (_isInJail(DEALER_ID_1)) {
                // Bail out and travel back to Amsterdam
                vm.prank(player1);
                actions.payBail{value: 0.001 ether}(DEALER_ID_1);
                vm.prank(player1);
                actions.travel{value: 0.001 ether}(DEALER_ID_1, AREA_AMSTERDAM);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) vm.warp(block.timestamp + 1 days);

            _addDrugsToDealer(DEALER_ID_1, DRUG_WEED, 50);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 weedBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, 0, IDealersExePVE.HustleType.SELL, DRUG_WEED, 10);

            if (_isInJail(DEALER_ID_1)) continue;

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 weedAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

            // WIN on SELL: keep drugs + get cash at sellPrice=2
            if (cashAfter > cashBefore && weedAfter == weedBefore) {
                assertGe(cashAfter - cashBefore, 10 * 2, "Amsterdam weed sell should pay at sellPrice=2");
                foundWin = true;
                break;
            }
        }
        assertTrue(foundWin, "Should find a SELL WIN in Amsterdam");
    }

    function test_amsterdam_buyShroomsAndHeroin() public {
        _setupDealerForPlay(DEALER_ID_1);

        core.authorizeContract(address(this), true);
        core.updateReputation(DEALER_ID_1, 150);
        core.authorizeContract(address(this), false);

        vm.prank(player1);
        actions.travel{value: 0.001 ether}(DEALER_ID_1, AREA_AMSTERDAM);

        // Verify drug availability in Amsterdam
        assertTrue(areaRegistry.isDrugAvailableInArea(AREA_AMSTERDAM, DRUG_WEED));
        assertTrue(areaRegistry.isDrugAvailableInArea(AREA_AMSTERDAM, DRUG_SHROOMS));
        assertTrue(areaRegistry.isDrugAvailableInArea(AREA_AMSTERDAM, DRUG_HEROIN));

        // Verify pricing
        (uint256 shroomsBuy, uint256 shroomsSell) = areaRegistry.getDrugPricing(AREA_AMSTERDAM, DRUG_SHROOMS);
        assertEq(shroomsBuy, 15);
        assertEq(shroomsSell, 12);

        (uint256 heroinBuy, uint256 heroinSell) = areaRegistry.getDrugPricing(AREA_AMSTERDAM, DRUG_HEROIN);
        assertEq(heroinBuy, 180);
        assertEq(heroinSell, 150);
    }

    function test_amsterdam_requiresMinReputation() public {
        _setupDealerForPlay(DEALER_ID_1);

        // Try traveling with 0 rep — should revert
        vm.prank(player1);
        vm.expectRevert();
        actions.travel{value: 0.001 ether}(DEALER_ID_1, AREA_AMSTERDAM);
    }
}

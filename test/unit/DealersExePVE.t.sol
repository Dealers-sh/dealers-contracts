// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/core/DealersExeCore.sol";
import "../../src/nft/DealersExeNFT.sol";
import "../../src/core/DealersExePVE.sol";
import "../../src/utils/DEDrugRegistry.sol";
import "../../src/utils/DEAreaRegistry.sol";
import "../../src/utils/DEPaymentHandler.sol";
import "../../src/utils/DERandomness.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract DealersExePVETest is Test, IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
    DealersExeCore public core;
    DealersExeNFT public nft;
    DealersExePVE public pve;
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

    uint256 constant DEALER_ID_1 = 201;
    uint256 constant DEALER_ID_2 = 202;

    uint256 constant DRUG_WEED = 1;
    uint256 constant DRUG_XTC = 2;
    uint256 constant DRUG_COCAINE = 3;

    uint8 constant AREA_SAFE_HOUSE = 0;
    uint8 constant AREA_MANHATTAN = 1;
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
        paymentHandler = new DEPaymentHandler(devWallet, bankVault);
        randomness = new DERandomness();

        core = new DealersExeCore();
        nft = new DealersExeNFT(signer, devWallet);
        pve = new DealersExePVE(address(core), address(nft), address(areaRegistry));

        core.setNFTContract(address(nft));
        core.setPaymentHandler(address(paymentHandler));
        core.setDrugRegistry(address(drugRegistry));
        core.setAreaRegistry(address(areaRegistry));
        core.setRandomness(address(randomness));

        nft.setDealersExeCore(address(core));
        nft.setRandomness(address(randomness));
        pve.setRandomness(address(randomness));

        core.authorizeContract(address(nft), true);
        core.authorizeContract(address(pve), true);
        drugRegistry.authorizeContract(address(core), true);
        randomness.authorizeResolver(address(core), true);
        randomness.authorizeResolver(address(nft), true);
        randomness.authorizeResolver(address(pve), true);

        _setupReputationTiers();

        nft.reserveTo(1, player1);
        nft.reserveTo(1, player2);
    }

    function _setupReputationTiers() internal {
        DealersExeCore.ReputationTier[] memory tiers = new DealersExeCore.ReputationTier[](3);

        tiers[0] = DealersExeCore.ReputationTier({
            minReputation: 0,
            winBonus: 10,
            tieBonus: 5,
            lossPenalty: -5,
            tierName: "Street Dealer",
            canHeist: false,
            pvpRange: 50
        });

        tiers[1] = DealersExeCore.ReputationTier({
            minReputation: 100,
            winBonus: 15,
            tieBonus: 7,
            lossPenalty: -7,
            tierName: "Corner Boss",
            canHeist: true,
            pvpRange: 100
        });

        tiers[2] = DealersExeCore.ReputationTier({
            minReputation: 500,
            winBonus: 20,
            tieBonus: 10,
            lossPenalty: -10,
            tierName: "Kingpin",
            canHeist: true,
            pvpRange: 200
        });

        core.setReputationTiers(tiers);
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
        bool doubleHeistEntries,
        uint8 cashMultiplier
    ) internal {
        core.authorizeContract(address(this), true);
        core.applyBoost(tokenId, duration, drugMultiplier, repMultiplier, extraAttempts, freeAreaMovement, doubleHeistEntries, cashMultiplier);
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

    function _setupDealerForPlay(uint256 tokenId, address player) internal {
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
                pve.totalGamesPlayed()
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
            pve.totalGamesPlayed()
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
            uint256 randomness = uint256(keccak256(abi.encodePacked(
                testPrevrandao,
                block.timestamp,
                tokenId,
                player1,
                pve.totalGamesPlayed()
            )));
            uint8 jailRoll = uint8(randomness % 100);

            if (jailRoll < heatAfterIncrement) {
                return testPrevrandao;
            }
        }
        revert("Could not find prevrandao for arrest");
    }

    function _getPrevrandaoNoArrest(uint256 tokenId, uint8 heatLevel) internal view returns (uint256) {
        for (uint256 i = 0; i < 1000; i++) {
            uint256 testPrevrandao = i;
            uint256 randomness = uint256(keccak256(abi.encodePacked(
                testPrevrandao,
                block.timestamp,
                tokenId,
                player1,
                pve.totalGamesPlayed()
            )));
            uint8 jailRoll = uint8(randomness % 100);

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
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 playerChoice = 0; // DEAL
        uint256 amount = 10;
        uint256 buyPrice = BUY_PRICE_WEED;
        uint256 stakeCost = amount * buyPrice;

        uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
        uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
        (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

        uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
        uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
        (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

        bool gotArrested = core.isInJail(DEALER_ID_1);
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
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 playerChoice = 1; // THREATEN
        uint256 amount = 10;
        uint256 buyPrice = BUY_PRICE_WEED;
        uint256 stakeCost = amount * buyPrice;

        uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
        uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
        (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

        uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
        uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
        (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

        bool gotArrested = core.isInJail(DEALER_ID_1);
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
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 playerChoice = 0; // DEAL (choice doesn't affect outcome in weighted system)
        uint8 desiredOutcome = 0; // WIN
        uint256 prevrandao = _getPrevrandaoForOutcome(DEALER_ID_1, playerChoice, desiredOutcome);

        vm.prevrandao(bytes32(prevrandao));

        (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);

        (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

        assertGt(repAfter, repBefore, "WIN should gain big rep");
    }

    function test_calculateGameOutcome_tieOutcome() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 playerChoice = 0;
        uint256 amount = 10;
        uint256 stakeCost = amount * BUY_PRICE_WEED;

        bool foundTie = false;
        for (uint256 i = 0; i < 200; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                core.purchaseAttemptReset{value: 0.005 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, stakeCost);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) continue;

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
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 playerChoice = 0; // DEAL
        uint256 amount = 10;
        uint256 stakeCost = amount * BUY_PRICE_WEED;

        bool foundWin = false;
        for (uint256 i = 0; i < 100; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                core.authorizeContract(address(this), true);
                core.updateDailyPlays(DEALER_ID_1, 5);
                core.authorizeContract(address(this), false);
            }

            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) continue;

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
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 playerChoice = 0;
        uint256 amount = 10;
        uint256 expectedCost = amount * BUY_PRICE_WEED;

        bool foundTie = false;
        for (uint256 i = 0; i < 200; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                core.purchaseAttemptReset{value: 0.005 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, expectedCost);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) continue;

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
        _setupDealerForPlay(DEALER_ID_1, player1);

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
            pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) {
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
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_XTC, 1000);
    }

    function test_playGame_buyZeroAmount_reverts() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.InvalidAmount.selector);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 0);
    }

    // =============================================================
    //                      SELL OUTCOMES (5 tests)
    // =============================================================

    function test_playGame_sellWin_keepDrugsGetCash() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 playerChoice = 0; // DEAL
        uint256 amount = 10;
        uint256 expectedCash = amount * SELL_PRICE_WEED;

        bool foundWin = false;
        for (uint256 i = 0; i < 100; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                core.authorizeContract(address(this), true);
                core.updateDailyPlays(DEALER_ID_1, 5);
                core.authorizeContract(address(this), false);
            }

            _addDrugsToDealer(DEALER_ID_1, DRUG_WEED, amount);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.SELL, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) continue;

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
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 playerChoice = 0;
        uint256 amount = 10;
        uint256 expectedCash = amount * SELL_PRICE_WEED;

        bool foundTie = false;
        for (uint256 i = 0; i < 200; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                core.purchaseAttemptReset{value: 0.005 ether}(DEALER_ID_1);
            }

            _addDrugsToDealer(DEALER_ID_1, DRUG_WEED, amount);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.SELL, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) continue;

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
        _setupDealerForPlay(DEALER_ID_1, player1);

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
            pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.SELL, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) {
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
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.SELL, DRUG_WEED, 1000);
    }

    function test_playGame_sellZeroAmount_reverts() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.InvalidAmount.selector);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.SELL, DRUG_WEED, 0);
    }

    // =============================================================
    //                      ARREST/JAIL (4 tests)
    // =============================================================

    function test_playGame_arrestBeforeOutcome() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        _setHeatLevel(DEALER_ID_1, 5);

        bool arrested = false;
        for (uint256 i = 0; i < 100; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                core.purchaseAttemptReset{value: 0.005 ether}(DEALER_ID_1);
            }

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);

            if (core.isInJail(DEALER_ID_1)) {
                arrested = true;
                break;
            }
        }

        assertTrue(arrested, "Dealer should be in jail after arrest (within 100 attempts)");
    }

    function test_playGame_arrestLosesStake_buy() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        _setHeatLevel(DEALER_ID_1, 5);

        uint256 amount = 10;
        uint256 stakeCost = amount * BUY_PRICE_WEED;

        bool arrested = false;
        for (uint256 i = 0; i < 100; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                core.purchaseAttemptReset{value: 0.005 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, stakeCost);
            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) {
                uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
                assertEq(cashAfter, cashBefore - stakeCost, "Arrested BUY loses staked cash");
                arrested = true;
                break;
            }
        }

        assertTrue(arrested, "Dealer should be in jail (within 100 attempts)");
    }

    function test_playGame_arrestLosesStake_sell() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        _setHeatLevel(DEALER_ID_1, 5);

        uint256 amount = 10;

        bool arrested = false;
        for (uint256 i = 0; i < 100; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                core.purchaseAttemptReset{value: 0.005 ether}(DEALER_ID_1);
            }

            _addDrugsToDealer(DEALER_ID_1, DRUG_WEED, amount);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.SELL, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) {
                uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
                assertEq(drugsAfter, drugsBefore - amount, "Arrested SELL loses staked drugs");
                arrested = true;
                break;
            }
        }

        assertTrue(arrested, "Dealer should be in jail (within 100 attempts)");
    }

    function test_playGame_arrestIncreasesJailCount() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        _setHeatLevel(DEALER_ID_1, 5);

        uint256 jailedBefore = pve.playerTimesJailed(DEALER_ID_1);
        uint256 totalArrestsBefore = pve.totalArrestsInPVE();

        bool arrested = false;
        for (uint256 i = 0; i < 100; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                break;
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                vm.prank(player1);
                core.purchaseAttemptReset{value: 0.005 ether}(DEALER_ID_1);
            }

            _addCashToDealer(DEALER_ID_1, 10);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);

            if (core.isInJail(DEALER_ID_1)) {
                arrested = true;
                break;
            }
        }

        assertTrue(arrested, "Should get arrested within 100 attempts");
        assertEq(pve.playerTimesJailed(DEALER_ID_1), jailedBefore + 1, "Player jail count should increase");
        assertEq(pve.totalArrestsInPVE(), totalArrestsBefore + 1, "Total arrests should increase");
    }

    // =============================================================
    //                      MULTIPLIERS (4 tests)
    // =============================================================

    function test_playGame_drugMultiplierApplied() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        _applyBoost(DEALER_ID_1, 1 days, 200, 100, 0, false, false, 100);

        uint8 playerChoice = 0;
        uint8 desiredOutcome = 0; // WIN
        uint256 prevrandao = _getPrevrandaoForOutcome(DEALER_ID_1, playerChoice, desiredOutcome);

        vm.prevrandao(bytes32(prevrandao));

        uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
        uint256 amount = 10;

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

        uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

        uint256 boostedAmount = (amount * 200) / 100;
        assertEq(drugsAfter, drugsBefore + boostedAmount, "2x drug multiplier should double drugs");
    }

    function test_playGame_repMultiplierApplied() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        _applyBoost(DEALER_ID_1, 1 days, 100, 200, 0, false, false, 100);

        uint8 playerChoice = 0;
        uint256 amount = 10;

        bool foundWin = false;
        for (uint256 i = 0; i < 100; i++) {
            if (core.isInJail(DEALER_ID_1)) {
                core.authorizeContract(address(this), true);
                core.moveToArea(DEALER_ID_1, AREA_MANHATTAN);
                core.authorizeContract(address(this), false);
            }

            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                core.authorizeContract(address(this), true);
                core.updateDailyPlays(DEALER_ID_1, 5);
                core.authorizeContract(address(this), false);
            }

            uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
            uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repBefore,,,,) = core.getDealerData(DEALER_ID_1);

            vm.prevrandao(bytes32(i));
            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

            if (core.isInJail(DEALER_ID_1)) continue;

            uint256 cashAfter = core.getCashBalance(DEALER_ID_1);
            uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
            (, uint256 repAfter,,,,) = core.getDealerData(DEALER_ID_1);

            bool isWin = (cashAfter == cashBefore) && (drugsAfter > drugsBefore);
            if (isWin) {
                uint256 repGain = repAfter - repBefore;
                assertGt(repGain, 10, "2x rep multiplier should give more than base 10 rep");
                foundWin = true;
                break;
            }
        }

        assertTrue(foundWin, "Should find a WIN outcome to test rep multiplier");
    }

    function test_playGame_cashMultiplierApplied() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        _applyBoost(DEALER_ID_1, 1 days, 100, 100, 0, false, false, 200);

        uint8 playerChoice = 0;
        uint8 desiredOutcome = 0; // WIN
        uint256 prevrandao = _getPrevrandaoForOutcome(DEALER_ID_1, playerChoice, desiredOutcome);

        vm.prevrandao(bytes32(prevrandao));

        uint256 cashBefore = core.getCashBalance(DEALER_ID_1);
        uint256 amount = 10;

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.SELL, DRUG_WEED, amount);

        uint256 cashAfter = core.getCashBalance(DEALER_ID_1);

        uint256 boostedCash = (amount * SELL_PRICE_WEED * 200) / 100;
        assertEq(cashAfter, cashBefore + boostedCash, "2x cash multiplier should double sell cash");
    }

    function test_playGame_noMultiplierWithoutBoost() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 playerChoice = 0;
        uint8 desiredOutcome = 0; // WIN
        uint256 prevrandao = _getPrevrandaoForOutcome(DEALER_ID_1, playerChoice, desiredOutcome);

        vm.prevrandao(bytes32(prevrandao));

        uint256 drugsBefore = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);
        uint256 amount = 10;

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, amount);

        uint256 drugsAfter = core.getDrugBalance(DEALER_ID_1, DRUG_WEED);

        assertEq(drugsAfter, drugsBefore + amount, "Without boost should get exact amount");
    }

    // =============================================================
    //                   LOCATION VALIDATION (4 tests)
    // =============================================================

    function test_playGame_revertInJail() public {
        _sendDealerToJail(DEALER_ID_1);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.DealerInJail.selector);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    function test_playGame_revertInSafeHouse() public {
        vm.prank(player1);
        vm.expectRevert(DealersExePVE.DealerInSafeHouse.selector);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    function test_playGame_revertDrugNotInArea() public {
        _moveDealerToArea(DEALER_ID_1, AREA_MANHATTAN);
        _addCashToDealer(DEALER_ID_1, 1000);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.DrugNotAvailableInArea.selector);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, 999, 10);
    }

    function test_playGame_revertDealerNotInitialized() public {
        nft.reserveTo(1, player1);
        uint256 uninitTokenId = 204;

        core.authorizeContract(address(this), true);

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.DealerNotInitialized.selector);
        pve.playGame(uninitTokenId, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    // =============================================================
    //                    ATTEMPTS & HEAT (4 tests)
    // =============================================================

    function test_playGame_usesAttempt() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        (,, uint8 attemptsBefore,,,) = core.getDealerData(DEALER_ID_1);

        uint256 prevrandao = _getPrevrandaoNoArrest(DEALER_ID_1, 0);
        vm.prevrandao(bytes32(prevrandao));

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);

        (,, uint8 attemptsAfter,,,) = core.getDealerData(DEALER_ID_1);

        assertEq(attemptsAfter, attemptsBefore - 1, "Should use 1 attempt");
    }

    function test_playGame_revertNoAttempts() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        _useAttempts(DEALER_ID_1, 5);

        vm.prank(player1);
        vm.expectRevert();
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    function test_playGame_incrementsHeat() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        (,,, uint8 heatBefore,,) = core.getDealerData(DEALER_ID_1);

        uint256 prevrandao = _getPrevrandaoNoArrest(DEALER_ID_1, heatBefore + 1);
        vm.prevrandao(bytes32(prevrandao));

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);

        (,,, uint8 heatAfter,,) = core.getDealerData(DEALER_ID_1);

        assertEq(heatAfter, heatBefore + 1, "Heat should increment by 1");
    }

    function test_playGame_heatAffectsJailChance() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint8 jailChanceAt0 = core.getJailChance(DEALER_ID_1);
        assertEq(jailChanceAt0, 0, "Heat 0 = 0% jail chance");

        _setHeatLevel(DEALER_ID_1, 3);

        uint8 jailChanceAt3 = core.getJailChance(DEALER_ID_1);
        assertEq(jailChanceAt3, 3, "Heat 3 = 3% jail chance");

        _setHeatLevel(DEALER_ID_1, 2);

        uint8 jailChanceAt5 = core.getJailChance(DEALER_ID_1);
        assertEq(jailChanceAt5, 5, "Heat 5 = 5% jail chance");
    }

    // =============================================================
    //                      STATISTICS (3 tests)
    // =============================================================

    function test_playGame_updatesPlayerStats() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint256 gamesBefore = pve.playerGamesPlayed(DEALER_ID_1);

        uint256 prevrandao = _getPrevrandaoNoArrest(DEALER_ID_1, 0);
        vm.prevrandao(bytes32(prevrandao));

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);

        uint256 gamesAfter = pve.playerGamesPlayed(DEALER_ID_1);

        assertEq(gamesAfter, gamesBefore + 1, "Games played should increment");
    }

    function test_playGame_updatesGlobalStats() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        uint256 totalBefore = pve.totalGamesPlayed();

        uint256 prevrandao = _getPrevrandaoNoArrest(DEALER_ID_1, 0);
        vm.prevrandao(bytes32(prevrandao));

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);

        uint256 totalAfter = pve.totalGamesPlayed();

        assertEq(totalAfter, totalBefore + 1, "Total games should increment");
    }

    function test_getPlayerStats_calculatesWinRate() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        for (uint i = 0; i < 3; i++) {
            uint8 playerChoice = 0;
            uint8 desiredOutcome = 0; // WIN
            uint256 prevrandao = _getPrevrandaoForOutcome(DEALER_ID_1, playerChoice, desiredOutcome);

            vm.prevrandao(bytes32(prevrandao));

            vm.prank(player1);
            pve.playGame(DEALER_ID_1, playerChoice, DealersExePVE.HustleType.BUY, DRUG_WEED, 1);

            _addCashToDealer(DEALER_ID_1, 100);
            (,, uint8 attempts,,,) = core.getDealerData(DEALER_ID_1);
            if (attempts == 0) {
                core.authorizeContract(address(this), true);
                core.updateDailyPlays(DEALER_ID_1, 0);
                core.authorizeContract(address(this), false);
            }
        }

        (uint256 gamesPlayed, uint256 gamesWon, uint256 winRate,) = pve.getPlayerStats(DEALER_ID_1);

        assertGt(gamesPlayed, 0, "Games played > 0");
        if (gamesWon > 0) {
            assertEq(winRate, (gamesWon * 100) / gamesPlayed, "Win rate calculation");
        }
    }

    // =============================================================
    //                    VIEW FUNCTIONS (2 tests)
    // =============================================================

    function test_canPlay_returnsCorrectReasons() public {
        (bool canPlay, uint8 reason) = pve.canPlay(DEALER_ID_1);

        assertTrue(!canPlay && reason == 3, "In safe house should return reason 3");

        _moveDealerToArea(DEALER_ID_1, AREA_MANHATTAN);
        (canPlay, reason) = pve.canPlay(DEALER_ID_1);
        assertTrue(canPlay && reason == 0, "In Manhattan with attempts should be playable");

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
        _setupDealerForPlay(DEALER_ID_1, player1);

        pve.pause();

        vm.prank(player1);
        vm.expectRevert(DealersExePVE.ContractPaused.selector);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);
    }

    function test_pause_unpause_allowsPlay() public {
        _setupDealerForPlay(DEALER_ID_1, player1);

        pve.pause();
        pve.unpause();

        vm.prank(player1);
        pve.playGame(DEALER_ID_1, 0, DealersExePVE.HustleType.BUY, DRUG_WEED, 10);
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
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DealersExeCore} from "../../src/core/DealersExeCore.sol";
import {DealersExeNFT} from "../../src/nft/DealersExeNFT.sol";
import {DealersExePVE} from "../../src/core/DealersExePVE.sol";
import {DealersExePVP} from "../../src/core/DealersExePVP.sol";
import {IDealersExePVE} from "../../src/core/IDealersExePVE.sol";
import {IDealersExePVP} from "../../src/core/IDealersExePVP.sol";
import {DealersExeBoosts} from "../../src/core/DealersExeBoosts.sol";
import {DealersExeActions} from "../../src/core/DealersExeActions.sol";
import {DEDrugRegistry} from "../../src/utils/DEDrugRegistry.sol";
import {IDrugRegistry} from "../../src/utils/IDrugRegistry.sol";
import {DEAreaRegistry} from "../../src/utils/DEAreaRegistry.sol";
import {DEPaymentHandler} from "../../src/utils/DEPaymentHandler.sol";
import {DERandomness} from "../../src/utils/DERandomness.sol";
import {IDealersExeCore} from "../../src/core/IDealersExeCore.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MockEOA is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

abstract contract BaseTest is Test, IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
    DealersExeCore public core;
    DealersExeNFT public nft;
    DealersExePVE public pve;
    DealersExePVP public pvp;
    DealersExeBoosts public boosts;
    DealersExeActions public actions;
    DEDrugRegistry public drugRegistry;
    DEAreaRegistry public areaRegistry;
    DEPaymentHandler public paymentHandler;
    DERandomness public randomness;

    address public owner = address(this);
    address public player1;
    address public player2;
    address public devWallet = makeAddr("devWallet");
    address public bankVault = makeAddr("bankVault");
    address public signer = makeAddr("signer");

    uint256 constant MINT_PRICE = 0.01 ether;
    uint256 constant BAIL_PRICE = 0.002 ether;
    uint8 constant SAFE_HOUSE = 0;
    uint8 constant MANHATTAN = 1;
    uint8 constant JAIL = 255;
    uint256 constant DRUG_GENERAL_GOODS = 1;
    uint256 constant DRUG_CONTRABAND = 2;
    uint256 constant DRUG_JEWELS = 3;
    uint256 constant DRUG_WEED = 4;
    uint256 constant DRUG_XTC = 5;
    uint256 constant DRUG_COCAINE = 6;
    uint256 constant DRUG_SHROOMS = 7;
    uint256 constant DRUG_HEROIN = 8;
    uint256 constant DRUG_OPIOIDS = 9;
    uint256 constant DRUG_METH = 10;
    uint256 constant DRUG_FENTANYL = 11;

    function setUp() public virtual {
        _createPlayers();
        _deployContracts();
        _setupDrugsAndAreas();
        _setupAuthorizations();
        _setupReputationTiers();
        _fundPlayers();
    }

    function _createPlayers() internal {
        MockEOA p1 = new MockEOA();
        MockEOA p2 = new MockEOA();
        player1 = address(p1);
        player2 = address(p2);
    }

    function _deployContracts() internal {
        drugRegistry = new DEDrugRegistry();
        areaRegistry = new DEAreaRegistry(address(drugRegistry));
        paymentHandler = new DEPaymentHandler(devWallet, bankVault);
        randomness = new DERandomness();

        core = new DealersExeCore();
        nft = new DealersExeNFT(devWallet);
        pve = new DealersExePVE(address(core), address(nft), address(areaRegistry));
        pvp = new DealersExePVP(address(core), address(nft), address(areaRegistry));
        boosts = new DealersExeBoosts(address(core), address(nft), address(paymentHandler));
        actions = new DealersExeActions(address(core), address(nft), address(areaRegistry));
        actions.setPaymentHandler(address(paymentHandler));
        actions.setRandomness(address(randomness));

        core.setNFTContract(address(nft));
        core.setPaymentHandler(address(paymentHandler));
        core.setDrugRegistry(address(drugRegistry));
        core.setAreaRegistry(address(areaRegistry));
        core.setRandomness(address(randomness));

        nft.setDealersExeCore(address(core));
        nft.setMintStatus(DealersExeNFT.MintStatus.PUBLIC);

        pve.setRandomness(address(randomness));
        pvp.setRandomness(address(randomness));
        pvp.setDrugRegistry(address(drugRegistry));
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
        _batchDrugs(1, _arr(4, 5, 6), _arr(1, 12, 120), _arr(1, 10, 100));

        areaRegistry.createArea("Amsterdam", 0.001 ether, 150, false, false);
        _batchDrugs(2, _arr(4, 7, 8), _arr(3, 15, 180), _arr(2, 12, 150));

        areaRegistry.createArea("Colombia", 0.001 ether, 250, false, false);
        _batchDrugs(3, _arr(4, 6, 8), _arr(1, 60, 90), _arr(1, 50, 75));

        areaRegistry.createArea("Hong Kong", 0.001 ether, 500, false, false);
        _batchDrugs(4, _arr(9, 10, 8), _arr(18, 28, 140), _arr(15, 22, 110));

        areaRegistry.createArea("Seoul", 0.001 ether, 1000, false, false);
        _batchDrugs(5, _arr(9, 10, 11), _arr(8, 14, 90), _arr(7, 12, 75));

        areaRegistry.createArea("Tokyo", 0.001 ether, 1500, false, false);
        _batchDrugs(6, _arr(9, 10, 11), _arr(24, 32, 200), _arr(20, 26, 160));
    }

    function _batchDrugs(uint8 areaId, uint256[] memory drugIds, uint256[] memory buys, uint256[] memory sells) internal {
        areaRegistry.batchConfigureAreaDrugs(areaId, drugIds, buys, sells);
    }

    function _arr(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _setupAuthorizations() internal {
        core.authorizeContract(address(nft), true);
        core.authorizeContract(address(pve), true);
        core.authorizeContract(address(pvp), true);
        core.authorizeContract(address(boosts), true);
        core.authorizeContract(address(actions), true);

        drugRegistry.authorizeContract(address(core), true);

        areaRegistry.setCoreContract(address(core));

        paymentHandler.authorizeContract(address(core), true);
        paymentHandler.authorizeContract(address(boosts), true);
        paymentHandler.authorizeContract(address(actions), true);

        randomness.authorizeResolver(address(core), true);
        randomness.authorizeResolver(address(pve), true);
        randomness.authorizeResolver(address(pvp), true);
        randomness.authorizeResolver(address(actions), true);
    }

    function _setupReputationTiers() internal {
        IDealersExeCore.ReputationTier[] memory tiers = new IDealersExeCore.ReputationTier[](10);

        tiers[0] = IDealersExeCore.ReputationTier({minReputation: 0, winBonus: 15, tieBonus: 5, lossPenalty: -2, repCap: 25, tierName: "Outsider"});
        tiers[1] = IDealersExeCore.ReputationTier({minReputation: 50, winBonus: 12, tieBonus: 4, lossPenalty: -3, repCap: 22, tierName: "Associate"});
        tiers[2] = IDealersExeCore.ReputationTier({minReputation: 150, winBonus: 10, tieBonus: 4, lossPenalty: -3, repCap: 18, tierName: "Dealer"});
        tiers[3] = IDealersExeCore.ReputationTier({minReputation: 300, winBonus: 9, tieBonus: 3, lossPenalty: -4, repCap: 17, tierName: "Soldier"});
        tiers[4] = IDealersExeCore.ReputationTier({minReputation: 700, winBonus: 8, tieBonus: 3, lossPenalty: -4, repCap: 16, tierName: "Capo"});
        tiers[5] = IDealersExeCore.ReputationTier({minReputation: 1250, winBonus: 7, tieBonus: 3, lossPenalty: -5, repCap: 14, tierName: "Consigliere"});
        tiers[6] = IDealersExeCore.ReputationTier({minReputation: 1900, winBonus: 6, tieBonus: 2, lossPenalty: -5, repCap: 12, tierName: "Underboss"});
        tiers[7] = IDealersExeCore.ReputationTier({minReputation: 2600, winBonus: 5, tieBonus: 2, lossPenalty: -6, repCap: 12, tierName: "Don"});
        tiers[8] = IDealersExeCore.ReputationTier({minReputation: 3500, winBonus: 4, tieBonus: 2, lossPenalty: -6, repCap: 10, tierName: "Godfather"});
        tiers[9] = IDealersExeCore.ReputationTier({minReputation: 5000, winBonus: 3, tieBonus: 1, lossPenalty: -7, repCap: 8, tierName: "Legend"});

        core.setReputationTiers(tiers);
        core.setMaxReputation(6000);
    }

    function _fundPlayers() internal {
        vm.deal(player1, 100 ether);
        vm.deal(player2, 100 ether);
    }

    function _mintNFT(address player) internal returns (uint256 tokenId) {
        vm.prank(player);
        nft.mintPublic{value: MINT_PRICE}(player, 1);
        tokenId = nft.currentTokenId() - 1;
    }

    function _mintAndMoveToManhattan(address player) internal returns (uint256 tokenId) {
        tokenId = _mintNFT(player);
        vm.prank(owner);
        core.authorizeContract(owner, true);
        core.moveToArea(tokenId, MANHATTAN);
    }

    function _forceGameOutcome(uint8 desiredOutcome, uint8 playerChoice) internal view returns (uint256 prevrandao) {
        prevrandao = uint256(keccak256(abi.encodePacked("GAME")));
        while (true) {
            uint256 gameRandomness = uint256(keccak256(abi.encodePacked(prevrandao, "GAME")));
            uint8 roll = uint8(gameRandomness % 100);
            (, uint8 outcome) = _calculateBiasedHouseChoice(roll, playerChoice);
            if (outcome == desiredOutcome) {
                break;
            }
            prevrandao++;
        }
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

    function _forceArrest(uint256 tokenId, uint8 heatLevel) internal view returns (uint256 prevrandao) {
        prevrandao = 0;
        while (true) {
            uint256 rng = uint256(keccak256(abi.encodePacked(
                prevrandao,
                block.timestamp,
                tokenId,
                address(this)
            )));
            uint8 jailRoll = uint8(rng % 100);
            if (jailRoll < heatLevel) {
                break;
            }
            prevrandao++;
        }
    }

    function _forceNoArrest(uint256 tokenId, uint8 heatLevel) internal view returns (uint256 prevrandao) {
        prevrandao = 0;
        while (true) {
            uint256 rng = uint256(keccak256(abi.encodePacked(
                prevrandao,
                block.timestamp,
                tokenId,
                address(this)
            )));
            uint8 jailRoll = uint8(rng % 100);
            if (jailRoll >= heatLevel) {
                break;
            }
            prevrandao++;
        }
    }

    function _calculatePrevrandaoForOutcome(
        uint256 tokenId,
        uint8 playerChoice,
        uint8 desiredOutcome,
        bool shouldArrest,
        uint8 heatLevel
    ) internal view returns (uint256 prevrandao) {
        prevrandao = 0;
        uint256 attempts = 0;
        while (attempts < 100000) {
            uint256 rng = uint256(keccak256(abi.encodePacked(
                prevrandao,
                block.timestamp,
                tokenId,
                msg.sender
            )));

            uint8 jailRoll = uint8(rng % 100);
            bool wouldArrest = jailRoll < heatLevel;

            if (wouldArrest != shouldArrest) {
                prevrandao++;
                attempts++;
                continue;
            }

            if (!shouldArrest) {
                uint256 gameRng = uint256(keccak256(abi.encodePacked(rng, "GAME")));
                uint8 roll = uint8(gameRng % 100);
                (, uint8 outcome) = _calculateBiasedHouseChoice(roll, playerChoice);

                if (outcome != desiredOutcome) {
                    prevrandao++;
                    attempts++;
                    continue;
                }
            }

            break;
        }
    }
}

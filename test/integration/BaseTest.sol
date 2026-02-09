// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DealersExeCore} from "../../src/core/DealersExeCore.sol";
import {DealersExeNFT} from "../../src/nft/DealersExeNFT.sol";
import {DealersExePVE} from "../../src/core/DealersExePVE.sol";
import {DealersExePVP} from "../../src/core/DealersExePVP.sol";
import {DealersExeBoosts} from "../../src/core/DealersExeBoosts.sol";
import {DEDrugRegistry} from "../../src/utils/DEDrugRegistry.sol";
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
    uint256 constant DRUG_WEED = 1;
    uint256 constant DRUG_XTC = 2;
    uint256 constant DRUG_COCAINE = 3;

    function setUp() public virtual {
        _createPlayers();
        _deployContracts();
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

    function _setupAuthorizations() internal {
        core.authorizeContract(address(nft), true);
        core.authorizeContract(address(pve), true);
        core.authorizeContract(address(pvp), true);
        core.authorizeContract(address(boosts), true);

        drugRegistry.authorizeContract(address(core), true);

        areaRegistry.setCoreContract(address(core));

        paymentHandler.authorizeContract(address(core), true);
        paymentHandler.authorizeContract(address(boosts), true);

        randomness.authorizeResolver(address(core), true);
        randomness.authorizeResolver(address(pve), true);
        randomness.authorizeResolver(address(pvp), true);
    }

    function _setupReputationTiers() internal {
        DealersExeCore.ReputationTier[] memory tiers = new DealersExeCore.ReputationTier[](5);

        tiers[0] = DealersExeCore.ReputationTier({
            minReputation: 0,
            winBonus: 5,
            tieBonus: 2,
            lossPenalty: -3,
            tierName: "Street Rat"
        });

        tiers[1] = DealersExeCore.ReputationTier({
            minReputation: 50,
            winBonus: 8,
            tieBonus: 3,
            lossPenalty: -4,
            tierName: "Corner Boy"
        });

        tiers[2] = DealersExeCore.ReputationTier({
            minReputation: 100,
            winBonus: 12,
            tieBonus: 5,
            lossPenalty: -5,
            tierName: "Hustler"
        });

        tiers[3] = DealersExeCore.ReputationTier({
            minReputation: 250,
            winBonus: 15,
            tieBonus: 7,
            lossPenalty: -6,
            tierName: "Shot Caller"
        });

        tiers[4] = DealersExeCore.ReputationTier({
            minReputation: 500,
            winBonus: 20,
            tieBonus: 10,
            lossPenalty: -8,
            tierName: "Kingpin"
        });

        core.setReputationTiers(tiers);
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

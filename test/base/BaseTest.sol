// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "../../src/core/DealersExeCore.sol";
import "../../src/nft/DealersExeNFT.sol";
import "../../src/core/DealersExePVE.sol";
import "../../src/core/DealersExePVP.sol";
import "../../src/core/DealersExeBoosts.sol";
import "../../src/utils/DEPaymentHandler.sol";
import "../../src/utils/DEDrugRegistry.sol";
import "../../src/utils/DEAreaRegistry.sol";
import "../../src/utils/DERandomness.sol";

abstract contract BaseTest is Test, IERC721Receiver {
    DEDrugRegistry public drugRegistry;
    DEAreaRegistry public areaRegistry;
    DEPaymentHandler public paymentHandler;
    DERandomness public randomness;
    DealersExeCore public core;
    DealersExeNFT public nft;
    DealersExePVE public pve;
    DealersExePVP public pvp;
    DealersExeBoosts public boosts;

    address public owner;
    address public player1;
    address public player2;
    address public devWallet;
    address public bankVault;

    uint256 public constant PLAYER_STARTING_BALANCE = 100 ether;

    function setUp() public virtual {
        _setupAccounts();
        _deployContracts();
        _setupAuthorizations();
        _fundPlayers();
    }

    function _setupAccounts() internal {
        owner = address(this);
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        devWallet = makeAddr("devWallet");
        bankVault = makeAddr("bankVault");
    }

    function _deployContracts() internal {
        vm.startPrank(owner);

        drugRegistry = new DEDrugRegistry();

        areaRegistry = new DEAreaRegistry(address(drugRegistry));

        paymentHandler = new DEPaymentHandler(devWallet, bankVault);

        randomness = new DERandomness();

        core = new DealersExeCore();

        nft = new DealersExeNFT(devWallet);

        pve = new DealersExePVE(address(core), address(nft), address(areaRegistry));

        pvp = new DealersExePVP(address(core), address(nft), address(areaRegistry));

        boosts = new DealersExeBoosts(address(core), address(nft), address(paymentHandler));

        core.setDrugRegistry(address(drugRegistry));
        core.setAreaRegistry(address(areaRegistry));
        core.setNFTContract(address(nft));
        core.setPaymentHandler(address(paymentHandler));
        core.setRandomness(address(randomness));

        nft.setDealersExeCore(address(core));

        pve.setRandomness(address(randomness));
        pvp.setRandomness(address(randomness));
        pvp.setDrugRegistry(address(drugRegistry));

        vm.stopPrank();
    }

    function _setupAuthorizations() internal {
        vm.startPrank(owner);

        core.authorizeContract(address(nft), true);
        core.authorizeContract(address(pve), true);
        core.authorizeContract(address(pvp), true);
        core.authorizeContract(address(boosts), true);

        drugRegistry.authorizeContract(address(core), true);

        areaRegistry.setCoreContract(address(core));

        paymentHandler.authorizeContract(address(core), true);
        paymentHandler.authorizeContract(address(pve), true);
        paymentHandler.authorizeContract(address(pvp), true);
        paymentHandler.authorizeContract(address(boosts), true);

        randomness.authorizeResolver(address(core), true);
        randomness.authorizeResolver(address(pve), true);
        randomness.authorizeResolver(address(pvp), true);

        _setupReputationTiers();

        vm.stopPrank();
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
            minReputation: 150,
            winBonus: 12,
            tieBonus: 5,
            lossPenalty: -5,
            tierName: "Hustler"
        });

        tiers[3] = DealersExeCore.ReputationTier({
            minReputation: 400,
            winBonus: 18,
            tieBonus: 7,
            lossPenalty: -6,
            tierName: "Shot Caller"
        });

        tiers[4] = DealersExeCore.ReputationTier({
            minReputation: 800,
            winBonus: 25,
            tieBonus: 10,
            lossPenalty: -8,
            tierName: "Kingpin"
        });

        core.setReputationTiers(tiers);
    }

    function _fundPlayers() internal {
        vm.deal(player1, PLAYER_STARTING_BALANCE);
        vm.deal(player2, PLAYER_STARTING_BALANCE);
    }

    function _mintAndInitialize(address to) internal returns (uint256 tokenId) {
        vm.prank(owner);
        nft.reserveTo(1, to);
        tokenId = nft.currentTokenId() - 1;
    }

    function _moveOutOfSafeHouse(uint256 tokenId) internal {
        uint8 manhattanArea = 1;
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.moveToArea(tokenId, manhattanArea);
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function _computeLeaf(address account, uint256 maxAllocation) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, maxAllocation))));
    }

    function _computeMerkleRoot(bytes32 leaf1, bytes32 leaf2) internal pure returns (bytes32) {
        if (leaf1 < leaf2) {
            return keccak256(abi.encodePacked(leaf1, leaf2));
        }
        return keccak256(abi.encodePacked(leaf2, leaf1));
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

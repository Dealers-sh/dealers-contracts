// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "../../src/core/DealersCore.sol";
import "../../src/nft/DealersNFT.sol";
import "../../src/core/DealersPVE.sol";
import "../../src/core/DealersPVP.sol";
import "../../src/core/IDealersPVE.sol";
import "../../src/core/IDealersPVP.sol";
import "../../src/core/DealersBoosts.sol";
import "../../src/core/DealersActions.sol";
import "../../src/utils/DealersPaymentHandler.sol";
import "../../src/utils/DealersDrugRegistry.sol";
import "../../src/utils/DealersAreaRegistry.sol";
import "../../src/utils/DealersRandomness.sol";
import "../../src/utils/IDealersRandomness.sol";

abstract contract BaseTest is Test, IERC721Receiver {
    DealersDrugRegistry public drugRegistry;
    DealersAreaRegistry public areaRegistry;
    DealersPaymentHandler public paymentHandler;
    DealersRandomness public randomness;
    DealersCore public core;
    DealersNFT public nft;
    DealersPVE public pve;
    DealersPVP public pvp;
    DealersBoosts public boosts;
    DealersActions public actions;

    address public owner;
    address public player1;
    address public player2;
    address public devWallet;
    address public bankVault;

    uint256 public constant PLAYER_STARTING_BALANCE = 100 ether;

    function setUp() public virtual {
        _setupAccounts();
        _deployContracts();
        _setupDrugsAndAreas();
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

        drugRegistry = new DealersDrugRegistry();

        areaRegistry = new DealersAreaRegistry(address(drugRegistry));

        paymentHandler = new DealersPaymentHandler(devWallet, bankVault);

        randomness = new DealersRandomness();

        core = new DealersCore();

        nft = new DealersNFT(devWallet);

        pve = new DealersPVE(address(core), address(nft), address(areaRegistry));

        pvp = new DealersPVP(address(core), address(nft), address(areaRegistry));

        boosts = new DealersBoosts(address(core), address(nft), address(paymentHandler));

        actions = new DealersActions(address(core), address(nft), address(areaRegistry));
        actions.setPaymentHandler(address(paymentHandler));
        actions.setRandomness(address(randomness));

        core.setDrugRegistry(address(drugRegistry));
        core.setAreaRegistry(address(areaRegistry));
        core.setNFTContract(address(nft));
        core.setPaymentHandler(address(paymentHandler));

        nft.setDealersCore(address(core));

        pve.setRandomness(address(randomness));
        pve.setActions(address(actions));
        pvp.setRandomness(address(randomness));
        pvp.setDrugRegistry(address(drugRegistry));
        pvp.setActions(address(actions));

        vm.stopPrank();
    }

    function _setupDrugsAndAreas() internal {
        vm.startPrank(owner);

        // Register 11 drugs (IDs auto-increment 1-11)
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

        // Create 6 game areas (IDs auto-increment 1-6)
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

        vm.stopPrank();
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
        vm.startPrank(owner);

        core.authorizeContract(address(nft), true);
        core.authorizeContract(address(pve), true);
        core.authorizeContract(address(pvp), true);
        core.authorizeContract(address(boosts), true);
        core.authorizeContract(address(actions), true);

        drugRegistry.authorizeContract(address(core), true);

        areaRegistry.setCoreContract(address(core));

        paymentHandler.authorizeContract(address(core), true);
        paymentHandler.authorizeContract(address(pve), true);
        paymentHandler.authorizeContract(address(pvp), true);
        paymentHandler.authorizeContract(address(boosts), true);
        paymentHandler.authorizeContract(address(actions), true);

        randomness.authorizeResolver(address(pve), true);
        randomness.authorizeResolver(address(pvp), true);
        randomness.authorizeResolver(address(actions), true);

        actions.authorizeJailer(address(pve), true);
        actions.authorizeJailer(address(pvp), true);

        _setupReputationTiers();

        vm.stopPrank();
    }

    function _setupReputationTiers() internal {
        IDealersCore.ReputationTier[] memory tiers = new IDealersCore.ReputationTier[](10);

        tiers[0] = IDealersCore.ReputationTier({minReputation: 0, winBonus: 15, tieBonus: 5, lossPenalty: -2, repCap: 25, tierName: "Outsider"});
        tiers[1] = IDealersCore.ReputationTier({minReputation: 50, winBonus: 12, tieBonus: 4, lossPenalty: -3, repCap: 22, tierName: "Associate"});
        tiers[2] = IDealersCore.ReputationTier({minReputation: 150, winBonus: 10, tieBonus: 4, lossPenalty: -3, repCap: 18, tierName: "Dealer"});
        tiers[3] = IDealersCore.ReputationTier({minReputation: 300, winBonus: 9, tieBonus: 3, lossPenalty: -4, repCap: 17, tierName: "Soldier"});
        tiers[4] = IDealersCore.ReputationTier({minReputation: 700, winBonus: 8, tieBonus: 3, lossPenalty: -4, repCap: 16, tierName: "Capo"});
        tiers[5] = IDealersCore.ReputationTier({minReputation: 1250, winBonus: 7, tieBonus: 3, lossPenalty: -5, repCap: 14, tierName: "Consigliere"});
        tiers[6] = IDealersCore.ReputationTier({minReputation: 1900, winBonus: 6, tieBonus: 2, lossPenalty: -5, repCap: 12, tierName: "Underboss"});
        tiers[7] = IDealersCore.ReputationTier({minReputation: 2600, winBonus: 5, tieBonus: 2, lossPenalty: -6, repCap: 12, tierName: "Don"});
        tiers[8] = IDealersCore.ReputationTier({minReputation: 3500, winBonus: 4, tieBonus: 2, lossPenalty: -6, repCap: 10, tierName: "Godfather"});
        tiers[9] = IDealersCore.ReputationTier({minReputation: 5000, winBonus: 3, tieBonus: 1, lossPenalty: -7, repCap: 8, tierName: "Legend"});

        core.setReputationTiers(tiers);
        core.setMaxReputation(6000);
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

    function _isInJail(uint256 tokenId) internal view returns (bool) {
        return core.getGameState(tokenId).isJailed;
    }

    // =========================================================================
    //                  COMMIT-REVEAL HELPERS (test fixtures)
    // =========================================================================

    /// @dev Roll past REVEAL_OFFSET so reveal()/isExpired() are valid for `seq`
    function _advanceToRevealable(uint64 /*seq*/) internal {
        vm.roll(block.number + uint256(randomness.REVEAL_OFFSET()) + 1);
    }

    /// @dev Roll past EXPIRY_WINDOW so isExpired() returns true
    function _advanceToExpired() internal {
        vm.roll(block.number + uint256(randomness.REVEAL_OFFSET()) + uint256(randomness.EXPIRY_WINDOW()) + 1);
    }

    /// @dev Mock reveal(seq) to return a specific bit-packed rand
    function _mockReveal(uint64 seq, uint256 mockedRand) internal {
        vm.mockCall(
            address(randomness),
            abi.encodeWithSelector(IDealersRandomness.reveal.selector, seq),
            abi.encode(mockedRand)
        );
    }

    /// @dev Build a rand uint256 by packing 16-bit slots:
    ///      slot0 = arrest, slot1 = outcome, slot2 = drugSteal,
    ///      slot3 = drop, slot4 = confiscation
    function _packRand(
        uint16 arrestRng,
        uint16 outcomeRng,
        uint16 drugRng,
        uint16 dropRng,
        uint16 confiscRng
    ) internal pure returns (uint256) {
        return uint256(arrestRng)
            | (uint256(outcomeRng) << 16)
            | (uint256(drugRng) << 32)
            | (uint256(dropRng) << 48)
            | (uint256(confiscRng) << 64);
    }

    function _commitAndResolvePve(
        address player,
        uint256 tokenId,
        uint8 choice,
        IDealersPVE.HustleType ht,
        uint256 drugId,
        uint256 amount,
        uint256 mockedRand
    ) internal returns (uint64 seq) {
        vm.prank(player);
        seq = pve.commitGame(tokenId, choice, ht, drugId, amount);
        _mockReveal(seq, mockedRand);
        _advanceToRevealable(seq);
        pve.resolveGame(seq);
    }

    function _commitAndResolvePvp(
        address attackerOwner,
        uint256 attackerId,
        uint256 defenderId,
        uint256 mockedRand
    ) internal returns (uint64 seq) {
        vm.prank(attackerOwner);
        seq = pvp.commitAttack(attackerId, defenderId);
        _mockReveal(seq, mockedRand);
        _advanceToRevealable(seq);
        pvp.resolveAttack(seq);
    }

    // =========================================================================
    //         OUTCOME-SPECIFIC RAND CONSTANTS / HELPERS (commit-reveal)
    // =========================================================================
    // PVE outcome thresholds (from _calculateBiasedHouseChoice):
    //   roll < tieChance(50)              => TIE
    //   roll < tieChance + winChance(70)  => WIN
    //   else                              => LOSS
    // arrestRng % 1000 < heatLevel*jailChancePerHeat => arrest
    //   With heat=0, arrest never triggers regardless of arrestRng
    //   With heat>0, set arrestRng=0 to force arrest, 999 to avoid

    uint16 internal constant ARREST_RNG_NO  = 999;
    uint16 internal constant ARREST_RNG_YES = 0;
    uint16 internal constant OUTCOME_RNG_TIE  = 30;  // < 50
    uint16 internal constant OUTCOME_RNG_WIN  = 60;  // 50 <= 60 < 70
    uint16 internal constant OUTCOME_RNG_LOSS = 99;  // >= 70

    function _randPveOutcome(uint16 outcomeRng) internal pure returns (uint256) {
        return _packRand(ARREST_RNG_NO, outcomeRng, 0, 0, 0);
    }

    function _randPveArrest() internal pure returns (uint256) {
        return _packRand(ARREST_RNG_YES, 0, 0, 0, 0);
    }

    function _pveWin(
        address player,
        uint256 tokenId,
        uint8 choice,
        IDealersPVE.HustleType ht,
        uint256 drugId,
        uint256 amount
    ) internal returns (uint64) {
        return _commitAndResolvePve(player, tokenId, choice, ht, drugId, amount, _randPveOutcome(OUTCOME_RNG_WIN));
    }

    function _pveTie(
        address player,
        uint256 tokenId,
        uint8 choice,
        IDealersPVE.HustleType ht,
        uint256 drugId,
        uint256 amount
    ) internal returns (uint64) {
        return _commitAndResolvePve(player, tokenId, choice, ht, drugId, amount, _randPveOutcome(OUTCOME_RNG_TIE));
    }

    function _pveLoss(
        address player,
        uint256 tokenId,
        uint8 choice,
        IDealersPVE.HustleType ht,
        uint256 drugId,
        uint256 amount
    ) internal returns (uint64) {
        return _commitAndResolvePve(player, tokenId, choice, ht, drugId, amount, _randPveOutcome(OUTCOME_RNG_LOSS));
    }

    function _pveArrest(
        address player,
        uint256 tokenId,
        uint8 choice,
        IDealersPVE.HustleType ht,
        uint256 drugId,
        uint256 amount
    ) internal returns (uint64) {
        return _commitAndResolvePve(player, tokenId, choice, ht, drugId, amount, _randPveArrest());
    }

    // PVP outcome control:
    //   jailRng (slot0) % 1000 < jailChance + infamyBonus => arrest
    //   winRng  (slot1) % 100 < winChancePct => win

    function _randPvpAttackerWin() internal pure returns (uint256) {
        // jailRng=999 (no arrest), winRng=0 (always wins)
        return _packRand(999, 0, 0, 0, 0);
    }

    function _randPvpAttackerLoss() internal pure returns (uint256) {
        // jailRng=999 (no arrest), winRng=99 (loses unless 99 < winChance, max 75)
        return _packRand(999, 99, 0, 0, 0);
    }

    function _randPvpAttackerArrest() internal pure returns (uint256) {
        // jailRng=0 (always arrest if any jail chance)
        return _packRand(0, 0, 0, 0, 0);
    }

    function _pvpAttackerWins(address attackerOwner, uint256 attackerId, uint256 defenderId)
        internal returns (uint64)
    {
        return _commitAndResolvePvp(attackerOwner, attackerId, defenderId, _randPvpAttackerWin());
    }

    function _pvpAttackerLoses(address attackerOwner, uint256 attackerId, uint256 defenderId)
        internal returns (uint64)
    {
        return _commitAndResolvePvp(attackerOwner, attackerId, defenderId, _randPvpAttackerLoss());
    }

    function _pvpAttackerArrested(address attackerOwner, uint256 attackerId, uint256 defenderId)
        internal returns (uint64)
    {
        return _commitAndResolvePvp(attackerOwner, attackerId, defenderId, _randPvpAttackerArrest());
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/core/DealersCore.sol";
import "../../src/core/IDealersCore.sol";
import "../../src/core/DealersClaims.sol";
import "../../src/core/DealersPVE.sol";
import "../../src/core/DealersPVP.sol";
import "../../src/core/IDealersPVE.sol";
import "../../src/core/IDealersPVP.sol";
import "../../src/nft/DealersNFT.sol";
import "../../src/utils/DealersDrugRegistry.sol";
import "../../src/utils/DealersAreaRegistry.sol";
import "../../src/utils/DealersPaymentHandler.sol";
import "../../src/utils/DealersRandomness.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MockPVE {
    mapping(uint256 => IDealersPVE.PveStats) private _stats;

    function setStats(uint256 tokenId, uint32 wins, uint32 losses, uint32 ties) external {
        _stats[tokenId] = IDealersPVE.PveStats(wins, losses, ties, 0, 0, 0);
    }

    function dealerPveStats(uint256 tokenId)
        external
        view
        returns (uint32, uint32, uint32, uint32, uint32, uint32)
    {
        IDealersPVE.PveStats storage s = _stats[tokenId];
        return (s.wins, s.losses, s.ties, s.dealChoices, s.threatenChoices, s.bailChoices);
    }
}

contract MockPVP {
    mapping(uint256 => IDealersPVP.PvpStats) private _stats;

    function setStats(uint256 tokenId, uint32 attackWins, uint32 attackLosses, uint32 defendWins, uint32 defendLosses) external {
        _stats[tokenId] = IDealersPVP.PvpStats(attackWins, attackLosses, defendWins, defendLosses);
    }

    function dealerPvpStats(uint256 tokenId)
        external
        view
        returns (uint32, uint32, uint32, uint32)
    {
        IDealersPVP.PvpStats storage s = _stats[tokenId];
        return (s.attackWins, s.attackLosses, s.defendWins, s.defendLosses);
    }
}

contract DealersClaimsTest is Test, IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    DealersCore public core;
    DealersNFT public nft;
    DealersClaims public claims;
    DealersDrugRegistry public drugRegistry;
    DealersAreaRegistry public areaRegistry;
    DealersPaymentHandler public paymentHandler;
    DealersRandomness public randomness;
    MockPVE public mockPVE;
    MockPVP public mockPVP;

    address public player1;
    address public player2;

    uint256 constant DEALER_1 = 1;
    uint256 constant DEALER_2 = 2;
    uint256 constant DRUG_WEED = 4;

    function setUp() public virtual {
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");

        vm.deal(player1, 100 ether);
        vm.deal(player2, 100 ether);

        drugRegistry = new DealersDrugRegistry();
        areaRegistry = new DealersAreaRegistry(address(drugRegistry));
        _setupDrugsAndAreas();
        paymentHandler = new DealersPaymentHandler(makeAddr("devWallet"), makeAddr("bankVault"));
        randomness = new DealersRandomness();
        mockPVE = new MockPVE();
        mockPVP = new MockPVP();

        core = new DealersCore();
        nft = new DealersNFT(makeAddr("royalty"));
        claims = new DealersClaims(
            address(core), address(nft), address(mockPVE), address(mockPVP)
        );

        core.setNFTContract(address(nft));
        core.setPaymentHandler(address(paymentHandler));
        core.setDrugRegistry(address(drugRegistry));
        core.setAreaRegistry(address(areaRegistry));
        core.setRandomness(address(randomness));

        nft.setDealersCore(address(core));

        core.authorizeContract(address(nft), true);
        core.authorizeContract(address(claims), true);
        drugRegistry.authorizeContract(address(core), true);
        areaRegistry.setCoreContract(address(core));
        paymentHandler.authorizeContract(address(core), true);
        randomness.authorizeResolver(address(core), true);

        _setupReputationTiers();

        nft.reserveTo(1, player1);
        nft.reserveTo(1, player2);
    }

    function _setupReputationTiers() internal {
        IDealersCore.ReputationTier[] memory tiers = new IDealersCore.ReputationTier[](1);
        tiers[0] = IDealersCore.ReputationTier({
            minReputation: 0,
            winBonus: 10,
            tieBonus: 5,
            lossPenalty: -3,
            repCap: 25,
            tierName: "Outsider"
        });
        core.setReputationTiers(tiers);
        core.setMaxReputation(1000);
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
    }

    function _setAchievement(
        uint256 id, uint8 conditionType, uint256 conditionValue, uint256 threshold,
        uint8 rewardType, uint256 rewardId, uint256 rewardAmount
    ) internal {
        claims.setAchievement(id, DealersClaims.Achievement({
            conditionType: conditionType,
            conditionValue: conditionValue,
            threshold: threshold,
            rewardType: rewardType,
            rewardId: rewardId,
            rewardAmount: rewardAmount,
            active: true
        }));
    }

    // =========================================================================
    //                 ON-CHAIN ACHIEVEMENTS — HAPPY PATH
    // =========================================================================

    function test_claimAchievement_pveWins() public {
        _setAchievement(0, 1, 0, 5, 1, 0, 100); // PVE_WINS >= 5 → 100 cash
        mockPVE.setStats(DEALER_1, 5, 2, 1);

        uint256 cashBefore = core.getCashBalance(DEALER_1);
        vm.prank(player1);
        claims.claimAchievement(DEALER_1, 0);

        assertEq(core.getCashBalance(DEALER_1), cashBefore + 100);
        assertTrue(claims.hasClaimedAchievement(0, DEALER_1));
    }

    function test_claimAchievement_pveTotal() public {
        _setAchievement(0, 4, 0, 10, 0, 0, 50); // PVE_TOTAL >= 10 → 50 rep
        mockPVE.setStats(DEALER_1, 4, 3, 3);

        uint256 repBefore = core.getGameState(DEALER_1).totalReputation;
        vm.prank(player1);
        claims.claimAchievement(DEALER_1, 0);

        assertEq(core.getGameState(DEALER_1).totalReputation, repBefore + 50);
    }

    function test_claimAchievement_pvpAttackWins() public {
        _setAchievement(0, 5, 0, 3, 1, 0, 200); // PVP_ATTACK_WINS >= 3 → 200 cash
        mockPVP.setStats(DEALER_1, 3, 1, 0, 0);

        uint256 cashBefore = core.getCashBalance(DEALER_1);
        vm.prank(player1);
        claims.claimAchievement(DEALER_1, 0);

        assertEq(core.getCashBalance(DEALER_1), cashBefore + 200);
    }

    function test_claimAchievement_pvpTotalWins() public {
        _setAchievement(0, 7, 0, 5, 0, 0, 100); // PVP_TOTAL_WINS >= 5 → 100 rep
        mockPVP.setStats(DEALER_1, 3, 0, 2, 0);

        uint256 repBefore = core.getGameState(DEALER_1).totalReputation;
        vm.prank(player1);
        claims.claimAchievement(DEALER_1, 0);

        assertEq(core.getGameState(DEALER_1).totalReputation, repBefore + 100);
    }

    function test_claimAchievement_drugReward() public {
        _setAchievement(0, 1, 0, 1, 2, DRUG_WEED, 25); // PVE_WINS >= 1 → 25 weed
        mockPVE.setStats(DEALER_1, 1, 0, 0);

        uint256 drugBefore = core.getDrugBalance(DEALER_1, DRUG_WEED);
        vm.prank(player1);
        claims.claimAchievement(DEALER_1, 0);

        assertEq(core.getDrugBalance(DEALER_1, DRUG_WEED), drugBefore + 25);
    }

    function test_claimAchievement_reputationCondition() public {
        core.updateReputation(DEALER_1, 100);
        _setAchievement(0, 8, 0, 50, 1, 0, 500); // REPUTATION >= 50 → 500 cash

        uint256 cashBefore = core.getCashBalance(DEALER_1);
        vm.prank(player1);
        claims.claimAchievement(DEALER_1, 0);

        assertEq(core.getCashBalance(DEALER_1), cashBefore + 500);
    }

    function test_claimAchievement_differentTokensSameAchievement() public {
        _setAchievement(0, 1, 0, 1, 1, 0, 50);
        mockPVE.setStats(DEALER_1, 1, 0, 0);
        mockPVE.setStats(DEALER_2, 1, 0, 0);

        uint256 cash1 = core.getCashBalance(DEALER_1);
        uint256 cash2 = core.getCashBalance(DEALER_2);

        vm.prank(player1);
        claims.claimAchievement(DEALER_1, 0);
        vm.prank(player2);
        claims.claimAchievement(DEALER_2, 0);

        assertEq(core.getCashBalance(DEALER_1), cash1 + 50);
        assertEq(core.getCashBalance(DEALER_2), cash2 + 50);
    }

    function test_canClaimAchievement_returnsTrue() public {
        _setAchievement(0, 1, 0, 5, 1, 0, 100);
        mockPVE.setStats(DEALER_1, 5, 0, 0);

        assertTrue(claims.canClaimAchievement(DEALER_1, 0));
    }

    function test_canClaimAchievement_returnsFalseWhenBelowThreshold() public {
        _setAchievement(0, 1, 0, 5, 1, 0, 100);
        mockPVE.setStats(DEALER_1, 4, 0, 0);

        assertFalse(claims.canClaimAchievement(DEALER_1, 0));
    }

    function test_canClaimAchievement_returnsFalseWhenAlreadyClaimed() public {
        _setAchievement(0, 1, 0, 1, 1, 0, 50);
        mockPVE.setStats(DEALER_1, 1, 0, 0);

        vm.prank(player1);
        claims.claimAchievement(DEALER_1, 0);

        assertFalse(claims.canClaimAchievement(DEALER_1, 0));
    }

    // =========================================================================
    //                 ON-CHAIN ACHIEVEMENTS — REVERTS
    // =========================================================================

    function test_claimAchievement_revertThresholdNotMet() public {
        _setAchievement(0, 1, 0, 10, 1, 0, 100);
        mockPVE.setStats(DEALER_1, 5, 0, 0);

        vm.prank(player1);
        vm.expectRevert(DealersClaims.ThresholdNotMet.selector);
        claims.claimAchievement(DEALER_1, 0);
    }

    function test_claimAchievement_revertNotActive() public {
        claims.setAchievement(0, DealersClaims.Achievement({
            conditionType: 1, conditionValue: 0, threshold: 1,
            rewardType: 1, rewardId: 0, rewardAmount: 50, active: false
        }));
        mockPVE.setStats(DEALER_1, 5, 0, 0);

        vm.prank(player1);
        vm.expectRevert(DealersClaims.AchievementNotActive.selector);
        claims.claimAchievement(DEALER_1, 0);
    }

    function test_claimAchievement_revertDoubleClaim() public {
        _setAchievement(0, 1, 0, 1, 1, 0, 50);
        mockPVE.setStats(DEALER_1, 1, 0, 0);

        vm.startPrank(player1);
        claims.claimAchievement(DEALER_1, 0);

        vm.expectRevert(DealersClaims.AlreadyClaimed.selector);
        claims.claimAchievement(DEALER_1, 0);
        vm.stopPrank();
    }

    function test_claimAchievement_revertNotTokenOwner() public {
        _setAchievement(0, 1, 0, 1, 1, 0, 50);
        mockPVE.setStats(DEALER_1, 1, 0, 0);

        vm.prank(player2);
        vm.expectRevert(DealersClaims.NotTokenOwner.selector);
        claims.claimAchievement(DEALER_1, 0);
    }

    function test_setAchievement_revertConditionNone() public {
        vm.expectRevert(DealersClaims.InvalidAchievementConfig.selector);
        _setAchievement(0, 0, 0, 0, 1, 0, 50);
    }

    function test_setAchievement_revertInvalidConditionType() public {
        vm.expectRevert(DealersClaims.InvalidAchievementConfig.selector);
        _setAchievement(0, 99, 0, 5, 1, 0, 100);
    }

    function test_setAchievement_revertInvalidRewardType() public {
        vm.expectRevert(DealersClaims.InvalidAchievementConfig.selector);
        _setAchievement(0, 1, 0, 5, 99, 0, 100);
    }

    // =========================================================================
    //                    ADMIN GRANTS — HAPPY PATH
    // =========================================================================

    function test_grantReward_cash() public {
        uint256 cashBefore = core.getCashBalance(DEALER_1);
        claims.grantReward(DEALER_1, 1, 0, 100);
        assertEq(core.getCashBalance(DEALER_1), cashBefore + 100);
    }

    function test_grantReward_reputation() public {
        uint256 repBefore = core.getGameState(DEALER_1).totalReputation;
        claims.grantReward(DEALER_1, 0, 0, 50);
        assertEq(core.getGameState(DEALER_1).totalReputation, repBefore + 50);
    }

    function test_grantReward_drug() public {
        uint256 drugBefore = core.getDrugBalance(DEALER_1, DRUG_WEED);
        claims.grantReward(DEALER_1, 2, DRUG_WEED, 25);
        assertEq(core.getDrugBalance(DEALER_1, DRUG_WEED), drugBefore + 25);
    }

    function test_grantReward_attempts() public {
        claims.grantReward(DEALER_1, 3, 0, 0);
    }

    function test_batchGrantReward_samePayout() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = DEALER_1;
        tokenIds[1] = DEALER_2;

        uint256 cash1 = core.getCashBalance(DEALER_1);
        uint256 cash2 = core.getCashBalance(DEALER_2);

        claims.batchGrantReward(tokenIds, 1, 0, 50);

        assertEq(core.getCashBalance(DEALER_1), cash1 + 50);
        assertEq(core.getCashBalance(DEALER_2), cash2 + 50);
    }

    function test_batchGrantRewards_differentPayouts() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = DEALER_1;
        tokenIds[1] = DEALER_2;

        uint8[] memory rewardTypes = new uint8[](2);
        rewardTypes[0] = 1; // CASH
        rewardTypes[1] = 0; // REPUTATION

        uint256[] memory rewardIds = new uint256[](2);
        rewardIds[0] = 0;
        rewardIds[1] = 0;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 50;

        uint256 cash1 = core.getCashBalance(DEALER_1);
        uint256 rep2 = core.getGameState(DEALER_2).totalReputation;

        claims.batchGrantRewards(tokenIds, rewardTypes, rewardIds, amounts);

        assertEq(core.getCashBalance(DEALER_1), cash1 + 100);
        assertEq(core.getGameState(DEALER_2).totalReputation, rep2 + 50);
    }

    // =========================================================================
    //                    ADMIN GRANTS — REVERTS
    // =========================================================================

    function test_grantReward_revertNotOwner() public {
        vm.prank(player1);
        vm.expectRevert();
        claims.grantReward(DEALER_1, 1, 0, 100);
    }

    function test_batchGrantReward_revertNotOwner() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = DEALER_1;

        vm.prank(player1);
        vm.expectRevert();
        claims.batchGrantReward(tokenIds, 1, 0, 50);
    }

    function test_batchGrantRewards_revertLengthMismatch() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = DEALER_1;
        tokenIds[1] = DEALER_2;

        uint8[] memory rewardTypes = new uint8[](1);
        rewardTypes[0] = 1;

        uint256[] memory rewardIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert(DealersClaims.LengthMismatch.selector);
        claims.batchGrantRewards(tokenIds, rewardTypes, rewardIds, amounts);
    }

    function test_grantReward_revertInvalidRewardType() public {
        vm.expectRevert(DealersClaims.InvalidRewardType.selector);
        claims.grantReward(DEALER_1, 99, 0, 50);
    }

    // =========================================================================
    //                       ADMIN FUNCTIONS
    // =========================================================================

    function test_setAchievement() public {
        _setAchievement(0, 1, 0, 5, 1, 0, 100);

        DealersClaims.Achievement memory a = claims.getAchievement(0);
        assertEq(a.conditionType, 1);
        assertEq(a.threshold, 5);
        assertEq(a.rewardType, 1);
        assertEq(a.rewardAmount, 100);
        assertTrue(a.active);
        assertEq(claims.achievementCount(), 1);
    }

    function test_removeAchievement() public {
        _setAchievement(0, 1, 0, 5, 1, 0, 100);
        claims.removeAchievement(0);

        DealersClaims.Achievement memory a = claims.getAchievement(0);
        assertFalse(a.active);
    }

    function test_setAchievement_onlyOwner() public {
        vm.prank(player1);
        vm.expectRevert();
        _setAchievement(0, 1, 0, 5, 1, 0, 100);
    }

    function test_setCore_onlyOwner() public {
        vm.prank(player1);
        vm.expectRevert();
        claims.setDealersCore(address(core));
    }

    function test_setNFT_onlyOwner() public {
        vm.prank(player1);
        vm.expectRevert();
        claims.setDealersNFT(address(nft));
    }

    function test_setPVE_onlyOwner() public {
        vm.prank(player1);
        vm.expectRevert();
        claims.setPVE(address(mockPVE));
    }

    function test_setPVP_onlyOwner() public {
        vm.prank(player1);
        vm.expectRevert();
        claims.setPVP(address(mockPVP));
    }

    // =========================================================================
    //                          EVENTS
    // =========================================================================

    function test_emitsAchievementClaimedEvent() public {
        _setAchievement(0, 1, 0, 1, 1, 0, 100);
        mockPVE.setStats(DEALER_1, 1, 0, 0);

        vm.prank(player1);
        vm.expectEmit(true, true, false, true);
        emit DealersClaims.AchievementClaimed(DEALER_1, 0, 1, 100);
        claims.claimAchievement(DEALER_1, 0);
    }

    function test_emitsRewardGrantedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit DealersClaims.RewardGranted(DEALER_1, 1, 0, 50);
        claims.grantReward(DEALER_1, 1, 0, 50);
    }

    function test_emitsBatchRewardGrantedEvent() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = DEALER_1;
        tokenIds[1] = DEALER_2;

        vm.expectEmit(false, false, false, true);
        emit DealersClaims.BatchRewardGranted(2, 1, 0, 50);
        claims.batchGrantReward(tokenIds, 1, 0, 50);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";
import {DealersHeists} from "../../src/core/DealersHeists.sol";
import {DealersBankHeist} from "../../src/core/DealersBankHeist.sol";
import {IDealersHeists} from "../../src/core/IDealersHeists.sol";
import {MockEntropy} from "./MockEntropy.sol";

/**
 * @dev Shared fixture for the heist modules: deploys DealersHeists + DealersBankHeist
 *      against the real game stack from BaseTest, wires authorizations, and exposes
 *      helpers for the commit-reveal stage flow and dealer funding.
 */
abstract contract HeistsBaseTest is BaseTest {
    DealersHeists public heists;
    DealersBankHeist public bankHeist;
    MockEntropy public mockEntropy;

    // Stage difficulties (seeded in setup)
    uint8 internal constant DIFF_SMALL = 0;
    uint8 internal constant DIFF_BIG = 1;
    uint8 internal constant DIFF_HUGE = 2;

    uint96 internal constant SMALL_CASH = 500;
    uint96 internal constant BIG_CASH = 2500;
    uint96 internal constant HUGE_CASH = 10000;

    // mocked reveal values controlling stage outcome (low byte = roll) + jackpot trigger (bits 16+)
    uint256 internal constant RAND_WIN_NO_JP = uint256(50) << 16; // roll 0 = CLEAN; (>>16)%100 = 50 ≥ trigger → no jackpot
    uint256 internal constant RAND_WIN_JP = 0; // roll 0 = CLEAN; (>>16)%100 = 0 < trigger → jackpot
    uint256 internal constant RAND_SETBACK = 70; // roll 70 = SETBACK for stages 2-5 (CLEAN at stage 1)
    uint256 internal constant RAND_LOSS = 99; // roll 99 ≥ clean+setback for every stage → BUST

    function setUp() public virtual override {
        super.setUp();
        _deployHeists();
    }

    function _deployHeists() internal {
        mockEntropy = new MockEntropy();

        heists = new DealersHeists(
            address(core),
            address(nft),
            address(randomness),
            address(paymentHandler),
            address(drugRegistry),
            address(mockEntropy)
        );

        bankHeist = new DealersBankHeist(address(core), address(nft), address(pve), address(pvp), address(heists));

        // Registrations — additive, existing-pattern only.
        core.authorizeContract(address(heists), true);
        core.authorizeContract(address(bankHeist), true);
        paymentHandler.authorizeContract(address(heists), true);
        randomness.authorizeResolver(address(heists), true);
        heists.setActions(address(actions));
        actions.authorizeJailer(address(heists), true);

        // Difficulty config (repGate 0 for the small run so tests aren't rep-gated by default).
        heists.setDifficultyConfig(
            DIFF_SMALL, IDealersHeists.DifficultyConfig({repGate: 0, cashEntry: SMALL_CASH, active: true})
        );
        heists.setDifficultyConfig(
            DIFF_BIG, IDealersHeists.DifficultyConfig({repGate: 300, cashEntry: BIG_CASH, active: true})
        );
        heists.setDifficultyConfig(
            DIFF_HUGE, IDealersHeists.DifficultyConfig({repGate: 1250, cashEntry: HUGE_CASH, active: true})
        );
    }

    // ---- dealer funding helpers (authorize this test contract on core, act, revoke) ----

    function _giveCash(uint256 tokenId, uint256 amount) internal {
        core.authorizeContract(address(this), true);
        core.addCash(tokenId, amount);
        core.authorizeContract(address(this), false);
    }

    function _giveRep(uint256 tokenId, int256 delta) internal {
        core.authorizeContract(address(this), true);
        core.updateReputation(tokenId, delta);
        core.authorizeContract(address(this), false);
    }

    function _setHeat(uint256 tokenId, uint8 level) internal {
        core.authorizeContract(address(this), true);
        core.setHeatLevel(tokenId, level);
        core.authorizeContract(address(this), false);
    }

    /// @dev Mint, initialize, move out of the safe house, and fund a ready-to-play dealer.
    function _readyDealer(address to, uint256 cash) internal returns (uint256 tokenId) {
        tokenId = _mintAndInitialize(to);
        _moveOutOfSafeHouse(tokenId);
        _giveCash(tokenId, cash);
    }

    /// @dev Commit + resolve one stage with a controlled outcome.
    function _playStage(address player, uint256 heistId, uint256 mockedRand) internal returns (uint64 seq) {
        vm.prank(player);
        heists.commitStage(heistId);
        seq = heists.getHeist(heistId).commitSeq;
        _mockReveal(seq, mockedRand);
        _advanceToRevealable(seq);
        heists.resolveStage(seq);
    }
}

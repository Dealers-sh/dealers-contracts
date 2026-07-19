// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./DrugIds.s.sol";

/**
 * @title AreasConfig - Canonical game-area ladder (single source of truth)
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev The seven game areas plus the Black Market sell book, sim-aligned with
 *      test/simulation/economy_sim.py and the reputation tiers in SetupTiers. Every area
 *      configurator — the standalone setup (SetupAreas) and the live corrective (FixAreas) —
 *      reads the same _areaSpecs(), so the ladder can no longer drift between paths. createArea is creation-only, so the two paths split:
 *      _configureAreas creates on a fresh registry, _syncAreas re-pushes onto a live one
 *      through the update setters.
 * @author Berny0x
 */
abstract contract AreasConfig is DrugIds {
    // =============================================================
    //                          CONSTANTS
    // =============================================================

    uint256 constant FREE = 0;
    /** @dev Default hop ~$1; premium is the high-arbitrage sink surcharge (Tokyo/Dubai) at ~$1.67. */
    uint256 constant MOVEMENT_FEE = 0.0006 ether;
    uint256 constant PREMIUM_FEE = 0.001 ether;

    // Black Market is auto-created in DealersAreaRegistry (area 254).
    uint8 constant BLACK_MARKET_AREA = 254;

    /**
     * @dev Canonical config for one tradeable area. Areas carry exactly three drugs, so the
     *      pricing is held as fixed triples rather than dynamic arrays.
     */
    struct AreaSpec {
        uint8 id;
        string name;
        uint256 movementFee;
        uint256 minReputation;
        uint256[] drugIds;
        uint256[] buyPrices;
        uint256[] sellPrices;
    }

    // =============================================================
    //                      CANONICAL LADDER
    // =============================================================

    /**
     * @notice The nine tradeable areas in createArea order (ids 1-9).
     * @dev Gate rationale: Manhattan/Amsterdam onboard F2P; Amsterdam (250) and Colombia (500)
     *      sit between tier thresholds as deliberate "in-between" unlocks; Hong Kong (800) is
     *      the heist gate; Seoul/Tokyo/Dubai track Capo/Consigliere/Underboss. Dubai is not a fixed
     *      endgame — Moscow (7000) sits above it and the ladder keeps extending upward. Warsaw (2200)
     *      is early Eastern-Europe mid-game (opened early for the EE player base), which leaves the
     *      Tokyo(3000)->Dubai(5500) gap open by design. The Black Market book lives in
     *      _configureBlackMarket — it is special (area 254) and ungated.
     * @dev Season shuffle invariant: a new season rotates drug *identities* and arbitrage routes
     *      while holding each area's price slots (buy/sell) and rarity mix fixed — since PVE rep
     *      scales with stake value = amount x price, keeping the price ladder constant keeps the
     *      progression pace pinned (see economy_sim.py) so only the meta moves. Current season:
     *      Colombia is the double-rare cheap source (Fentanyl+Cocaine), Dubai's crown is Fentanyl,
     *      Tokyo trades Cocaine, Hong Kong trades Fentanyl, Seoul sources Heroin.
     * @dev Areas 8/9 (patch 1.1.0): Warsaw (2200) + Moscow (7000) share Slivo and Speed — cheap in
     *      Warsaw, premium in Moscow, the two long Warsaw->Moscow arbitrage runs. Moscow also carries
     *      Krokodil, a Moscow-only "buy-to-flex" (buy 500, sell 50) — a status hold, never a hustle
     *      target, which keeps an edgeless F2P from over-leveraging on it at Moscow's high stakes (see
     *      economy_sim). Prices sim-validated pace-neutral; the Slivo/Speed run margins vs Dubai farming
     *      rely on a shuttle the parking sim doesn't model — the one open check before mainnet.
     */
    function _areaSpecs() internal pure returns (AreaSpec[] memory specs) {
        specs = new AreaSpec[](9);
        specs[0] = _spec(1, "Manhattan", FREE, 0, WEED, METH, COCAINE, 1, 12, 120, 1, 10, 100);
        specs[1] = _spec(2, "Amsterdam", FREE, 250, WEED, XTC, HEROIN, 3, 15, 180, 2, 12, 150);
        specs[2] = _spec(3, "Colombia", MOVEMENT_FEE, 500, WEED, FENTANYL, COCAINE, 1, 60, 90, 1, 50, 75);
        specs[3] = _spec(4, "Hong Kong", MOVEMENT_FEE, 800, OPIOIDS, METH, FENTANYL, 22, 30, 175, 18, 25, 160);
        specs[4] = _spec(5, "Seoul", MOVEMENT_FEE, 1500, OPIOIDS, SHROOMS, HEROIN, 8, 14, 90, 7, 12, 75);
        specs[5] = _spec(6, "Tokyo", PREMIUM_FEE, 3000, OPIOIDS, METH, COCAINE, 24, 32, 200, 20, 26, 160);
        specs[6] = _spec(7, "Dubai", PREMIUM_FEE, 5500, XTC, HEROIN, FENTANYL, 14, 160, 200, 20, 200, 240);
        specs[7] = _spec(8, "Warsaw", MOVEMENT_FEE, 2200, SLIVO, SPEED, HEROIN, 120, 45, 130, 100, 38, 115);
        specs[8] = _spec(9, "Moscow", PREMIUM_FEE, 7000, SLIVO, SPEED, KROKODIL, 200, 90, 500, 250, 110, 50);
    }

    // =============================================================
    //                        CREATE PATH
    // =============================================================

    /**
     * @notice Create every area on a fresh registry and configure its drug book.
     * @dev Idempotent guard: skips when the registry already holds areas, so a re-run of a
     *      fresh-deploy script is a no-op rather than a duplicate-area error. Use _syncAreas to
     *      correct an already-populated registry. Asserts the registry hands back the expected
     *      sequential id so a divergence between this ladder and on-chain ordering fails loudly.
     */
    function _configureAreas(IAreaRegistry reg) internal {
        if (reg.getTotalAreas() > 0) {
            console.log("Areas: already configured, skipping");
            return;
        }

        AreaSpec[] memory specs = _areaSpecs();
        for (uint256 i; i < specs.length; ++i) {
            AreaSpec memory s = specs[i];
            uint8 createdId = reg.createArea(s.name, s.movementFee, s.minReputation, false, false);
            require(createdId == s.id, "AreasConfig: unexpected area id");
            reg.batchConfigureAreaDrugs(s.id, s.drugIds, s.buyPrices, s.sellPrices);
        }

        _configureBlackMarket(reg);
        console.log("Areas created + Black Market sell book configured:", specs.length);
    }

    // =============================================================
    //                         SYNC PATH
    // =============================================================

    /**
     * @notice Re-push the canonical ladder onto an already-populated registry.
     * @dev For live correction and per-season shuffles: createArea would duplicate, so this drives
     *      the per-field update setters instead. batchConfigureAreaDrugs only adds/updates the
     *      listed drugs — it never removes — so a season that rotates a drug out of an area must
     *      first prune the stale entry, else the area keeps both books. _pruneStaleDrugs handles
     *      that; the setters are owner-only and non-destructive (dealer locations and drug balances
     *      in Core stand — a removed drug is only made non-tradeable in that area).
     */
    function _syncAreas(IAreaRegistry reg) internal {
        AreaSpec[] memory specs = _areaSpecs();
        for (uint256 i; i < specs.length; ++i) {
            AreaSpec memory s = specs[i];
            reg.updateMovementFee(s.id, s.movementFee);
            reg.updateMinReputation(s.id, s.minReputation);
            _pruneStaleDrugs(reg, s);
            reg.batchConfigureAreaDrugs(s.id, s.drugIds, s.buyPrices, s.sellPrices);
        }

        _configureBlackMarket(reg);
        console.log("Areas: ladder re-synced onto live registry");
    }

    /**
     * @dev Remove any drug currently in the area that the new spec no longer lists. Iterates a
     *      memory snapshot of the live ids, so the registry's swap-and-pop removal can't disturb
     *      the walk. Ids present in both books are left for batchConfigureAreaDrugs to reprice.
     */
    function _pruneStaleDrugs(IAreaRegistry reg, AreaSpec memory s) internal {
        uint256[] memory current = reg.getAreaDrugIds(s.id);
        for (uint256 i; i < current.length; ++i) {
            if (!_inSpec(s.drugIds, current[i])) {
                reg.removeAreaDrug(s.id, current[i]);
            }
        }
    }

    function _inSpec(uint256[] memory ids, uint256 drugId) private pure returns (bool) {
        for (uint256 i; i < ids.length; ++i) {
            if (ids[i] == drugId) return true;
        }
        return false;
    }

    // =============================================================
    //                       INTERNAL HELPERS
    // =============================================================

    /**
     * @dev Black Market sell prices are 2x base value (sell-only by contract design; PVE hustles
     *      are blocked here and DealersActions.sellDrop is the only trade path). Buy prices are
     *      base-value sentinels, never read. Same call shape on both the create and sync paths.
     */
    function _configureBlackMarket(IAreaRegistry reg) internal {
        reg.batchConfigureAreaDrugs(
            BLACK_MARKET_AREA, _arr(GOODS, CONTRABAND, JEWELS), _arr(75, 500, 2500), _arr(150, 1200, 6500)
        );
    }

    function _spec(
        uint8 id,
        string memory name,
        uint256 fee,
        uint256 minRep,
        uint256 drug0,
        uint256 drug1,
        uint256 drug2,
        uint256 buy0,
        uint256 buy1,
        uint256 buy2,
        uint256 sell0,
        uint256 sell1,
        uint256 sell2
    ) private pure returns (AreaSpec memory) {
        return AreaSpec({
            id: id,
            name: name,
            movementFee: fee,
            minReputation: minRep,
            drugIds: _arr(drug0, drug1, drug2),
            buyPrices: _arr(buy0, buy1, buy2),
            sellPrices: _arr(sell0, sell1, sell2)
        });
    }

    function _arr(uint256 a, uint256 b, uint256 c) private pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }
}

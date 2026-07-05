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
 *      configurator — the all-in-one deploy (DeployAll), the standalone setup (SetupAreas)
 *      and the live corrective (FixAreas) — reads the same _areaSpecs(), so the ladder can
 *      no longer drift between paths. createArea is creation-only, so the two paths split:
 *      _configureAreas creates on a fresh registry, _syncAreas re-pushes onto a live one
 *      through the update setters.
 * @author Berny0x
 */
abstract contract AreasConfig is DrugIds {
    // =============================================================
    //                          CONSTANTS
    // =============================================================

    uint256 constant FREE = 0;
    uint256 constant MOVEMENT_FEE = 0.001 ether;
    uint256 constant PREMIUM_FEE = 0.002 ether;

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
     * @notice The seven tradeable areas in createArea order (ids 1-7).
     * @dev Gate rationale: Manhattan/Amsterdam onboard F2P; Amsterdam (250) and Colombia (500)
     *      sit between tier thresholds as deliberate "in-between" unlocks; Hong Kong (800) is
     *      the heist gate; Seoul/Tokyo/Dubai track Capo/Consigliere/Underboss. Dubai is the
     *      sell-heavy endgame zone (buy ~1.3x Tokyo, sell ~2x Tokyo). The Black Market book
     *      lives in _configureBlackMarket — it is special (area 254) and ungated.
     */
    function _areaSpecs() internal pure returns (AreaSpec[] memory specs) {
        specs = new AreaSpec[](7);
        specs[0] = _spec(1, "Manhattan", FREE, 0, WEED, XTC, COCAINE, 1, 12, 120, 1, 10, 100);
        specs[1] = _spec(2, "Amsterdam", FREE, 250, WEED, SHROOMS, HEROIN, 3, 15, 180, 2, 12, 150);
        specs[2] = _spec(3, "Colombia", MOVEMENT_FEE, 500, WEED, COCAINE, HEROIN, 1, 60, 90, 1, 50, 75);
        specs[3] = _spec(4, "Hong Kong", MOVEMENT_FEE, 800, OPIOIDS, METH, HEROIN, 22, 30, 175, 18, 25, 160);
        specs[4] = _spec(5, "Seoul", MOVEMENT_FEE, 1500, OPIOIDS, METH, FENTANYL, 8, 14, 90, 7, 12, 75);
        specs[5] = _spec(6, "Tokyo", MOVEMENT_FEE, 3000, OPIOIDS, METH, FENTANYL, 24, 32, 200, 20, 26, 160);
        specs[6] = _spec(7, "Dubai", PREMIUM_FEE, 5500, XTC, COCAINE, HEROIN, 14, 160, 200, 20, 200, 240);
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
        console.log("Areas: 7 created + Black Market sell book configured");
    }

    // =============================================================
    //                         SYNC PATH
    // =============================================================

    /**
     * @notice Re-push the canonical ladder onto an already-populated registry.
     * @dev For live correction: createArea would duplicate, so this drives the per-field update
     *      setters instead. All setters are owner-only and non-destructive — they overwrite the
     *      targeted field and leave dealer locations and untouched fields intact. Rewriting a
     *      value that already matches is a harmless no-op write.
     */
    function _syncAreas(IAreaRegistry reg) internal {
        AreaSpec[] memory specs = _areaSpecs();
        for (uint256 i; i < specs.length; ++i) {
            AreaSpec memory s = specs[i];
            reg.updateMovementFee(s.id, s.movementFee);
            reg.updateMinReputation(s.id, s.minReputation);
            reg.batchConfigureAreaDrugs(s.id, s.drugIds, s.buyPrices, s.sellPrices);
        }

        _configureBlackMarket(reg);
        console.log("Areas: ladder re-synced onto live registry");
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

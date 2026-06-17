// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title VerifyConfig - Verify All Contract Configurations
 * @notice Reads and displays the configuration state of all deployed contracts
 * @dev Run without broadcast - this is a read-only script.
 *      Loads addresses from testnet.json via DeployBase.
 *
 * Usage:
 *   source .env && forge script script/verify/VerifyConfig.s.sol:VerifyConfig \
 *       --rpc-url https://api.testnet.abs.xyz \
 *       --skip "RendererSVG" --skip "UploadTraits" --zksync
 */
interface IVerifyCore {
    function drugRegistry() external view returns (address);
    function areaRegistry() external view returns (address);
    function nftContract() external view returns (address);
    function paymentHandler() external view returns (address);
    function authorizedContracts(address) external view returns (bool);
    function owner() external view returns (address);
}

interface IVerifyNFT {
    function dealersCore() external view returns (address);
    function contractRendererSVG() external view returns (address);
    function contractRendererHTML() external view returns (address);
    function owner() external view returns (address);
    function mintOpen() external view returns (bool);
    function totalSupply() external view returns (uint256);
    function MAX_SUPPLY() external view returns (uint256);
}

interface IVerifyDrugRegistry {
    function getTotalDrugs() external view returns (uint256);
    function owner() external view returns (address);
}

interface IVerifyPaymentHandler {
    function authorizedContracts(address) external view returns (bool);
    function devWallet() external view returns (address);
    function bankVault() external view returns (address);
    function owner() external view returns (address);
}

interface IVerifyAreaRegistry {
    function coreContract() external view returns (address);
    function drugRegistry() external view returns (address);
    function getTotalAreas() external view returns (uint8);
    function owner() external view returns (address);
}

interface IVerifyPVP {
    function core() external view returns (address);
    function nftContract() external view returns (address);
    function areaRegistry() external view returns (address);
    function drugRegistry() external view returns (address);
    function randomness() external view returns (address);
    function actions() external view returns (address);
    function owner() external view returns (address);
}

interface IVerifyPVE {
    function dealersCore() external view returns (address);
    function dealersNFT() external view returns (address);
    function areaRegistry() external view returns (address);
    function randomness() external view returns (address);
    function actions() external view returns (address);
    function owner() external view returns (address);
}

interface IVerifyBoosts {
    function dealersCore() external view returns (address);
    function dealersNFT() external view returns (address);
    function paymentHandler() external view returns (address);
    function totalTiers() external view returns (uint256);
    function boostTiers(uint256 tierId)
        external
        view
        returns (
            uint256 price,
            uint64 duration,
            uint8 drugMultiplier,
            uint8 repMultiplier,
            uint8 extraAttempts,
            bool freeAreaMovement,
            uint8 cashMultiplier,
            bool isActive
        );
    function owner() external view returns (address);
}

interface IVerifyActions {
    function paymentHandler() external view returns (address);
    function randomness() external view returns (address);
    function authorizedJailers(address) external view returns (bool);
    function owner() external view returns (address);
}

interface IVerifyClaims {
    function dealersCore() external view returns (address);
    function dealersNFT() external view returns (address);
    function pveContract() external view returns (address);
    function pvpContract() external view returns (address);
    function heistsContract() external view returns (address);
    function nextAchievementId() external view returns (uint256);
    function owner() external view returns (address);
}

interface IVerifyRandomness {
    function isAuthorizedResolver(address) external view returns (bool);
    function owner() external view returns (address);
}

interface IVerifyMulticall {
    function core() external view returns (address);
    function pve() external view returns (address);
    function pvp() external view returns (address);
    function areaRegistry() external view returns (address);
    function drugRegistry() external view returns (address);
    function boosts() external view returns (address);
    function owner() external view returns (address);
}

interface IVerifyHeists {
    function core() external view returns (address);
    function nftContract() external view returns (address);
    function randomness() external view returns (address);
    function paymentHandler() external view returns (address);
    function drugRegistry() external view returns (address);
    function entropy() external view returns (address);
    function actions() external view returns (address);
    function paused() external view returns (bool);
    function backedEth() external view returns (uint256);
    function ethAddOn() external view returns (uint96);
    function jackpotReserve() external view returns (uint256);
    function difficultyConfigs(uint8 difficulty)
        external
        view
        returns (uint256 repGate, uint96 cashEntry, bool active);
    function jackpotConfig(uint256 stage)
        external
        view
        returns (uint16 triggerPct, uint32 minMultBps, uint32 maxMultBps);
    function owner() external view returns (address);
}

interface IVerifyEntropyFee {
    function getFeeV2() external view returns (uint128);
}

interface IVerifyChatFactory {
    function nftContract() external view returns (address);
    function owner() external view returns (address);
}

contract VerifyConfig is DeployBase {
    uint256 public issues;

    function run() external {
        _loadAddresses();

        console.log("");
        console.log("================================================================================");
        console.log("                    DEALERS.SH CONFIGURATION VERIFICATION");
        console.log("================================================================================");
        console.log("");

        _verifyCore();
        _verifyNFT();
        _verifyDrugRegistry();
        _verifyPaymentHandler();
        _verifyAreaRegistry();
        _verifyPVE();
        _verifyPVP();
        _verifyBoosts();
        _verifyActions();
        _verifyClaims();
        _verifyRandomness();
        _verifyMulticall();
        _verifyHeists();
        _verifyChatFactory();

        _printSummary();
    }

    function _verifyCore() internal view {
        console.log("DEALERS_CORE:", core);
        console.log("--------------------------------------------------------------------------------");

        if (core == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyCore c = IVerifyCore(core);

        console.log("  References:");
        _checkRef("    drugRegistry", c.drugRegistry(), drugRegistry);
        _checkRef("    areaRegistry", c.areaRegistry(), areaRegistry);
        _checkRef("    nftContract", c.nftContract(), nft);
        _checkRef("    paymentHandler", c.paymentHandler(), paymentHandler);
        // Note: Core no longer references randomness post commit-reveal migration

        console.log("  Authorizations:");
        _checkAuth("    PVE", c.authorizedContracts(pve), pve);
        _checkAuth("    PVP", c.authorizedContracts(pvp), pvp);
        _checkAuth("    Boosts", c.authorizedContracts(boosts), boosts);
        _checkAuth("    NFT", c.authorizedContracts(nft), nft);
        if (actions != address(0)) _checkAuth("    Actions", c.authorizedContracts(actions), actions);
        if (claims != address(0)) _checkAuth("    Claims", c.authorizedContracts(claims), claims);
        if (heists != address(0)) _checkAuth("    Heists", c.authorizedContracts(heists), heists);

        console.log("  Setup:");
        (bool tiersSet,) = core.staticcall(abi.encodeWithSignature("reputationTiers(uint256)", 0));
        if (tiersSet) {
            console.log("    reputationTiers: configured [OK]");
        } else {
            console.log("    reputationTiers: EMPTY [NEEDS CONFIG] (run SetupTiers)");
        }

        console.log("  Owner:", c.owner());
        console.log("");
    }

    function _verifyNFT() internal view {
        console.log("DEALERS_NFT:", nft);
        console.log("--------------------------------------------------------------------------------");

        if (nft == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyNFT n = IVerifyNFT(nft);

        console.log("  References:");
        _checkRef("    dealersCore", n.dealersCore(), core);
        _checkRenderer("    rendererSvg", n.contractRendererSVG(), rendererSvg);
        _checkRenderer("    rendererHtml", n.contractRendererHTML(), rendererHtml);

        console.log("  Status:");
        console.log("    mintOpen:", n.mintOpen());
        console.log("    totalSupply:", n.totalSupply());
        console.log("    maxSupply:", n.MAX_SUPPLY());

        console.log("  Owner:", n.owner());
        console.log("");
    }

    function _verifyDrugRegistry() internal view {
        console.log("DRUG_REGISTRY:", drugRegistry);
        console.log("--------------------------------------------------------------------------------");

        if (drugRegistry == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyDrugRegistry dr = IVerifyDrugRegistry(drugRegistry);

        console.log("  Status:");
        uint256 totalDrugs = dr.getTotalDrugs();
        console.log("    totalDrugs:", totalDrugs);
        if (totalDrugs == 0) console.log("    drugs: EMPTY [NEEDS CONFIG] (run SetupDrugs)");

        console.log("  Owner:", dr.owner());
        console.log("");
    }

    function _verifyPaymentHandler() internal view {
        console.log("PAYMENT_HANDLER:", paymentHandler);
        console.log("--------------------------------------------------------------------------------");

        if (paymentHandler == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyPaymentHandler ph = IVerifyPaymentHandler(paymentHandler);

        console.log("  Config:");
        _checkRef("    devWallet", ph.devWallet(), devWallet);
        _checkRef("    bankVault", ph.bankVault(), bankVault);

        console.log("  Authorizations:");
        _checkAuth("    Core", ph.authorizedContracts(core), core);
        _checkAuth("    Boosts", ph.authorizedContracts(boosts), boosts);
        if (actions != address(0)) _checkAuth("    Actions", ph.authorizedContracts(actions), actions);
        if (heists != address(0)) _checkAuth("    Heists", ph.authorizedContracts(heists), heists);

        console.log("  Owner:", ph.owner());
        console.log("");
    }

    function _verifyAreaRegistry() internal view {
        console.log("AREA_REGISTRY:", areaRegistry);
        console.log("--------------------------------------------------------------------------------");

        if (areaRegistry == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyAreaRegistry ar = IVerifyAreaRegistry(areaRegistry);

        console.log("  References:");
        _checkRef("    coreContract", ar.coreContract(), core);
        _checkRef("    drugRegistry", ar.drugRegistry(), drugRegistry);

        console.log("  Status:");
        uint8 totalAreas = ar.getTotalAreas();
        console.log("    totalAreas:", totalAreas);
        if (totalAreas == 0) console.log("    areas: EMPTY [NEEDS CONFIG] (run SetupAreas)");

        console.log("  Owner:", ar.owner());
        console.log("");
    }

    function _verifyPVE() internal view {
        console.log("DEALERS_PVE:", pve);
        console.log("--------------------------------------------------------------------------------");

        if (pve == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyPVE p = IVerifyPVE(pve);

        console.log("  References:");
        _checkRef("    dealersCore", p.dealersCore(), core);
        _checkRef("    dealersNFT", p.dealersNFT(), nft);
        _checkRef("    areaRegistry", p.areaRegistry(), areaRegistry);
        _checkRef("    randomness", p.randomness(), randomness);
        _checkRef("    actions", p.actions(), actions);

        console.log("  Owner:", p.owner());
        console.log("");
    }

    function _verifyPVP() internal view {
        console.log("DEALERS_PVP:", pvp);
        console.log("--------------------------------------------------------------------------------");

        if (pvp == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyPVP p = IVerifyPVP(pvp);

        console.log("  References:");
        _checkRef("    core", p.core(), core);
        _checkRef("    nftContract", p.nftContract(), nft);
        _checkRef("    areaRegistry", p.areaRegistry(), areaRegistry);
        _checkRef("    drugRegistry", p.drugRegistry(), drugRegistry);
        _checkRef("    randomness", p.randomness(), randomness);
        _checkRef("    actions", p.actions(), actions);

        console.log("  Owner:", p.owner());
        console.log("");
    }

    function _verifyBoosts() internal view {
        console.log("DEALERS_BOOSTS:", boosts);
        console.log("--------------------------------------------------------------------------------");

        if (boosts == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyBoosts b = IVerifyBoosts(boosts);

        console.log("  References:");
        _checkRef("    dealersCore", b.dealersCore(), core);
        _checkRef("    dealersNFT", b.dealersNFT(), nft);
        _checkRef("    paymentHandler", b.paymentHandler(), paymentHandler);

        console.log("  Setup:");
        uint256 totalTiers = b.totalTiers();
        uint256 activeTiers;
        bool unpricedActiveTier;
        for (uint256 i = 1; i <= totalTiers; i++) {
            (uint256 price,,,,,,, bool isActive) = b.boostTiers(i);
            if (isActive) {
                activeTiers++;
                if (price == 0) unpricedActiveTier = true;
            }
        }
        console.log("    totalTiers:", totalTiers);
        console.log("    activeTiers:", activeTiers);
        if (activeTiers == 0) console.log("    tiers: NONE ACTIVE [NEEDS CONFIG] (run SetupBoosts)");
        if (unpricedActiveTier) console.log("    tiers: ACTIVE TIER WITH ZERO PRICE [MISMATCH]");

        console.log("  Owner:", b.owner());
        console.log("");
    }

    function _verifyActions() internal view {
        console.log("DEALERS_ACTIONS:", actions);
        console.log("--------------------------------------------------------------------------------");

        if (actions == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyActions a = IVerifyActions(actions);

        console.log("  References:");
        _checkRef("    paymentHandler", a.paymentHandler(), paymentHandler);
        _checkRef("    randomness", a.randomness(), randomness);

        console.log("  Jailer Authorizations:");
        if (pve != address(0)) _checkAuth("    PVE", a.authorizedJailers(pve), pve);
        if (pvp != address(0)) _checkAuth("    PVP", a.authorizedJailers(pvp), pvp);
        if (heists != address(0)) _checkAuth("    Heists", a.authorizedJailers(heists), heists);

        console.log("  Owner:", a.owner());
        console.log("");
    }

    function _verifyClaims() internal view {
        console.log("DEALERS_CLAIMS:", claims);
        console.log("--------------------------------------------------------------------------------");

        if (claims == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyClaims c = IVerifyClaims(claims);

        console.log("  References:");
        _checkRef("    dealersCore", c.dealersCore(), core);
        _checkRef("    dealersNFT", c.dealersNFT(), nft);
        _checkRef("    pveContract", c.pveContract(), pve);
        _checkRef("    pvpContract", c.pvpContract(), pvp);
        // Tolerant call: pre-heists Claims deployments lack this getter; flag instead of reverting the report.
        try c.heistsContract() returns (address h) {
            _checkRef("    heistsContract", h, heists);
        } catch {
            console.log("    heistsContract: GETTER MISSING [OUTDATED DEPLOYMENT]");
        }

        console.log("  Setup:");
        uint256 achievementCount = c.nextAchievementId();
        console.log("    achievements:", achievementCount);
        if (achievementCount == 0) console.log("    achievements: EMPTY [NEEDS CONFIG] (run SetupClaims)");

        console.log("  Owner:", c.owner());
        console.log("");
    }

    function _verifyRandomness() internal view {
        console.log("RANDOMNESS:", randomness);
        console.log("--------------------------------------------------------------------------------");

        if (randomness == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyRandomness r = IVerifyRandomness(randomness);

        console.log("  Authorizations (Core no longer consumes randomness post-migration):");
        _checkAuth("    PVE", r.isAuthorizedResolver(pve), pve);
        _checkAuth("    PVP", r.isAuthorizedResolver(pvp), pvp);
        if (actions != address(0)) _checkAuth("    Actions", r.isAuthorizedResolver(actions), actions);
        if (heists != address(0)) _checkAuth("    Heists", r.isAuthorizedResolver(heists), heists);

        console.log("  Owner:", r.owner());
        console.log("");
    }

    function _verifyMulticall() internal view {
        console.log("DEALER_MULTICALL:", multicall);
        console.log("--------------------------------------------------------------------------------");

        if (multicall == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyMulticall m = IVerifyMulticall(multicall);

        console.log("  References:");
        _checkRef("    core", m.core(), core);
        _checkRef("    pve", m.pve(), pve);
        _checkRef("    pvp", m.pvp(), pvp);
        _checkRef("    areaRegistry", m.areaRegistry(), areaRegistry);
        _checkRef("    drugRegistry", m.drugRegistry(), drugRegistry);
        _checkRef("    boosts", m.boosts(), boosts);

        console.log("  Owner:", m.owner());
        console.log("");
    }

    function _verifyHeists() internal view {
        console.log("DEALERS_HEISTS:", heists);
        console.log("--------------------------------------------------------------------------------");

        if (heists == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyHeists h = IVerifyHeists(heists);

        console.log("  References:");
        _checkRef("    core", h.core(), core);
        _checkRef("    nftContract", h.nftContract(), nft);
        _checkRef("    randomness", h.randomness(), randomness);
        _checkRef("    paymentHandler", h.paymentHandler(), paymentHandler);
        _checkRef("    drugRegistry", h.drugRegistry(), drugRegistry);
        _checkRef("    actions", h.actions(), actions);
        _checkRef("    entropy", h.entropy(), _envEntropyTolerant());

        console.log("  Setup:");
        uint256 activeDifficulties;
        for (uint8 i = 0; i < 3; i++) {
            (,, bool active) = h.difficultyConfigs(i);
            if (active) activeDifficulties++;
        }
        console.log("    activeDifficulties:", activeDifficulties);
        if (activeDifficulties == 0) console.log("    difficulties: NONE ACTIVE [NEEDS CONFIG] (run SetupHeists)");

        console.log("  Status:");
        console.log("    paused:", h.paused());
        uint256 backed = h.backedEth();
        console.log("    backedEth:", backed);
        console.log("    balance:", heists.balance);
        if (heists.balance < backed) {
            console.log("    SOLVENCY [MISMATCH] balance below backedEth");
        } else {
            console.log("    solvency [OK]");
        }
        _checkJackpotReadiness(h);

        console.log("  Owner:", h.owner());
        console.log("");
    }

    /**
     * @dev A jackpot only fires when the free reserve covers the stage's max payout plus the Pyth
     *      fee (_fireJackpot skips otherwise) — so an unfunded reserve means add-on buyers silently
     *      never roll. Checks the reserve against the most expensive stage.
     */
    function _checkJackpotReadiness(IVerifyHeists h) internal view {
        uint32 maxMultBps;
        for (uint256 i = 0; i < 5; i++) {
            (,, uint32 stageMax) = h.jackpotConfig(i);
            if (stageMax > maxMultBps) maxMultBps = stageMax;
        }
        uint256 maxJackpot = (uint256(h.ethAddOn()) * maxMultBps) / 10000;

        uint256 pythFee;
        try IVerifyEntropyFee(h.entropy()).getFeeV2() returns (uint128 fee) {
            pythFee = fee;
        } catch {
            console.log("    pythFee: UNREADABLE [MISMATCH] (entropy address wrong?)");
        }

        uint256 reserve = h.jackpotReserve();
        console.log("    jackpotReserve:", reserve);
        console.log("    maxJackpot+fee:", maxJackpot + pythFee);
        if (reserve < maxJackpot + pythFee) {
            console.log("    jackpot funding: RESERVE TOO LOW [NEEDS CONFIG] (jackpots will skip; fundReserve)");
        } else {
            console.log("    jackpot funding [OK]");
        }
    }

    /**
     * @dev Env lookup mirroring _envAddrForNetwork but tolerant of unset vars — a verify
     *      script should report "(expected not set)", never revert.
     */
    function _envEntropyTolerant() internal view returns (address) {
        if (block.chainid == 2741) return vm.envOr("MAINNET_PYTH_ENTROPY", address(0));
        return vm.envOr("TESTNET_PYTH_ENTROPY", vm.envOr("PYTH_ENTROPY", address(0)));
    }

    function _verifyChatFactory() internal view {
        console.log("CHAT_FACTORY:", chatFactory);
        console.log("--------------------------------------------------------------------------------");

        if (chatFactory == address(0)) {
            console.log("  [SKIP] Address not set in environment");
            console.log("");
            return;
        }

        IVerifyChatFactory cf = IVerifyChatFactory(chatFactory);

        console.log("  References:");
        _checkRef("    nftContract", cf.nftContract(), nft);

        console.log("  Owner:", cf.owner());
        console.log("");
    }

    function _checkRef(string memory label, address actual, address expected) internal pure {
        if (expected == address(0)) {
            console.log(label, actual, "(expected not set)");
        } else if (actual == expected) {
            console.log(label, actual, "[OK]");
        } else {
            console.log(label, actual, "[MISMATCH]");
            console.log("      expected:", expected);
        }
    }

    function _checkRenderer(string memory label, address actual, address expected) internal pure {
        if (actual == address(0)) {
            console.log(label, "NOT SET [NEEDS CONFIG]");
        } else if (expected == address(0)) {
            console.log(label, actual, "(env not set)");
        } else if (actual == expected) {
            console.log(label, actual, "[OK]");
        } else {
            console.log(label, actual, "[MISMATCH]");
            console.log("      expected:", expected);
        }
    }

    function _checkAuth(string memory label, bool authorized, address addr) internal pure {
        if (addr == address(0)) {
            console.log(label, "N/A (address not set)");
        } else if (authorized) {
            console.log(label, "AUTHORIZED [OK]");
        } else {
            console.log(label, "NOT AUTHORIZED [NEEDS CONFIG]");
        }
    }

    function _printSummary() internal pure {
        console.log("================================================================================");
        console.log("  Review any [MISMATCH] or [NEEDS CONFIG] items above");
        console.log("================================================================================");
        console.log("");
    }
}

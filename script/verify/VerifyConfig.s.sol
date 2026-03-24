// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title VerifyConfig - Verify All Contract Configurations
 * @notice Reads and displays the configuration state of all deployed contracts
 * @dev Run without broadcast - this is a read-only script.
 *      Loads addresses from testnet.json via DeployBase.
 *
 * Usage:
 *   forge script script/verify/VerifyConfig.s.sol:VerifyConfig \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 */

interface IVerifyCore {
    function drugRegistry() external view returns (address);
    function areaRegistry() external view returns (address);
    function nftContract() external view returns (address);
    function paymentHandler() external view returns (address);
    function randomness() external view returns (address);
    function authorizedContracts(address) external view returns (bool);
    function owner() external view returns (address);
}

interface IVerifyNFT {
    function dealersExeCore() external view returns (address);
    function contractRendererSVG() external view returns (address);
    function contractRendererHTML() external view returns (address);
    function owner() external view returns (address);
    function mintStatus() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function MAX_SUPPLY() external view returns (uint256);
}

interface IVerifyDrugRegistry {
    function authorizedContracts(address) external view returns (bool);
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
    function owner() external view returns (address);
}

interface IVerifyPVP {
    function core() external view returns (address);
    function nftContract() external view returns (address);
    function areaRegistry() external view returns (address);
    function drugRegistry() external view returns (address);
    function randomness() external view returns (address);
    function owner() external view returns (address);
}

interface IVerifyPVE {
    function dealersExeCore() external view returns (address);
    function dealersExeNFT() external view returns (address);
    function areaRegistry() external view returns (address);
    function randomness() external view returns (address);
    function owner() external view returns (address);
}

interface IVerifyBoosts {
    function dealersExeCore() external view returns (address);
    function dealersExeNFT() external view returns (address);
    function paymentHandler() external view returns (address);
    function owner() external view returns (address);
}

interface IVerifyActions {
    function paymentHandler() external view returns (address);
    function randomness() external view returns (address);
    function owner() external view returns (address);
}

contract VerifyConfig is DeployBase {
    uint256 public issues;

    function run() external {
        _loadAddresses();

        console.log("");
        console.log("================================================================================");
        console.log("                    DEALERS.EXE CONFIGURATION VERIFICATION");
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
        _checkRef("    randomness", c.randomness(), randomness);

        console.log("  Authorizations:");
        _checkAuth("    PVE", c.authorizedContracts(pve), pve);
        _checkAuth("    PVP", c.authorizedContracts(pvp), pvp);
        _checkAuth("    Boosts", c.authorizedContracts(boosts), boosts);
        _checkAuth("    NFT", c.authorizedContracts(nft), nft);
        if (actions != address(0)) _checkAuth("    Actions", c.authorizedContracts(actions), actions);

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
        _checkRef("    dealersExeCore", n.dealersExeCore(), core);
        _checkRenderer("    rendererSvg", n.contractRendererSVG(), rendererSvg);
        _checkRenderer("    rendererHtml", n.contractRendererHTML(), rendererHtml);

        console.log("  Status:");
        console.log("    mintStatus:", _mintStatusString(n.mintStatus()));
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

        console.log("  Authorizations:");
        _checkAuth("    Core", dr.authorizedContracts(core), core);

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
        console.log("    devWallet:", ph.devWallet());
        console.log("    bankVault:", ph.bankVault());

        console.log("  Authorizations:");
        _checkAuth("    Core", ph.authorizedContracts(core), core);
        _checkAuth("    Boosts", ph.authorizedContracts(boosts), boosts);
        if (actions != address(0)) _checkAuth("    Actions", ph.authorizedContracts(actions), actions);

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
        _checkRef("    dealersExeCore", p.dealersExeCore(), core);
        _checkRef("    dealersExeNFT", p.dealersExeNFT(), nft);
        _checkRef("    areaRegistry", p.areaRegistry(), areaRegistry);
        _checkRef("    randomness", p.randomness(), randomness);

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
        _checkRef("    dealersExeCore", b.dealersExeCore(), core);
        _checkRef("    dealersExeNFT", b.dealersExeNFT(), nft);
        _checkRef("    paymentHandler", b.paymentHandler(), paymentHandler);

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

        console.log("  Owner:", a.owner());
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

    function _mintStatusString(uint8 status) internal pure returns (string memory) {
        if (status == 0) return "DISABLED";
        if (status == 1) return "FAMILY";
        if (status == 2) return "WHITELIST";
        if (status == 3) return "PUBLIC";
        return "UNKNOWN";
    }

    function _printSummary() internal pure {
        console.log("================================================================================");
        console.log("  Review any [MISMATCH] or [NEEDS CONFIG] items above");
        console.log("================================================================================");
        console.log("");
    }
}

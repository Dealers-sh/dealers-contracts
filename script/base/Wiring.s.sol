// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./DeployBase.s.sol";

/**
 * @title WiringBase - Single source of truth for the cross-contract wiring graph
 *
 * @dev One `_wireX()` per contract, covering EVERY edge that touches X — inbound references,
 *      outbound references, and authorizations. All edges are idempotent (state is read before
 *      each setter), and edges to contracts that are not deployed (address(0) in the deployments
 *      JSON) are skipped silently.
 *
 *      Consumers:
 *        - Deploy<X>.s.sol calls `_wireX()` right after deploying X — the smallest tx set that
 *          fully integrates the new instance, and nothing else is touched.
 *        - SetupWiring.s.sol calls every `_wireX()` — the global drift check / re-assert tool.
 *
 *      Contracts whose Core reference is constructor-only (DealersActions, DealersAreaChatGate)
 *      cannot be re-wired here; a Core redeploy forces their redeploy. DeployCore prints this.
 * @author Berny0x
 */

// =============================================================================
//                       WIRING-ONLY INTERFACE VIEWS
// =============================================================================

interface IHeistsWire {
    function core() external view returns (address);
    function nftContract() external view returns (address);
    function randomness() external view returns (address);
    function paymentHandler() external view returns (address);
    function drugRegistry() external view returns (address);
    function actions() external view returns (address);
    function setActions(address _actions) external;
    function setContracts(
        address _core,
        address _nftContract,
        address _randomness,
        address _paymentHandler,
        address _drugRegistry,
        address _entropy
    ) external;
}

interface IBankHeistWire {
    function core() external view returns (address);
    function nftContract() external view returns (address);
    function pve() external view returns (address);
    function pvp() external view returns (address);
    function heists() external view returns (address);
    function setContracts(address _core, address _nftContract, address _pve, address _pvp, address _heists) external;
}

interface IPaymentVault {
    function bankVault() external view returns (address);
    function setBankVault(address _bankVault) external;
}

interface INFTRendererWire {
    function contractRendererSVG() external view returns (address);
    function contractRendererHTML() external view returns (address);
    function setContractRendererSVG(address newAddress) external;
    function setContractRendererHTML(address newAddress) external;
}

abstract contract WiringBase is DeployBase {
    // =========================================================================
    //                          EDGE PRIMITIVES
    // =========================================================================

    /** @dev Set `target` via `setter` when it differs from `current`; skip when target is undeployed. */
    function _set(address current, address target, string memory label, function(address) external setter) internal {
        if (target == address(0)) return;
        if (current != target) {
            setter(target);
            console.log(string.concat("  ", label, ": SET"));
        } else {
            console.log(string.concat("  ", label, ": ok"));
        }
    }

    function _authCore(address module, string memory label) internal {
        if (module == address(0) || core == address(0)) return;
        IDealersCore c = IDealersCore(core);
        if (!c.authorizedContracts(module)) {
            c.authorizeContract(module, true);
            console.log(string.concat("  ", label, ": AUTHORIZED"));
        } else {
            console.log(string.concat("  ", label, ": ok"));
        }
    }

    function _authPayment(address module, string memory label) internal {
        if (module == address(0) || paymentHandler == address(0)) return;
        IPaymentHandler ph = IPaymentHandler(paymentHandler);
        if (!ph.authorizedContracts(module)) {
            ph.authorizeContract(module, true);
            console.log(string.concat("  ", label, ": AUTHORIZED"));
        } else {
            console.log(string.concat("  ", label, ": ok"));
        }
    }

    function _authResolver(address module, string memory label) internal {
        if (module == address(0) || randomness == address(0)) return;
        IRandomness rng = IRandomness(randomness);
        if (!rng.isAuthorizedResolver(module)) {
            rng.authorizeResolver(module, true);
            console.log(string.concat("  ", label, ": AUTHORIZED"));
        } else {
            console.log(string.concat("  ", label, ": ok"));
        }
    }

    function _authJailer(address module, string memory label) internal {
        if (module == address(0) || actions == address(0)) return;
        IActionsContract a = IActionsContract(actions);
        if (!a.authorizedJailers(module)) {
            a.authorizeJailer(module, true);
            console.log(string.concat("  ", label, ": AUTHORIZED"));
        } else {
            console.log(string.concat("  ", label, ": ok"));
        }
    }

    /** @dev Returns `target` when a sync is needed, address(0) when current already matches or target is undeployed. */
    function _differs(address current, address target) internal pure returns (address) {
        return (target != address(0) && current != target) ? target : address(0);
    }

    /** @dev Batch-repoint Heists at the current core/nft/randomness/paymentHandler/drugRegistry set. */
    function _syncHeistsRefs() internal {
        if (heists == address(0)) return;
        IHeistsWire h = IHeistsWire(heists);
        address dCore = _differs(h.core(), core);
        address dNft = _differs(h.nftContract(), nft);
        address dRnd = _differs(h.randomness(), randomness);
        address dPay = _differs(h.paymentHandler(), paymentHandler);
        address dDrug = _differs(h.drugRegistry(), drugRegistry);
        if (
            dCore == address(0) && dNft == address(0) && dRnd == address(0) && dPay == address(0)
                && dDrug == address(0)
        ) {
            console.log("  Heists refs: ok");
            return;
        }
        h.setContracts(dCore, dNft, dRnd, dPay, dDrug, address(0));
        console.log("  Heists refs: SYNCED");
    }

    /** @dev Batch-repoint BankHeist; its setContracts reverts mid-season, so a skip is reported, not fatal. */
    function _syncBankHeistRefs() internal {
        if (bankHeist == address(0)) return;
        IBankHeistWire b = IBankHeistWire(bankHeist);
        address dCore = _differs(b.core(), core);
        address dNft = _differs(b.nftContract(), nft);
        address dPve = _differs(b.pve(), pve);
        address dPvp = _differs(b.pvp(), pvp);
        address dHeists = _differs(b.heists(), heists);
        if (
            dCore == address(0) && dNft == address(0) && dPve == address(0) && dPvp == address(0)
                && dHeists == address(0)
        ) {
            console.log("  BankHeist refs: ok");
            return;
        }
        try b.setContracts(dCore, dNft, dPve, dPvp, dHeists) {
            console.log("  BankHeist refs: SYNCED");
        } catch {
            console.log("  BankHeist refs: SKIPPED (season in flight - settle/cancel it, then re-run SetupWiring)");
        }
    }

    // =========================================================================
    //                       PER-CONTRACT WIRE SETS
    // =========================================================================

    function _wireDrugRegistry() internal {
        if (drugRegistry == address(0)) return;
        console.log("Wiring DrugRegistry:");
        if (core != address(0)) {
            IDealersCore c = IDealersCore(core);
            _set(c.drugRegistry(), drugRegistry, "Core -> DrugRegistry", c.setDrugRegistry);
        }
        if (areaRegistry != address(0)) {
            IAreaRegistry ar = IAreaRegistry(areaRegistry);
            _set(ar.drugRegistry(), drugRegistry, "AreaRegistry -> DrugRegistry", ar.setDrugRegistry);
        }
        if (pvp != address(0)) {
            IPVPContract p = IPVPContract(pvp);
            _set(p.drugRegistry(), drugRegistry, "PVP -> DrugRegistry", p.setDrugRegistry);
        }
        if (multicall != address(0)) {
            IMulticallContract mc = IMulticallContract(multicall);
            _set(mc.drugRegistry(), drugRegistry, "Multicall -> DrugRegistry", mc.setDrugRegistry);
        }
        _syncHeistsRefs();
        console.log("");
    }

    function _wireAreaRegistry() internal {
        if (areaRegistry == address(0)) return;
        console.log("Wiring AreaRegistry:");
        IAreaRegistry ar = IAreaRegistry(areaRegistry);
        _set(ar.coreContract(), core, "AreaRegistry -> Core", ar.setCoreContract);
        _set(ar.drugRegistry(), drugRegistry, "AreaRegistry -> DrugRegistry", ar.setDrugRegistry);
        if (core != address(0)) {
            IDealersCore c = IDealersCore(core);
            _set(c.areaRegistry(), areaRegistry, "Core -> AreaRegistry", c.setAreaRegistry);
        }
        if (pve != address(0)) {
            IPVEContract p = IPVEContract(pve);
            _set(p.areaRegistry(), areaRegistry, "PVE -> AreaRegistry", p.setAreaRegistry);
        }
        if (pvp != address(0)) {
            IPVPContract p = IPVPContract(pvp);
            _set(p.areaRegistry(), areaRegistry, "PVP -> AreaRegistry", p.setAreaRegistry);
        }
        if (actions != address(0)) {
            IActionsContract a = IActionsContract(actions);
            _set(a.areaRegistry(), areaRegistry, "Actions -> AreaRegistry", a.setAreaRegistry);
        }
        if (multicall != address(0)) {
            IMulticallContract mc = IMulticallContract(multicall);
            _set(mc.areaRegistry(), areaRegistry, "Multicall -> AreaRegistry", mc.setAreaRegistry);
        }
        console.log("");
    }

    function _wireCore() internal {
        if (core == address(0)) return;
        console.log("Wiring Core:");
        IDealersCore c = IDealersCore(core);

        _set(c.drugRegistry(), drugRegistry, "Core -> DrugRegistry", c.setDrugRegistry);
        _set(c.areaRegistry(), areaRegistry, "Core -> AreaRegistry", c.setAreaRegistry);
        _set(c.nftContract(), nft, "Core -> NFT", c.setNFTContract);
        _set(c.paymentHandler(), paymentHandler, "Core -> PaymentHandler", c.setPaymentHandler);

        _authCore(pve, "Core auth PVE");
        _authCore(pvp, "Core auth PVP");
        _authCore(boosts, "Core auth Boosts");
        _authCore(nft, "Core auth NFT");
        _authCore(claims, "Core auth Claims");
        _authCore(actions, "Core auth Actions");
        _authCore(heists, "Core auth Heists");
        _authCore(bankHeist, "Core auth BankHeist");

        _authPayment(core, "PaymentHandler auth Core");

        if (areaRegistry != address(0)) {
            IAreaRegistry ar = IAreaRegistry(areaRegistry);
            _set(ar.coreContract(), core, "AreaRegistry -> Core", ar.setCoreContract);
        }
        if (nft != address(0)) {
            IDealersNFT n = IDealersNFT(nft);
            _set(n.dealersCore(), core, "NFT -> Core", n.setDealersCore);
        }
        if (boosts != address(0)) {
            IBoostsContract b = IBoostsContract(boosts);
            _set(b.dealersCore(), core, "Boosts -> Core", b.setDealersCore);
        }
        if (pve != address(0)) {
            IPVEContract p = IPVEContract(pve);
            _set(p.dealersCore(), core, "PVE -> Core", p.setDealersCore);
        }
        if (pvp != address(0)) {
            IPVPContract p = IPVPContract(pvp);
            _set(p.core(), core, "PVP -> Core", p.setCore);
        }
        if (claims != address(0)) {
            IClaimsContract cl = IClaimsContract(claims);
            _set(cl.dealersCore(), core, "Claims -> Core", cl.setDealersCore);
        }
        if (multicall != address(0)) {
            IMulticallContract mc = IMulticallContract(multicall);
            _set(mc.core(), core, "Multicall -> Core", mc.setCore);
        }
        _syncHeistsRefs();
        _syncBankHeistRefs();
        console.log("");
    }

    function _wirePaymentHandler() internal {
        if (paymentHandler == address(0)) return;
        console.log("Wiring PaymentHandler:");

        _authPayment(core, "PaymentHandler auth Core");
        _authPayment(boosts, "PaymentHandler auth Boosts");
        _authPayment(actions, "PaymentHandler auth Actions");
        _authPayment(heists, "PaymentHandler auth Heists");

        if (core != address(0)) {
            IDealersCore c = IDealersCore(core);
            _set(c.paymentHandler(), paymentHandler, "Core -> PaymentHandler", c.setPaymentHandler);
        }
        if (boosts != address(0)) {
            IBoostsContract b = IBoostsContract(boosts);
            _set(b.paymentHandler(), paymentHandler, "Boosts -> PaymentHandler", b.setPaymentHandler);
        }
        if (actions != address(0)) {
            IActionsContract a = IActionsContract(actions);
            _set(a.paymentHandler(), paymentHandler, "Actions -> PaymentHandler", a.setPaymentHandler);
        }
        _syncHeistsRefs();

        if (bankHeist != address(0) && IPaymentVault(paymentHandler).bankVault() != bankHeist) {
            console.log("  WARNING: bankVault does not point at the BankHeist event vault.");
            console.log("    Intentional only if the event is over; otherwise: setBankVault(bankHeist).");
        }
        console.log("");
    }

    function _wireRandomness() internal {
        if (randomness == address(0)) return;
        console.log("Wiring Randomness:");

        _authResolver(pve, "Randomness auth PVE");
        _authResolver(pvp, "Randomness auth PVP");
        _authResolver(actions, "Randomness auth Actions");
        _authResolver(heists, "Randomness auth Heists");

        if (pve != address(0)) {
            IPVEContract p = IPVEContract(pve);
            _set(p.randomness(), randomness, "PVE -> Randomness", p.setRandomness);
        }
        if (pvp != address(0)) {
            IPVPContract p = IPVPContract(pvp);
            _set(p.randomness(), randomness, "PVP -> Randomness", p.setRandomness);
        }
        if (actions != address(0)) {
            IActionsContract a = IActionsContract(actions);
            _set(a.randomness(), randomness, "Actions -> Randomness", a.setRandomness);
        }
        _syncHeistsRefs();
        console.log("");
    }

    function _wireNFT() internal {
        if (nft == address(0)) return;
        console.log("Wiring NFT:");

        if (core != address(0)) {
            IDealersCore c = IDealersCore(core);
            _set(c.nftContract(), nft, "Core -> NFT", c.setNFTContract);
        }
        _authCore(nft, "Core auth NFT");

        IDealersNFT n = IDealersNFT(nft);
        _set(n.dealersCore(), core, "NFT -> Core", n.setDealersCore);

        INFTRendererWire nr = INFTRendererWire(nft);
        _set(nr.contractRendererSVG(), rendererSvg, "NFT -> RendererSVG", nr.setContractRendererSVG);
        _set(nr.contractRendererHTML(), rendererHtml, "NFT -> RendererHTML", nr.setContractRendererHTML);

        if (boosts != address(0)) {
            IBoostsContract b = IBoostsContract(boosts);
            _set(b.dealersNFT(), nft, "Boosts -> NFT", b.setDealersNFT);
        }
        if (pve != address(0)) {
            IPVEContract p = IPVEContract(pve);
            _set(p.dealersNFT(), nft, "PVE -> NFT", p.setDealersNFT);
        }
        if (pvp != address(0)) {
            IPVPContract p = IPVPContract(pvp);
            _set(p.nftContract(), nft, "PVP -> NFT", p.setNFTContract);
        }
        if (claims != address(0)) {
            IClaimsContract cl = IClaimsContract(claims);
            _set(cl.dealersNFT(), nft, "Claims -> NFT", cl.setDealersNFT);
        }
        if (actions != address(0)) {
            IActionsContract a = IActionsContract(actions);
            _set(a.nftContract(), nft, "Actions -> NFT", a.setNFTContract);
        }
        if (chatFactory != address(0)) {
            IChatFactory cf = IChatFactory(chatFactory);
            _set(cf.nftContract(), nft, "ChatFactory -> NFT", cf.setNFTContract);
        }
        _syncHeistsRefs();
        _syncBankHeistRefs();

        if (rendererSvg != address(0)) {
            console.log("  NOTE: RendererSVG.setDealersNFT is EVM-mode; if the NFT address changed run:");
            console.log(string.concat("    cast send ", vm.toString(rendererSvg), " \"setDealersNFT(address)\""));
        }
        console.log("");
    }

    function _wireBoosts() internal {
        if (boosts == address(0)) return;
        console.log("Wiring Boosts:");

        _authCore(boosts, "Core auth Boosts");
        _authPayment(boosts, "PaymentHandler auth Boosts");

        IBoostsContract b = IBoostsContract(boosts);
        _set(b.dealersCore(), core, "Boosts -> Core", b.setDealersCore);
        _set(b.dealersNFT(), nft, "Boosts -> NFT", b.setDealersNFT);
        _set(b.paymentHandler(), paymentHandler, "Boosts -> PaymentHandler", b.setPaymentHandler);

        if (multicall != address(0)) {
            IMulticallContract mc = IMulticallContract(multicall);
            _set(mc.boosts(), boosts, "Multicall -> Boosts", mc.setBoosts);
        }
        console.log("");
    }

    function _wirePVE() internal {
        if (pve == address(0)) return;
        console.log("Wiring PVE:");

        _authCore(pve, "Core auth PVE");
        _authResolver(pve, "Randomness auth PVE");
        _authJailer(pve, "Actions.jailer auth PVE");

        IPVEContract p = IPVEContract(pve);
        _set(p.dealersCore(), core, "PVE -> Core", p.setDealersCore);
        _set(p.dealersNFT(), nft, "PVE -> NFT", p.setDealersNFT);
        _set(p.areaRegistry(), areaRegistry, "PVE -> AreaRegistry", p.setAreaRegistry);
        _set(p.randomness(), randomness, "PVE -> Randomness", p.setRandomness);
        _set(p.actions(), actions, "PVE -> Actions", p.setActions);

        if (claims != address(0)) {
            IClaimsContract cl = IClaimsContract(claims);
            _set(cl.pveContract(), pve, "Claims -> PVE", cl.setPVE);
        }
        if (multicall != address(0)) {
            IMulticallContract mc = IMulticallContract(multicall);
            _set(mc.pve(), pve, "Multicall -> PVE", mc.setPVE);
        }
        _syncBankHeistRefs();
        console.log("");
    }

    function _wirePVP() internal {
        if (pvp == address(0)) return;
        console.log("Wiring PVP:");

        _authCore(pvp, "Core auth PVP");
        _authResolver(pvp, "Randomness auth PVP");
        _authJailer(pvp, "Actions.jailer auth PVP");

        IPVPContract p = IPVPContract(pvp);
        _set(p.core(), core, "PVP -> Core", p.setCore);
        _set(p.nftContract(), nft, "PVP -> NFT", p.setNFTContract);
        _set(p.areaRegistry(), areaRegistry, "PVP -> AreaRegistry", p.setAreaRegistry);
        _set(p.drugRegistry(), drugRegistry, "PVP -> DrugRegistry", p.setDrugRegistry);
        _set(p.randomness(), randomness, "PVP -> Randomness", p.setRandomness);
        _set(p.actions(), actions, "PVP -> Actions", p.setActions);

        if (claims != address(0)) {
            IClaimsContract cl = IClaimsContract(claims);
            _set(cl.pvpContract(), pvp, "Claims -> PVP", cl.setPVP);
        }
        if (multicall != address(0)) {
            IMulticallContract mc = IMulticallContract(multicall);
            _set(mc.pvp(), pvp, "Multicall -> PVP", mc.setPVP);
        }
        _syncBankHeistRefs();
        console.log("");
    }

    function _wireClaims() internal {
        if (claims == address(0)) return;
        console.log("Wiring Claims:");

        _authCore(claims, "Core auth Claims");

        IClaimsContract cl = IClaimsContract(claims);
        _set(cl.dealersCore(), core, "Claims -> Core", cl.setDealersCore);
        _set(cl.dealersNFT(), nft, "Claims -> NFT", cl.setDealersNFT);
        _set(cl.pveContract(), pve, "Claims -> PVE", cl.setPVE);
        _set(cl.pvpContract(), pvp, "Claims -> PVP", cl.setPVP);
        _set(cl.heistsContract(), heists, "Claims -> Heists", cl.setHeists);
        console.log("");
    }

    function _wireActions() internal {
        if (actions == address(0)) return;
        console.log("Wiring Actions:");

        _authCore(actions, "Core auth Actions");
        _authPayment(actions, "PaymentHandler auth Actions");
        _authResolver(actions, "Randomness auth Actions");

        IActionsContract a = IActionsContract(actions);
        _set(a.paymentHandler(), paymentHandler, "Actions -> PaymentHandler", a.setPaymentHandler);
        _set(a.randomness(), randomness, "Actions -> Randomness", a.setRandomness);
        _set(a.nftContract(), nft, "Actions -> NFT", a.setNFTContract);
        _set(a.areaRegistry(), areaRegistry, "Actions -> AreaRegistry", a.setAreaRegistry);

        _authJailer(pve, "Actions.jailer auth PVE");
        _authJailer(pvp, "Actions.jailer auth PVP");
        _authJailer(heists, "Actions.jailer auth Heists");

        if (pve != address(0)) {
            IPVEContract p = IPVEContract(pve);
            _set(p.actions(), actions, "PVE -> Actions", p.setActions);
        }
        if (pvp != address(0)) {
            IPVPContract p = IPVPContract(pvp);
            _set(p.actions(), actions, "PVP -> Actions", p.setActions);
        }
        if (heists != address(0)) {
            IHeistsWire h = IHeistsWire(heists);
            _set(h.actions(), actions, "Heists -> Actions", h.setActions);
        }
        console.log("");
    }

    function _wireMulticall() internal {
        if (multicall == address(0)) return;
        console.log("Wiring Multicall:");

        IMulticallContract mc = IMulticallContract(multicall);
        _set(mc.core(), core, "Multicall -> Core", mc.setCore);
        _set(mc.pve(), pve, "Multicall -> PVE", mc.setPVE);
        _set(mc.pvp(), pvp, "Multicall -> PVP", mc.setPVP);
        _set(mc.areaRegistry(), areaRegistry, "Multicall -> AreaRegistry", mc.setAreaRegistry);
        _set(mc.drugRegistry(), drugRegistry, "Multicall -> DrugRegistry", mc.setDrugRegistry);
        _set(mc.boosts(), boosts, "Multicall -> Boosts", mc.setBoosts);
        console.log("");
    }

    function _wireChatFactory() internal {
        if (chatFactory == address(0)) return;
        console.log("Wiring ChatFactory:");

        IChatFactory cf = IChatFactory(chatFactory);
        _set(cf.nftContract(), nft, "ChatFactory -> NFT", cf.setNFTContract);
        console.log("");
    }

    function _wireHeists() internal {
        if (heists == address(0)) return;
        console.log("Wiring Heists:");

        _authCore(heists, "Core auth Heists");
        _authPayment(heists, "PaymentHandler auth Heists");
        _authResolver(heists, "Randomness auth Heists");
        _authJailer(heists, "Actions.jailer auth Heists");

        IHeistsWire h = IHeistsWire(heists);
        _set(h.actions(), actions, "Heists -> Actions", h.setActions);

        if (claims != address(0)) {
            IClaimsContract cl = IClaimsContract(claims);
            _set(cl.heistsContract(), heists, "Claims -> Heists", cl.setHeists);
        }
        _syncHeistsRefs();
        _syncBankHeistRefs();
        console.log("");
    }

    function _wireBankHeist() internal {
        if (bankHeist == address(0)) return;
        console.log("Wiring BankHeist:");

        _authCore(bankHeist, "Core auth BankHeist");
        _syncBankHeistRefs();

        if (paymentHandler != address(0) && IPaymentVault(paymentHandler).bankVault() != bankHeist) {
            console.log("  WARNING: PaymentHandler.bankVault does not point at BankHeist.");
            console.log("    Intentional only if the event is over; otherwise: setBankVault(bankHeist).");
        }
        console.log("");
    }
}

# Audit Scope — Dealers.sh

On-chain PvE/PvP mafia strategy game on **Abstract Chain** (zkSync-based L2, chain id `2741`).

- **Audited commit:** _tag the release at handoff_ (latest `main` after the heist merge)
- **Compiler:** `solc 0.8.28`, `via-ir = true`, `optimizer = true`, `optimizer_runs = 100`
- **Language target:** zkSync VM (native) for game contracts; EVM bytecode for the SVG renderer (see [Build](#build--test))
- **Libraries:** OpenZeppelin `v5.4.0`, Solady, Pyth Entropy (external oracle)

> **Trusted owner.** Every module is `Ownable` (Solady). The owner is trusted to set
> configuration, authorize modules, and fund/withdraw the heist reserve. Owner key management is
> out of scope; audit assumes a non-malicious, secured admin (multisig recommended).

---

## In scope

Deployed game contracts that hold state and/or value.

| Contract | Purpose |
|---|---|
| `DealersCore` | Central game-state hub; `onlyAuthorized` gate for all state mutation |
| `DealersNFT` | ERC721 dealers with on-chain metadata + embedded gameplay UI |
| `DealersPVE` | Player-vs-Environment hustle game |
| `DealersPVP` | Same-area player-vs-player battles |
| `DealersBoosts` | Time-limited boost tiers (drug/rep/cash multipliers, extra attempts) |
| `DealersActions` | Player actions (movement, jail/bail, safe house, arrests) |
| `DealersClaims` | Achievement + admin reward claims |
| `DealersHeists` | Daily push-your-luck heist runs + optional ETH jackpot (Pyth) |
| `DealersMulticall` | Read-only aggregator (view) |
| `DealersPaymentHandler` | Centralized ETH custody + fee distribution |
| `DealersRandomness` | In-house commit-reveal randomness |
| `DealersAreaRegistry` | Area + drug-pricing registry |
| `DealersDrugRegistry` | Global drug registry |

Interfaces for the above (`IDealers*`) and the Pyth consumer interfaces (`src/utils/pyth/`) are in
scope as part of the contracts that use them.

## ⭐ Priority — session-key attack surface (mainnet)

These functions are the **only** entrypoints granted to [Abstract Global Wallet **session keys**](https://docs.abs.xyz/abstract-global-wallet/session-keys)
on mainnet — i.e. a delegated key can call them **without per-transaction user approval**, bounded
only by the session limits below. This is the highest-priority surface: assume a session key may be
**lost or malicious** and audit what it can do to the owner's dealer, other players, and contract
funds within these bounds (griefing, value extraction up to the cap, state corruption, reentrancy
across the commit/resolve pairs).

**Session limits** (per key, enforced by the wallet — not the contracts):

| Limit | Value |
|---|---|
| Duration | 14 days |
| Gas/fee budget | 0.1 ETH lifetime |
| Payable value | 0.25 ETH lifetime · 0.1 ETH max per call |
| Non-payable calls | 0 value |

**Whitelisted selectors:**

| Contract | Functions | Payable |
|---|---|:--:|
| `DealersActions` | `travel`, `payBail`, `bribeCop`, `purchaseCash`, `purchaseAttemptReset` | 💰 |
| `DealersActions` | `commitBreakout`, `resolveBreakout`, `commitWantedPoster`, `resolveWantedPoster`, `sellDrop` | — |
| `DealersPVE` | `commitGame`, `resolveGame` | — |
| `DealersPVP` | `commitAttack`, `resolveAttack` | — |
| `DealersBoosts` | `purchaseBoost` | 💰 |
| `DealersClaims` | `claimAchievement`, `claimAchievements` | — |
| `DealersHeists` | `startHeist` | 💰 |
| `DealersHeists` | `commitStage`, `resolveStage`, `cashOut`, `claimJackpot` | — |
| `DealersChatFactory` | `postMessage` | — |

> A session key signs for the dealer owner. `purchaseBoost` and `startHeist` move ETH (capped per the
> table); `cashOut`/`claimJackpot` pull value **to the NFT owner**, not the key. Confirm no whitelisted
> selector lets a rogue key redirect funds, exceed the per-use cap, or grief another player's run.

## Out of scope — concept (NOT deployed)

| Contract | Status |
|---|---|
| `DealersBankHeist` / `IDealersBankHeist` | **CONCEPT.** Not deployed (mainnet `bankHeist` stays `address(0)`); ships later via `script/deploy/DeployBankHeist.s.sol`. Accounting, interfaces, and config are provisional. Marked in-source with `@custom:status OUT OF AUDIT SCOPE` (`grep -rn "OUT OF AUDIT SCOPE" src/`). |

## Lower priority / scope to confirm

View/pure or peripheral; no value custody. Confirm inclusion with the audit firm.

- **Renderers / storage:** `DealerRendererSVG`, `DealerRendererHTML`, `File` — deterministic on-chain art + FileStore I/O.
- **Social:** `DealersChatFactory`, `DealersChatRoom`, `DealersAreaChatGate` — on-chain chat, gated by dealer area.

## Not in scope

`test/`, `script/`, `lib/` (dependencies), and any contract under `src/` not listed above.

---

## Build & test

Abstract runs the zkSync VM natively but the SVG renderer uses `EXTCODECOPY` (SSTORE2/FileStore), so
it must be built as **EVM** bytecode. Two paths:

```bash
# Game contracts (native zkSync) — skip the EVM-only artifacts
forge build --zksync --skip "RendererSVG" --skip "UploadTraits"
forge test  --zksync --skip "RendererSVG" --skip "UploadTraits"

# SVG renderer (EVM bytecode)
forge build
forge test --match-contract "DealerRendererSVG"
```

`UploadTraits.s.sol` and `DealerRendererSVG` share the EVM-only SSTORE2 pattern; both are skipped in
the zkSync build (not a bug — the two-path deploy strategy).

---

## Trust model & assumptions

- **Authorization.** State-mutating entrypoints on `DealersCore` are guarded by `onlyAuthorized`;
  only owner-registered module contracts may call them. A compromised/buggy authorized module can
  corrupt game state — the authorized set is part of the trust boundary.
- **Randomness.**
  - `DealersRandomness` is an in-house **commit-reveal** scheme; a committed round resolves to
    win/bust only and cannot be rewound. A missed reveal window is a terminal loss (same rule across
    PVE/PVP/Heists). Validator/sequencer influence over the reveal source should be assessed.
  - **Pyth Entropy** (`IEntropyV2`) decides heist **jackpot values** only. Callbacks are pull-based;
    a never-arriving callback is recoverable after a timeout (`reclaimStuckJackpot`). Pyth is a
    trusted external oracle.
- **ETH custody.** `DealersPaymentHandler` and `DealersHeists` hold ETH. All outflows are pull-based
  / `.call()`-based (Abstract-compatible). `DealersHeists` is solvent by construction: a jackpot
  only fires if `jackpotReserve >= maxPayout + fee`, else it is skipped — winners can never extract
  more than the contract holds. `withdrawReserve` exposes only the free reserve, never escrowed or
  owed jackpot ETH.
- **Heist jackpot:** at most **one jackpot per run** (first trigger locks it; a reserve-skip stays
  eligible). The reserve should be pre-funded before launch (see `fundReserve`).

## Known / intentional design decisions

- **Drug supply is uncapped on-chain** — no global cap; reconstruct supply from
  `DealersCore.DrugBalanceUpdated` events.
- **Boosts read live at resolve** — multipliers apply at outcome time ("pay-to-grow" is by design).
- **Jail/heat:** heat 0–5 drives jail chance; bail costs a capped reputation penalty.

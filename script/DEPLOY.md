# Deployment Guide — Abstract (Testnet + Mainnet)

All deployment scripts read addresses from `script/data/deployments/{NETWORK}.json` and trait pointers from `script/data/{NETWORK}/pointers.json`, where `{NETWORK}` is `testnet` (chain 11124) or `mainnet` (chain 2741).

Shell orchestrators (`upload-traits.sh`, `verify-source.sh`) honor a single env var:

```bash
NETWORK=testnet ./script/upload-traits.sh         # default
NETWORK=mainnet ./script/upload-traits.sh         # mainnet
```

For Solidity scripts the network is detected from `block.chainid` via the `--rpc-url` you pass — no env var required there. `--rpc-url` accepts the `foundry.toml` aliases `abstract-testnet` and `abstract` (mainnet); `cast` resolves them the same way, so no raw URLs are needed anywhere.

**Examples below are testnet. For mainnet, swap every:** `abstract-testnet` → `abstract`, `NETWORK=testnet` → `NETWORK=mainnet`, and `deployments/testnet.json` → `deployments/mainnet.json`.


## TLDR Checklist

```
 1. cast wallet import dealersKeystore --interactive     (one-time)
 2. Create .env (per-network MAINNET_/TESTNET_): DEV_WALLET, BANK_VAULT, ROYALTY_RECEIVER, PYTH_ENTROPY, APP_URL (HTML iframe-escape, optional), ETHERSCAN_API_KEY
 3. forge build && forge build --zksync --skip "RendererSVG" --skip "UploadTraits"  (EVM + zkSync)
 4. DeployAll.s.sol            --zksync                  (14 contracts incl. heists + drugs/areas + wire + tiers + claims + chat)
    (or: DeployAll --sig "runGameOnly()"                  game contracts only — defer NFT/renderers/heists)
 5. DeployRendererSVG.s.sol    NO --zksync               (SVG renderer, EVM mode)
 6. cast send NFT setContractRendererSVG(address)         (link SVG to NFT)
 7. DeployHtmlRenderer.s.sol   --zksync                  (HTML renderer + config + link to NFT)
 8. UploadTraits — uploadPlaceholder()  NO --zksync       (store + set placeholder SVG; network-aware)
 9. UploadTraits — uploadNormal() + uploadSpecial()       (store + set normal/special traits)
10. UploadTraits — uploadOneOfOnesRange()  NO --zksync   (store 1/1 SVGs)
11. UploadGzipJs.s.sol upload()    NO --zksync           (store app JS — embeds ALL contract addresses, incl. heists)
12. UploadGzipJs.s.sol setFilename --zksync              (set filename on HTML renderer)
13. testnet/SetupTestnetPricing.s.sol  --zksync          (optional: 10x fee reduction)
14a. ../generateAssignments.py                          (per-slot trait combos → assignments.json)
14b. assign-traits.sh                                    (assign combos + 1/1s to pool slots)
15. setDealersNFT(NFT) on RendererSVG  NO --zksync       (pool-index source; auto-set by DeployRendererSVG)
16. setMintOpen(true) on NFT                              (open public mint; tokens reveal via resolve)
17. VerifyConfig.s.sol                                    (read-only sanity check)
18. verify-source.sh                                      (optional: block explorer)
```

---

## 1. Prerequisites

### Keystore (one-time)

```bash
cast wallet import dealersKeystore --interactive
```

### .env

```bash
# Deploy wallets/config resolve per network: MAINNET_<KEY> (required on mainnet),
# TESTNET_<KEY> on testnet (falls back to unprefixed). Mainnet example:
MAINNET_DEV_WALLET=0x...
MAINNET_BANK_VAULT=0x...            # PaymentHandler bank-fee vault (treasury/multisig, must receive ETH)
MAINNET_ROYALTY_RECEIVER=0x...
MAINNET_PYTH_ENTROPY=0x...          # heist module (required)
MAINNET_APP_URL=https://...         # HTML renderer: iframe-sandbox escape target (optional; settable later)
ETHERSCAN_API_KEY=your_key
```

Contract addresses are managed via `script/data/deployments/{NETWORK}.json` — do not put them in `.env`.

### Build

```bash
forge build                                  # EVM (renderers)
forge build --zksync --skip "RendererSVG" --skip "UploadTraits"     # zkSync (game)
```

---

## 2. Deploy Game Contracts

Deploys all 13 game contracts in dependency order, registers drugs, creates areas, wires cross-references, sets authorizations, and configures the 10-tier reputation system.

For a fresh deploy, delete the JSON first: `rm -f script/data/deployments/testnet.json`

```bash
source .env && forge script script/deploy/DeployAll.s.sol:DeployAll --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

Contracts deployed: DealersDrugRegistry, DealersAreaRegistry, DealersCore, DealersPaymentHandler, DealersRandomness, DealersNFT, DealersBoosts, DealersPVE, DealersPVP, DealersClaims, DealersActions, DealersMulticall, DealersChatFactory, DealersAreaChatGate.

Setups included: 11 drugs, 7 areas, all cross-contract wiring + authorizations, 10-tier reputation system, 24 achievements, WORLD + 9 area chat rooms.

Addresses auto-saved to `script/data/deployments/testnet.json`.

### 2a. Game-Only Mode (defer NFT)

Use this when you need stable game-contract addresses (e.g. for session-key approval on mainnet) before
locking in NFT details. Deploys every game contract **except** `DealersNFT` and the renderers. Modules that
require an NFT address in their constructor (Boosts, PVE, PVP, Claims, Actions, ChatFactory) are given
`DEV_WALLET` as a placeholder; the real NFT is wired in later via `SetupWiring`.

```bash
source .env && forge script script/deploy/DeployAll.s.sol:DeployAll \
  --sig "runGameOnly()" \
  --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

What this does:
- Deploys: DrugRegistry, AreaRegistry, Core, PaymentHandler, Randomness, Boosts, PVE, PVP, Claims, Actions, Multicall, ChatFactory + AreaChatGate.
- Skips: DealersNFT (and SVG + HTML renderers, which live in their own scripts).
- Skips NFT-touching wiring: `Core.setNFTContract`, `Core.authorizeContract(nft)`, `NFT.setDealersCore`, `Boosts.setDealersNFT`, `Claims.setDealersNFT`.
- Saves addresses to `script/data/deployments/{network}.json` with `nft` left as `0x0`.
- `ROYALTY_RECEIVER` is not required in this mode.

Module addresses are stable — they're determined by deploy nonce, not by NFT, so the session-key approval
you submit from this deploy remains valid after the NFT lands.

**Follow-up once NFT design is final:**

```bash
# 1. Deploy NFT
source .env && forge script script/deploy/DeployNFT.s.sol:DeployNFT \
  --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"

# 2. Re-wire (idempotent — points every module's NFT ref at the real NFT, authorizes NFT on Core,
#    sets NFT.dealersCore. Covers Core, NFT, Boosts, Claims, PVE, PVP, Actions, ChatFactory.)
source .env && forge script script/setup/SetupWiring.s.sol:SetupWiring \
  --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"

# 3. SVG + HTML renderers, gzip upload, mint enable — steps 3-12 above.
```

---

## 3. Deploy SVG Renderer

Uses SSTORE2/EXTCODECOPY — must deploy in EVM mode (no `--zksync`).

```bash
source .env && forge script script/deploy/DeployRendererSVG.s.sol:DeployRendererSVG --rpc-url abstract-testnet --account dealersKeystore --broadcast
```

### Link SVG Renderer to NFT

The NFT contract is zkSync-native, so linking must be done via `cast send`:

```bash
source .env
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
RENDERER_SVG=$(jq -r .rendererSvg script/data/deployments/testnet.json)
cast send $DEALERS_NFT "setContractRendererSVG(address)" $RENDERER_SVG --rpc-url abstract-testnet --account dealersKeystore
```

---

## 4. Deploy HTML Renderer

Deploys as zkSync-native. Configures RPC URL (chain-derived), SVG renderer reference, and links to NFT in one step. Uses a placeholder gzip filename if none is set — update it after uploading the actual gzip (step 8).

It also sets the **App URL** from `APP_URL` in `.env` (network-prefixed: `MAINNET_APP_URL` / `TESTNET_APP_URL`). The embedded game opens this URL to route users out when it's running inside a restrictive iframe sandbox. If `APP_URL` is unset the deploy skips it with a warning — set it later with:

```bash
DEALERS_HTML=$(jq -r .rendererHtml script/data/deployments/testnet.json)
cast send $DEALERS_HTML "setAppUrl(string)" "https://your.app.url" --rpc-url abstract-testnet --account dealersKeystore
```

```bash
source .env && forge script script/deploy/DeployHtmlRenderer.s.sol:DeployHtmlRenderer --zksync --skip "RendererSVG" --skip "UploadTraits" --rpc-url abstract-testnet --account dealersKeystore --broadcast
```

---

## 5. Storing the Placeholder

The placeholder is the image a token shows until it is revealed (and for any pool slot with no
traits). This **stores** the placeholder SVG in FileStore and **sets** it on the renderer.

```bash
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadPlaceholder()" --rpc-url abstract-testnet --account dealersKeystore --broadcast
```

Reads the SVG from `script/data/traits.json` -> `.placeholder`, uploads to FileStore (large SVGs auto-chunk via SSTORE2), sets it on the renderer, and caches the pointer in the network-specific `script/data/{NETWORK}/pointers.json`. Use this network-aware `UploadTraits` entrypoint — **not** the legacy `UploadPlaceholder.s.sol`, which caches into the shared `traits.json` and will reuse a wrong-network pointer across testnet/mainnet.

---

## 6. Storing & Setting Traits

`uploadNormal()` / `uploadSpecial()` do two things in one call — the three verbs used throughout
this guide:

- **Storing** — write the trait-layer SVG bytes to FileStore (SSTORE2), caching the pointers in `script/data/traits.json`.
- **Setting** — register those pointers on the renderer's palette via `batchAddTraits` (`traits[charType][category]`).
- **Assigning** (separate, §10) — bind trait combinations to pool slots via `batchSetTraits` / `batchSetOneOfOnes`.

Re-running skips any layer whose pointer is already cached.

```bash
# Normal traits
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadNormal()" --rpc-url abstract-testnet --account dealersKeystore --broadcast

# Special traits
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadSpecial()" --rpc-url abstract-testnet --account dealersKeystore --broadcast
```

---

## 7. Storing One-of-Ones

One-of-ones are complete SVGs with no palette, so they only need **storing** — their pool-slot
**assigning** happens in §10. This writes each 1/1 SVG to FileStore in chunks and caches the
pointers in `script/data/traits.json`.

```bash
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadOneOfOnesRange(uint256,uint256)" 0 5 --rpc-url abstract-testnet --account dealersKeystore --broadcast --slow
# ...repeat with 5 5, 10 5, ..., 40 5 until all are stored
```

---

## 8. Storing the App JS + Setting the Filename

Two-step process due to Abstract's dual VM. The gzip is built from the app, which **embeds every
contract address** (read from the deployments JSON) — so run this only after `DeployAll` (which
deploys all game contracts, **including heists**) and the renderers.

### Prerequisites

```bash
cd ../dealers-app && ./build-single-file.sh
```

This copies output to `script/data/dealers.js.gz.b64`.

### Step 1: Store in FileStore (EVM mode)

```bash
source .env && forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs --sig "upload()" --rpc-url abstract-testnet --account dealersKeystore --broadcast
```

### Step 2: Set filename on HTML renderer (zkSync mode)

```bash
source .env && forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs --sig "setFilename(string)" "dealers-testnet-1781659195.js.gz" --zksync --skip "RendererSVG" --skip "UploadTraits" --rpc-url abstract-testnet --account dealersKeystore --broadcast
```

---

## 9. Setup Testnet Pricing (optional)

Divides all ETH fees by 10 for cheaper testnet gameplay.

```bash
source .env && forge script script/testnet/SetupTestnetPricing.s.sol:SetupTestnetPricing --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

---

## 10. Assigning Traits to the Pool

This fills the **deck**, not tokens. The renderer holds each character's packed bytes32 per **pool
slot** in `storedTraits[poolIndex]` (1..10000), independent of any token. Which token receives which
slot is decided randomly at `resolve` time, so the whole pool **must** be assigned **before**
`setMintOpen` (the draw can land on any slot). `batchSetTraits` / `batchSetOneOfOnes` have no
`_exists` check, only `onlyOwner`.

### Step 1: Generate the assignment manifest (off-chain, deterministic)

```bash
cd .. && python3 generateAssignments.py
```

Reads `script/data/traits.json` and `incompatibility_rules`, emits
`script/data/assignments.json` — one entry per pool slot in 1..10000 with the
packed `bytes32` and the kind (`normal` / `special` / `oneOfOne`). RNG is seeded
per-slot so output is fully reproducible. Tunable constants
(`SPECIAL_COUNT`, `ONE_OF_ONE_IDS`, `BASE_SEED`) live at the top of the
generator file.

### Step 2: Assign on-chain in chunks

```bash
NETWORK=testnet ./script/assign-traits.sh            # all 10000 in chunks of 250
CHUNK=100 NETWORK=mainnet ./script/assign-traits.sh  # smaller chunks for mainnet
```

The orchestrator walks the manifest in `CHUNK`-sized slices, calling
`assignTokenTraitsRange` per slice, then a single `assignOneOfOnesFromManifest`.
Idempotent — re-running re-applies identical writes.

Toggle phases independently:

```bash
DO_TRAITS=0   NETWORK=testnet ./script/assign-traits.sh   # only one-of-ones
DO_ONEOFONES=0 NETWORK=testnet ./script/assign-traits.sh  # only traits
```

### Packed format (`storedTraits[poolIndex]`)

```
bits  [0..7]    cat 0  (backdrop)        1-indexed (0 = no trait)
bits  [8..15]   cat 1  (head)
...
bits  [88..95]  cat 11 (accessory)
bits  [96..103] character type           0=NORMAL, 1=SPECIAL
```

SPECIAL falls back to NORMAL per-category if `traits[SPECIAL][cat]` is empty —
the generator mirrors that behavior.

---

## 11. Reveal (per-token, at runtime)

Reveal is per-token. After `mint` (commit), anyone — a session key, the player, or a keeper —
calls `resolve(tokenId)` to draw the token's pool slot and bind its artwork. A token shows the
placeholder until it resolves. This works once the pool is fully assigned (§10) and the placeholder
is set (§5).

```bash
# Optional keeper sweep of still-unrevealed tokens (skips any not yet revealable):
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
cast send $DEALERS_NFT "resolveMany(uint256[])" "[1,2,3]" --rpc-url abstract-testnet --account dealersKeystore
```

---

## 12. Enable Minting

```bash
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
cast send $DEALERS_NFT "setMintOpen(bool)" true --rpc-url abstract-testnet --account dealersKeystore
```

Minting is a single public sale. Buying calls `mint(dest, count)` (commit): the dealer and its
game state are created immediately, while the artwork is assigned later by `resolve(tokenId)`
(reveal) — callable by anyone (session key, the player, or a keeper).

---

## 13. Verify Configuration

Read-only — confirms all cross-contract references and authorizations.

```bash
forge script script/verify/VerifyConfig.s.sol:VerifyConfig --rpc-url abstract-testnet --zksync --skip "RendererSVG" --skip "UploadTraits"
```

Reports `[OK]`, `[MISMATCH]`, or `[NEEDS CONFIG]` for every slot.

---

## 14. Source Verification (optional)

```bash
source .env && ./script/verify-source.sh              # all contracts
source .env && ./script/verify-source.sh game          # game contracts only
source .env && ./script/verify-source.sh renderers     # renderers only
```

---

## 15. Heist Module

`DealersHeists` (daily push-your-luck supply/cash runs + ETH jackpot) is **deployed, wired, and
configured by `DeployAll`** (step 4): the contract ships its full sim-tuned config (difficulties,
stage tables, jackpot, scalars) as constructor defaults, so no config step is needed. `DeployAll`
requires `MAINNET_PYTH_ENTROPY` / `TESTNET_PYTH_ENTROPY` in `.env`. The 80% bank-fee share flows to
`PaymentHandler.bankVault` = `BANK_VAULT` (`MAINNET_BANK_VAULT` on mainnet), a treasury/multisig.

> **The bank vault must be able to receive ETH.** `PaymentHandler._processFee` pushes the bank share
> via `.call` and reverts the whole fee tx if it fails — so the address must be an EOA or a Safe,
> never a contract without a payable `receive`.

The standalone scripts below are only for **re-tuning** the live config (`SetupHeists`) or **adding
heists to a deployment that predates the DeployAll integration** (`DeployHeists` deploys + wires).

### Prerequisites

Core game already deployed (`core`, `nft`, `randomness`, `paymentHandler`, `drugRegistry` in the
deployments JSON). Add the Pyth Entropy contract for the target chain to `.env` (network-prefixed;
mainnet requires the `MAINNET_` form):

```bash
TESTNET_PYTH_ENTROPY=0x...
MAINNET_PYTH_ENTROPY=0x...
```

Get the Pyth Entropy address from Pyth's Abstract deployment docs — it is **not** hardcoded.

### 15.1 Deploy + wire DealersHeists

```bash
source .env && forge script script/deploy/DeployHeists.s.sol:DeployHeists --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

Deploys `DealersHeists`, saves it to the deployments JSON, and wires it idempotently. `bankVault` is not touched — the bank-fee share flows to the treasury (`MAINNET_BANK_VAULT`).

| Wiring | Purpose |
|--------|---------|
| `Core.authorizeContract` → Heists | mutates core state |
| `PaymentHandler.authorizeContract` → Heists | Heists pays the ETH add-on fee |
| `Randomness.authorizeResolver` → Heists | commit/reveal randomness |
| `Actions.authorizeJailer` + `Heists.setActions` → Heists | arrest-on-bust (only if Actions deployed) |

### 15.2 Configure DealersHeists

```bash
source .env && forge script script/setup/SetupHeists.s.sol:SetupHeists --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

Re-asserts the difficulty tiers, stage tables, and tuned jackpot config — all of which already ship as `DealersHeists` constructor defaults, so this is a re-assertion / live-tuning tool (not required after a fresh `DeployAll`). Sim-tuned values (see `test/simulation/HeistEconomySimulation.t.sol` + `heist_tuning.py`):

| Difficulty | Rep gate | $CASH stake |
|-----------|----------|-------------|
| D0 Street Score | 600 (Soldier) | 600 |
| D1 Warehouse Job | 1,500 (Capo) | 4,000 |
| D2 Cartel Heist | 5,500 (Underboss) | 25,000 |

Jackpot triggers `40/34/30/32/40%`, bands 0.7-1x up to 1.5-20x (reserve self-funds at the 60% cut).

The heist mode is live after this step.

### Notes

- **Re-runnable**: both scripts are idempotent (check state before each setter).
- **`bankVault`**: stays the treasury (`MAINNET_BANK_VAULT`); the 80% bank-fee share flows there.
- **Not in `DeployAll`** by design — deploy this module with its own scripts after the game contracts.

---

## Redeploying Individual Contracts

Each contract has its own deploy script. After deploying, run SetupWiring to re-wire.

| Contract | Script | Constructor Deps |
|----------|--------|-----------------|
| DealersDrugRegistry | `DeployDrugRegistry.s.sol` | none |
| DealersAreaRegistry | `DeployAreaRegistry.s.sol` | drugRegistry |
| DealersCore | `DeployCore.s.sol` | none |
| DealersPaymentHandler | `DeployPaymentHandler.s.sol` | devWallet, bankVault |
| DealersRandomness | `DeployRandomness.s.sol` | none |
| DealersNFT | `DeployNFT.s.sol` | royaltyReceiver |
| DealersBoosts | `DeployBoosts.s.sol` | core, nft, paymentHandler |
| DealersPVE | `DeployPVE.s.sol` | core, nft, areaRegistry |
| DealersPVP | `DeployPVP.s.sol` | core, nft, areaRegistry |
| DealersClaims | `DeployClaims.s.sol` | core, nft, pve, pvp |
| DealersActions | `DeployActions.s.sol` | core, nft, areaRegistry |
| DealersMulticall | `DeployMulticall.s.sol` | core, pve, pvp, areaRegistry, drugRegistry |
| DealersChatFactory | `DeployChatFactory.s.sol` | nft |

### Workflow: Deploy + Re-wire

```bash
# 1. Deploy the contract
source .env && forge script script/deploy/Deploy<Contract>.s.sol:<Contract> --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"

# 2. Re-wire (idempotent — only updates stale references)
source .env && forge script script/setup/SetupWiring.s.sol:SetupWiring --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

### Redeploying Core

Most impactful — every module references Core. After deploying a new Core:

1. Run SetupWiring (re-wires all modules + re-authorizes)
2. Run SetupTiers (reputation tiers are stored on Core)
3. Run SetupRebalance (CoreConfig — jail chance — is stored on Core; also re-asserts PVE odds + PVP config)

```bash
source .env && forge script script/setup/SetupTiers.s.sol:SetupTiers --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
source .env && forge script script/setup/SetupRebalance.s.sol:SetupRebalance --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

### Applying the economy rebalance to an existing deployment

The sim-calibrated economy (docs/ECONOMY_BALANCE_SIM.md) now ships in the CONSTRUCTOR DEFAULTS of Core (tiers + jail), PVE (odds + stake scaling), PVP (cash steal), Boosts (multipliers), and Heists (difficulties, stage rep, jackpot table, 60% reserve) — a fresh deploy via DeployAll (+ DeployHeists) needs NO economy setters; the setup scripts below are idempotent re-assertions / live-tuning tools. NOTE: the rebalance changed contract source (DealersPVE stake scaling at minimum) — a deployment older than that change needs contract redeploys + SetupWiring first; on old contracts SetupRebalance's `setStakeScaling` call reverts. To retune an already-deployed game, run:

```bash
source .env && forge script script/setup/SetupTiers.s.sol:SetupTiers --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
source .env && forge script script/setup/SetupRebalance.s.sol:SetupRebalance --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
source .env && forge script script/setup/SetupBoosts.s.sol:SetupBoosts --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
source .env && forge script script/setup/SetupHeists.s.sol:SetupHeists --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

---

## Notes

- **Address persistence**: all deploy scripts save to `script/data/deployments/{NETWORK}.json` (chain-derived from `block.chainid`). Scripts load from JSON first, falling back to `.env`.
- **Idempotent**: DeployAll skips contracts with existing addresses. SetupWiring checks state before calling setters. Safe to re-run.
- **Two build modes**: game contracts require `--zksync`, renderers must NOT use `--zksync` (SSTORE2/EXTCODECOPY).
- **`--skip` flags**: always pass `--skip "RendererSVG" --skip "UploadTraits"` with `--zksync` to prevent compilation errors.
- **FileStore**: `0xFe1411d6864592549AdE050215482e4385dFa0FB` — same on mainnet and testnet.
- **Fresh deploy**: delete `script/data/deployments/testnet.json` before running DeployAll.

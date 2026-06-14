# Deployment Guide — Abstract (Testnet + Mainnet)

All deployment scripts read addresses from `script/data/deployments/{NETWORK}.json` and trait pointers from `script/data/{NETWORK}/pointers.json`, where `{NETWORK}` is `testnet` (chain 11124) or `mainnet` (chain 2741).

Shell orchestrators (`upload-traits.sh`, `verify-source.sh`) honor a single env var:

```bash
NETWORK=testnet ./script/upload-traits.sh         # default
NETWORK=mainnet ./script/upload-traits.sh         # mainnet
```

For Solidity scripts the network is detected from `block.chainid` via the `--rpc-url` you pass — no env var required there. Examples below show testnet RPCs; swap in `https://api.mainnet.abs.xyz` for mainnet.


## TLDR Checklist

```
 1. cast wallet import dealersKeystore --interactive     (one-time)
 2. Create .env with DEV_WALLET, BANK_VAULT, ROYALTY_RECEIVER, ETHERSCAN_API_KEY
 3. forge build && forge build --zksync --skip "RendererSVG" --skip "UploadTraits"  (EVM + zkSync)
 4. DeployAll.s.sol            --zksync                  (13 contracts + drugs/areas + wire + tiers + claims + chat)
    (or: DeployAll --sig "runGameOnly()"                  game contracts only — defer NFT/renderers)
 5. DeployRendererSVG.s.sol    NO --zksync               (SVG renderer, EVM mode)
 6. cast send NFT setContractRendererSVG(address)         (link SVG to NFT)
 7. DeployHtmlRenderer.s.sol   --zksync                  (HTML renderer + config + link to NFT)
 8. UploadPlaceholder.s.sol    NO --zksync               (fallback SVG)
 9. UploadTraits — uploadNormal() + uploadSpecial()       (trait SVGs to FileStore)
10. UploadTraits — uploadOneOfOnesRange()  NO --zksync   (1/1 SVGs to FileStore)
11. UploadGzipJs.s.sol upload()    NO --zksync           (upload JS to FileStore)
12. UploadGzipJs.s.sol setFilename --zksync              (set filename on HTML renderer)
13. testnet/SetupTestnetPricing.s.sol  --zksync          (optional: 10x fee reduction)
14a. ../generateAssignments.py                          (per-token trait combos → assignments.json)
14b. assign-traits.sh                                    (chunked batchSetTraits + batchSetOneOfOnes)
15. reveal() on RendererSVG                               (switch from placeholder)
16. setMintStatus(3) on NFT                               (enable public mint)
17. VerifyConfig.s.sol                                    (read-only sanity check)
18. verify-source.sh                                      (optional: block explorer)
19. (optional) DeployHeists + SetupHeists                 (heist module add-on — see §15)
```

---

## 1. Prerequisites

### Keystore (one-time)

```bash
cast wallet import dealersKeystore --interactive
```

### .env

```bash
DEV_WALLET=0x...
BANK_VAULT=0x...
ROYALTY_RECEIVER=0x...
ETHERSCAN_API_KEY=your_key
ABSTRACT_TESTNET_RPC=https://api.testnet.abs.xyz
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
  --rpc-url abstract --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
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
  --rpc-url abstract-mainnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"

# 2. Re-wire (idempotent — points every module's NFT ref at the real NFT, authorizes NFT on Core,
#    sets NFT.dealersCore. Covers Core, NFT, Boosts, Claims, PVE, PVP, Actions, ChatFactory.)
source .env && forge script script/setup/SetupWiring.s.sol:SetupWiring \
  --rpc-url abstract-mainnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"

# 3. SVG + HTML renderers, gzip upload, mint enable — steps 3-12 above.
```

---

## 3. Deploy SVG Renderer

Uses SSTORE2/EXTCODECOPY — must deploy in EVM mode (no `--zksync`).

```bash
source .env && forge script script/deploy/DeployRendererSVG.s.sol:DeployRendererSVG --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

### Link SVG Renderer to NFT

The NFT contract is zkSync-native, so linking must be done via `cast send`:

```bash
source .env
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
RENDERER_SVG=$(jq -r .rendererSvg script/data/deployments/testnet.json)
cast send $DEALERS_NFT "setContractRendererSVG(address)" $RENDERER_SVG --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

---

## 4. Deploy HTML Renderer

Deploys as zkSync-native. Configures RPC URL, SVG renderer reference, and links to NFT in one step. Uses a placeholder gzip filename if none is set — update it after uploading the actual gzip (step 8).

```bash
source .env && forge script script/deploy/DeployHtmlRenderer.s.sol:DeployHtmlRenderer --zksync --skip "RendererSVG" --skip "UploadTraits" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

---

## 5. Upload Placeholder SVG

Fallback image shown before reveal or for tokens without traits assigned.

```bash
source .env && forge script script/upload/UploadPlaceholder.s.sol:UploadPlaceholder --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

Reads from `script/data/traits.json` -> `.placeholder`. Large SVGs auto-chunked via SSTORE2.

---

## 6. Upload Trait SVGs

Uploads trait SVG art to FileStore and registers them on DealerRendererSVG. Pointers cached in `script/data/traits.json` — re-running skips already-uploaded traits.

```bash
# Normal traits
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadNormal()" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast

# Special traits
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadSpecial()" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

---

## 7. Upload One-of-Ones (optional)

Two separate phases: upload SVG content to FileStore (prep), then assign pointers
to token IDs (only at reveal time).

```bash
# Upload SVGs to FileStore in chunks (writes pointers back to traits.json)
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadOneOfOnesRange(uint256,uint256)" 0 5 --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast --slow
# ...repeat with 5 5, 10 5, ..., 40 5 until all 45 are uploaded

# Assign cached pointers to token IDs (run once, at reveal time)
source .env && forge script script/upload/AssignTraits.s.sol:AssignTraits --sig "assignOneOfOnes(uint256[])" "[1,42,100,...]" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

---

## 8. Upload Gzip JS + Set Filename

Two-step process due to Abstract's dual VM. The gzip is built from the app after contract addresses are known.

### Prerequisites

```bash
cd ../dealers-app && ./build-single-file.sh
```

This copies output to `script/data/dealers.js.gz.b64`.

### Step 1: Upload to FileStore (EVM mode)

```bash
source .env && forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs --sig "upload()" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

### Step 2: Set filename on HTML renderer (zkSync mode)

```bash
source .env && forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs --sig "setFilename(string)" "dealers-testnet-1776332930.js.gz" --zksync --skip "RendererSVG" --skip "UploadTraits" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

---

## 9. Setup Testnet Pricing (optional)

Divides all ETH fees by 10 for cheaper testnet gameplay.

```bash
source .env && forge script script/testnet/SetupTestnetPricing.s.sol:SetupTestnetPricing --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

---

## 10. Assign Traits to Tokens

Traits can be assigned **before mint** — `batchSetTraits` and `batchSetOneOfOnes`
have no `_exists` check, only `onlyOwner`. The renderer stores the packed bytes32
per tokenId in `storedTraits[tokenId]` independently of ownership.

### Step 1: Generate the assignment manifest (off-chain, deterministic)

```bash
cd .. && python3 generateAssignments.py
```

Reads `script/data/traits.json` and `incompatibility_rules`, emits
`script/data/assignments.json` — one entry per tokenId in 1..10000 with the
packed `bytes32` and the kind (`normal` / `special` / `oneOfOne`). RNG is seeded
per-tokenId so output is fully reproducible. Tunable constants
(`SPECIAL_COUNT`, `ONE_OF_ONE_IDS`, `BASE_SEED`) live at the top of the
generator file.

### Step 2: Push assignments on-chain in chunks

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

### Packed format (`storedTraits[tokenId]`)

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

## 11. Reveal

Switches all tokens from placeholder to their actual trait-based SVGs. Call only after all traits and placeholder are uploaded.

```bash
RENDERER_SVG=$(jq -r .rendererSvg script/data/deployments/testnet.json)
cast send $RENDERER_SVG "reveal()" --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

---

## 12. Enable Minting

```bash
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
cast send $DEALERS_NFT "setMintStatus(uint8)" 3 --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

Mint statuses: `0` DISABLED, `1` FAMILY, `2` WHITELIST, `3` PUBLIC.

---

## 13. Verify Configuration

Read-only — confirms all cross-contract references and authorizations.

```bash
forge script script/verify/VerifyConfig.s.sol:VerifyConfig --rpc-url https://api.testnet.abs.xyz --zksync --skip "RendererSVG" --skip "UploadTraits"
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

## 15. Heist Module (optional add-on)

Self-contained module — **not** part of `DeployAll`. The initial rollout ships only `DealersHeists`
(daily push-your-luck supply/cash runs + optional ETH jackpot). The community bank-heist event
(`DealersBankHeist`) is deferred and deployed later via §15.3; until then the 80% bank-fee share
keeps accruing to the address `PaymentHandler` was deployed with (`BANK_VAULT` — a treasury/multisig).

> **`BANK_VAULT` must be able to receive ETH.** `PaymentHandler._processFee` pushes the bank share
> via `.call` and reverts the whole fee tx if it fails — so the address must be an EOA or a Safe,
> never a contract without a payable `receive`.

### Prerequisites

Core game already deployed (`core`, `nft`, `randomness`, `paymentHandler`, `drugRegistry` in the
deployments JSON; `pve` + `pvp` are additionally needed for the later bank-heist step). Add to `.env`:

```bash
# External Pyth Entropy contract for the target chain (network-prefixed; mainnet requires the MAINNET_ form).
TESTNET_PYTH_ENTROPY=0x...
MAINNET_PYTH_ENTROPY=0x...
# Optional — bank-heist prep-window length in seconds (default 604800 = 7 days). Only used by §15.3.
BANK_HEIST_PREP_DURATION=604800
```

Get the Pyth Entropy address from Pyth's Abstract deployment docs — it is **not** hardcoded.

### 15.1 Deploy + wire DealersHeists

```bash
source .env && forge script script/deploy/DeployHeists.s.sol:DeployHeists --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

Deploys `DealersHeists`, saves it to the deployments JSON, and wires it idempotently. `bankVault` is left untouched (bank-fee share keeps flowing to the launch treasury).

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

Sets the 3 difficulty tiers (REQUIRED — `startHeist` reverts until set), the stage tables, and the tuned jackpot config. Sim-tuned values (see `test/simulation/HeistEconomySimulation.t.sol` + `heist_tuning.py`):

| Difficulty | Rep gate | $CASH stake |
|-----------|----------|-------------|
| D0 Street Score | 600 (Soldier) | 600 |
| D1 Warehouse Job | 1,500 (Capo) | 2,500 |
| D2 Cartel Heist | 5,500 (Underboss) | 12,000 |

Jackpot triggers `3/5/8/10/13%` (≈32% player ETH return riding to stage 5; reserve self-funds at the 40% cut).

The daily heists are live after this step. The bank heist remains undeployed.

### 15.3 Add the community bank heist (later)

Run only when launching the recurring event. Requires `DealersHeists` already deployed. This deploys
`DealersBankHeist`, authorizes it on Core, **repoints `PaymentHandler.bankVault` from the treasury to
the event vault**, and ships it **paused**.

```bash
source .env && forge script script/deploy/DeployBankHeist.s.sol:DeployBankHeist --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

Then, when ready to run the event:

```bash
# 1. (optional) Migrate ETH that accrued at the treasury bankVault into the new event vault — send to its receive().
BANK_HEIST=$(jq -r .bankHeist script/data/deployments/testnet.json)
# cast send $BANK_HEIST --value <amount> --rpc-url $ABSTRACT_TESTNET_RPC --account <treasury>

# 2. Unpause to open entries.
cast send $BANK_HEIST "unpause()" --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

Keeper loop off-chain per cycle: `requestDraw` → `snapshotWeights` (paginated, repeat until `weightCursor == entryCount`) → wait for the Pyth seed → `settle`. Freezing weights before the seed arrives is what blocks post-close activity grinding.

### Notes

- **Re-runnable**: all three scripts are idempotent (check state before each setter).
- **`bankVault` swap**: §15.3's `setBankVault` moves the 80% bank-fee share from the treasury to the event vault. ETH already accrued at the treasury stays there — migrate it separately.
- **Storage-layout**: `DealersBankHeist` is deployed fresh in §15.3 — fine since it has no prior deployment.
- **Not in `DeployAll` / `deploy-all.sh`** by design — deploy this module on its own cadence.

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

- **Address persistence**: all deploy scripts save to `script/data/deployments/testnet.json`. Scripts load from JSON first, falling back to `.env`.
- **Idempotent**: DeployAll skips contracts with existing addresses. SetupWiring checks state before calling setters. Safe to re-run.
- **Two build modes**: game contracts require `--zksync`, renderers must NOT use `--zksync` (SSTORE2/EXTCODECOPY).
- **`--skip` flags**: always pass `--skip "RendererSVG" --skip "UploadTraits"` with `--zksync` to prevent compilation errors.
- **FileStore**: `0xFe1411d6864592549AdE050215482e4385dFa0FB` — same on mainnet and testnet.
- **Fresh deploy**: delete `script/data/deployments/testnet.json` before running DeployAll.

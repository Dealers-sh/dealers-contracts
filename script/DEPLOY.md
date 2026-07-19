# Operations & Redeploy Runbook — Abstract (Mainnet + Testnet)

Mainnet is live. There is no full-deploy path anymore — `DeployAll.s.sol` was removed (it lives in
git history if a from-scratch environment is ever needed). What remains is a **per-contract
redeploy model**: every contract has its own script in `script/deploy/` that deploys a new
instance and then re-wires **exactly the edges that touch it** — inbound references, outbound
references, and authorizations — reading on-chain state before every setter so only stale edges
broadcast.

The wiring graph itself lives in one place: [base/Wiring.s.sol](base/Wiring.s.sol) (`WiringBase`,
one `_wireX()` per contract). Deploy scripts call their own wire set;
[setup/SetupWiring.s.sol](setup/SetupWiring.s.sol) calls all of them as a global drift check.

## Conventions

- Addresses persist in `script/data/deployments/{NETWORK}.json` (`testnet` = chain 11124,
  `mainnet` = chain 2741, derived from `block.chainid`). Deploy scripts load from JSON first,
  fall back to `.env`, and save back after deploying. Do not put contract addresses in `.env`.
- `--rpc-url` accepts the `foundry.toml` aliases `abstract-testnet` and `abstract` (mainnet).
- Wallet/config env vars are network-prefixed: `MAINNET_<KEY>` (required on mainnet),
  `TESTNET_<KEY>` (falls back to unprefixed). Keys: `DEV_WALLET`, `BANK_VAULT`,
  `ROYALTY_RECEIVER`, `PYTH_ENTROPY`, `APP_URL`.
- Game contracts build/deploy with `--zksync --skip "RendererSVG" --skip "UploadTraits"`.
  Renderer/upload scripts using SSTORE2/EXTCODECOPY run in EVM mode (**no** `--zksync`).
- Examples below are testnet. For mainnet swap `abstract-testnet` → `abstract` and
  `NETWORK=testnet` → `NETWORK=mainnet`.

## Mainnet interlock

On chain 2741 every deploy script reverts unless `CONFIRM=<ContractName>` is set in the
environment — a fat-fingered script name can never broadcast a mainnet redeploy:

```bash
source .env && CONFIRM=DealersPVE forge script script/deploy/DeployPVE.s.sol:DeployPVE --rpc-url abstract --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

The guard applies to simulation too — run the dry-run (drop `--broadcast`) with the same
`CONFIRM` to preview exactly which wiring txs will fire.

---

## 1. Prerequisites

```bash
cast wallet import dealersKeystore --interactive     # one-time keystore

forge build                                          # EVM (renderers)
forge build --zksync --skip "RendererSVG" --skip "UploadTraits"   # zkSync (game)
```

---

## 2. Redeploying a contract

General procedure — same for every contract:

```bash
# 1. Dry-run: shows the deploy + the exact wiring txs that would fire
source .env && CONFIRM=<ContractName> forge script script/deploy/Deploy<X>.s.sol:Deploy<X> --rpc-url abstract --account dealersKeystore --zksync --skip "RendererSVG" --skip "UploadTraits"

# 2. Broadcast (same command + --broadcast)

# 3. Run the REQUIRED follow-ups from the table below (the script also prints them)

# 4. Sanity check + source verify
forge script script/verify/VerifyConfig.s.sol:VerifyConfig --rpc-url abstract --zksync --skip "RendererSVG" --skip "UploadTraits"
source .env && NETWORK=mainnet ./script/verify-source.sh game
```

**Universal follow-up:** the app bundle embeds every contract address — after ANY redeploy,
rebuild and re-upload the gzip (§6).

### Per-contract runbook

| Contract | Script | Ctor deps | State abandoned on redeploy | Required follow-ups |
|----------|--------|-----------|------------------------------|---------------------|
| DealersDrugRegistry | `DeployDrugRegistry` | — | Drug definitions (balances/pricing survive via drugId) | `SetupDrugs` — **same order = same ids** |
| DealersAreaRegistry | `DeployAreaRegistry` | drugRegistry | Areas + pricing; dealer-in-area reverse index | `SetupAreas`. Prefer live admin fns (`createArea`, `configureAreaDrug`) over redeploy |
| DealersCore | `DeployCore` | — | **ALL dealer state** (rep/cash/drugs/heat/areas). Full game reset — last resort | `SetupTiers`, `SetupRebalance`, **redeploy Actions** (ctor-only core), new AreaChatGate + `setRoomGate` per room |
| DealersPaymentHandler | `DeployPaymentHandler` | devWallet, bankVault | None (pass-through) | If bank-heist event live: `setBankVault(bankHeist)` |
| DealersRandomness | `DeployRandomness` | — | Pending commits (in-flight rounds unresolvable) | Let pending rounds drain first |
| DealersNFT | `DeployNFT` | royaltyReceiver | **THE COLLECTION** (owners, reveals, mint state) — last resort | `RendererSVG.setDealersNFT` via cast (EVM), pool assignment before `setMintOpen` |
| DealersBoosts | `DeployBoosts` | core, nft, paymentHandler | Active paid boosts | `SetupBoosts` only if retuning |
| DealersPVE | `DeployPVE` | core, nft, areaRegistry | Pending rounds + lifetime PVE stats (feed achievements + seasons) | `SetupRebalance` only if retuning |
| DealersPVP | `DeployPVP` | core, nft, areaRegistry | Pending battles, cooldowns + lifetime PVP stats | `SetupRebalance` only if retuning |
| DealersClaims | `DeployClaims` | core, nft, pve, pvp | Ladder + **claimed flags — everyone can re-claim** | `SetupClaims` |
| DealersActions | `DeployActions` | core, nft, areaRegistry | In-flight action commits | — (also the mandatory follow-up to a Core redeploy) |
| DealersMulticall | `DeployMulticall` | core, pve, pvp, areaRegistry, drugRegistry | None (stateless views) | gzip rebuild only |
| DealersChatFactory | `DeployChatFactory` | nft | All rooms + message history | `SetupChat` |
| DealersHeists | `DeployHeists` | core, nft, randomness, paymentHandler, drugRegistry, PYTH_ENTROPY | **Jackpot ETH reserve** (stays in old contract), lifetime heist stats | `SetupHeists` only if retuning; migrate/fund jackpot |
| DealersBankHeist | `DeployBankHeist` | core, nft, pve, pvp, heists | **Event vault ETH** + season history | Ships PAUSED; migrate vault, `unpause` + `openSeason` |

Constructor-only references (cannot be re-pointed, force downstream redeploys):
- `DealersActions.core` → Core redeploy ⇒ Actions redeploy.
- `DealersAreaChatGate.core` → Core redeploy ⇒ deploy a new gate and `ChatFactory.setRoomGate`
  on every area room (`SetupChat` only gates newly created rooms).

Everything else is re-pointable: `DealersHeists.setContracts` and `DealersBankHeist.setContracts`
batch-repoint their deps (the wire sets sync them automatically; BankHeist's reverts while a
season is in flight — the wiring reports the skip, settle/cancel then re-run `SetupWiring`).

---

## 3. SetupWiring — global drift check

Re-asserts the FULL wiring graph (all 15 wire sets, incl. Heists, Multicall, BankHeist).
Idempotent: a clean deployment broadcasts nothing and prints all `ok`. Not needed after a
single-contract redeploy (those self-wire) — use it after a multi-contract session or as proof
nothing is stale.

```bash
source .env && forge script script/setup/SetupWiring.s.sol:SetupWiring --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

---

## 4. Config & tuning scripts (`script/setup/`)

All idempotent unless noted; the sim-calibrated economy ships in constructor defaults, so these
are re-assertion / live-tuning tools:

| Script | Touches | Purpose |
|--------|---------|---------|
| `SetupTiers` | Core | Canonical 10-tier reputation ladder (base/TiersConfig) |
| `SetupRebalance` | Core, PVE, PVP | CoreConfig (jail/fees), PVE odds + stake scaling, PVP config |
| `SetupBoosts` | Boosts | Boost tier retune |
| `SetupHeists` | Heists | Difficulties, stage tables, jackpot config |
| `SetupClaims` | Claims | Achievement ladder (base/ClaimsAchievements) — overwrites |
| `SetupAreas` | AreaRegistry | Create area ladder + pricing on a fresh registry |
| `SetupSeason` | AreaRegistry | Apply a season's area ladder (drug shuffle + fees + gates) to a live registry |
| `SetupDrugs` | DrugRegistry | Register the 11 drugs (order defines ids) |
| `SetupChat` | ChatFactory | WORLD + area rooms with a fresh AreaChatGate |
| `FixTiers` / `FixAreas` / `FixAchievements` | live correctives | Re-sync a live contract onto the canonical ladders |
| `GrantReward` | Core/Boosts | Owner grants (referral rewards etc.) |

Canonical config lives in `script/base/` (`TiersConfig`, `AreasConfig`, `ClaimsAchievements`,
`DrugIds`) — one source of truth shared by setup and corrective scripts.

### Patch migrations

One-shot scripts that migrate live prod state for a specific release live under `script/patch-<x-y-z>/`
with a `RUNBOOK.md` documenting the ordered apply. Recurring tools (`SetupSeason`, season lifecycle,
correctives) stay in `script/setup/`.

| Patch | Folder | Contents |
|-------|--------|----------|
| 1.1.0 | `script/patch-1-1-0/` | Bank Heist launch, area shuffle + fees, +2 areas (Warsaw/Moscow), +3 drugs (Slivo/Krokodil/Speed), bribe/bail → 0.0006 ETH. See `RUNBOOK.md`. |

---

## 5. Renderers

**DealerRendererSVG** uses SSTORE2/EXTCODECOPY — EVM mode, **no** `--zksync`. The script skips
the deploy if `rendererSvg` is already in the deployments JSON (delete the key to force):

```bash
source .env && forge script script/deploy/DeployRendererSVG.s.sol:DeployRendererSVG --rpc-url abstract-testnet --account dealersKeystore --broadcast
# then link on the zk side:
cast send $DEALERS_NFT "setContractRendererSVG(address)" $RENDERER_SVG --rpc-url abstract-testnet --account dealersKeystore
```

**DealerRendererHTML** is zkSync-native; the script deploys (or reuses), configures RPC/SVG
ref/gzip filename/App URL, and links to the NFT:

```bash
source .env && forge script script/deploy/DeployHtmlRenderer.s.sol:DeployHtmlRenderer --zksync --skip "RendererSVG" --skip "UploadTraits" --rpc-url abstract-testnet --account dealersKeystore --broadcast
```

A RendererSVG redeploy also means re-uploading the placeholder, traits, 1/1s, and re-running
trait assignment (§7) — budget for it.

---

## 6. App JS (gzip) — the routine live op

The bundle **embeds every contract address** from the deployments JSON, so this runs after any
redeploy. Two steps due to the dual VM:

```bash
cd ../dealers-app && ./build-single-file.sh          # copies to script/data/dealers.js.gz.b64

# Step 1: store in FileStore (EVM mode)
source .env && forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs --sig "upload()" --rpc-url abstract-testnet --account dealersKeystore --broadcast

# Step 2: set filename on the HTML renderer (zkSync mode; filename printed by step 1)
source .env && forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs --sig "setFilename(string)" "dealers-testnet-<ts>.js.gz" --zksync --skip "RendererSVG" --skip "UploadTraits" --rpc-url abstract-testnet --account dealersKeystore --broadcast
```

---

## 7. Trait pipeline (reference — only needed after an NFT/RendererSVG redeploy)

All EVM mode (no `--zksync`) unless noted. Pointers cache per network in
`script/data/{NETWORK}/pointers.json`.

```bash
# Placeholder (store + set on renderer)
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadPlaceholder()" --rpc-url abstract-testnet --account dealersKeystore --broadcast

# Trait palettes (store + register)
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadNormal()" --rpc-url abstract-testnet --account dealersKeystore --broadcast
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadSpecial()" --rpc-url abstract-testnet --account dealersKeystore --broadcast

# One-of-ones (store; repeat 0 5, 5 5, ... 40 5)
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadOneOfOnesRange(uint256,uint256)" 0 5 --rpc-url abstract-testnet --account dealersKeystore --broadcast --slow

# Assign combos to pool slots (must cover ALL 10000 slots BEFORE setMintOpen)
cd .. && python3 generateAssignments.py              # emits script/data/assignments.json
CHUNK=100 NETWORK=mainnet ./script/assign-traits.sh  # chunked batchSetTraits + 1/1s; idempotent
```

Reveal is per-token and permissionless: `resolve(tokenId)` / `resolveMany(uint256[])` after
`REVEAL_DELAY` blocks (see COMMANDS.md).

---

## 8. Verification

```bash
# Read-only config sanity: [OK] / [MISMATCH] / [NEEDS CONFIG] for every wiring slot
forge script script/verify/VerifyConfig.s.sol:VerifyConfig --rpc-url abstract-testnet --zksync --skip "RendererSVG" --skip "UploadTraits"

# Source verification on Abscan
source .env && ./script/verify-source.sh              # all | game | renderers
```

---

## Notes

- **Idempotent everywhere**: deploy-script wiring and SetupWiring read state before each setter;
  re-running is safe and broadcasts only stale edges.
- **Two build modes**: game contracts require `--zksync`; renderer/upload scripts using
  SSTORE2/EXTCODECOPY must NOT (and always pass `--skip "RendererSVG" --skip "UploadTraits"`
  alongside `--zksync`).
- **FileStore**: `0xFe1411d6864592549AdE050215482e4385dFa0FB` — same on mainnet and testnet.
- **`nftCtor`** in the deployments JSON records the placeholder NFT address baked into module
  constructors by the historical game-only deploy — verify-source.sh needs it to re-encode ctor
  args. Never delete it.
- **Testnet-only helpers**: `script/testnet/SetupTestnetPricing.s.sol` (10x fee reduction),
  `SetupTestnetDealers.s.sol`.

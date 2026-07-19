# Patch 1.1.0 — Deployment Runbook

Season-1 economy patch: launches Bank Heist, reshuffles the area economy, extends the ladder with
two new areas, adds two drugs, and trims the bribe/bail fees. Ship **testnet → verify → mainnet**
(same commands, swap `--rpc-url abstract-testnet` → `abstract-mainnet`). All scripts run with
`--account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"`.

One-shot migration scripts for this patch live in this folder (`script/patch-1-1-0/`). The recurring
tools they lean on (`SetupSeason`, `SetupBankHeistSeason`) stay in `script/setup/`; canonical config
(`AreasConfig`, `DrugIds`, `SetupDrugs`) stays in `script/base` + `script/setup`.

## Scope

| # | Change | Script | Status |
|---|--------|--------|--------|
| 1 | New drugs **Slivo** (id 12), **Krokodil** (id 13), **Speed** (id 14) | `patch-1-1-0/AddDrugs` | ✅ built |
| 2 | New areas **Warsaw** (id 8, gate 2,200), **Moscow** (id 9, gate 7,000) | `patch-1-1-0/AddAreas` | ✅ built |
| 3 | Season area shuffle + move fees (0.0006 default / 0.001 Tokyo+Dubai) | `setup/SetupSeason` | ✅ built + testnet-verified |
| 4 | Bribe **and** bail fee 0.001 → 0.0006 ETH | `patch-1-1-0/SetFees` | ✅ built |
| 5 | Bank Heist genesis season (fund vault, unpause, openSeason) | `setup/SetupBankHeistSeason` | ✅ built |

> **Fee plumbing:** bribe is `CoreConfig.bribeCopFee` (SetFees does a read-modify-write so every other
> CoreConfig field is preserved); bail is the **jail area (255) movement fee** — `payBail` reads
> `areaRegistry.getMovementFee(255)`. SetFees sets both.

## New content design — sim-validated

New ladder: Seoul 1,500 → **Warsaw 2,200** → Tokyo 3,000 → Dubai 5,500 → **Moscow 7,000**. Warsaw is
opened early as Eastern-Europe mid-game (large EE player base); Moscow stays the endgame above Dubai.
This leaves the Tokyo→Dubai gap open by design.

**Warsaw** (id 8) — gate 2,200, fee 0.0006. Products (3): **Slivo** + **Speed** (cheap source) · Heroin.
**Moscow** (id 9) — gate 7,000, fee 0.001. Products (3): **Slivo** + **Speed** (premium) · **Krokodil** (flex).

- **Slivo** (id 12, COMMON, base 8) — `120/100` Warsaw → `200/250` Moscow (long arbitrage run).
- **Speed** (id 14, UNCOMMON, base 30) — shared Warsaw/Moscow: `45/38` Warsaw → `90/110` Moscow.
- **Krokodil** (id 13, RARE, base 500) — Moscow-exclusive **buy-to-flex**: `500/50` (sell ≪ buy), a
  status hold, never a hustle/farm target.

Modeled in `economy_sim.py` (areas 8/9, drugs 12/13/14). Two findings baked in: (1) naive Krokodil
`500/450` gambler's-ruined edgeless F2P at Moscow's high stakes — `500/50` fixes it (the buy-AI ignores
it, F2P trades Slivo instead); (2) area id no longer tracks gate order (Warsaw gates below Tokyo/Dubai),
so `update_area` ranks by gate + affordability. Result: **all archetypes reach expected tiers with
healthy cash, pacing (d600, tier arrival) unchanged** (F2P Godfather @ ~3.6M; endgame whales still 41k rep).

Not modeled: the Warsaw→Moscow Slivo/Speed *shuttle* (the sim parks players, doesn't arbitrage-travel).
The parking evidence shows Moscow isn't a runaway earner, but a shuttle archetype is the one open check
if you want to confirm the runs don't beat Dubai farming.

## Deploy sequence

Run top-to-bottom on testnet, verify each, then repeat on mainnet. **Order matters:** drugs → areas →
season pricing (SetupSeason maintains all 9, so areas 8/9 must exist first).

**1. Register new drugs** — Slivo (12), Krokodil (13), Speed (14)
```
source .env && forge script script/patch-1-1-0/AddDrugs.s.sol:AddDrugs --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```
Self-asserts ids 12/13/14 + total 14. Verify: `cast call $DRUG_REGISTRY "getTotalDrugs()(uint256)"` → `14`.

**2. Create new areas** — Warsaw (8), Moscow (9) + drug books
```
source .env && forge script script/patch-1-1-0/AddAreas.s.sol:AddAreas --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```
Self-asserts ids 8/9, counts 3/3. Verify: `getTotalAreas()` → `9`.

**3. Apply season pricing + move-fee shuffle** — areas 1–7 rotation, and now maintains 8/9
```
source .env && forge script script/setup/SetupSeason.s.sol:SetupSeason --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```
Self-asserts exact drug count + prices + fees per area.

**4. Bribe + bail → 0.0006 ETH**
```
source .env && forge script script/patch-1-1-0/SetFees.s.sol:SetFees --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```
Self-asserts both. Verify: `core.config().bribeCopFee` and `getMovementFee(255)` → `600000000000000`.

**5. Bank Heist genesis season** — retune `duration`/`entryFee`/`VAULT_SEED` in the script for mainnet
(current values are the 9h testnet rehearsal; `zeroBaseline = true` for genesis)
```
source .env && forge script script/setup/SetupBankHeistSeason.s.sol:SetupBankHeistSeason --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```
Verify: `paused()` → `false`; `seasonCount()` incremented; vault ≥ seed.

## Post-deploy checks (read-only, per network)

- Drugs: `getTotalDrugs() == 14`.
- Areas: `getTotalAreas() == 9`; drug counts 3 for all ids 1–9.
- Move fees: `0 / 0 / 0.0006 / 0.0006 / 0.0006 / 0.001 / 0.001 / 0.0006 / 0.001` (Manhattan…Moscow).
- Bail `getMovementFee(255) == 0.0006e18`; bribe `config().bribeCopFee == 0.0006e18`.
- Gates: 0/250/500/800/1500/3000/5500 + 2200 (Warsaw) + 7000 (Moscow).
- Bank Heist: unpaused, season open.

## Rollback

- **Fees** (bribe/bail/move): re-run the setter with the prior value — fully reversible.
- **Drug placement**: `removeAreaDrug(areaId, drugId)` prunes a bad slot.
- **Areas/drugs are additive**: `createArea`/`createDrug` can't be undone — deactivate instead
  (area `isActive=false`, drug `isActive=false`) if a new id must be pulled.

[validate against baseline]: ../../test/simulation/economy_sim.py

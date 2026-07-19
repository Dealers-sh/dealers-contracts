---
name: end-season
description: End a DealersBankHeist season — freeze every entrant's score, then settle the pot to open claims. Use when the user wants to end/close/settle a bank-heist season, run freezeScores, or asks what to do after a season closes.
---

# End a Bank Heist Season

Runs the post-close keeper lifecycle for `DealersBankHeist`: **freezeScores → settle**. Both calls
are permissionless (any funded signer, not just the owner). Claims stay player-driven; rolling the
next season is a separate `SetupBankHeistSeason` run.

## Lifecycle it covers

```
close (auto, at closesAt)
  └─ freezeScores(id, N)   window (close, close+freezeWindow]   loops until every entrant frozen
        └─ settle(id)      window (close, close+refundTimeout]   reserves pot = potBps × availableVault, opens claims
```

Not covered here (by design): `claim(id, tokenId)` (players pull their own share, 30-day window),
`sweepExpired(id)` (dust back to vault after the claim window), and `openSeason` (next season).

## How to run

Always **preview first** (no `--broadcast` → simulates and prints the phase + projected outcome,
sends nothing), then execute. Set `SEASON=<id>` to target an earlier season (default = latest).

**Preview (testnet):**
```bash
source .env && forge script script/setup/EndBankHeistSeason.s.sol:EndBankHeistSeason --rpc-url abstract-testnet --zksync --skip "RendererSVG" --skip "UploadTraits"
```

**Execute (testnet):**
```bash
source .env && forge script script/setup/EndBankHeistSeason.s.sol:EndBankHeistSeason --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG" --skip "UploadTraits"
```

For mainnet swap `--rpc-url abstract` (no `CONFIRM` gate — that only guards contract redeploys, not this keeper).

Idempotent: safe to re-run. A settled or skipped season short-circuits; a partially-frozen season
resumes from the cursor. `freezeScores` pages 250 entrants per tx, looping until fully frozen.

## Reading the output

The script logs the season phase and what it did. Interpret and report:

- **`NOT CLOSED yet`** — season is still live; report the seconds remaining, do nothing.
- **`SETTLED | pot`** — done. Report pot (wei → ETH) and totalScore. Payouts are now claimable
  (`claim`) for `claimWindow` seconds; pari-mutuel: `score / totalScore × pot`.
- **`ALREADY SETTLED`** — nothing to do; report the existing pot.
- **`SKIPPED` / `BELOW MIN ENTRANTS` / `totalScore 0 → skipped`** — no payout; entrants reclaim
  their $CASH via `claimRefund`.
- **`FREEZE WINDOW CLOSED` / `SETTLE WINDOW CLOSED`** — a keeper deadline was missed; the season
  is refund-only. Flag this loudly — it means the pot won't distribute.

## After settling

- Tell players they can `claim(seasonId, tokenId)` (pays the current NFT owner) within the claim window.
- To start the next season, run `SetupBankHeistSeason` with `ZERO_BASELINE = false` (genesis mode is
  season-1 only; later seasons score delta-vs-entry). It only opens once the prior season is terminal.
- After the claim window expires, anyone may `sweepExpired(seasonId)` to return the unclaimed remainder to the vault.

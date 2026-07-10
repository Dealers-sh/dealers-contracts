---
name: referral-rewards
description: Process pending referral reward claims — check on-chain whether an attempt reset or boost (tier 1-4) can be applied to a dealer tokenId, produce the grant command, and mark the claim fulfilled in Supabase. Use when the user asks to process, check, or fulfill referral claims/rewards.
---

# Referral Reward Fulfillment

Referral claims live in Supabase. Each claim grants a dealer (NFT tokenId) either an
**attempt reset** or a **boost tier 1-4** (1 Grinder / 2 Hustler / 3 Kingpin / 4 Godfather).
Rewards are granted on-chain by the owner wallet, then the claim is marked fulfilled via
`resolve_referral_claim(<claim_id>, 'fulfilled', '<tx_hash>')`.

## Workflow

### 1. Get pending claims

Table is `referral_claims` with columns `id` (claim id for resolve), `address`, `reward`
(`reset` = attempt reset, `boost_t1`..`boost_t4` = boost tier), `cost`, `target_dealer_id`
(the NFT tokenId), `status`, `fulfilled_tx`, `created_at`, `resolved_at`.

```sql
select * from referral_claims where status = 'pending' order by created_at;
```

Run it via the Supabase MCP server if connected; otherwise print it for the user to run in
the Supabase dashboard and have them paste the rows back.

### 2. Check eligibility (read-only, safe to run)

For each claim:

```bash
bash .claude/skills/referral-rewards/check-claim.sh <tokenId> attempts
bash .claude/skills/referral-rewards/check-claim.sh <tokenId> boost <tierId>
```

Exit 0 = APPLY (prints the exact `cast send`), exit 2 = HOLD. The rules it enforces:

- **Attempt reset**: only when effective attempts are 0 (the grant refills to max, so granting
  with attempts remaining wastes it). Otherwise HOLD until depleted. Attempts also auto-refill
  at midnight UTC — that is fine, apply as soon as they hit 0 regardless.
- **Boost**: no active boost → apply. Active boost → apply only if the claim tier's live price
  is strictly higher than the active tier's (mirrors `_canUpgradeBoost`; a better tier extends
  from the current expiry, no time lost). Same or lower tier → HOLD until the reported expiry
  (`purchaseBoost` would revert `BoostTierTooLow`).

### 3. Grant (user runs — keystore needs an interactive password)

Never broadcast yourself. Present the command(s) the script printed and ask the user to run
them and paste back the tx hash(es):

- Attempt reset: `cast send <claims> "grantReward(uint256,uint8,uint256,uint256)" <tokenId> 3 0 0 --rpc-url https://api.mainnet.abs.xyz --account dealersKeystore`
- Boost: `cast send <boosts> "purchaseBoost(uint256,uint256)" <tokenId> <tierId> --rpc-url https://api.mainnet.abs.xyz --account dealersKeystore` — free for the owner, no `--value` needed.
- Many attempt resets at once: `batchGrantReward(uint256[],uint8,uint256,uint256)` on Claims
  with `"[id1,id2,...]" 3 0 0`.
- **Never** `purchaseBoostBatch` for gifting — it silently skips dealers the caller doesn't own.

Addresses come from `script/data/deployments/mainnet.json` (`.claims`, `.boosts`, `.core`).

### 4. Verify and resolve

For each tx hash the user pastes back:

1. Verify it succeeded: `cast receipt <tx> status --rpc-url https://api.mainnet.abs.xyz` must be `1 (success)`.
2. Mark fulfilled in Supabase (MCP, or print the SQL):

```sql
select resolve_referral_claim(<claim_id>, 'fulfilled', '<tx_hash>');
```

Never resolve a claim without a successful tx hash for it.

### 5. Report

Summarize per claim: **applied** (tx + resolved) or **held** (reason + earliest retry —
boost expiry timestamp, or "when attempts depleted"). Held claims stay untouched in
Supabase; the user re-runs this skill later to re-check them.

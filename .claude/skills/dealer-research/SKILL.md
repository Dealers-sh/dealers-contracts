---
name: dealer-research
description: Research a player/dealer on Abstract mainnet — ETH spend, playstyle (PVE/PVP/heists), per-day growth, and whether they progress faster than the economy sim anticipates. Use when the user asks to research, profile, or investigate a dealer/tokenId/player/wallet, how much someone spends, what they play, or how fast they are growing.
---

# Dealer Research

Profile one player end-to-end: what they spend, what they play, how fast they climb the
reputation ladder, and how that compares to the pace `economy_sim.py` anticipates.

## Step 1 — pull the data

```bash
python3 .claude/skills/dealer-research/research-dealer.py <tokenId>
# or start from a wallet (picks its highest-rep dealer as target):
python3 .claude/skills/dealer-research/research-dealer.py --wallet 0x...
```

The script combines three sources (env overrides: `GRAPH_URL`, `RPC`, `EXPLORER`):

- **Goldsky subgraph** (`dealers/1.0.1`) — dealer fleet, PVE games, actions, boosts, heists,
  PVP battles, achievement claims, per-day rep trajectory.
- **Block-explorer API** — every wallet tx to a game contract (addresses from
  `script/data/deployments/mainnet.json`), labeled by function selector, with real ETH values.
  This is the only way to see **`purchaseAttemptReset`: it emits no event**, so paid attempt
  refills are invisible to the subgraph.
- Selector table is hardcoded in the script; if a module is redeployed with changed
  signatures, re-derive with `cast sig "<signature>"` and update it.

## Step 2 — read the live economy config

Deployed config can drift from source constructors — never benchmark against source values.

```bash
for i in 3 4 5 6 7 8; do cast call $(jq -r .core script/data/deployments/mainnet.json) "reputationTiers(uint256)(uint256,int16,int16,int16,int16,string)" $i --rpc-url https://api.mainnet.abs.xyz; echo ---; done
cast call $(jq -r .boosts script/data/deployments/mainnet.json) "boostTiers(uint256)(uint256,uint64,uint8,uint8,uint8,bool,uint8,bool)" <tierId> --rpc-url https://api.mainnet.abs.xyz
cast call $(jq -r .pve script/data/deployments/mainnet.json) "winChance()(uint8)" --rpc-url https://api.mainnet.abs.xyz
```

Tier fields: `(minReputation, winBonus, tieBonus, lossPenalty, repCap, name)`.
Boost fields: `(price, duration, drugMult, repMult, extraAttempts, freeMovement, cashMult, active)`.
Attempts/day = 5 base + boost `extraAttempts`. Canonical upper repCaps are 72/80/90/100
(Consigliere→Godfather, see `script/setup/FixTiers.s.sol`) — flag it if mainnet differs.

## Step 3 — benchmark against the sim

`test/simulation/economy_sim.py` (gitignored but present locally). Override the FINAL2 ladder
caps with the **live on-chain caps** from step 2, pick the sim boost tier whose
`extra_attempts` matches the player's live boost, then compare median tier-arrival days:

```bash
cd test/simulation && python3 -c "
from economy_sim import make_candidates, report_detail
from copy import deepcopy
cfg = deepcopy(make_candidates()['FINAL2'])
for i, cap in [(5, 72), (6, 80), (7, 90), (8, 100)]:  # live caps from step 2
    cfg.tiers[i].cap = cap
report_detail(cfg, 'pve', 3, days=60, trials=200)  # boost index: 0=F2P .. match by extra_attempts
report_detail(cfg, 'pve', 0, days=60, trials=200)  # F2P baseline
"
```

Player's actual pace: days from `minted` to each threshold in the script's per-day table
(thresholds 600/1500/3000/5500/10000/22000 = Soldier/Capo/Consigliere/Underboss/Don/Godfather).

## Interpreting

Lead the report with: total ETH spend, dominant game mode, and actual-vs-anticipated days to
their current rank. Known reasons a player beats the sim (check each, in this order):

1. **Attempt resets** — 0.001 ETH per full refill, uncapped per day, not modeled in the sim.
   The single biggest legitimate accelerator; count them per day from the script output.
2. **Cap-staking** — compare `avgStake` per day to the cap-stake (`repCap × divisor`, where
   divisor = `50 + totalRep × 2500/10000`). Achievement-cash milestones bankroll this; a player
   who claims them same-day is never stake-limited (sim players arrive much poorer).
3. **Zero downtime** — bribes on heat, instant bail, all daily attempts consumed.
4. **Luck** — PVE win rate vs the configured `winChance` (25%); flag sustained deviation over
   a large sample as worth a second look.
5. **Owner grants** — nonzero `grants=` in the fleet listing means Claims-granted rewards
   (referral program etc.); discount those from "organic" growth.

Reference case: dealer #38 hit Underboss day 10.6 vs sim day ~23 (Kingpin PVE archetype) via
resets + cap-staking + luck — see memory `project_dealer38_case_study`.

Caveats: mainnet-only; explorer scan caps at 10k txs (script warns if the wallet is too
hyperactive to scan back to mint); PVE games are commit+resolve tx pairs; sim boost durations
may not match live tiers — match on `extra_attempts`, not name.

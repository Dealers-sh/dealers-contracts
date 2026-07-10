---
name: jackpot-status
description: Check the DealersHeists jackpot pool on Abstract mainnet — current reserve, solvency, daily trend, payouts and funding. Use when the user asks about the jackpot balance, jackpot pool health, or whether the jackpot is growing or shrinking.
---

# Jackpot Pool Status

Run the bundled script and summarize the output:

```bash
bash .claude/skills/jackpot-status/check-jackpot.sh
```

Optional first argument is the lookback window in days (default 7), e.g. `check-jackpot.sh 14`. Set `RPC` to override the RPC URL (default `https://api.mainnet.abs.xyz`).

The script reads the heists address from `script/data/deployments/mainnet.json` and reports:

- **Current state**: contract ETH balance, `jackpotReserve` (free reserve backing future jackpots), `escrowedJackpot` (reserved for in-flight Pyth requests), `totalJackpotOwed` (won but unclaimed), and `backedEth` (sum of the three — must be ≤ balance for solvency).
- **Daily trend**: `jackpotReserve` sampled once per day over the window (historical `eth_call` at calibrated block heights).
- **Events**: `JackpotWon` count + total paid, and any `ReserveFunded` owner top-ups in the window.

When summarizing:

1. Lead with the verdict: growing, shrinking, or flat — compare the oldest sample to the newest, and compare against the seed (0.1 ETH funded 2026-06-30).
2. Flag insolvency immediately if `backedEth` > balance.
3. Note payout velocity (jackpots won vs. reserve delta) so inflow from the 60% ETH add-on share can be judged against outflow.
4. Ignore small dips followed by recovery — the pool is designed to oscillate around its seed level.

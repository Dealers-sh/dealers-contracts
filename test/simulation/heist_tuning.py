#!/usr/bin/env python3
"""
Heist economy tuning sweep (analytical, exact — no Monte-Carlo needed for means).

Mirrors the stage math in src/core/DealersHeists.sol and the deployed economy config
(SetupTiers / SetupBoosts / SetupAreas). Fast sweeps over difficulty stakes, pot-multiplier
trim, and jackpot trigger/reserve to find settings that land cash + ETH in ECONOMY_DESIGN 5.1.

Run:  python3 test/simulation/heist_tuning.py
"""

# ----------------------------------------------------------------------------
# Heist stage tables (DealersHeists constructor defaults)
# ----------------------------------------------------------------------------
CLEAN   = [0.72, 0.62, 0.52, 0.42, 0.32]
SETBACK = [0.20, 0.28, 0.33, 0.38, 0.40]
BUST    = [0.08, 0.10, 0.15, 0.20, 0.28]
KEEP    = [0.50, 0.45, 0.40, 0.35, 0.30]
POT_MIN = [10000, 18000, 30000, 52000, 100000]   # bps of stake
POT_MAX = [14000, 28000, 46000, 78000, 160000]
REP_REWARD = [0, 2, 4, 7, 12]

# Legacy multiplier-jackpot tables — kept only to drive the historical sweeps in [4]/[5].
# The shipped economy is now the compensation model in [7] (sub-1x partial refund).
JACK_TRIGGER = [1, 2, 3, 4, 5]                    # percent
JACK_MIN = [12000, 15000, 20000, 30000, 50000]    # bps of add-on
JACK_MAX = [30000, 45000, 70000, 120000, 200000]
ETH_ADD_ON = 0.001
MIN_CASH_STAGE = 2  # stage index 1 (0-based) = earliest cashable

# Boosts (SetupBoosts): cashMult %, extraAttempts
BOOSTS = {
    "none":      (100, 0),
    "Grinder":   (125, 2),
    "Hustler":   (150, 3),
    "Kingpin":   (175, 6),
    "Godfather": (225, 7),
}
BASE_ATTEMPTS = 5
VARIATION = 0.8  # E[attempts] = full * (0.7*1 + 0.2*0.5 + 0.1*0)

# Convex tiers (SetupTiers): name -> minRep
TIERS = [
    ("Outsider", 0), ("Associate", 100), ("Dealer", 250), ("Soldier", 600),
    ("Capo", 1500), ("Consigliere", 3000), ("Underboss", 5500), ("Don", 10000),
    ("Godfather", 22000), ("Legend", 50000),
]

# ECONOMY_DESIGN 5.1 daily-net (boosted) bands per tier
DAILY_BAND = {
    "Dealer": (500, 1500), "Soldier": (2000, 5000), "Capo": (5000, 15000),
    "Consigliere": (15000, 40000), "Underboss": (30000, 80000),
    "Don": (60000, 150000), "Godfather": (100000, 300000),
}

def avg_pot_mult(pot_scale_bps):
    """Average gross pot multiple per stage (x), scaled by pot_scale_bps/10000."""
    return [((POT_MIN[i] + POT_MAX[i]) / 2 / 10000) * (pot_scale_bps / 10000) for i in range(5)]

def reach(target_idx):
    """P(reach & be committing stage i), for i in 0..target_idx. reach[0]=1."""
    r = [1.0] * (target_idx + 1)
    for i in range(1, target_idx + 1):
        r[i] = r[i - 1] * CLEAN[i - 1]
    return r

def unstaked_ev(target_idx, pot_scale_bps=10000):
    """Gross pot EV as a multiple of stake for cash-out at stage (target_idx+1)."""
    mult = avg_pot_mult(pot_scale_bps)
    r = reach(target_idx)
    ev = 0.0
    for i in range(target_idx + 1):
        ev += r[i] * SETBACK[i] * mult[i] * KEEP[i]     # setback partial payout at stage i
    ev += r[target_idx] * CLEAN[target_idx] * mult[target_idx]  # clean cash at target
    return ev

def bust_prob(target_idx):
    r = reach(target_idx)
    return sum(r[i] * BUST[i] for i in range(target_idx + 1))

def best_cashout(pot_scale_bps=10000):
    """Return (best_target_idx, ev) maximizing EV among cashable stages (>= MIN_CASH_STAGE)."""
    best = (1, 0.0)
    for t in range(MIN_CASH_STAGE - 1, 5):   # idx 1..4 == stage 2..5
        ev = unstaked_ev(t, pot_scale_bps)
        if ev > best[1]:
            best = (t, ev)
    return best

def net_per_run(stake, cash_mult, ev):
    return stake * (ev * cash_mult / 100 - 1)

def jackpot_return(target_idx, trigger_scale, reserve_cut_bps):
    """(player_return_fraction, reserve_net_per_bet, solvent)."""
    r = reach(target_idx)
    jmult = [(JACK_MIN[i] + JACK_MAX[i]) / 2 / 10000 for i in range(5)]
    ev_eth = 0.0
    for i in range(target_idx + 1):
        trig = JACK_TRIGGER[i] / 100 * trigger_scale
        ev_eth += r[i] * CLEAN[i] * trig * jmult[i] * ETH_ADD_ON
    reserve_in = ETH_ADD_ON * reserve_cut_bps / 10000
    return ev_eth / ETH_ADD_ON, reserve_in - ev_eth, (reserve_in - ev_eth) > 0

def tier_of(rep):
    name = TIERS[0][0]
    for n, mr in TIERS:
        if rep >= mr:
            name = n
    return name

# ----------------------------------------------------------------------------
print("=" * 78)
print(" HEIST TUNING SWEEP  (analytical, exact)")
print("=" * 78)

# 1) Unstaked EV by cash-out target & pot trim
print("\n[1] Unstaked gross-pot EV (x stake) by cash-out target & pot trim")
print("    target:     stage2  stage3  stage4  ride5   | bust@best")
for ps in (10000, 8000, 6000):
    evs = [unstaked_ev(t, ps) for t in range(1, 5)]
    bt, _ = best_cashout(ps)
    print(f"    pot {ps//100:3d}% :  " + "  ".join(f"{e:5.3f}" for e in evs)
          + f"   | best=stage{bt+1} bust={bust_prob(bt)*100:4.1f}%")

# 2) Candidate configs: gates + stakes, evaluate per-tier daily net vs 5.1 (Kingpin split play)
print("\n[2] Candidate configs — per-tier daily net, Kingpin boost, split=4 actual runs/day")
print("    (PASS = inside 5.1 band, HI/LO = outside)")

SPLIT_RUNS = 4   # actual heist runs/day for an engaged player (rest -> PVE/PVP)
ALLIN_KINGPIN = round((BASE_ATTEMPTS + BOOSTS["Kingpin"][1]) * VARIATION)  # ~9

candidates = {
    "A: gates 600/1500/5500, stake 600/2500/10000, pot100": {
        "gates": [600, 1500, 5500], "stakes": [600, 2500, 10000], "pot": 10000},
    "B: gates 600/1500/5500, stake 800/3500/14000, pot 80": {
        "gates": [600, 1500, 5500], "stakes": [800, 3500, 14000], "pot": 8000},
    "C: gates 600/3000/10000, stake 600/4500/17000, pot100": {
        "gates": [600, 3000, 10000], "stakes": [600, 4500, 17000], "pot": 10000},
}

def pick_difficulty(rep, gates):
    d = -1
    for i, g in enumerate(gates):
        if rep >= g:
            d = i
    return d

for label, cfg in candidates.items():
    print(f"\n  {label}")
    _, ev = best_cashout(cfg["pot"])
    cash_mult = BOOSTS["Kingpin"][0]
    for name, minrep in TIERS:
        if name not in DAILY_BAND:
            continue
        d = pick_difficulty(minrep, cfg["gates"])
        if d < 0:
            print(f"    {name:12s} (rep {minrep:5d}): no heist access")
            continue
        stake = cfg["stakes"][d]
        npr = net_per_run(stake, cash_mult, ev)
        daily = npr * SPLIT_RUNS
        lo, hi = DAILY_BAND[name]
        flag = "PASS" if lo <= daily <= hi else ("HI" if daily > hi else "LO")
        print(f"    {name:12s} (rep {minrep:5d}): D{d} stake {stake:6d}  "
              f"net/run {npr:8.0f}  daily {daily:9.0f}  band {lo}-{hi}  [{flag}]")

# 3) Whale ceiling check: Godfather, Godfather-boost, all-in vs split, 30d
print("\n[3] Godfather whale check (Godfather boost, 30 days)")
for label, cfg in candidates.items():
    _, ev = best_cashout(cfg["pot"])
    cm = BOOSTS["Godfather"][0]
    stake = cfg["stakes"][-1]
    npr = net_per_run(stake, cm, ev)
    allin = round((BASE_ATTEMPTS + BOOSTS["Godfather"][1]) * VARIATION)  # ~10
    d_allin = npr * allin
    d_split = npr * SPLIT_RUNS
    print(f"  {label[:1]}: stake {stake:6d}  net/run {npr:8.0f}  "
          f"split 30d {d_split*30/1e6:5.2f}M  all-in({allin}/d) 30d {d_allin*30/1e6:5.2f}M")
print("  5.1 Godfather: 1-5M typical / 10M whale ceiling")

# 4) Jackpot generosity vs solvency
print("\n[4] Jackpot tuning — player return vs reserve solvency")
print("    (return shown for ride@5 = max exposure; must stay < reserve cut %)")
for scale, cut, lab in [(1.0, 4000, "current x1.0 / 40%"),
                        (2.0, 4000, "x2.0 / 40%"),
                        (2.5, 4000, "x2.5 / 40%"),
                        (3.0, 4000, "x3.0 / 40%"),
                        (3.5, 6000, "x3.5 / 60%")]:
    ret5, net5, solv5 = jackpot_return(4, scale, cut)
    ret3, _, _ = jackpot_return(2, scale, cut)
    print(f"    {lab:18s}: ride@5 {ret5*100:4.1f}%  cash@3 {ret3*100:4.1f}%  "
          f"reserve/bet {net5*1e6:+7.1f}e-6 ETH  {'SOLVENT' if solv5 else 'DEPLETES'}")

# 5) Integer jackpot triggers (what actually goes in setJackpotConfig)
print("\n[5] Integer jackpot trigger presets (triggerPct must be int)")
for preset, label in [([1,2,3,4,5], "current"),
                      ([3,5,8,10,13], "x2.5-ish (recommended)"),
                      ([2,4,6,8,10], "x2.0 clean")]:
    saved = JACK_TRIGGER
    JACK_TRIGGER = preset
    ret5, net5, solv5 = jackpot_return(4, 1.0, 4000)
    ret3, _, _ = jackpot_return(2, 1.0, 4000)
    JACK_TRIGGER = saved
    print(f"    {str(preset):20s} {label:24s}: ride@5 {ret5*100:4.1f}%  "
          f"cash@3 {ret3*100:4.1f}%  reserve/bet {net5*1e6:+6.1f}e-6  {'SOLVENT' if solv5 else 'DEPLETES'}")

# 6) Supply-run realization by area (sell/base ratio of the rare drug + common availability)
print("\n[6] Supply-run realization by area (drugs paid at base, sold at area price)")
AREA = {  # area: list of (drugId, rarity 0/1/2, base, sell)
    "Hong Kong": [(9,0,18,18),(10,1,25,25),(8,2,150,160)],
    "Seoul":     [(9,0,18,7),(10,1,25,12),(11,2,200,75)],
    "Tokyo":     [(9,0,18,20),(10,1,25,26),(11,2,200,160)],
    "Dubai":     [(5,1,10,20),(6,2,100,200),(8,2,150,240)],
}
for area, drugs in AREA.items():
    rarities = {r for _, r, _, _ in drugs}
    has_common = 0 in rarities
    rare = [(b, s) for _, r, b, s in drugs if r == 2]
    ratio = sum(s for _, s in rare) / sum(b for b, _ in rare)
    print(f"    {area:10s}: rare sell/base {ratio:4.2f}x  common drug: {'yes' if has_common else 'NO -> common% leaks to cash'}")

# 7) Compensation model (SHIPPED) — frequent partial refund instead of a rare multiple.
#    Surfaced to players as a "compensation", not a jackpot. Fires on a cleared stage off the
#    stage reveal; the amount stays Pyth-VRF-backed in a tight [0.7,0.9]x band. Solvency must
#    cover payout + the per-fire Pyth fee from the 40% reserve cut.
print("\n[7] Compensation model (shipped: flat 25% trigger, 0.7-0.9x add-on)")
PYTH_FEE_ETH = 0.000024006155          # Abstract live entropy fee, paid per fire, non-refundable
ADDON_ETH = 0.001
FEE_FRAC = PYTH_FEE_ETH / ADDON_ETH    # ~2.40% of the add-on
COMP_PAY = 0.80                        # avg of the 0.7-0.9 band
RESERVE_CUT = 0.40

def comp_fire_prob(trig_pct, target_idx):
    """P(compensation fires at least once) for a run resolving clean through stage 0..target_idx.
       Fires at most once; trigger rolled only on a CLEAN resolution."""
    r = reach(target_idx)
    p_not, p_fire = 1.0, 0.0
    t = trig_pct / 100
    for i in range(target_idx + 1):
        p_fire += r[i] * CLEAN[i] * t * p_not
        p_not *= (1 - CLEAN[i] * t)
    return p_fire

print(f"    Pyth fee {FEE_FRAC*100:.2f}% of add-on -> effective cost/fire {(COMP_PAY+FEE_FRAC)*100:.1f}%; "
      f"depletes above ~{RESERVE_CUT/(COMP_PAY+FEE_FRAC)*100:.0f}% per-run fire")
print("    trig%   fire% cash@3  fire% ride@5   reserve net/bet")
for t in (20, 25, 30, 40):
    pf3 = comp_fire_prob(t, 2)
    pf5 = comp_fire_prob(t, 4)
    net = (RESERVE_CUT - pf5 * (COMP_PAY + FEE_FRAC)) * ADDON_ETH
    mark = " <- shipped" if t == 25 else ""
    print(f"    {t:3d}%      {pf3*100:5.1f}%        {pf5*100:5.1f}%        "
          f"{net*1e6:+7.1f}e-6 ETH  [{'SOLVENT' if net > 0 else 'DEPLETES'}]{mark}")

# 8) ESCALATING HYBRID model — consolation floor + per-stage escalating moonshot.
#    Design intent: every cleared stage rolls the jackpot with an INCREASING payout band;
#    stages 1-2 are consolation-ish (can pay under the add-on), stage 3+ is always a net win
#    (min >= 1x), stage 5 reaches 1.5-20x. The contract rolls value UNIFORMLY in [min,max],
#    so a wide band's mean is its midpoint — the "usually small / rarely 20x" feel comes from
#    the STAGE ladder (one fire per run: an early fire latches the slot; surviving deep
#    unfired earns the big band). Triggers are FRONT-LOADED so shallow cash@3 play consumes
#    its reserve cut too, keeping the reserve lean instead of accumulating off conservative
#    players. Solvency: the reserve cut must cover expected payout + Pyth fee per fire (worst
#    case = ride@5, max exposure). Escrow per fire = maxMult x add-on, skipped (not lost) if
#    the reserve can't cover it -> seed requirement is just the deepest ceiling (0.02 ETH).
print("\n[8] ESCALATING HYBRID — consolation floor, escalating bands, front-loaded triggers")

def hybrid_eval(trig, mn, mx, target_idx, cut):
    """Exact EV with fire-once semantics. Returns (fire_prob, ev_frac_of_addon,
       p_big = P(roll >= 10x), reserve_net_eth). Validated against the Solidity
       Monte Carlo (test_staked_jackpot) to <0.5% — reach[i] already conditions on
       prior stages being clean, so no-prior-fire is just prod(1 - t_j)."""
    r = reach(target_idx)
    p_nofire, p_fire, ev, p_big = 1.0, 0.0, 0.0, 0.0
    for i in range(target_idx + 1):
        t = trig[i] / 100
        pf = r[i] * CLEAN[i] * t * p_nofire
        avg = (mn[i] + mx[i]) / 2 / 10000
        p_fire += pf
        ev += pf * avg
        if mx[i] >= 100000:
            p_big += pf * (mx[i] - 100000) / (mx[i] - mn[i])  # P(roll >= 10x) within band
        p_nofire *= (1 - t)
    net = (cut - ev - p_fire * FEE_FRAC) * ADDON_ETH
    return p_fire, ev, p_big, net

# (trigger%, minMultBps, maxMultBps, reserve cut)
PRESETS = {
    "flat compensation (old)": ([25, 25, 25, 25, 25],
                                [7000, 7000, 7000, 7000, 7000],
                                [9000, 9000, 9000, 9000, 9000], 0.40),
    "old generous (pre-flat)": ([3, 5, 8, 10, 13],
                                [12000, 15000, 20000, 30000, 50000],
                                [30000, 45000, 70000, 120000, 200000], 0.40),
    "hybrid @40% cut":         ([14, 16, 18, 20, 25],
                                [7000, 7000, 8000, 8000, 9000],
                                [9000, 15000, 40000, 120000, 200000], 0.40),
    "hot, thin margin @60%":   ([40, 35, 30, 30, 35],
                                [7000, 9000, 10000, 12000, 15000],
                                [11000, 24000, 58000, 125000, 200000], 0.60),
    "CHOSEN (SetupHeists)":    ([40, 34, 30, 32, 40],
                                [7000, 9000, 10000, 12000, 15000],
                                [10000, 23000, 55000, 120000, 200000], 0.60),
}

print("    preset                    fire%@5  ret@3  ret@5  P(>=10x)/run  reserve net/bet")
for name, (trig, mn, mx, cut) in PRESETS.items():
    pf5, ev5, pbig5, net5 = hybrid_eval(trig, mn, mx, 4, cut)
    _, ev3, _, _ = hybrid_eval(trig, mn, mx, 2, cut)
    print(f"    {name:25s} {pf5*100:5.1f}%  {ev3*100:5.1f}%  {ev5*100:5.1f}%   "
          f"{pbig5*100:6.3f}%     {net5*1e6:+7.1f}e-6 ETH  [{'SOLVENT' if net5 > 0 else 'DEPLETES'}]")

print("\n    Blended reserve accrual (strategy mix 40% cash@3 / 25% cash@4 / 35% ride@5):")
for name, (trig, mn, mx, cut) in PRESETS.items():
    _, _, _, n3 = hybrid_eval(trig, mn, mx, 2, cut)
    _, _, _, n4 = hybrid_eval(trig, mn, mx, 3, cut)
    _, _, _, n5 = hybrid_eval(trig, mn, mx, 4, cut)
    blend = 0.40 * n3 + 0.25 * n4 + 0.35 * n5
    print(f"    {name:25s} {blend*1e6:+6.1f}e-6/bet  ({blend*100000:+.2f} ETH per 100k games)")

print("\n    Per-stage detail (P(fire first here | ride@5), avg pay):")
for name, (trig, mn, mx, cut) in PRESETS.items():
    pf5, ev5, pbig5, net5 = hybrid_eval(trig, mn, mx, 4, cut)
    if net5 <= 0 or "(old" in name or "pre-flat" in name:
        continue
    r = reach(4)
    p_nofire = 1.0
    parts = []
    for i in range(5):
        t = trig[i] / 100
        pf = r[i] * CLEAN[i] * t * p_nofire
        parts.append(f"s{i+1} {pf*100:4.1f}%@{(mn[i]+mx[i])/2/10000:5.2f}x[{mn[i]/10000:.1f}-{mx[i]/10000:.0f}]")
        p_nofire *= (1 - t)
    print(f"    {name:25s} " + "  ".join(parts))

print("\n" + "=" * 78)

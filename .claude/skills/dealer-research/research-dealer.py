#!/usr/bin/env python3
"""Profile a dealer's on-chain behavior: spend, playstyle, growth trajectory.

Usage:
    python3 research-dealer.py <tokenId>
    python3 research-dealer.py --wallet 0x...

Env overrides: GRAPH_URL, RPC, EXPLORER.
Mainnet-only (the subgraph indexes mainnet).
"""
import collections
import datetime
import json
import os
import sys
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))

GRAPH_URL = os.environ.get(
    "GRAPH_URL",
    "https://api.goldsky.com/api/public/project_cmr9ocvnd54rg01z9abw0henh/subgraphs/dealers/1.0.1/gn",
)
RPC = os.environ.get("RPC", "https://api.mainnet.abs.xyz")
EXPLORER = os.environ.get("EXPLORER", "https://block-explorer-api.mainnet.abs.xyz")
UA = {"user-agent": "curl/8.4.0"}  # Goldsky 403s the default python UA

# Selectors of every player-facing state-changing function. Re-derive with
# `cast sig "<signature>"` if a module is redeployed with changed signatures.
SELECTORS = {
    "0x40c10f19": ("nft", "mint", None),
    "0x4f896d4f": ("nft", "resolve", 0),
    "0xd722c7f5": ("chatFactory", "postMessage", None),
    "0x2942e902": ("pve", "commitGame", 0),
    "0x75532478": ("pve", "resolveGame", None),
    "0x572c7a0c": ("actions", "bribeCop", 0),
    "0x861295ae": ("actions", "purchaseAttemptReset", 0),
    "0x9a7a0fd4": ("actions", "payBail", 0),
    "0xd6291e9e": ("actions", "travel", 0),
    "0xf32158eb": ("actions", "purchaseCash", 0),
    "0x09a5edb7": ("actions", "commitBreakout", 0),
    "0xb4be3c56": ("actions", "resolveBreakout", None),
    "0x1f56e296": ("actions", "commitWantedPoster", 0),
    "0x60a8ddd7": ("actions", "resolveWantedPoster", None),
    "0x0319baf2": ("actions", "sellDrop", 0),
    "0x0ed20e95": ("boosts", "purchaseBoost", 0),
    "0x245b2273": ("boosts", "purchaseBoostBatch", None),
    "0x9522aafd": ("heists", "startHeist", 0),
    "0x0356ed21": ("heists", "commitStage", None),
    "0x33411794": ("heists", "resolveStage", None),
    "0x5c7b79f5": ("heists", "cashOut", None),
    "0x61699707": ("heists", "abandonHeist", None),
    "0x26ec3eed": ("heists", "claimJackpot", 0),
    "0x3d4b46eb": ("pvp", "commitAttack", 0),
    "0x28e7a394": ("pvp", "resolveAttack", None),
    "0x6d7feb72": ("claims", "claimAchievements", 0),
}
CHOICE = {0: "DEAL", 1: "THREATEN", 2: "BAIL"}
OUTCOME = {0: "WIN", 1: "TIE", 2: "LOSS"}
HUSTLE = {0: "BUY", 1: "SELL"}


def gql(query):
    req = urllib.request.Request(
        GRAPH_URL, json.dumps({"query": query}).encode(),
        {"content-type": "application/json", **UA},
    )
    data = json.loads(urllib.request.urlopen(req).read())
    if "errors" in data:
        sys.exit(f"subgraph error: {data['errors']}")
    return data["data"]


def day(ts):
    return datetime.datetime.utcfromtimestamp(int(ts)).strftime("%Y-%m-%d")


def paginate(entity, where, fields):
    rows = []
    for skip in range(0, 6000, 1000):
        batch = gql(
            f"{{ {entity}(first: 1000, skip: {skip}, orderBy: blockTimestamp, "
            f"orderDirection: asc, where: {{ {where} }}) {{ blockTimestamp {fields} }} }}"
        )[entity]
        rows.extend(batch)
        if len(batch) < 1000:
            return rows
    print(f"!! WARNING: {entity} truncated at 6000 rows (graph-node skip limit)")
    return rows


def load_game_contracts():
    path = os.path.join(REPO_ROOT, "script", "data", "deployments", "mainnet.json")
    deployments = json.load(open(path))
    return {
        addr.lower(): name
        for name, addr in deployments.items()
        if isinstance(addr, str) and addr.startswith("0x") and int(addr, 16) != 0
    }


def scan_wallet(owner, game_contracts, stop_date):
    """Walk the explorer tx list newest-first; stop once past stop_date."""
    rows, truncated = [], False
    for page in range(1, 101):
        url = f"{EXPLORER}/transactions?address={owner}&limit=100&page={page}"
        data = json.loads(urllib.request.urlopen(urllib.request.Request(url, headers=UA)).read())
        items = data["items"]
        if not items:
            break
        for tx in items:
            if (tx.get("from") or "").lower() != owner:
                continue
            to = (tx.get("to") or "").lower()
            if to in game_contracts:
                rows.append(tx)
        if items[-1]["receivedAt"][:10] < stop_date:
            break
    else:
        truncated = True
    return rows, truncated


def spend_report(txs, target_token):
    agg = collections.defaultdict(lambda: [0, 0])   # label -> [count, wei]
    per_token = collections.defaultdict(lambda: [0, 0])
    resets_by_day = collections.Counter()
    failed = 0
    for tx in txs:
        if tx.get("status") == "failed":
            failed += 1
            continue
        sel = tx["data"][:10]
        contract, fn, token_arg = SELECTORS.get(sel, ("?", f"unknown({sel})", None))
        label = f"{contract}.{fn}"
        wei = int(tx["value"])
        agg[label][0] += 1
        agg[label][1] += wei
        token = None
        if token_arg == 0 and len(tx["data"]) >= 74:
            token = int(tx["data"][10:74], 16)
        if token == target_token:
            per_token[label][0] += 1
            per_token[label][1] += wei
            if fn == "purchaseAttemptReset":
                resets_by_day[tx["receivedAt"][:10]] += 1
    return agg, per_token, resets_by_day, failed


def print_spend(title, agg):
    print(f"\n== {title} ==")
    total = 0
    for label, (n, wei) in sorted(agg.items(), key=lambda kv: -kv[1][1]):
        total += wei
        eth = f"{wei / 1e18:.4f} ETH" if wei else "free"
        print(f"  {label:<32} n={n:<4} {eth}")
    print(f"  {'TOTAL':<32}       {total / 1e18:.4f} ETH")


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)

    if args[0] == "--wallet":
        owner = args[1].lower()
        target_token = None
    else:
        target_token = int(args[0])
        dealer = gql(f'{{ dealer(id: "{target_token}") {{ owner }} }}')["dealer"]
        if not dealer:
            sys.exit(f"dealer {target_token} not found in subgraph")
        owner = dealer["owner"]

    fleet = gql(
        f'{{ dealers(where: {{ owner: "{owner}" }}) {{ tokenId reputation totalReputation cash '
        f"heatLevel currentArea infamy threat armor pveGamesPlayed pvpAttacks pvpDefenses pvpWins "
        f"heistsStarted actionsCount rewardsReceived boostExpiresAt mintedAt lastActiveAt }} }}"
    )["dealers"]
    if not fleet:
        sys.exit(f"no dealers owned by {owner}")
    if target_token is None:
        target_token = max(fleet, key=lambda d: int(d["reputation"]))["tokenId"]
        target_token = int(target_token)

    print(f"== WALLET {owner} — {len(fleet)} dealer(s), target #{target_token} ==")
    for d in fleet:
        marker = " <-- target" if int(d["tokenId"]) == target_token else ""
        boost = f" boostUntil={day(d['boostExpiresAt'])}" if d["boostExpiresAt"] else ""
        print(
            f"  #{d['tokenId']:<5} rep={d['reputation']:<6} (total {d['totalReputation']}) "
            f"cash={d['cash']:<8} heat={d['heatLevel']} pve={d['pveGamesPlayed']:<4} "
            f"pvpAtk={d['pvpAttacks']} heists={d['heistsStarted']} grants={d['rewardsReceived']} "
            f"minted={day(d['mintedAt'])} lastActive={day(d['lastActiveAt'])}{boost}{marker}"
        )

    tid = f'dealer: "{target_token}"'
    pve = paginate("pveGames", tid, "playerChoice houseChoice outcome hustleType cashChange reputationChange stakedCash")
    actions = paginate("dealerActions", tid, "kind success amount fromArea toArea")
    reps = paginate("statChanges", f'{tid}, kind: "reputation"', "newValue change")
    boosts = paginate("boostPurchases", tid, "tierId expiresAt")
    claims = paginate("achievementClaims", tid, "achievementId rewardType rewardAmount")
    heist_events = paginate("heistEvents", tid, "kind stage pot amount")
    attacks = paginate("pvpBattles", f'attacker: "{target_token}"', "attackerWon cashStolen drugsStolen attackerRepChange")
    defenses = paginate(
        "pvpBattles", f'defender: "{target_token}"',
        "attackerWon cashStolen drugsStolen defenderRepChange attacker { tokenId }",
    )

    print(f"\n== PVE PLAYSTYLE — {len(pve)} games ==")
    if pve:
        for name, key, labels in [
            ("choices", "playerChoice", CHOICE), ("outcomes", "outcome", OUTCOME), ("hustle", "hustleType", HUSTLE),
        ]:
            counts = collections.Counter(labels.get(int(g[key]), g[key]) for g in pve)
            print(f"  {name}: {dict(counts)}")
        wins = sum(1 for g in pve if int(g["outcome"]) == 0)
        print(f"  win rate: {wins / len(pve):.1%} (configured winChance: read on-chain)")
        print(f"  rep from PVE: {sum(int(g['reputationChange']) for g in pve)}")
        print(f"  cash net from PVE: {sum(int(g['cashChange']) for g in pve)} "
              f"(total staked: {sum(int(g['stakedCash']) for g in pve)})")

    print("\n== ACTIONS ==")
    for kind, rows in collections.Counter(a["kind"] for a in actions).most_common():
        subset = [a for a in actions if a["kind"] == kind]
        amount = sum(int(a["amount"] or 0) for a in subset)
        print(f"  {kind:<14} n={rows:<4} amountSum={amount}")

    print("\n== BOOSTS ==")
    for b in boosts:
        print(f"  tier {b['tierId']} bought {day(b['blockTimestamp'])}, expires {day(b['expiresAt'])}")

    if heist_events:
        print(f"\n== HEIST EVENTS ({len(heist_events)}) ==")
        for e in heist_events:
            extra = f" amount={e['amount']}" if e["amount"] else f" pot={e['pot']}"
            print(f"  {day(e['blockTimestamp'])} {e['kind']} stage={e['stage']}{extra}")

    print(f"\n== PVP — {len(attacks)} attacks, {len(defenses)} defenses ==")
    if attacks:
        won = sum(1 for a in attacks if a["attackerWon"])
        print(f"  attacks won: {won}, cash stolen: {sum(int(a['cashStolen']) for a in attacks if a['attackerWon'])}")
    for de in defenses:
        result = "lost" if de["attackerWon"] else "held"
        print(f"  {day(de['blockTimestamp'])} raided by #{de['attacker']['tokenId']}: {result}, "
              f"-{de['cashStolen']} cash, -{de['drugsStolen']} drugs, rep {de['defenderRepChange']}")

    print(f"\n== ACHIEVEMENTS ({len(claims)}) ==")
    reward_types = {0: "REP", 1: "CASH", 2: "DRUG", 3: "ATTEMPTS"}
    for c in claims:
        rt = reward_types.get(int(c["rewardType"]), c["rewardType"])
        print(f"  {day(c['blockTimestamp'])} id={c['achievementId']:<4} {rt} {c['rewardAmount']}")

    game_contracts = load_game_contracts()
    earliest = min(day(d["mintedAt"]) for d in fleet)
    wallet_txs, truncated = scan_wallet(owner, game_contracts, earliest)
    agg, per_token, resets_by_day, failed = spend_report(wallet_txs, target_token)

    print(f"\n== PER-DAY (dealer #{target_token}) ==")
    by_day = collections.defaultdict(list)
    for g in pve:
        by_day[day(g["blockTimestamp"])].append(g)
    rep_close = {}
    for r in reps:
        rep_close[day(r["blockTimestamp"])] = int(r["newValue"])
    print(f"  {'day':<12} {'games':>5} {'rep+':>6} {'rep/g':>6} {'avgStake':>9} {'maxStake':>9} {'resets':>6} {'repEOD':>7}")
    running_rep = 0
    for d in sorted(set(by_day) | set(rep_close) | set(resets_by_day)):
        games = by_day.get(d, [])
        rep_gain = sum(int(g["reputationChange"]) for g in games)
        stakes = [int(g["stakedCash"]) for g in games] or [0]
        running_rep = rep_close.get(d, running_rep)
        per_game = f"{rep_gain / len(games):.1f}" if games else "-"
        print(f"  {d:<12} {len(games):>5} {rep_gain:>6} {per_game:>6} {sum(stakes) // len(stakes):>9} "
              f"{max(stakes):>9} {resets_by_day.get(d, 0):>6} {running_rep:>7}")

    print_spend(f"ETH SPEND — wallet-wide ({len(wallet_txs)} game txs, {failed} failed)", agg)
    print_spend(f"ETH SPEND — attributable to #{target_token} (tokenId-decodable calls only)", per_token)
    if truncated:
        print("\n!! WARNING: explorer scan hit the 100-page/10k-tx cap before reaching mint date —")
        print("!! spend totals may be incomplete for hyperactive wallets.")
    print("\nNOTE: purchaseAttemptReset emits no event — the reset counts above come from wallet tx")
    print("scanning, not the subgraph. PVE txs are commit+resolve pairs (2 txs per game).")


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
set -euo pipefail

RPC="${RPC:-https://api.mainnet.abs.xyz}"
DAYS="${1:-7}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEPLOYMENTS="$REPO_ROOT/script/data/deployments/mainnet.json"

HEISTS=$(sed -n 's/.*"heists": "\(0x[0-9a-fA-F]*\)".*/\1/p' "$DEPLOYMENTS")
if [ -z "$HEISTS" ] || [ "$HEISTS" = "0x0000000000000000000000000000000000000000" ]; then
  echo "No heists address in $DEPLOYMENTS" >&2
  exit 1
fi

NOW_BLOCK=$(cast block-number --rpc-url "$RPC")
NOW_TS=$(cast block "$NOW_BLOCK" --rpc-url "$RPC" -f timestamp)
CAL_BLOCK=$((NOW_BLOCK - 100000))
CAL_TS=$(cast block "$CAL_BLOCK" --rpc-url "$RPC" -f timestamp)
BLOCKS_PER_DAY=$((100000 * 86400 / (NOW_TS - CAL_TS)))

wei_to_eth() { cast to-unit "$1" ether; }

echo "== DealersHeists jackpot pool =="
echo "contract: $HEISTS"
echo "block: $NOW_BLOCK ($(date -r "$NOW_TS" '+%Y-%m-%d %H:%M'))"
echo ""
echo "-- current --"
echo "balance:          $(wei_to_eth "$(cast balance "$HEISTS" --rpc-url "$RPC")") ETH"
for f in jackpotReserve escrowedJackpot totalJackpotOwed backedEth; do
  v=$(cast call "$HEISTS" "$f()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
  printf "%-17s %s ETH\n" "$f:" "$(wei_to_eth "$v")"
done

echo ""
echo "-- daily jackpotReserve (last $DAYS days) --"
for d in $(seq 0 "$DAYS"); do
  b=$((NOW_BLOCK - d * BLOCKS_PER_DAY))
  v=$(cast call "$HEISTS" "jackpotReserve()(uint256)" --rpc-url "$RPC" --block "$b" 2>/dev/null | awk '{print $1}') || true
  if [ -n "${v:-}" ]; then
    ts=$(cast block "$b" --rpc-url "$RPC" -f timestamp)
    echo "$(date -r "$ts" '+%Y-%m-%d %H:%M')  block $b  $(wei_to_eth "$v") ETH"
  else
    echo "block $b: no data (pre-deploy)"
    break
  fi
done

FROM_BLOCK=$((NOW_BLOCK - DAYS * BLOCKS_PER_DAY))

echo ""
echo "-- JackpotWon events (last $DAYS days) --"
cast logs --rpc-url "$RPC" --from-block "$FROM_BLOCK" --to-block "$NOW_BLOCK" \
  --address "$HEISTS" "JackpotWon(uint64 indexed,uint256 indexed,uint256)" 2>/dev/null |
  grep "data:" | awk '{print $2}' | while read -r d; do
    cast to-unit "$(cast to-dec "$d")" ether
  done | awk '{s+=$1; n++} END {if (n) printf "%d jackpots won, %.6f ETH paid out\n", n, s; else print "none"}'

echo ""
echo "-- ReserveFunded events (last $DAYS days) --"
FUNDED=$(cast logs --rpc-url "$RPC" --from-block "$FROM_BLOCK" --to-block "$NOW_BLOCK" \
  --address "$HEISTS" "ReserveFunded(address indexed,uint256)" 2>/dev/null | grep "data:" || true)
if [ -n "$FUNDED" ]; then
  echo "$FUNDED" | awk '{print $2}' | while read -r d; do
    echo "$(cast to-unit "$(cast to-dec "$d")" ether) ETH"
  done
else
  echo "none"
fi

#!/usr/bin/env bash
# Read-only eligibility check for a referral reward claim.
#
# Usage:
#   check-claim.sh <tokenId> attempts
#   check-claim.sh <tokenId> boost <tierId 1-4>
#
# Env overrides: RPC (default https://api.mainnet.abs.xyz), DEPLOYMENTS (default script/data/deployments/mainnet.json)
#
# Exit codes: 0 = APPLY (prints the cast send command), 2 = HOLD, 1 = error.
set -euo pipefail

RPC="${RPC:-https://api.mainnet.abs.xyz}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEPLOYMENTS="${DEPLOYMENTS:-$REPO_ROOT/script/data/deployments/mainnet.json}"

TOKEN_ID="${1:?usage: check-claim.sh <tokenId> attempts|boost [tierId]}"
REWARD="${2:?usage: check-claim.sh <tokenId> attempts|boost [tierId]}"

CORE=$(jq -r .core "$DEPLOYMENTS")
BOOSTS=$(jq -r .boosts "$DEPLOYMENTS")
CLAIMS=$(jq -r .claims "$DEPLOYMENTS")

TIER_NAMES=(none Grinder Hustler Kingpin Godfather)

# cast annotates large values ("1783455707 [1.783e9]") — keep only the first field per line
dealer_data() {
  cast call "$CORE" "getDealerData(uint256)(uint8,uint256,uint8,uint8,uint32,bool)" "$TOKEN_ID" --rpc-url "$RPC" | awk '{print $1}'
}

echo "== Referral claim check =="
echo "tokenId: $TOKEN_ID   reward: $REWARD ${3:-}"
echo "core: $CORE   boosts: $BOOSTS   claims: $CLAIMS"
echo

DATA=($(dealer_data))
INITIALIZED="${DATA[5]}"
ATTEMPTS="${DATA[2]}"

if [[ "$INITIALIZED" != "true" ]]; then
  echo "ERROR: dealer $TOKEN_ID is not initialized on DealersCore — grant would revert."
  exit 1
fi

case "$REWARD" in
  attempts)
    echo "Effective attempts remaining: $ATTEMPTS"
    if [[ "$ATTEMPTS" -gt 0 ]]; then
      echo
      echo "VERDICT: HOLD — dealer still has $ATTEMPTS attempt(s). Re-check once depleted (auto-refill is midnight UTC)."
      exit 2
    fi
    echo
    echo "VERDICT: APPLY — attempts depleted. Run:"
    echo
    echo "cast send $CLAIMS \"grantReward(uint256,uint8,uint256,uint256)\" $TOKEN_ID 3 0 0 --rpc-url $RPC --account dealersKeystore"
    ;;

  boost)
    TIER="${3:?boost requires a tierId (1-4)}"
    [[ "$TIER" -ge 1 && "$TIER" -le 4 ]] || { echo "ERROR: tierId must be 1-4"; exit 1; }

    ACTIVE=$(cast call "$CORE" "hasActiveBoost(uint256)(bool)" "$TOKEN_ID" --rpc-url "$RPC")
    APPLY_CMD="cast send $BOOSTS \"purchaseBoost(uint256,uint256)\" $TOKEN_ID $TIER --rpc-url $RPC --account dealersKeystore"

    if [[ "$ACTIVE" != "true" ]]; then
      echo "No active boost."
      echo
      echo "VERDICT: APPLY — tier $TIER (${TIER_NAMES[$TIER]}). Run:"
      echo
      echo "$APPLY_CMD"
      exit 0
    fi

    ACTIVE_TIER=$(cast call "$BOOSTS" "activeTierId(uint256)(uint256)" "$TOKEN_ID" --rpc-url "$RPC")
    NEW_PRICE=$(cast call "$BOOSTS" "boostTiers(uint256)(uint256,uint64,uint8,uint8,uint8,bool,uint8,bool)" "$TIER" --rpc-url "$RPC" | head -1 | awk '{print $1}')
    ACTIVE_PRICE=$(cast call "$BOOSTS" "boostTiers(uint256)(uint256,uint64,uint8,uint8,uint8,bool,uint8,bool)" "$ACTIVE_TIER" --rpc-url "$RPC" | head -1 | awk '{print $1}')
    EXPIRES_AT=$(cast call "$CORE" "dealerBoosts(uint256)(uint64,uint8,uint8,uint8,bool,uint8,bool)" "$TOKEN_ID" --rpc-url "$RPC" | head -1 | awk '{print $1}')
    EXPIRES_HUMAN=$(date -u -r "$EXPIRES_AT" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || date -u -d "@$EXPIRES_AT" '+%Y-%m-%d %H:%M UTC')

    echo "Active boost: tier $ACTIVE_TIER (${TIER_NAMES[$ACTIVE_TIER]:-unknown}), expires $EXPIRES_HUMAN"
    echo "Claim boost:  tier $TIER (${TIER_NAMES[$TIER]}), price $NEW_PRICE vs active price $ACTIVE_PRICE"
    echo

    if [[ "$NEW_PRICE" -gt "$ACTIVE_PRICE" ]]; then
      echo "VERDICT: APPLY — claim tier is better; it extends from the current expiry (no time lost). Run:"
      echo
      echo "$APPLY_CMD"
    else
      echo "VERDICT: HOLD — active boost is same or better; purchaseBoost would revert BoostTierTooLow."
      echo "Re-check after expiry: $EXPIRES_HUMAN"
      exit 2
    fi
    ;;

  *)
    echo "ERROR: unknown reward '$REWARD' (expected: attempts | boost)"
    exit 1
    ;;
esac

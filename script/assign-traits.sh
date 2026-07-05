#!/usr/bin/env bash
# Reveal-time orchestrator: chunked batchSetTraits + one batchSetOneOfOnes.
#
# Reads script/data/assignments.json (produced by ../generateAssignments.py)
# and walks every normal+special entry in chunks, then assigns one-of-ones in
# a single call. Idempotent: re-running re-applies identical writes.
#
# Tunables via env:
#   NETWORK         (default: testnet)         testnet | mainnet | local
#   RPC             (default: derived from NETWORK)
#   ACCOUNT         (default: dealersKeystore)
#   CHUNK           (default: 250)             tokens per batchSetTraits call
#   OO_CHUNK        (default: 0)               one-of-ones per call; 0 = single call
#   DO_TRAITS       (default: 1)               0 to skip the trait phase
#   DO_ONEOFONES    (default: 1)               0 to skip the one-of-one phase

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

NETWORK="${NETWORK:-testnet}"
case "$NETWORK" in
  testnet) DEFAULT_RPC="https://api.testnet.abs.xyz" ;;
  mainnet) DEFAULT_RPC="https://api.mainnet.abs.xyz" ;;
  local)   DEFAULT_RPC="http://127.0.0.1:8545" ;;
  *)
    echo "FATAL: unknown NETWORK '$NETWORK'. Expected one of: testnet, mainnet, local." >&2
    exit 1
    ;;
esac

RPC="${RPC:-$DEFAULT_RPC}"
ACCOUNT="${ACCOUNT:-dealersKeystore}"
CHUNK="${CHUNK:-250}"
OO_CHUNK="${OO_CHUNK:-0}"
DO_TRAITS="${DO_TRAITS:-1}"
DO_ONEOFONES="${DO_ONEOFONES:-1}"

ASSIGNMENTS_JSON="script/data/assignments.json"
DEPLOY_JSON="script/data/deployments/${NETWORK}.json"
POINTERS_JSON="script/data/${NETWORK}/pointers.json"

if [ ! -f "$ASSIGNMENTS_JSON" ]; then
  echo "FATAL: $ASSIGNMENTS_JSON not found. Run ../generateAssignments.py first." >&2
  exit 1
fi
if [ ! -f "$DEPLOY_JSON" ]; then
  echo "FATAL: $DEPLOY_JSON not found. Deploy the renderer first." >&2
  exit 1
fi
if [ "$DO_ONEOFONES" = "1" ] && [ ! -f "$POINTERS_JSON" ]; then
  echo "FATAL: $POINTERS_JSON not found. Run upload-traits.sh first." >&2
  exit 1
fi

RENDERER_SVG="$(jq -r '.rendererSvg' "$DEPLOY_JSON")"
if [ -z "$RENDERER_SVG" ] || [ "$RENDERER_SVG" = "null" ]; then
  echo "FATAL: rendererSvg not set in $DEPLOY_JSON. Deploy it first." >&2
  exit 1
fi

NS_TOTAL=$(jq '[.tokens[] | select(.kind != "oneOfOne")] | length' "$ASSIGNMENTS_JSON")
OO_TOTAL=$(jq '[.tokens[] | select(.kind == "oneOfOne")] | length' "$ASSIGNMENTS_JSON")

PASS_FILE="$(mktemp -t dealers-keystore-pass.XXXXXX)"
chmod 600 "$PASS_FILE"
cleanup() { rm -f "$PASS_FILE"; }
trap cleanup EXIT INT TERM

read -rs -p "Enter keystore password for '$ACCOUNT': " KEYSTORE_PASSWORD
echo
printf '%s' "$KEYSTORE_PASSWORD" > "$PASS_FILE"
unset KEYSTORE_PASSWORD

KEY="--account $ACCOUNT --password-file $PASS_FILE"

echo "============================================================"
echo "  Trait assignment orchestrator"
echo "============================================================"
echo "  NETWORK:        $NETWORK"
echo "  RPC:            $RPC"
echo "  DEPLOY_JSON:    $DEPLOY_JSON"
echo "  POINTERS_JSON:  $POINTERS_JSON"
echo "  ASSIGNMENTS:    $ASSIGNMENTS_JSON"
echo "  RENDERER_SVG:   $RENDERER_SVG"
echo "  CHUNK:          $CHUNK"
echo "  OO_CHUNK:       $OO_CHUNK"
echo "  N+S total:      $NS_TOTAL"
echo "  1/1 total:      $OO_TOTAL"
echo "  DO_TRAITS:      $DO_TRAITS"
echo "  DO_ONEOFONES:   $DO_ONEOFONES"
echo ""

if [ "$DO_TRAITS" = "1" ]; then
  s=0
  while [ "$s" -lt "$NS_TOTAL" ]; do
    c="$CHUNK"
    if [ $((s + c)) -gt "$NS_TOTAL" ]; then
      c=$((NS_TOTAL - s))
    fi
    end=$((s + c))
    echo "---- traits [$s, $end) ----"
    forge script script/upload/AssignTraits.s.sol:AssignTraits \
      --sig "assignTokenTraitsRange(uint256,uint256)" "$s" "$c" \
      --rpc-url "$RPC" $KEY --broadcast --slow
    s=$end
  done
  echo ""
fi

if [ "$DO_ONEOFONES" = "1" ]; then
  if [ "$OO_CHUNK" -gt 0 ]; then
    s=0
    while [ "$s" -lt "$OO_TOTAL" ]; do
      c="$OO_CHUNK"
      if [ $((s + c)) -gt "$OO_TOTAL" ]; then
        c=$((OO_TOTAL - s))
      fi
      end=$((s + c))
      echo "---- one-of-ones [$s, $end) ----"
      forge script script/upload/AssignTraits.s.sol:AssignTraits \
        --sig "assignOneOfOnesFromManifestRange(uint256,uint256)" "$s" "$c" \
        --rpc-url "$RPC" $KEY --broadcast --slow
      s=$end
    done
  else
    echo "---- one-of-ones ----"
    forge script script/upload/AssignTraits.s.sol:AssignTraits \
      --sig "assignOneOfOnesFromManifest()" \
      --rpc-url "$RPC" $KEY --broadcast --slow
  fi
  echo ""
fi

echo "============================================================"
echo "  Assignment complete."
echo "============================================================"
echo "Verify with:"
echo "  cast call $RENDERER_SVG 'isTraitStored(uint256)(bool)' 1 --rpc-url $RPC"
echo "  cast call $RENDERER_SVG 'getStoredTraits(uint256)(uint8[12])' 1 --rpc-url $RPC"

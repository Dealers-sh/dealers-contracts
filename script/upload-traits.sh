#!/usr/bin/env bash
# Orchestrated chunked upload of traits.json -> FileStore + DealerRendererSVG.
#
# Resilient to broadcast failures mid-chunk: on failure we null the slice's
# pointers in traits.json (because foundry's simulation pre-writes fake pointers)
# and retry. Successful chunks are durable - re-running this script is idempotent.
#
# Tunables via env:
#   RPC      (default: https://api.testnet.abs.xyz)
#   KEY      (default: --account dealersKeystore)
#   CHUNK    (default: 28)
#   RETRIES  (default: 3)
#   DO_PLACEHOLDER (default: 1)  -- 0 to skip placeholder upload
#   DO_REVEAL      (default: 0)  -- 1 to call reveal() at the end

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

RPC="${RPC:-https://api.testnet.abs.xyz}"
ACCOUNT="${ACCOUNT:-dealersKeystore}"
CHUNK="${CHUNK:-28}"
RETRIES="${RETRIES:-3}"
DO_PLACEHOLDER="${DO_PLACEHOLDER:-1}"
DO_REVEAL="${DO_REVEAL:-0}"

TRAITS_JSON="script/data/traits.json"
DEPLOY_JSON="script/data/deployments/testnet.json"

RENDERER_SVG="$(jq -r '.rendererSvg' "$DEPLOY_JSON")"
if [ -z "$RENDERER_SVG" ] || [ "$RENDERER_SVG" = "null" ]; then
  echo "FATAL: rendererSvg not set in $DEPLOY_JSON. Deploy it first." >&2
  exit 1
fi

# Prompt for keystore password once and reuse via --password-file
PASS_FILE="$(mktemp -t dealers-keystore-pass.XXXXXX)"
chmod 600 "$PASS_FILE"
cleanup() {
  rm -f "$PASS_FILE"
}
trap cleanup EXIT INT TERM

read -rs -p "Enter keystore password for '$ACCOUNT': " KEYSTORE_PASSWORD
echo
printf '%s' "$KEYSTORE_PASSWORD" > "$PASS_FILE"
unset KEYSTORE_PASSWORD

KEY="--account $ACCOUNT --password-file $PASS_FILE"

echo "============================================================"
echo "  Trait upload orchestrator"
echo "============================================================"
echo "  RPC:           $RPC"
echo "  RENDERER_SVG:  $RENDERER_SVG"
echo "  CHUNK:         $CHUNK"
echo "  RETRIES:       $RETRIES"
echo "  DO_PLACEHOLDER:$DO_PLACEHOLDER"
echo "  DO_REVEAL:     $DO_REVEAL"
echo ""

null_slice() {
  local typeKey=$1
  local start=$2
  local end=$3
  jq --arg tk "$typeKey" --argjson s "$start" --argjson e "$end" \
    '.[$tk] |= [range(0;length) as $i | .[$i] | if ($i >= $s and $i < $e) then .pointer = null else . end]' \
    "$TRAITS_JSON" > "$TRAITS_JSON.tmp" && mv "$TRAITS_JSON.tmp" "$TRAITS_JSON"
}

run_chunk() {
  local typeKey=$1
  local sig=$2
  local start=$3
  local count=$4
  local end=$((start + count))

  for attempt in $(seq 1 "$RETRIES"); do
    echo "---- $typeKey [$start, $end)  attempt $attempt/$RETRIES ----"
    if forge script script/upload/UploadTraits.s.sol:UploadTraits \
         --sig "$sig" "$start" "$count" \
         --rpc-url "$RPC" $KEY --broadcast --slow; then
      return 0
    fi
    echo ">> $typeKey [$start, $end) failed on attempt $attempt."
    if [ "$attempt" -lt "$RETRIES" ]; then
      echo ">> Nulling pointers in slice and retrying..."
      null_slice "$typeKey" "$start" "$end"
    fi
  done

  echo ""
  echo "ABORT: $typeKey [$start, $end) failed all $RETRIES attempts." >&2
  echo "Inspect, then re-run this script. Already-registered chunks will be skipped." >&2
  exit 1
}

upload_type() {
  local typeKey=$1
  local sig=$2
  local total
  total=$(jq ".$typeKey | length" "$TRAITS_JSON")
  if [ "$total" = "0" ] || [ -z "$total" ]; then
    echo "=== $typeKey: 0 entries, skipping ==="
    return
  fi
  echo "=== $typeKey: $total entries, chunk size $CHUNK ==="
  local s=0
  while [ "$s" -lt "$total" ]; do
    local c="$CHUNK"
    if [ $((s + c)) -gt "$total" ]; then
      c=$((total - s))
    fi
    run_chunk "$typeKey" "$sig" "$s" "$c"
    s=$((s + c))
  done
  echo ""
}

upload_type "normal"  "uploadNormalRange(uint256,uint256)"
upload_type "special" "uploadSpecialRange(uint256,uint256)"

if [ "$DO_PLACEHOLDER" = "1" ]; then
  echo "=== placeholder ==="
  forge script script/upload/UploadTraits.s.sol:UploadTraits \
    --sig "uploadPlaceholder()" \
    --rpc-url "$RPC" $KEY --broadcast --slow
  echo ""
fi

if [ "$DO_REVEAL" = "1" ]; then
  echo "=== reveal ==="
  cast send "$RENDERER_SVG" "reveal()" --rpc-url "$RPC" $KEY
  echo ""
fi

echo "============================================================"
echo "  Upload complete."
echo "============================================================"
echo "Verify with:"
echo "  cast call $RENDERER_SVG 'traitCount(uint8,uint8)(uint256)' 0 0 --rpc-url $RPC"
echo "  cast call $RENDERER_SVG 'revealed()(bool)' --rpc-url $RPC"

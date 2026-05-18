#!/usr/bin/env bash
# Orchestrated chunked upload of traits.json -> FileStore + DealerRendererSVG.
#
# Per-network: pointers are read from / written to
#   script/data/{NETWORK}/pointers.json
# while trait content (SVGs, names, categories) stays in the shared
#   script/data/traits.json
#
# Resilient to broadcast failures mid-chunk: on failure we restore the slice's
# pointers from a pre-chunk snapshot (foundry's simulation can inject phantom
# pointers when the broadcast then fails). Successful chunks are durable.
#
# Tunables via env:
#   NETWORK         (default: testnet)         testnet | mainnet | local
#   RPC             (default: derived from NETWORK)
#   ACCOUNT         (default: dealersKeystore)
#   CHUNK           (default: 28)              normal/special chunk size
#   ONEOFONE_CHUNK  (default: 5)               one-of-one chunk size
#   RETRIES         (default: 3)
#   DO_PLACEHOLDER  (default: 1)
#   DO_ONEOFONE     (default: 1)
#   DO_REVEAL       (default: 0)

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
CHUNK="${CHUNK:-28}"
ONEOFONE_CHUNK="${ONEOFONE_CHUNK:-5}"
RETRIES="${RETRIES:-3}"
DO_PLACEHOLDER="${DO_PLACEHOLDER:-1}"
DO_ONEOFONE="${DO_ONEOFONE:-1}"
DO_REVEAL="${DO_REVEAL:-0}"

TRAITS_JSON="script/data/traits.json"
DEPLOY_JSON="script/data/deployments/${NETWORK}.json"
POINTERS_JSON="script/data/${NETWORK}/pointers.json"

if [ ! -f "$DEPLOY_JSON" ]; then
  echo "FATAL: $DEPLOY_JSON not found. Deploy the renderer first." >&2
  exit 1
fi
if [ ! -f "$POINTERS_JSON" ]; then
  mkdir -p "$(dirname "$POINTERS_JSON")"
  printf '%s\n' '{"normal":[],"special":[],"oneofone":[],"placeholder":null}' > "$POINTERS_JSON"
  echo "Initialized empty pointer store at $POINTERS_JSON"
fi

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
echo "  NETWORK:        $NETWORK"
echo "  RPC:            $RPC"
echo "  DEPLOY_JSON:    $DEPLOY_JSON"
echo "  POINTERS_JSON:  $POINTERS_JSON"
echo "  RENDERER_SVG:   $RENDERER_SVG"
echo "  CHUNK:          $CHUNK"
echo "  ONEOFONE_CHUNK: $ONEOFONE_CHUNK"
echo "  RETRIES:        $RETRIES"
echo "  DO_PLACEHOLDER: $DO_PLACEHOLDER"
echo "  DO_ONEOFONE:    $DO_ONEOFONE"
echo "  DO_REVEAL:      $DO_REVEAL"
echo ""

snapshot_slice() {
  local typeKey=$1
  local start=$2
  local end=$3
  jq --arg tk "$typeKey" --argjson s "$start" --argjson e "$end" \
    '(.[$tk] // []) | .[$s:$e]' "$POINTERS_JSON"
}

restore_slice() {
  local typeKey=$1
  local start=$2
  local snapshot=$3
  jq --arg tk "$typeKey" --argjson s "$start" --argjson snap "$snapshot" '
    . as $root
    | ($root[$tk] // []) as $arr
    | ($arr | length) as $alen
    | ($snap | length) as $slen
    | ([$alen, $s + $slen] | max) as $newLen
    | .[$tk] = [
        range(0; $newLen) as $i
        | if ($i >= $s and ($i - $s) < $slen) then $snap[$i - $s]
          elif ($i < $alen) then $arr[$i]
          else null end
      ]
  ' "$POINTERS_JSON" > "$POINTERS_JSON.tmp" && mv "$POINTERS_JSON.tmp" "$POINTERS_JSON"
}

run_chunk() {
  local typeKey=$1
  local sig=$2
  local start=$3
  local count=$4
  local end=$((start + count))

  local snapshot
  snapshot=$(snapshot_slice "$typeKey" "$start" "$end")

  for attempt in $(seq 1 "$RETRIES"); do
    echo "---- $typeKey [$start, $end)  attempt $attempt/$RETRIES ----"
    if forge script script/upload/UploadTraits.s.sol:UploadTraits \
         --sig "$sig" "$start" "$count" \
         --rpc-url "$RPC" $KEY --broadcast --slow; then
      return 0
    fi
    echo ">> $typeKey [$start, $end) failed on attempt $attempt."
    if [ "$attempt" -lt "$RETRIES" ]; then
      echo ">> Restoring pre-chunk pointer snapshot and retrying..."
      restore_slice "$typeKey" "$start" "$snapshot"
    fi
  done

  echo ""
  echo "ABORT: $typeKey [$start, $end) failed all $RETRIES attempts." >&2
  echo ">> Restoring pre-chunk pointer snapshot." >&2
  restore_slice "$typeKey" "$start" "$snapshot"
  echo "Inspect, then re-run this script. Already-registered chunks will be skipped." >&2
  exit 1
}

upload_type() {
  local typeKey=$1
  local sig=$2
  local chunkSize=${3:-$CHUNK}
  local total
  total=$(jq ".$typeKey | length" "$TRAITS_JSON")
  if [ "$total" = "0" ] || [ -z "$total" ]; then
    echo "=== $typeKey: 0 entries, skipping ==="
    return
  fi
  echo "=== $typeKey: $total entries, chunk size $chunkSize ==="
  local s=0
  while [ "$s" -lt "$total" ]; do
    local c="$chunkSize"
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

if [ "$DO_ONEOFONE" = "1" ]; then
  upload_type "oneofone" "uploadOneOfOnesRange(uint256,uint256)" "$ONEOFONE_CHUNK"
fi

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

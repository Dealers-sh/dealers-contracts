#!/usr/bin/env bash
# Orchestrated chunked upload of traits.json -> FileStore + DealerRendererSVG.
#
# Per-network: pointers are read from / written to
#   script/data/{NETWORK}/pointers.json
# while trait content (SVGs, names, categories) stays in the shared
#   script/data/traits.json
#
# Only entries whose pointer is null/missing in pointers.json are uploaded.
# Filled entries are not scanned by the forge script — the null-index list is
# computed in shell and fed to upload{Normal,Special,OneOfOnes}Indices in chunks.
#
# Resilient to broadcast failures mid-chunk: on failure we restore pointers.json
# from a pre-chunk file snapshot. Successful chunks are durable.
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
POINTERS_SNAPSHOT="${POINTERS_JSON}.snapshot"

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
  rm -f "$PASS_FILE" "$POINTERS_SNAPSHOT"
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

# Comma-separated indices into traits.json[$typeKey] whose corresponding
# pointers.json[$typeKey][i].pointer is null or missing.
null_indices() {
  local typeKey=$1
  jq -r --slurpfile P "$POINTERS_JSON" --arg tk "$typeKey" '
    ($P[0][$tk] // []) as $ptrs
    | [ .[$tk] | to_entries[]
        | .key as $i
        | select($ptrs[$i].pointer == null)
        | $i ]
    | join(",")
  ' "$TRAITS_JSON"
}

run_chunk() {
  local sig=$1
  local indices_csv=$2

  cp "$POINTERS_JSON" "$POINTERS_SNAPSHOT"

  for attempt in $(seq 1 "$RETRIES"); do
    echo "---- $sig indices=[$indices_csv]  attempt $attempt/$RETRIES ----"
    if forge script script/upload/UploadTraits.s.sol:UploadTraits \
         --sig "$sig" "[$indices_csv]" \
         --rpc-url "$RPC" $KEY --broadcast --slow; then
      rm -f "$POINTERS_SNAPSHOT"
      return 0
    fi
    echo ">> chunk failed on attempt $attempt."
    if [ "$attempt" -lt "$RETRIES" ]; then
      echo ">> Restoring pre-chunk pointers.json snapshot and retrying..."
      cp "$POINTERS_SNAPSHOT" "$POINTERS_JSON"
    fi
  done

  echo ""
  echo "ABORT: chunk failed all $RETRIES attempts." >&2
  echo ">> Restoring pre-chunk pointers.json snapshot." >&2
  cp "$POINTERS_SNAPSHOT" "$POINTERS_JSON"
  rm -f "$POINTERS_SNAPSHOT"
  echo "Inspect, then re-run this script. Already-filled pointers will be skipped." >&2
  exit 1
}

upload_type() {
  local typeKey=$1
  local sig=$2
  local chunkSize=${3:-$CHUNK}

  local csv
  csv=$(null_indices "$typeKey")

  if [ -z "$csv" ]; then
    echo "=== $typeKey: no null pointers, skipping ==="
    return
  fi

  IFS=',' read -r -a arr <<< "$csv"
  local total=${#arr[@]}
  echo "=== $typeKey: $total null entries, chunk size $chunkSize ==="

  local s=0
  while [ "$s" -lt "$total" ]; do
    local c="$chunkSize"
    if [ $((s + c)) -gt "$total" ]; then
      c=$((total - s))
    fi
    local slice_csv
    slice_csv=$(IFS=','; echo "${arr[*]:s:c}")
    run_chunk "$sig" "$slice_csv"
    s=$((s + c))
  done
  echo ""
}

upload_type "normal"  "uploadNormalIndices(uint256[])"
upload_type "special" "uploadSpecialIndices(uint256[])"

if [ "$DO_ONEOFONE" = "1" ]; then
  upload_type "oneofone" "uploadOneOfOnesIndices(uint256[])" "$ONEOFONE_CHUNK"
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

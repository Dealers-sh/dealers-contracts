#!/bin/bash

# Source Code Verification for Block Explorer
# Uploads contract source to Etherscan for public verification.
#
# Usage:
#   source .env && ./script/verify-source.sh                            # verify all (testnet default)
#   source .env && NETWORK=mainnet ./script/verify-source.sh            # mainnet
#   source .env && ./script/verify-source.sh boosts pvp                 # verify specific contracts
#   source .env && ./script/verify-source.sh renderers                  # verify renderers only
#
# Requires: ETHERSCAN_API_KEY + DEV_WALLET/BANK_VAULT/ROYALTY_RECEIVER in .env.
# Contract addresses are loaded from script/data/deployments/{NETWORK}.json
# (env vars still override).

set -e

NETWORK="${NETWORK:-testnet}"
case "$NETWORK" in
  testnet)
    CHAIN_ID=11124
    ZKSYNC_VERIFIER_URL="https://api-explorer-verify.testnet.abs.xyz/contract_verification"
    ;;
  mainnet)
    CHAIN_ID=2741
    ZKSYNC_VERIFIER_URL="https://api-explorer-verify.mainnet.abs.xyz/contract_verification"
    ;;
  *)
    echo "FATAL: unknown NETWORK '$NETWORK'. Expected testnet or mainnet." >&2
    exit 1
    ;;
esac

VERIFIER_URL="https://api.etherscan.io/v2/api?chainid=${CHAIN_ID}"
SOLC_VERSION="0.8.28"
DEPLOY_JSON="script/data/deployments/${NETWORK}.json"

if [ ! -f "$DEPLOY_JSON" ]; then
    echo "FATAL: $DEPLOY_JSON not found." >&2
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo -e "${RED}Error: ETHERSCAN_API_KEY not set${NC}"
    exit 1
fi

# Load address from testnet.json, returns empty string if not found
_addr() {
    local val
    val=$(jq -r ".$1 // empty" "$DEPLOY_JSON" 2>/dev/null || true)
    if [ -n "$val" ] && [ "$val" != "0x0000000000000000000000000000000000000000" ]; then
        echo "$val"
    fi
}

DRUG_REGISTRY="${DRUG_REGISTRY:-$(_addr drugRegistry)}"
AREA_REGISTRY="${AREA_REGISTRY:-$(_addr areaRegistry)}"
DEALERS_CORE="${DEALERS_CORE:-$(_addr core)}"
PAYMENT_HANDLER="${PAYMENT_HANDLER:-$(_addr paymentHandler)}"
RANDOMNESS="${RANDOMNESS:-$(_addr randomness)}"
DEALERS_NFT="${DEALERS_NFT:-$(_addr nft)}"
DEALERS_BOOSTS="${DEALERS_BOOSTS:-$(_addr boosts)}"
DEALERS_PVE="${DEALERS_PVE:-$(_addr pve)}"
DEALERS_PVP="${DEALERS_PVP:-$(_addr pvp)}"
DEALERS_CLAIMS="${DEALERS_CLAIMS:-$(_addr claims)}"
DEALERS_ACTIONS="${DEALERS_ACTIONS:-$(_addr actions)}"
DEALERS_MULTICALL="${DEALERS_MULTICALL:-$(_addr multicall)}"
CHAT_FACTORY="${CHAT_FACTORY:-$(_addr chatFactory)}"
RENDERER_SVG="${RENDERER_SVG:-$(_addr rendererSvg)}"
RENDERER_HTML="${RENDERER_HTML:-$(_addr rendererHtml)}"

verify_contract() {
    local address=$1
    local contract_path=$2
    local constructor_args=$3
    local use_zksync=$4
    local name=$(echo "$contract_path" | cut -d':' -f2)

    if [ -z "$address" ]; then
        echo -e "${YELLOW}  Skipping $name (no address set)${NC}"
        return 0
    fi

    echo -ne "  Verifying ${GREEN}$name${NC} at $address... "

    local output
    local rc=0
    if [ "$use_zksync" = "true" ]; then
        if [ -z "$constructor_args" ]; then
            output=$(forge verify-contract "$address" \
                "$contract_path" \
                --verifier zksync \
                --verifier-url "$ZKSYNC_VERIFIER_URL" \
                --chain "$CHAIN_ID" \
                --zksync \
                --watch 2>&1) || rc=$?
        else
            output=$(forge verify-contract "$address" \
                "$contract_path" \
                --constructor-args "$constructor_args" \
                --verifier zksync \
                --verifier-url "$ZKSYNC_VERIFIER_URL" \
                --chain "$CHAIN_ID" \
                --zksync \
                --watch 2>&1) || rc=$?
        fi
    else
        if [ -z "$constructor_args" ]; then
            output=$(forge verify-contract "$address" \
                "$contract_path" \
                --verifier etherscan \
                --verifier-url "$VERIFIER_URL" \
                --etherscan-api-key "$ETHERSCAN_API_KEY" \
                --chain "$CHAIN_ID" \
                --compiler-version "$SOLC_VERSION" \
                --num-of-optimizations 200 \
                --via-ir \
                --watch 2>&1) || rc=$?
        else
            output=$(forge verify-contract "$address" \
                "$contract_path" \
                --constructor-args "$constructor_args" \
                --verifier etherscan \
                --verifier-url "$VERIFIER_URL" \
                --etherscan-api-key "$ETHERSCAN_API_KEY" \
                --chain "$CHAIN_ID" \
                --compiler-version "$SOLC_VERSION" \
                --num-of-optimizations 200 \
                --via-ir \
                --watch 2>&1) || rc=$?
        fi
    fi

    if [ $rc -eq 0 ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "$output" | tail -5 | sed 's/^/    /'
    fi
}

# ── Contract definitions ─────────────────────────────────────────────────────

verify_drug_registry() {
    verify_contract "$DRUG_REGISTRY" \
        "src/utils/DealersDrugRegistry.sol:DealersDrugRegistry" "" "true"
}

verify_area_registry() {
    local args=$(cast abi-encode "constructor(address)" "$DRUG_REGISTRY")
    verify_contract "$AREA_REGISTRY" \
        "src/utils/DealersAreaRegistry.sol:DealersAreaRegistry" "$args" "true"
}

verify_core() {
    verify_contract "$DEALERS_CORE" \
        "src/core/DealersCore.sol:DealersCore" "" "true"
}

verify_payment_handler() {
    local args=$(cast abi-encode "constructor(address,address)" "$DEV_WALLET" "$BANK_VAULT")
    verify_contract "$PAYMENT_HANDLER" \
        "src/utils/DealersPaymentHandler.sol:DealersPaymentHandler" "$args" "true"
}

verify_randomness() {
    verify_contract "$RANDOMNESS" \
        "src/utils/DealersRandomness.sol:DealersRandomness" "" "true"
}

verify_nft() {
    local args=$(cast abi-encode "constructor(address)" "$ROYALTY_RECEIVER")
    verify_contract "$DEALERS_NFT" \
        "src/nft/DealersNFT.sol:DealersNFT" "$args" "true"
}

verify_boosts() {
    local args=$(cast abi-encode "constructor(address,address,address)" "$DEALERS_CORE" "$DEALERS_NFT" "$PAYMENT_HANDLER")
    verify_contract "$DEALERS_BOOSTS" \
        "src/core/DealersBoosts.sol:DealersBoosts" "$args" "true"
}

verify_pve() {
    local args=$(cast abi-encode "constructor(address,address,address)" "$DEALERS_CORE" "$DEALERS_NFT" "$AREA_REGISTRY")
    verify_contract "$DEALERS_PVE" \
        "src/core/DealersPVE.sol:DealersPVE" "$args" "true"
}

verify_pvp() {
    local args=$(cast abi-encode "constructor(address,address,address)" "$DEALERS_CORE" "$DEALERS_NFT" "$AREA_REGISTRY")
    verify_contract "$DEALERS_PVP" \
        "src/core/DealersPVP.sol:DealersPVP" "$args" "true"
}

verify_claims() {
    local args=$(cast abi-encode "constructor(address,address,address,address)" "$DEALERS_CORE" "$DEALERS_NFT" "$DEALERS_PVE" "$DEALERS_PVP")
    verify_contract "$DEALERS_CLAIMS" \
        "src/core/DealersClaims.sol:DealersClaims" "$args" "true"
}

verify_actions() {
    local args=$(cast abi-encode "constructor(address,address,address)" "$DEALERS_CORE" "$DEALERS_NFT" "$AREA_REGISTRY")
    verify_contract "$DEALERS_ACTIONS" \
        "src/core/DealersActions.sol:DealersActions" "$args" "true"
}

verify_multicall() {
    local args=$(cast abi-encode "constructor(address,address,address,address,address)" "$DEALERS_CORE" "$DEALERS_PVE" "$DEALERS_PVP" "$AREA_REGISTRY" "$DRUG_REGISTRY")
    verify_contract "$DEALERS_MULTICALL" \
        "src/core/DealersMulticall.sol:DealersMulticall" "$args" "true"
}

verify_chat_factory() {
    local args=$(cast abi-encode "constructor(address)" "$DEALERS_NFT")
    verify_contract "$CHAT_FACTORY" \
        "src/social/DealersChatFactory.sol:DealersChatFactory" "$args" "true"
}

verify_renderer_svg() {
    verify_contract "$RENDERER_SVG" \
        "src/nft/DealerRendererSVG.sol:DealerRendererSVG" "" "false"
}

verify_renderer_html() {
    local filestore="0xFe1411d6864592549AdE050215482e4385dFa0FB"
    local args=$(cast abi-encode "constructor(address)" "$filestore")
    verify_contract "$RENDERER_HTML" \
        "src/nft/DealerRendererHTML.sol:DealerRendererHTML" "$args" "true"
}

# ── Main ─────────────────────────────────────────────────────────────────────

echo "=============================================="
echo "  Dealers.sh Source Code Verification"
echo "  Network:  $NETWORK"
echo "  Chain ID: $CHAIN_ID"
echo "  Deploy:   $DEPLOY_JSON"
echo "=============================================="
echo ""

ALL_GAME=(drug_registry area_registry core payment_handler randomness nft boosts pve pvp claims actions multicall chat_factory)
ALL_RENDERERS=(renderer_svg renderer_html)

if [ $# -eq 0 ]; then
    targets=("${ALL_GAME[@]}" "${ALL_RENDERERS[@]}")
else
    targets=()
    for arg in "$@"; do
        case "$arg" in
            all)         targets=("${ALL_GAME[@]}" "${ALL_RENDERERS[@]}") ;;
            game)        targets+=("${ALL_GAME[@]}") ;;
            renderers)   targets+=("${ALL_RENDERERS[@]}") ;;
            drug*|DR*)   targets+=(drug_registry) ;;
            area*|AR*)   targets+=(area_registry) ;;
            core|CO*)    targets+=(core) ;;
            pay*|PH*)    targets+=(payment_handler) ;;
            rand*|RN*)   targets+=(randomness) ;;
            nft|NF*)     targets+=(nft) ;;
            boost*|BO*)  targets+=(boosts) ;;
            pve|PVE*)    targets+=(pve) ;;
            pvp|PVP*)    targets+=(pvp) ;;
            claim*|CL*)  targets+=(claims) ;;
            action*|AC*) targets+=(actions) ;;
            multi*|MC*)  targets+=(multicall) ;;
            chat*|CF*)   targets+=(chat_factory) ;;
            svg)         targets+=(renderer_svg) ;;
            html)        targets+=(renderer_html) ;;
            *)           echo -e "${RED}Unknown target: $arg${NC}"; exit 1 ;;
        esac
    done
fi

echo "Verifying: ${targets[*]}"
echo ""

for target in "${targets[@]}"; do
    case "$target" in
        drug_registry)   verify_drug_registry ;;
        area_registry)   verify_area_registry ;;
        core)            verify_core ;;
        payment_handler) verify_payment_handler ;;
        randomness)      verify_randomness ;;
        nft)             verify_nft ;;
        boosts)          verify_boosts ;;
        pve)             verify_pve ;;
        pvp)             verify_pvp ;;
        claims)          verify_claims ;;
        actions)         verify_actions ;;
        multicall)       verify_multicall ;;
        chat_factory)    verify_chat_factory ;;
        renderer_svg)    verify_renderer_svg ;;
        renderer_html)   verify_renderer_html ;;
    esac
done

echo ""
echo "=============================================="
echo "  Verification Complete"
echo "=============================================="

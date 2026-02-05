#!/bin/bash

# Renderer Contract Verification Script for Abstract Testnet
# Usage: source .env && ./script/verify-renderers.sh
#
# Verifies renderer contracts deployed in EVM mode (without --zksync flag).
# Requires: RENDERER_SVG, RENDERER_HTML environment variables

set -e

# Configuration
CHAIN_ID=11124
VERIFIER_URL="https://api.etherscan.io/v2/api?chainid=${CHAIN_ID}"
ETHERSCAN_API_KEY="P5U7KEVRI6WKS9J2UKCDI8HW61SUD5X8VF"
COMPILER_VERSION="0.8.28"
FILESTORE_ADDRESS="0xFe1411d6864592549AdE050215482e4385dFa0FB"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "   Renderer Contract Verification (EVM Mode)"
echo "   Chain ID: $CHAIN_ID"
echo "=============================================="
echo ""

verify_renderer() {
    local address=$1
    local contract_path=$2
    local constructor_args=$3
    local name=$(echo $contract_path | cut -d':' -f2)

    if [ -z "$address" ]; then
        echo -e "${YELLOW}Skipping $name (no address set)${NC}"
        return 0
    fi

    echo -e "Verifying ${GREEN}$name${NC} at $address..."

    if [ -z "$constructor_args" ]; then
        forge verify-contract "$address" \
            "$contract_path" \
            --verifier etherscan \
            --verifier-url "$VERIFIER_URL" \
            --etherscan-api-key "$ETHERSCAN_API_KEY" \
            --chain "$CHAIN_ID" \
            --compiler-version "$COMPILER_VERSION" \
            && echo -e "${GREEN}✓ $name verified${NC}" \
            || echo -e "${RED}✗ $name verification failed${NC}"
    else
        forge verify-contract "$address" \
            "$contract_path" \
            --verifier etherscan \
            --verifier-url "$VERIFIER_URL" \
            --etherscan-api-key "$ETHERSCAN_API_KEY" \
            --chain "$CHAIN_ID" \
            --compiler-version "$COMPILER_VERSION" \
            --constructor-args $constructor_args \
            && echo -e "${GREEN}✓ $name verified${NC}" \
            || echo -e "${RED}✗ $name verification failed${NC}"
    fi
    echo ""
}

# Verify DealerRendererSVG (no constructor args)
verify_renderer "$RENDERER_SVG" "src/nft/DealerRendererSVG.sol:DealerRendererSVG"

# Verify DealerRendererHTML (with FileStore address as constructor arg)
if [ -n "$RENDERER_HTML" ]; then
    ARGS=$(cast abi-encode "constructor(address)" "$FILESTORE_ADDRESS")
    verify_renderer "$RENDERER_HTML" "src/nft/DealerRendererHTML.sol:DealerRendererHTML" "$ARGS"
fi

echo "=============================================="
echo "   Renderer Verification Complete"
echo "=============================================="

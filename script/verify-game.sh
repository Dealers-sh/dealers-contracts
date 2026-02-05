#!/bin/bash

# Batch Contract Verification Script for Abstract Testnet
# Usage: source .env && ./script/verify-all.sh
#
# Reads contract addresses from environment variables and verifies all contracts.
# Requires: DRUG_REGISTRY, AREA_REGISTRY, DEALERS_CORE, PAYMENT_HANDLER,
#           DEALERS_NFT, DEALERS_BOOSTS, DEALERS_PVE, DEALERS_PVP,
#           DEV_WALLET, BANK_VAULT, ROYALTY_RECEIVER

set -e

# Configuration
CHAIN_ID=11124
VERIFIER_URL="https://api.etherscan.io/v2/api?chainid=${CHAIN_ID}"
ETHERSCAN_API_KEY="P5U7KEVRI6WKS9J2UKCDI8HW61SUD5X8VF"
COMPILER_VERSION="0.8.28"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "   Dealers.Exe Contract Verification"
echo "   Chain ID: $CHAIN_ID"
echo "=============================================="
echo ""

verify_contract() {
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
            --zksync \
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
            --zksync \
            --constructor-args $constructor_args \
            && echo -e "${GREEN}✓ $name verified${NC}" \
            || echo -e "${RED}✗ $name verification failed${NC}"
    fi
    echo ""
}

# Verify contracts without constructor args
echo "=== Contracts without constructor args ==="
echo ""
verify_contract "$DRUG_REGISTRY" "src/utils/DEDrugRegistry.sol:DEDrugRegistry"
verify_contract "$DEALERS_CORE" "src/core/DealersExeCore.sol:DealersExeCore"

# Verify contracts with constructor args
echo "=== Contracts with constructor args ==="
echo ""

# DEAreaRegistry(drugRegistry)
if [ -n "$AREA_REGISTRY" ] && [ -n "$DRUG_REGISTRY" ]; then
    ARGS=$(cast abi-encode "constructor(address)" "$DRUG_REGISTRY")
    verify_contract "$AREA_REGISTRY" "src/utils/DEAreaRegistry.sol:DEAreaRegistry" "$ARGS"
fi

# DEPaymentHandler(devWallet, bankVault)
if [ -n "$PAYMENT_HANDLER" ] && [ -n "$DEV_WALLET" ] && [ -n "$BANK_VAULT" ]; then
    ARGS=$(cast abi-encode "constructor(address,address)" "$DEV_WALLET" "$BANK_VAULT")
    verify_contract "$PAYMENT_HANDLER" "src/utils/DEPaymentHandler.sol:DEPaymentHandler" "$ARGS"
fi

# DealersExeNFT(royaltyReceiver)
if [ -n "$DEALERS_NFT" ] && [ -n "$ROYALTY_RECEIVER" ]; then
    ARGS=$(cast abi-encode "constructor(address)" "$ROYALTY_RECEIVER")
    verify_contract "$DEALERS_NFT" "src/nft/DealersExeNFT.sol:DealersExeNFT" "$ARGS"
fi

# DealersExeBoosts(core, nft, paymentHandler)
if [ -n "$DEALERS_BOOSTS" ] && [ -n "$DEALERS_CORE" ] && [ -n "$DEALERS_NFT" ] && [ -n "$PAYMENT_HANDLER" ]; then
    ARGS=$(cast abi-encode "constructor(address,address,address)" "$DEALERS_CORE" "$DEALERS_NFT" "$PAYMENT_HANDLER")
    verify_contract "$DEALERS_BOOSTS" "src/core/DealersExeBoosts.sol:DealersExeBoosts" "$ARGS"
fi

# DealersExePVE(core, nft, areaRegistry)
if [ -n "$DEALERS_PVE" ] && [ -n "$DEALERS_CORE" ] && [ -n "$DEALERS_NFT" ] && [ -n "$AREA_REGISTRY" ]; then
    ARGS=$(cast abi-encode "constructor(address,address,address)" "$DEALERS_CORE" "$DEALERS_NFT" "$AREA_REGISTRY")
    verify_contract "$DEALERS_PVE" "src/core/DealersExePVE.sol:DealersExePVE" "$ARGS"
fi

# DealersExePVP(core, nft, areaRegistry)
if [ -n "$DEALERS_PVP" ] && [ -n "$DEALERS_CORE" ] && [ -n "$DEALERS_NFT" ] && [ -n "$AREA_REGISTRY" ]; then
    ARGS=$(cast abi-encode "constructor(address,address,address)" "$DEALERS_CORE" "$DEALERS_NFT" "$AREA_REGISTRY")
    verify_contract "$DEALERS_PVP" "src/core/DealersExePVP.sol:DealersExePVP" "$ARGS"
fi

echo "=============================================="
echo "   Verification Complete"
echo "=============================================="
echo ""
echo "Note: Renderers (SVG/HTML) are deployed in EVM mode"
echo "and may need separate verification without --zksync flag."

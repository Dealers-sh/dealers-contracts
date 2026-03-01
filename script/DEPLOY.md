# Deployment Guide — Abstract Testnet

Full fresh deployment flow for Dealers.Exe contracts on Abstract Testnet.

## 1. Prerequisites

### Keystore Setup (one-time)

```bash
cast wallet import dealersKeystore --interactive
```

### Environment Config

Create a `.env` with the required config variables:

```bash
DEV_WALLET=0x...
BANK_VAULT=0x...
ROYALTY_RECEIVER=0x...
FILESTORE_ADDRESS=0xFe1411d6864592549AdE050215482e4385dFa0FB
ETHERSCAN_API_KEY=your_key

ABSTRACT_TESTNET_RPC=https://api.testnet.abs.xyz
ABSTRACT_TESTNET_CHAIN_ID=11124
```

Contract addresses are not needed in `.env` — they are auto-saved to and loaded from `script/data/deployments/testnet.json`.

## 2. Build

Build both EVM (for renderers) and zkSync (for game contracts):

```bash
forge build
forge build --zksync
```

## 3. Deploy Game Contracts

Unset any stale contract addresses, then run `DeployAll` which deploys all game contracts, wires cross-references, sets authorizations, and configures reputation tiers:

```bash
unset DRUG_REGISTRY AREA_REGISTRY DEALERS_CORE PAYMENT_HANDLER RANDOMNESS \
      DEALERS_NFT DEALERS_BOOSTS DEALERS_PVE DEALERS_PVP DEALERS_CLAIMS

source .env && forge script script/deploy/DeployAll.s.sol:DeployAll \
  --rpc-url abstract-testnet \
  --account dealersKeystore \
  --broadcast \
  --zksync \
  --skip "DealerRenderer" --skip "DeployRenderers"
```

Addresses are automatically saved to `script/data/deployments/testnet.json`. All subsequent scripts load from this file first (falling back to `.env`).

## 4. Deploy Renderers

Renderers use SSTORE2/EXTCODECOPY and must be deployed in EVM mode (no `--zksync`):

```bash
source .env && forge script script/deploy/DeployRenderers.s.sol:DeployRenderers \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast
```

Addresses are auto-saved to `script/data/deployments/testnet.json`.

## 5. Set Renderers on NFT

Use the addresses from the console output (or read them from `testnet.json`):

```bash
source .env

DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
RENDERER_SVG=$(jq -r .rendererSvg script/data/deployments/testnet.json)
RENDERER_HTML=$(jq -r .rendererHtml script/data/deployments/testnet.json)

cast send $DEALERS_NFT "setContractRendererSVG(address)" $RENDERER_SVG \
  --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore

cast send $DEALERS_NFT "setContractRendererHTML(address)" $RENDERER_HTML \
  --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

## 6. Setup Testnet Pricing (OPTIONAL)

Reduces all ETH fees by 10x for testnet (attempt resets, bribes, boosts, area movement, jail bail):

```bash
source .env && forge script script/setup/SetupTestnetPricing.s.sol:SetupTestnetPricing \
  --rpc-url $ABSTRACT_TESTNET_RPC \
  --account dealersKeystore \
  --broadcast \
  --zksync \
  --skip "DealerRenderer" --skip "DeployRenderers"
```

## 7. Setup Claims

Configures default achievement milestones:

```bash
source .env && forge script script/setup/SetupClaims.s.sol:SetupClaims \
  --rpc-url abstract-testnet \
  --account dealersKeystore \
  --broadcast \
  --zksync \
  --skip "DealerRenderer" --skip "DeployRenderers"
```

## 8. Upload SVG Traits to FileStore

Upload normal traits, special traits, and placeholder (all EVM mode, no `--zksync`).
All scripts load the renderer address from `testnet.json` automatically.

```bash
# Normal traits
forge script script/upload/UploadTraits.s.sol:UploadTraits \
  --sig "uploadNormal()" \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast

# Special traits
forge script script/upload/UploadTraits.s.sol:UploadTraits \
  --sig "uploadSpecial()" \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast

# Placeholder SVG
forge script script/upload/UploadPlaceholder.s.sol:UploadPlaceholder \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast
```

Trait pointers are cached in `script/data/traits.json` — re-running skips already-uploaded traits.

## 9. Verify Address State

All deployed addresses are persisted in `script/data/deployments/testnet.json`. You can inspect them with:

```bash
jq . script/data/deployments/testnet.json
```

Your `.env` only needs config variables (not contract addresses):

```bash
DEV_WALLET=0x...
BANK_VAULT=0x...
ROYALTY_RECEIVER=0x...
FILESTORE_ADDRESS=0xFe1411d6864592549AdE050215482e4385dFa0FB
ETHERSCAN_API_KEY=...
ABSTRACT_TESTNET_RPC=https://api.testnet.abs.xyz
ABSTRACT_TESTNET_CHAIN_ID=11124
```

## 10. Verify Configuration

Read-only check — confirms all cross-contract references and authorizations are correctly set:

```bash
forge script script/verify/VerifyConfig.s.sol:VerifyConfig \
  --rpc-url https://api.testnet.abs.xyz \
  --zksync \
  --skip "DealerRenderer" --skip "DeployRenderers"
```

No `--broadcast` needed. Reports `[OK]`, `[MISMATCH]`, or `[NEEDS CONFIG]` for every slot.

### Source Verification (block explorer)

```bash
source .env && ./script/verify-source.sh              # all contracts
source .env && ./script/verify-source.sh game          # game contracts only
source .env && ./script/verify-source.sh renderers     # renderers only
```

## Notes

- **Address persistence**: all deploy scripts save addresses to `script/data/deployments/testnet.json`. All scripts load from this file first, falling back to `.env`.
- **`DeployAll` is idempotent**: any contract with a non-zero address (from JSON or `.env`) will be skipped.
- **Two build modes**: game contracts require `--zksync`, renderers must NOT use `--zksync` (they rely on SSTORE2/EXTCODECOPY).
- **`--skip` flags**: always pass `--skip "DealerRenderer" --skip "DeployRenderers"` when building with `--zksync` to prevent compilation errors.
- **FileStore address**: `0xFe1411d6864592549AdE050215482e4385dFa0FB` — same on both mainnet and testnet.
- **Enable minting** (when ready): `cast send $(jq -r .nft script/data/deployments/testnet.json) "setMintStatus(uint8)" 3 --rpc-url https://api.testnet.abs.xyz --account dealersKeystore` (3 = PUBLIC).

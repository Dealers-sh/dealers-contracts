# Deployment Guide — Abstract Testnet

## TLDR Checklist

```
 1. cast wallet import dealersKeystore --interactive     (one-time)
 2. Create .env with DEV_WALLET, BANK_VAULT, ROYALTY_RECEIVER, ETHERSCAN_API_KEY
 3. forge build && forge build --zksync                  (EVM + zkSync)
 4. DeployAll.s.sol            --zksync                  (12 game contracts + wire + tiers)
 5. DeployRenderers.s.sol      NO --zksync               (SVG + HTML renderers)
 6. cast send NFT setContractRendererSVG/HTML             (link renderers)
 7. UploadPlaceholder.s.sol    NO --zksync               (fallback SVG)
 8. UploadTraits — uploadNormal() + uploadSpecial()       (trait SVGs to FileStore)
 9. UploadOneOfOnes.s.sol      NO --zksync               (optional: 1/1 SVGs)
10. SetupClaims.s.sol          --zksync                  (22 achievements)
11. SetupTestnetPricing.s.sol  --zksync                  (optional: 10x fee reduction)
12. batchSetTraits on RendererSVG                         (assign traits to tokens)
13. reveal() on RendererSVG                               (switch from placeholder)
14. setMintStatus(3) on NFT                               (enable public mint)
15. VerifyConfig.s.sol                                    (read-only sanity check)
16. verify-source.sh                                      (optional: block explorer)
```

---

## 1. Prerequisites

### Keystore (one-time)

```bash
cast wallet import dealersKeystore --interactive
```

### .env

```bash
DEV_WALLET=0x...
BANK_VAULT=0x...
ROYALTY_RECEIVER=0x...
ETHERSCAN_API_KEY=your_key
ABSTRACT_TESTNET_RPC=https://api.testnet.abs.xyz
```

Contract addresses are managed via `script/data/deployments/testnet.json` — do not put them in `.env`.

### Build

```bash
forge build                                              # EVM (renderers)
forge build --zksync --skip "RendererSVG"  # zkSync (game)
```

---

## 2. Deploy Game Contracts

Deploys all 12 game contracts in dependency order, wires cross-references, sets authorizations, and configures 10-tier reputation system.

For a fresh deploy, delete the JSON first: `rm -f script/data/deployments/testnet.json`

```bash
source .env && forge script script/deploy/DeployAll.s.sol:DeployAll \
  --rpc-url abstract-testnet \
  --account dealersKeystore \
  --broadcast \
  --zksync \
  --skip "RendererSVG"
```

Contracts deployed: DEDrugRegistry, DEAreaRegistry, DealersExeCore, DEPaymentHandler, DERandomness, DealersExeNFT, DealersExeBoosts, DealersExePVE, DealersExePVP, DealersExeClaims, DealersExeActions, DealersExeMulticall.

Addresses auto-saved to `script/data/deployments/testnet.json`.

---

## 3. Deploy Renderers

Renderers use SSTORE2/EXTCODECOPY — must deploy in EVM mode (no `--zksync`).

```bash
source .env && forge script script/deploy/DeployRenderers.s.sol:DeployRenderers \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast
```

Deploys DealerRendererSVG and DealerRendererHTML. The HTML renderer points to FileStore (`0xFe1411d6864592549AdE050215482e4385dFa0FB`) and defaults to `src1.min.js.gz` (already on FileStore).

---

## 4. Link Renderers to NFT

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

---

## 5. Upload Placeholder SVG

Fallback image shown before reveal or for tokens without traits assigned.

```bash
source .env && forge script script/upload/UploadPlaceholder.s.sol:UploadPlaceholder \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast
```

Reads from `script/data/traits.json` → `.placeholder`. Large SVGs auto-chunked via SSTORE2.

---

## 6. Upload Trait SVGs

Uploads trait SVG art to FileStore and registers them on DealerRendererSVG. Pointers cached in `script/data/traits.json` — re-running skips already-uploaded traits.

```bash
# Normal traits
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits \
  --sig "uploadNormal()" \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast

# Special traits
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits \
  --sig "uploadSpecial()" \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast
```

---

## 7. Upload One-of-Ones (optional)

Upload unique SVGs and assign them to specific token IDs.

```bash
# Upload SVGs to FileStore
source .env && forge script script/upload/UploadOneOfOnes.s.sol:UploadOneOfOnes \
  --sig "uploadOneOfOnes()" \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast

# Assign to token IDs (off-chain determined)
source .env && forge script script/upload/UploadOneOfOnes.s.sol:UploadOneOfOnes \
  --sig "assignAllOneOfOnes(uint256[])" "[1,42,100]" \
  --rpc-url https://api.testnet.abs.xyz \
  --account dealersKeystore \
  --broadcast
```

---

## 8. Setup Claims

Configures 22 achievement milestones (PVE/PVP wins, rep milestones, drug rewards).

```bash
source .env && forge script script/setup/SetupClaims.s.sol:SetupClaims \
  --rpc-url abstract-testnet \
  --account dealersKeystore \
  --broadcast \
  --zksync \
  --skip "RendererSVG"
```

---

## 9. Setup Testnet Pricing (optional)

Divides all ETH fees by 10 for cheaper testnet gameplay.

```bash
source .env && forge script script/setup/SetupTestnetPricing.s.sol:SetupTestnetPricing \
  --rpc-url abstract-testnet \
  --account dealersKeystore \
  --broadcast \
  --zksync \
  --skip "RendererSVG"
```

---

## 10. Assign Traits to Tokens

After minting, assign traits to token IDs. Traits are generated off-chain and packed into bytes32.

```bash
RENDERER_SVG=$(jq -r .rendererSvg script/data/deployments/testnet.json)

cast send $RENDERER_SVG "batchSetTraits(uint256[],bytes32[])" \
  "[1,2,3]" "[0x...,0x...,0x...]" \
  --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

Each bytes32: 12 trait uint8s (bytes 0-11) + character type uint8 (byte 12).

---

## 11. Reveal

Switches all tokens from placeholder to their actual trait-based SVGs. Call only after all traits and placeholder are uploaded.

```bash
RENDERER_SVG=$(jq -r .rendererSvg script/data/deployments/testnet.json)

cast send $RENDERER_SVG "reveal()" \
  --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

---

## 12. Enable Minting

```bash
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)

cast send $DEALERS_NFT "setMintStatus(uint8)" 3 \
  --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

Mint statuses: `0` DISABLED, `1` FAMILY, `2` WHITELIST, `3` PUBLIC.

---

## 13. Verify Configuration

Read-only — confirms all cross-contract references and authorizations.

```bash
forge script script/verify/VerifyConfig.s.sol:VerifyConfig \
  --rpc-url https://api.testnet.abs.xyz \
  --skip "RendererSVG"
```

Reports `[OK]`, `[MISMATCH]`, or `[NEEDS CONFIG]` for every slot.

---

## 14. Source Verification (optional)

```bash
source .env && ./script/verify-source.sh              # all contracts
source .env && ./script/verify-source.sh game          # game contracts only
source .env && ./script/verify-source.sh renderers     # renderers only
```

---

## Redeploying Individual Contracts

Each contract has its own deploy script. After deploying, run SetupWiring to re-wire.

| Contract | Script | Constructor Deps |
|----------|--------|-----------------|
| DEDrugRegistry | `DeployDrugRegistry.s.sol` | none |
| DEAreaRegistry | `DeployAreaRegistry.s.sol` | drugRegistry |
| DealersExeCore | `DeployCore.s.sol` | none |
| DEPaymentHandler | `DeployPaymentHandler.s.sol` | devWallet, bankVault |
| DERandomness | `DeployRandomness.s.sol` | none |
| DealersExeNFT | `DeployNFT.s.sol` | royaltyReceiver |
| DealersExeBoosts | `DeployBoosts.s.sol` | core, nft, paymentHandler |
| DealersExePVE | `DeployPVE.s.sol` | core, nft, areaRegistry |
| DealersExePVP | `DeployPVP.s.sol` | core, nft, areaRegistry |
| DealersExeClaims | `DeployClaims.s.sol` | core, nft, pve, pvp |
| DealersExeActions | `DeployActions.s.sol` | core, nft, areaRegistry |
| DealersExeMulticall | `DeployMulticall.s.sol` | core, pve, pvp, areaRegistry, drugRegistry |

### Workflow: Deploy + Re-wire

```bash
# 1. Deploy the contract
source .env && forge script script/deploy/Deploy<Contract>.s.sol:<Contract> \
  --rpc-url abstract-testnet \
  --account dealersKeystore \
  --broadcast \
  --zksync \
  --skip "RendererSVG"

# 2. Re-wire (idempotent — only updates stale references)
source .env && forge script script/setup/SetupWiring.s.sol:SetupWiring \
  --rpc-url abstract-testnet \
  --account dealersKeystore \
  --broadcast \
  --zksync \
  --skip "RendererSVG"
```

### Redeploying Core

Most impactful — every module references Core. After deploying a new Core:

1. Run SetupWiring (re-wires all modules + re-authorizes)
2. Run SetupTiers (reputation tiers are stored on Core)

```bash
source .env && forge script script/setup/SetupTiers.s.sol:SetupTiers \
  --rpc-url abstract-testnet \
  --account dealersKeystore \
  --broadcast \
  --zksync \
  --skip "RendererSVG"
```

---

## Notes

- **Address persistence**: all deploy scripts save to `script/data/deployments/testnet.json`. Scripts load from JSON first, falling back to `.env`.
- **Idempotent**: DeployAll skips contracts with existing addresses. SetupWiring checks state before calling setters. Safe to re-run.
- **Two build modes**: game contracts require `--zksync`, renderers must NOT use `--zksync` (SSTORE2/EXTCODECOPY).
- **`--skip` flags**: always pass `--skip "RendererSVG"` with `--zksync` to prevent compilation errors.
- **FileStore**: `0xFe1411d6864592549AdE050215482e4385dFa0FB` — same on mainnet and testnet. Gzipped JS (`src1.min.js.gz`) already uploaded.
- **Fresh deploy**: delete `script/data/deployments/testnet.json` before running DeployAll.

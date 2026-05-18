# Deployment Guide — Abstract (Testnet + Mainnet)

All deployment scripts read addresses from `script/data/deployments/{NETWORK}.json` and trait pointers from `script/data/{NETWORK}/pointers.json`, where `{NETWORK}` is `testnet` (chain 11124) or `mainnet` (chain 2741).

Shell orchestrators (`upload-traits.sh`, `verify-source.sh`) honor a single env var:

```bash
NETWORK=testnet ./script/upload-traits.sh         # default
NETWORK=mainnet ./script/upload-traits.sh         # mainnet
```

For Solidity scripts the network is detected from `block.chainid` via the `--rpc-url` you pass — no env var required there. Examples below show testnet RPCs; swap in `https://api.mainnet.abs.xyz` for mainnet.


## TLDR Checklist

```
 1. cast wallet import dealersKeystore --interactive     (one-time)
 2. Create .env with DEV_WALLET, BANK_VAULT, ROYALTY_RECEIVER, ETHERSCAN_API_KEY
 3. forge build && forge build --zksync --skip "RendererSVG"  (EVM + zkSync)
 4. DeployAll.s.sol            --zksync                  (13 contracts + drugs/areas + wire + tiers + claims + chat)
 5. DeployRendererSVG.s.sol    NO --zksync               (SVG renderer, EVM mode)
 6. cast send NFT setContractRendererSVG(address)         (link SVG to NFT)
 7. DeployHtmlRenderer.s.sol   --zksync                  (HTML renderer + config + link to NFT)
 8. UploadPlaceholder.s.sol    NO --zksync               (fallback SVG)
 9. UploadTraits — uploadNormal() + uploadSpecial()       (trait SVGs to FileStore)
10. UploadTraits — uploadOneOfOnesRange()  NO --zksync   (1/1 SVGs to FileStore)
11. UploadGzipJs.s.sol upload()    NO --zksync           (upload JS to FileStore)
12. UploadGzipJs.s.sol setFilename --zksync              (set filename on HTML renderer)
13. SetupTestnetPricing.s.sol  --zksync                  (optional: 10x fee reduction)
14. AssignTraits — assignTokenTraits()/assignOneOfOnes() NO --zksync (reveal-time mapping)
15. reveal() on RendererSVG                               (switch from placeholder)
16. setMintStatus(3) on NFT                               (enable public mint)
17. VerifyConfig.s.sol                                    (read-only sanity check)
18. verify-source.sh                                      (optional: block explorer)
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

Contract addresses are managed via `script/data/deployments/{NETWORK}.json` — do not put them in `.env`.

### Build

```bash
forge build                                  # EVM (renderers)
forge build --zksync --skip "RendererSVG"     # zkSync (game)
```

---

## 2. Deploy Game Contracts

Deploys all 13 game contracts in dependency order, registers drugs, creates areas, wires cross-references, sets authorizations, and configures the 10-tier reputation system.

For a fresh deploy, delete the JSON first: `rm -f script/data/deployments/testnet.json`

```bash
source .env && forge script script/deploy/DeployAll.s.sol:DeployAll --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG"
```

Contracts deployed: DealersDrugRegistry, DealersAreaRegistry, DealersCore, DealersPaymentHandler, DealersRandomness, DealersNFT, DealersBoosts, DealersPVE, DealersPVP, DealersClaims, DealersActions, DealersMulticall, DealersChatFactory, DealersAreaChatGate.

Setups included: 11 drugs, 7 areas, all cross-contract wiring + authorizations, 10-tier reputation system, 24 achievements, WORLD + 9 area chat rooms.

Addresses auto-saved to `script/data/deployments/testnet.json`.

---

## 3. Deploy SVG Renderer

Uses SSTORE2/EXTCODECOPY — must deploy in EVM mode (no `--zksync`).

```bash
source .env && forge script script/deploy/DeployRendererSVG.s.sol:DeployRendererSVG --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

### Link SVG Renderer to NFT

The NFT contract is zkSync-native, so linking must be done via `cast send`:

```bash
source .env
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
RENDERER_SVG=$(jq -r .rendererSvg script/data/deployments/testnet.json)
cast send $DEALERS_NFT "setContractRendererSVG(address)" $RENDERER_SVG --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

---

## 4. Deploy HTML Renderer

Deploys as zkSync-native. Configures RPC URL, SVG renderer reference, and links to NFT in one step. Uses a placeholder gzip filename if none is set — update it after uploading the actual gzip (step 8).

```bash
source .env && forge script script/deploy/DeployHtmlRenderer.s.sol:DeployHtmlRenderer --zksync --skip "RendererSVG" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

---

## 5. Upload Placeholder SVG

Fallback image shown before reveal or for tokens without traits assigned.

```bash
source .env && forge script script/upload/UploadPlaceholder.s.sol:UploadPlaceholder --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

Reads from `script/data/traits.json` -> `.placeholder`. Large SVGs auto-chunked via SSTORE2.

---

## 6. Upload Trait SVGs

Uploads trait SVG art to FileStore and registers them on DealerRendererSVG. Pointers cached in `script/data/traits.json` — re-running skips already-uploaded traits.

```bash
# Normal traits
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadNormal()" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast

# Special traits
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadSpecial()" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

---

## 7. Upload One-of-Ones (optional)

Two separate phases: upload SVG content to FileStore (prep), then assign pointers
to token IDs (only at reveal time).

```bash
# Upload SVGs to FileStore in chunks (writes pointers back to traits.json)
source .env && forge script script/upload/UploadTraits.s.sol:UploadTraits --sig "uploadOneOfOnesRange(uint256,uint256)" 0 5 --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast --slow
# ...repeat with 5 5, 10 5, ..., 40 5 until all 45 are uploaded

# Assign cached pointers to token IDs (run once, at reveal time)
source .env && forge script script/upload/AssignTraits.s.sol:AssignTraits --sig "assignOneOfOnes(uint256[])" "[1,42,100,...]" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

---

## 8. Upload Gzip JS + Set Filename

Two-step process due to Abstract's dual VM. The gzip is built from the app after contract addresses are known.

### Prerequisites

```bash
cd ../dealers-app && ./build-single-file.sh
```

This copies output to `script/data/dealers.js.gz.b64`.

### Step 1: Upload to FileStore (EVM mode)

```bash
source .env && forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs --sig "upload()" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

### Step 2: Set filename on HTML renderer (zkSync mode)

```bash
source .env && forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs --sig "setFilename(string)" "dealers-testnet-1776332930.js.gz" --zksync --skip "RendererSVG" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

---

## 9. Setup Testnet Pricing (optional)

Divides all ETH fees by 10 for cheaper testnet gameplay.

```bash
source .env && forge script script/setup/SetupTestnetPricing.s.sol:SetupTestnetPricing --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG"
```

---

## 10. Assign Traits to Tokens

After minting, assign traits to token IDs. Traits are generated off-chain and packed into bytes32.

```bash
RENDERER_SVG=$(jq -r .rendererSvg script/data/deployments/testnet.json)
cast send $RENDERER_SVG "batchSetTraits(uint256[],bytes32[])" "[1,2,3]" "[0x...,0x...,0x...]" --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

Each bytes32: 12 trait uint8s (bytes 0-11) + character type uint8 (byte 12).

---

## 11. Reveal

Switches all tokens from placeholder to their actual trait-based SVGs. Call only after all traits and placeholder are uploaded.

```bash
RENDERER_SVG=$(jq -r .rendererSvg script/data/deployments/testnet.json)
cast send $RENDERER_SVG "reveal()" --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

---

## 12. Enable Minting

```bash
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
cast send $DEALERS_NFT "setMintStatus(uint8)" 3 --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore
```

Mint statuses: `0` DISABLED, `1` FAMILY, `2` WHITELIST, `3` PUBLIC.

---

## 13. Verify Configuration

Read-only — confirms all cross-contract references and authorizations.

```bash
forge script script/verify/VerifyConfig.s.sol:VerifyConfig --rpc-url https://api.testnet.abs.xyz --zksync --skip "RendererSVG"
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
| DealersDrugRegistry | `DeployDrugRegistry.s.sol` | none |
| DealersAreaRegistry | `DeployAreaRegistry.s.sol` | drugRegistry |
| DealersCore | `DeployCore.s.sol` | none |
| DealersPaymentHandler | `DeployPaymentHandler.s.sol` | devWallet, bankVault |
| DealersRandomness | `DeployRandomness.s.sol` | none |
| DealersNFT | `DeployNFT.s.sol` | royaltyReceiver |
| DealersBoosts | `DeployBoosts.s.sol` | core, nft, paymentHandler |
| DealersPVE | `DeployPVE.s.sol` | core, nft, areaRegistry |
| DealersPVP | `DeployPVP.s.sol` | core, nft, areaRegistry |
| DealersClaims | `DeployClaims.s.sol` | core, nft, pve, pvp |
| DealersActions | `DeployActions.s.sol` | core, nft, areaRegistry |
| DealersMulticall | `DeployMulticall.s.sol` | core, pve, pvp, areaRegistry, drugRegistry |
| DealersChatFactory | `DeployChatFactory.s.sol` | nft |

### Workflow: Deploy + Re-wire

```bash
# 1. Deploy the contract
source .env && forge script script/deploy/Deploy<Contract>.s.sol:<Contract> --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG"

# 2. Re-wire (idempotent — only updates stale references)
source .env && forge script script/setup/SetupWiring.s.sol:SetupWiring --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG"
```

### Redeploying Core

Most impactful — every module references Core. After deploying a new Core:

1. Run SetupWiring (re-wires all modules + re-authorizes)
2. Run SetupTiers (reputation tiers are stored on Core)

```bash
source .env && forge script script/setup/SetupTiers.s.sol:SetupTiers --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync --skip "RendererSVG"
```

---

## Notes

- **Address persistence**: all deploy scripts save to `script/data/deployments/testnet.json`. Scripts load from JSON first, falling back to `.env`.
- **Idempotent**: DeployAll skips contracts with existing addresses. SetupWiring checks state before calling setters. Safe to re-run.
- **Two build modes**: game contracts require `--zksync`, renderers must NOT use `--zksync` (SSTORE2/EXTCODECOPY).
- **`--skip` flags**: always pass `--skip "RendererSVG"` with `--zksync` to prevent compilation errors.
- **FileStore**: `0xFe1411d6864592549AdE050215482e4385dFa0FB` — same on mainnet and testnet.
- **Fresh deploy**: delete `script/data/deployments/testnet.json` before running DeployAll.

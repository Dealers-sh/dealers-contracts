---
paths: "**/*.sol, foundry.toml"
---

## Abstract Chain Foundry Rules

### Build Commands

Abstract uses zkSync VM natively, but also supports EVM bytecode via interpreter.

```bash
# Native zkSync build (game contracts) - skip renderer contracts and their deployment script
forge build --zksync --skip "RendererSVG"

# Standard EVM build (renderer contracts use SSTORE2/FileStore with EXTCODECOPY)
forge build

# Tests
forge test --zksync --skip "RendererSVG"
```

### Two-Path Deployment Strategy

**DealerRendererSVG** uses `EXTCODECOPY` via SSTORE2/FileStore — deploys as EVM bytecode (no `--zksync`).

**DealerRendererHTML** no longer uses EXTCODECOPY (browser fetches from FileStore at runtime) — deploys as native zkSync bytecode.

**Game contracts** (Core, NFT, PVE, PVP, Boosts, etc.) deploy as native zkSync bytecode.

```bash
# Deploy SVG renderer (EVM mode - no --zksync flag)
forge script script/deploy/DeployRendererSVG.s.sol:DeployRendererSVG \
  --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast

# Deploy HTML renderer (zkSync native - includes configuration)
forge script script/deploy/DeployHtmlRenderer.s.sol:DeployHtmlRenderer \
  --zksync --skip "RendererSVG" \
  --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

### Chain Configuration

| Property | Mainnet | Testnet |
|----------|---------|---------|
| Name | Abstract | Abstract Testnet |
| Chain ID | 2741 | 11124 |
| RPC URL | https://api.mainnet.abs.xyz | https://api.testnet.abs.xyz |
| Explorer | https://abscan.org/ | https://sepolia.abscan.org/ |

### EVM Interpreter Limitations

When deploying EVM bytecode contracts:
- `DELEGATECALL` between EVM and native contracts will revert
- Gas costs 150-400% higher than native zkSync contracts
- Unsupported opcodes: `CALLCODE`, `SELFDESTRUCT`, `BLOBHASH`, `BLOBBASEFEE`

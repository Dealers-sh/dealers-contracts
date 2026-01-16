---
paths: "**/*.sol, foundry.toml"
---

## Abstract Chain Foundry Rules

### Build Commands

Abstract uses zkSync VM natively, but also supports EVM bytecode via interpreter.

```bash
# Native zkSync build (game contracts) - skip renderer contracts and their deployment script
forge build --zksync --skip "DealerRenderer" --skip "DeployRenderers"

# Standard EVM build (renderer contracts use SSTORE2/FileStore with EXTCODECOPY)
forge build

# Tests
forge test --zksync --skip "DealerRenderer" --skip "DeployRenderers"
```

### Two-Path Deployment Strategy

**Renderer contracts** (DealerRendererSVG, DealerRendererHTML) use `EXTCODECOPY` via SSTORE2/FileStore, which is not supported natively on zkSync VM. These deploy as EVM bytecode via Abstract's EVM interpreter (150-400% higher gas, but functionally equivalent).

**Game contracts** (Core, NFT, PVE, PVP, Boosts, etc.) deploy as native zkSync bytecode for optimal gas efficiency.

```bash
# Deploy renderers (EVM interpreter mode - no --zksync flag)
forge script script/DeployRenderers.s.sol --rpc-url https://api.testnet.abs.xyz --broadcast

# Deploy game contracts (native zkSync mode)
forge script script/DeployGame.s.sol --zksync --rpc-url https://api.testnet.abs.xyz --broadcast
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

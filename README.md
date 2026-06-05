# Dealers.sh

[![CI](https://github.com/Dealers-sh/dealers-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/Dealers-sh/dealers-contracts/actions/workflows/ci.yml)
![Solidity](https://img.shields.io/badge/Solidity-0.8.28-363636?logo=solidity)
![Built with](https://img.shields.io/badge/Built%20with-Foundry--zkSync-2f3136)
![Abstract](https://img.shields.io/badge/Abstract-chain%202741-1be3a3)
![License](https://img.shields.io/badge/License-Proprietary-red)

On-chain PvE/PvP mafia strategy game on [Abstract Chain](https://abs.xyz) (zkSync-based L2). Hustles,
same-area battles, daily push-your-luck heists, and dynamic NFT dealers with fully on-chain SVG +
interactive HTML renders.

> **Audit:** scope, trust model, and build commands for reviewers are in [AUDIT.md](AUDIT.md).

## Architecture

Game state lives in `DealersCore`; every module is authorized there via `onlyAuthorized` and is
independently swappable.

| Contract | Area | Purpose | Audit |
|---|---|---|:--:|
| `DealersCore` | core | Central state hub (dealer data, drugs, rep, heat/jail, boosts) | ✅ |
| `DealersPVE` | core | Player vs Environment hustles | ✅ |
| `DealersPVP` | core | Player vs Player same-area battles | ✅ |
| `DealersBoosts` | core | Tiered, time-limited boosts (Grinder → Godfather) | ✅ |
| `DealersActions` | core | Movement, bail, bribe, safe house, arrests | ✅ |
| `DealersClaims` | core | Achievement / admin reward claims | ✅ |
| `DealersHeists` | core | Daily push-your-luck heist runs + optional ETH jackpot (Pyth) | ✅ |
| `DealersMulticall` | core | Read-only aggregator for frontends | ✅ |
| `DealersBankHeist` | core | Recurring community bank-heist event | 🧪 concept |
| `DealersNFT` | nft | ERC721 dealers (10,000 supply) with on-chain metadata | ✅ |
| `DealerRendererSVG` | nft | Dynamic SVG from per-token traits (SSTORE2) | ◐ |
| `DealerRendererHTML` | nft | Interactive HTML via FileStore (`animation_url`) | ◐ |
| `DealersPaymentHandler` | utils | ETH custody + fee distribution | ✅ |
| `DealersRandomness` | utils | In-house commit-reveal randomness | ✅ |
| `DealersAreaRegistry` | utils | Areas, drug pricing, dealer locations | ✅ |
| `DealersDrugRegistry` | utils | Global drug registry | ✅ |
| `Dealers{ChatFactory,ChatRoom,AreaChatGate}` | social | On-chain area-gated chat | ◐ |

✅ in audit scope · 🧪 concept, **not deployed** & out of scope · ◐ view/peripheral, scope to confirm — see [AUDIT.md](AUDIT.md).

## Build

Abstract runs the zkSync VM natively, but the SVG renderer uses `EXTCODECOPY` (SSTORE2/FileStore) and
must be built as **EVM** bytecode. Two paths — requires [foundry-zksync](https://github.com/matter-labs/foundry-zksync):

```bash
# Game contracts (native zkSync) — skip the EVM-only artifacts
forge build --zksync --skip "RendererSVG" --skip "UploadTraits"

# SVG renderer (EVM bytecode)
forge build
```

## Test

```bash
forge test --zksync --skip "RendererSVG" --skip "UploadTraits"   # game contracts
forge test --match-contract "DealerRendererSVG"                  # EVM renderer
```

## Deploy

Full step-by-step lives in [script/DEPLOY.md](script/DEPLOY.md). Quick start:

```bash
# One-time encrypted keystore
cast wallet import dealersKeystore --interactive

# Deploy the full stack to testnet
forge script script/deploy/DeployAll.s.sol:DeployAll --zksync --skip "RendererSVG" \
  --rpc-url abstract-testnet --account dealersKeystore --broadcast
```

The SVG renderer deploys **without** `--zksync` (SSTORE2/EXTCODECOPY is EVM-only). Testnet-only setup
(`SetupTestnetDealers`, `SetupTestnetPricing`) lives in [script/testnet/](script/testnet/); the
`DealersBankHeist` concept ships separately via `script/deploy/DeployBankHeist.s.sol` and is not part
of the audited launch.

## Networks

| Network | Chain ID | RPC | Explorer |
|---|---|---|---|
| Abstract Mainnet | 2741 | `https://api.mainnet.abs.xyz` | [abscan.org](https://abscan.org) |
| Abstract Testnet | 11124 | `https://api.testnet.abs.xyz` | [sepolia.abscan.org](https://sepolia.abscan.org) |

## Repo layout

```
src/      core/ · nft/ · social/ · utils/ (+ utils/pyth/)   — contracts + interfaces
script/   deploy/ · setup/ · testnet/ · upload/ · verify/ · base/ · data/
test/     unit/ · integration/ · heists/ · simulation/ · base/
```

## Dependencies

- [OpenZeppelin v5.5.0](https://github.com/OpenZeppelin/openzeppelin-contracts) — ERC721Enumerable, ReentrancyGuard, ECDSA
- [Solady](https://github.com/Vectorized/solady) — Ownable, LibString, Base64
- [Pyth Entropy](https://docs.pyth.network/entropy) — heist jackpot randomness
- [forge-std](https://github.com/foundry-rs/forge-std) — testing

## License

Proprietary — all rights reserved. This code may not be copied, modified, or distributed without
explicit permission.

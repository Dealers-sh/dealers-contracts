# Dealers.sh

On-chain mafia strategy game on [Abstract Chain](https://abs.xyz). PvE hustles, PvP battles, dynamic NFT dealers with fully on-chain SVG + interactive HTML renders.

## Architecture

```
src/
  core/          Game logic
    DealersCore          Central state hub (dealer data, drugs, rep tiers, heat/jail)
    DealersPVE           Player vs Environment — buy/sell/intimidate hustles
    DealersPVP           Player vs Player — same-area battles with drug/cash theft
    DealersBoosts        Tiered boost system (Grinder → Godfather)
    DealersActions       Player actions (movement, bail, bribe, cash topup)
    DealersClaims        Achievement / reward claims
    DealersMulticall     Batched read API for frontends

  nft/           NFT + rendering
    DealersNFT           ERC721 (8,888 supply) with on-chain metadata
    DealerRendererSVG    Dynamic SVG from per-token traits (SSTORE2)
    DealerRendererHTML   Interactive HTML via FileStore (animation_url)

  social/        On-chain chat
    DealersChatFactory   Deploys gated chat rooms
    DealersChatRoom      Per-room messaging
    DealersAreaChatGate  Area-based access control

  utils/         Shared infrastructure
    DealersAreaRegistry      Areas, drug pricing, dealer locations
    DealersDrugRegistry      Drug definitions, supply tracking
    DealersPaymentHandler    ETH fee collection and distribution
    DealersRandomness        Seeded randomness (prevrandao + nonce)
```

All game modules are authorized in `DealersCore` via `onlyAuthorized`. State lives in Core; modules are swappable.

## Build

Requires [foundry-zksync](https://github.com/matter-labs/foundry-zksync).

```bash
forge build --zksync --skip "RendererSVG"   # game contracts (zkSync native)
forge build                                  # renderer contracts (EVM bytecode)
```

## Test

```bash
forge test --zksync --skip "RendererSVG" -vvv
```

## Deploy

```bash
# One-time keystore setup
cast wallet import dealersKeystore --interactive

# Deploy all
./script/deploy-all.sh

# Individual deploys
forge script script/deploy/DeployAll.s.sol --zksync --skip "RendererSVG" \
  --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
```

SVG renderer deploys without `--zksync` (uses SSTORE2/EXTCODECOPY — EVM only).

## Networks

| Network | Chain ID | RPC |
|---------|----------|-----|
| Abstract Mainnet | 2741 | `https://api.mainnet.abs.xyz` |
| Abstract Testnet | 11124 | `https://api.testnet.abs.xyz` |

## Dependencies

- [OpenZeppelin v5.4.0](https://github.com/OpenZeppelin/openzeppelin-contracts) — ERC721Enumerable, ReentrancyGuard, ECDSA
- [Solady](https://github.com/Vectorized/solady) — Ownable, LibString, Base64
- [forge-std](https://github.com/foundry-rs/forge-std) — Testing

## License

All rights reserved. This code is proprietary and may not be copied, modified, or distributed without explicit permission.

# Dealers.exe

On-chain mafia strategy game on [Abstract Chain](https://abs.xyz). PvE hustles, PvP battles, dynamic NFT dealers with fully on-chain SVG + interactive HTML renders.

## Architecture

```
src/
  core/          Game logic
    DealersExeCore       Central state hub (dealer data, drugs, rep tiers, heat/jail)
    DealersExePVE        Player vs Environment — buy/sell/intimidate hustles
    DealersExePVP        Player vs Player — same-area battles with drug/cash theft
    DealersExeBoosts     Tiered boost system (Grinder → Godfather)
    DealersExeActions    Player actions (movement, bail, bribe, cash topup)
    DealersExeClaims     Achievement / reward claims
    DealersExeMulticall  Batched read API for frontends

  nft/           NFT + rendering
    DealersExeNFT        ERC721 (8,888 supply) with on-chain metadata
    DealerRendererSVG    Dynamic SVG from per-token traits (SSTORE2)
    DealerRendererHTML   Interactive HTML via FileStore (animation_url)

  social/        On-chain chat
    DEChatFactory        Deploys gated chat rooms
    DEChatRoom           Per-room messaging
    DEAreaChatGate       Area-based access control

  utils/         Shared infrastructure
    DEAreaRegistry       Areas, drug pricing, dealer locations
    DEDrugRegistry       Drug definitions, supply tracking
    DEPaymentHandler     ETH fee collection and distribution
    DERandomness         Seeded randomness (prevrandao + nonce)
```

All game modules are authorized in `DealersExeCore` via `onlyAuthorized`. State lives in Core; modules are swappable.

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

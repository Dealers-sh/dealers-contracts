# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Dealers.sh / Drug Wars** - An on-chain PvE/PvP mafia strategy game built on Abstract Chain with dynamic NFT dealers, embedded gameplay interfaces, and player-to-player drug trading.

This is a Foundry project targeting Abstract Chain (zkSync-based L2). The project uses Abstract Chain's FileStore (address: `0xFe1411d6864592549AdE050215482e4385dFa0FB` on both mainnet and testnet) for on-chain file storage.

## Commands

### Building
```bash
forge build
```

### Testing
```bash
forge test
forge test -vvv  # verbose output
```

### Deployment
```bash
# Set up encrypted keystore (one-time)
cast wallet import dealersKeystore --interactive

# Deploy all contracts to Abstract testnet
./script/deploy-all.sh

# Deploy individual contracts
./script/deploy-core.sh
./script/deploy-nft.sh
# etc.
```

### Gas Snapshots
```bash
forge snapshot
```

## Architecture

### Modular Contract System

The project follows a **modular architecture** where a central data contract (`DealersCore`) manages all game state, while specialized module contracts handle specific game mechanics. This design enables:
- Easy addition of new game features without touching core state
- Clear separation of concerns
- Upgradeable game modules while maintaining state continuity

### Core Contracts

**DealersCore** ([src/DealersCore.sol](src/DealersCore.sol))
- Central state management hub for all game data
- Stores dealer stats (reputation, area, heat level, attempts)
- Manages drug balances per dealer (tokenId => drugId => amount)
- Handles area/drug configuration, supply caps, jail/safe house mechanics
- Boost system for time-limited multipliers
- Authorization system: Only authorized contracts can modify state via `onlyAuthorized` modifier

**DealersNFT** ([src/DealersNFT.sol](src/DealersNFT.sol))
- ERC721 with dynamic on-chain metadata and embedded HTML gameplay UI
- Max supply: 10000 NFTs with 100 reserved
- Minting stages: DISABLED → FAMILY → WHITELIST → PUBLIC
- Per-token seed generation for deterministic trait rendering
- Integrates with renderer contracts (SVG + HTML) for fully on-chain visuals

**DealersPVE** ([src/DealersPVE.sol](src/DealersPVE.sol))
- Player-vs-Environment game module using `prevrandao` for randomness
- Rock-paper-scissors style gameplay: DEAL/THREATEN/BAIL
- Drug rewards with boost multipliers, jail checks, heat increment

**DealersBoosts** ([src/DealersBoosts.sol](src/DealersBoosts.sol))
- 3 boost tiers: Grinder (24h), Hustler (7d), Kingpin (30d)
- Multipliers for drugs, reputation, extra attempts

**DealersPVP** ([src/DealersPVP.sol](src/DealersPVP.sol))
- Same-area PVP requirement
- Win chance: 50% + (threat - armor), capped 25-75%
- 1-hour cooldown, 2% drug steal on win

**DealersPaymentHandler** ([src/DealersPaymentHandler.sol](src/DealersPaymentHandler.sol))
- Centralized ETH management and fee distribution
- Abstract Chain compatible (uses `.call()` instead of `.transfer()`)

### Renderer Architecture

**DealerRendererSVG** ([src/DealerRendererSVG.sol](src/DealerRendererSVG.sol))
- Generates dynamic SVG art for dealers based on token seed
- Character type distribution system (1/1s, special editions)

**DealerRendererHTML** ([src/DealerRendererHTML.sol](src/DealerRendererHTML.sol))
- Wraps SVG in interactive HTML for `animation_url`
- Uses EthFS/FileStore for on-chain file storage

### Network Configuration

Networks are configured in `foundry.toml`:
- **Abstract Mainnet**: Chain ID 2741, RPC: `https://api.mainnet.abs.xyz`
- **Abstract Testnet**: Chain ID 11124, RPC: `https://api.testnet.abs.xyz`

Deployment uses `--zksync` flag for Abstract Chain compatibility.

## Contract Dependencies

- **OpenZeppelin v5.4.0**: ERC721Enumerable, ReentrancyGuard, ECDSA
- **Solady**: Ownable, LibString, Base64, gas-optimized utilities
- **forge-std**: Testing framework

## Development Notes

### Authorization Pattern
All game modules must be authorized in `DealersCore.authorizeContract()` before they can modify state.

### Supply Management
Drug supply is capped per rarity:
- Common: 10,000,000
- Uncommon: 1,000,000
- Rare: 100,000

### Heat & Jail System
- Heat level 0-5 determines jail chance percentage
- Jail: Pay bail to exit, 10% reputation penalty (capped at 50)
- Safe House: Free to enter, costs movement fee to leave. No farming allowed. Manhattan is the starting area.

### Gas Optimization
- Optimizer: 200 runs with via-ir enabled
- Pack related uint8/uint32 fields in single storage slots
- Use unchecked blocks for safe arithmetic
- Cache storage reads in memory variables

### Solidity Version
All contracts use `^0.8.28` with via-ir compilation.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Dealers.Exe / Drug Wars** - An on-chain PvE/PvP mafia strategy game built on Abstract Chain with dynamic NFT dealers, embedded gameplay interfaces, and player-to-player drug trading.

This is a Hardhat 3 Beta Solidity project using `node:test` for testing and `viem` for Ethereum interactions. The project uses Abstract Chain's FileStore (address: `0xFe1411d6864592549AdE050215482e4385dFa0FB` on both mainnet and testnet) for on-chain file storage.

## Commands

### Testing
```bash
# Run all tests
npx hardhat test

# Run only Solidity tests
npx hardhat test solidity

# Run only Node.js tests
npx hardhat test nodejs
```

### Deployment
```bash
# Deploy to local simulated chain
npx hardhat ignition deploy ignition/modules/Counter.ts

# Deploy to Abstract testnet
npx hardhat ignition deploy --network abstractTestnet ignition/modules/Counter.ts

# Deploy to Abstract mainnet
npx hardhat ignition deploy --network abstract ignition/modules/Counter.ts

# Deploy to Sepolia
npx hardhat ignition deploy --network sepolia ignition/modules/Counter.ts
```

### Configuration Management
```bash
# Set private key for Sepolia deployments
npx hardhat keystore set SEPOLIA_PRIVATE_KEY

# Set private key for Abstract testnet
npx hardhat keystore set ABSTRACT_TESTNET_PRIVATE_KEY

# Set private key for Abstract mainnet
npx hardhat keystore set ABSTRACT_PRIVATE_KEY
```

## Architecture

### Modular Contract System

The project follows a **modular architecture** where a central data contract (`DealersExeCore`) manages all game state, while specialized module contracts handle specific game mechanics. This design enables:
- Easy addition of new game features without touching core state
- Clear separation of concerns
- Upgradeable game modules while maintaining state continuity

### Core Contracts

**DealersExeCore** ([contracts/DealersExeCore.sol](contracts/DealersExeCore.sol))
- Central state management hub for all game data
- Stores dealer stats (reputation, area, daily plays, PvP status)
- Manages drug balances per dealer (tokenId => drugId => amount)
- Handles area/drug configuration and supply caps
- Authorization system: Only authorized contracts can modify state via `onlyAuthorized` modifier
- Key functions: `initializeDealer()`, `updateReputation()`, `updateDrugBalance()`, `moveToArea()`, `updateDailyPlays()`

**DealersExeNFT** ([contracts/DealersExeNFT.sol](contracts/DealersExeNFT.sol))
- ERC721 with dynamic on-chain metadata and embedded HTML gameplay UI
- Max supply: 8,888 NFTs with 200 reserved
- Minting stages: DISABLED → FAMILY → WHITELIST → PUBLIC (signature-based for FAMILY/WHITELIST)
- Per-token seed generation for deterministic trait rendering
- Calls `DealersExeCore.initializeDealer()` on mint to set up game state
- Integrates with renderer contracts (SVG + HTML) for fully on-chain visuals
- Metadata includes both static traits (from renderer) and dynamic traits (from Core: area, reputation, PvP status)

**DealersExePVE** ([contracts/DealersExePVE.sol](contracts/DealersExePVE.sol))
- Player-vs-Environment game module
- Rock-paper-scissors style gameplay: DEAL/THREATEN/BAIL
- Optional ETH staking (0.001-0.01 ETH) with payout handling
- Drug rewards based on rarity drop rates (75% common, 20% uncommon, 5% rare)
- Integrates with `DERandomness` for game resolution and `DEPaymentHandler` for ETH distribution
- Reputation changes based on tier-specific bonuses/penalties from Core

**DERandomness** ([contracts/DERandomness.sol](contracts/DERandomness.sol))
- Multi-module randomness provider using `prevrandao`
- Designed for easy VRF upgrade (contains future VRF infrastructure)
- Resolves game outcomes by calling back to authorized resolver contracts
- 5-minute request timeout with refund capability

**DEPaymentHandler** ([contracts/DEPaymentHandler.sol](contracts/DEPaymentHandler.sol))
- Centralized ETH management and fee distribution
- 10% total game fee split: 5% to dev wallet, 5% to bank vault
- Abstract Chain compatible (uses `.call()` instead of `.transfer()`)
- Tracks all financial metrics: totalProcessed, totalPayouts, totalDevFees, totalBankFees

### Renderer Architecture

**DealerRendererSVG** ([contracts/DealerRendererSVG.sol](contracts/DealerRendererSVG.sol))
- Generates dynamic SVG art for dealers based on token seed
- Provides trait metadata for NFT attributes
- Character type distribution system (1/1s, special editions)

**DealerRendererHTML** ([contracts/DealerRendererHTML.sol](contracts/DealerRendererHTML.sol))
- Wraps SVG in interactive HTML for `animation_url`
- Enables embedded gameplay interface directly in NFT metadata

**File.sol** ([contracts/File.sol](contracts/File.sol))
- EthFS/FileStore integration for on-chain file storage
- Used for storing larger data blobs in contract bytecode slices

### Game Mechanics Flow

1. **Dealer Creation**: NFT mint → `DealersExeNFT._mintDealer()` → `DealersExeCore.initializeDealer(tokenId)` → Dealer gets starting reputation (25), area (Manhattan), drugs (100 common, 10 uncommon, 1 rare)

2. **PVE Game Flow**:
   - Player calls `DealersExePVE.playGame()` with choice and optional stake
   - PVE requests randomness from `DERandomness`
   - DERandomness generates random number and calls back `DealersExePVE.resolveGame()`
   - Resolution updates Core state (reputation, drug balance) and processes payment via `DEPaymentHandler`

3. **State Updates**: Game modules (PVE, future PVP) call Core's authorized functions to modify dealer state. Core enforces supply caps, prevents negative balances, and maintains consistency.

### Network Configuration

The project is configured for multiple networks in [hardhat.config.ts](hardhat.config.ts):
- `hardhatMainnet`: Local L1 simulation
- `hardhatOp`: Local OP Stack simulation
- `sepolia`: Ethereum testnet
- `abstract`: Abstract Chain mainnet (Chain ID: 2741)
- `abstractTestnet`: Abstract Chain testnet (Chain ID: 11124)

Environment variables are required for deployment (see [.env.example](.env.example)).

## Contract Dependencies

- **OpenZeppelin v5.4.0**: ERC721Enumerable, ReentrancyGuard, ECDSA, IERC2981
- **Solady v0.1.26**: Ownable, LibString, Base64, and various gas-optimized utilities
- **forge-std v1.9.4**: For Foundry-compatible Solidity tests

## Development Notes

### Authorization Pattern
All game modules must be authorized in `DealersExeCore.authorizeContract()` before they can modify state. Check authorization setup when adding new game modules.

### Supply Management
Drug supply is capped per rarity:
- Common: 10,000,000
- Uncommon: 1,000,000
- Rare: 100,000

Core enforces these caps in `updateDrugBalance()`. Ensure new modules respect this constraint.

### Reputation Tiers
The reputation system uses configurable tiers (set via `setReputationTiers()`). Each tier defines:
- Minimum reputation threshold
- Win/tie/loss bonuses
- PvP capabilities and attack ranges
- Tier display name

When implementing reputation-affecting features, always use `getReputationChange()` to maintain tier consistency.

### Gas Optimization
Contracts use tight packing and unchecked arithmetic where overflow is impossible. Follow these patterns:
- Pack related uint8/uint32 fields in single storage slots
- Use unchecked blocks for loop increments and safe arithmetic
- Cache storage reads in memory variables when accessing multiple times

### Solidity Version
All contracts use `^0.8.20` (except File.sol which uses `^0.8.22`). The production profile in hardhat.config.ts enables optimizer with 200 runs.

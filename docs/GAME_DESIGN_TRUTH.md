# Dealers.Exe - Game Design Source of Truth

> This document is the single reference for understanding what the game does, how it works, and what each contract is responsible for.

---

## The Game in One Sentence

**Players mint dealer NFTs, travel between areas to buy and sell drugs at different prices, compete against each other in PVP, build reputation to unlock better areas, and risk going to jail if their heat gets too high.**

---

## Core Philosophy

| Principle | Description |
|-----------|-------------|
| **Reputation is everything** | All activities ladder up to reputation. Higher rep = better areas = better margins = more rep. |
| **Risk vs Reward** | Every action builds heat. More plays = more risk of jail. Jail = lose your stake + rep penalty. |
| **Area arbitrage** | Drug prices vary by area. The game is finding profitable trades across locations. |
| **PVP adds stakes** | Players in the same area can attack each other. Winners steal drugs, losers lose rep. |

---

## The Core Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   MINT          TRAVEL         HUSTLE         BUILD REP        │
│    │               │              │               │             │
│    ▼               ▼              ▼               ▼             │
│  Get NFT ──► Move to ──► Buy/Sell ──► Win = +Rep ──►           │
│  +100 $CASH    Area       Drugs      Lose = -Rep    │           │
│  +50 Weed    (pay fee)  (risk jail)                 │           │
│                                                     │           │
│                    ┌────────────────────────────────┘           │
│                    │                                            │
│                    ▼                                            │
│              UNLOCK AREAS ──► Better drug margins ──► More rep  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

OPTIONAL PATHS:
  • PVP: Attack players in your area → steal drugs, gain/lose rep
  • Boosts: Pay ETH → temporary multipliers on rewards
  • Heists: [FUTURE] Group activities for big rep gains
```

---

## Player Actions Reference

### Starting Out

| Action | What Happens | Contract | Function |
|--------|--------------|----------|----------|
| **Mint NFT** | Get dealer with 100 $CASH, 50 Weed, starts in Safe House | `DealersExeNFT` | `mintPublic()`, `mintFamily()`, `mintWhitelist()` |
| **View Stats** | See rep, area, heat, drugs, cash | `DealersExeCore` | `getDealerData()`, `getDrugBalance()`, `getCashBalance()` |

### Movement

| Action | What Happens | Contract | Function |
|--------|--------------|----------|----------|
| **Travel to Area** | Pay movement fee, change location. Must meet min rep requirement. | `DealersExeCore` | `travel(tokenId, areaId)` |
| **Check Area Info** | See movement fee, min rep, available drugs, prices | `DEAreaRegistry` | `getAreaInfo()`, `getDrugPricing()` |

**Movement Rules:**
- Safe House (0): Free to enter, but can't play PVE/PVP there
- Jail (255): Can't travel there directly, only sent when caught
- Regular areas: Pay fee, must meet minimum reputation

### PVE - Hustles (Main Gameplay)

| Action | What Happens | Contract | Function |
|--------|--------------|----------|----------|
| **BUY Hustle** | Stake $CASH to try to get drugs | `DealersExePVE` | `playGame(tokenId, choice, HustleType.BUY, drugId, amount)` |
| **SELL Hustle** | Stake drugs to try to get $CASH | `DealersExePVE` | `playGame(tokenId, choice, HustleType.SELL, drugId, amount)` |

**How It Works:**
```
1. You choose: BUY or SELL
2. You pick: which drug, how much to stake
3. You pick: DEAL (0), THREATEN (1), or BAIL (2) - rock/paper/scissors style
4. System rolls:
   - First: Jail check (heat level = % chance of arrest)
   - If not jailed: Outcome roll (50% tie, 25% win, 25% lose)
5. Results applied to your dealer
```

**Outcomes - BUY Hustle:**
| Outcome | $CASH | Drugs | Reputation |
|---------|-------|-------|------------|
| WIN | Keep | Get (boosted) | + Big |
| TIE | Lose | Get (boosted) | + Small |
| LOSE | Lose | Nothing | - Penalty |
| JAILED | Lose stake | Nothing | - 10% (cap 50) |

**Outcomes - SELL Hustle:**
| Outcome | $CASH | Drugs | Reputation |
|---------|-------|-------|------------|
| WIN | Get (boosted) | Keep | + Big |
| TIE | Get (boosted) | Lose | + Small |
| LOSE | Nothing | Lose | - Penalty |
| JAILED | Nothing | Lose stake | - 10% (cap 50) |

**Costs:**
- Uses 1 daily attempt (base: 5/day)
- Adds 1 heat level (max 5 = 5% jail chance)

### PVP - Attacks

| Action | What Happens | Contract | Function |
|--------|--------------|----------|----------|
| **Attack Player** | Challenge another dealer in same area | `DealersExePVP` | `attack(attackerId, defenderId)` |
| **Check Win Chance** | Preview battle odds | `DealersExePVP` | `calculateWinChance()`, `previewBattle()` |

**How It Works:**
```
1. Both dealers must be in same area (not Safe House or Jail)
2. Attacker pays 1 attempt, gains 1 heat
3. Jail check on attacker first
4. If not jailed: Battle roll
   - Base win chance: 50%
   - Modified by: attacker threat - defender armor (clamped 25%-75%)
5. Winner steals 10% of loser's drugs (area drugs only)
6. Winner gains rep, loser loses rep
```

**Restrictions:**
- 1 hour cooldown between attacking same target
- Defender can only be attacked 5 times per day
- Can't attack yourself
- Can't attack in Safe House or Jail

### Jail System

| Action | What Happens | Contract | Function |
|--------|--------------|----------|----------|
| **Pay Bail** | Pay fee, exit jail, reset heat, return to previous area | `DealersExeCore` | `payBail(tokenId)` |
| **Attempt Breakout** | 33% chance to escape free, once per day, keeps heat | `DealersExeCore` | `attemptBreakout(tokenId)` |

**How You Get Jailed:**
- Every PVE/PVP action adds 1 heat (max 5)
- Heat level = jail chance percentage (0-5%)
- Getting jailed: lose your stake + 10% rep (max 50 rep loss)

**Heat Management:**
| Action | What Happens | Contract | Function |
|--------|--------------|----------|----------|
| **Bribe Cop** | Pay 0.002 ETH, reset heat to 0 | `DealersExeCore` | `bribeCop(tokenId)` |
| **Remove Wanted Poster** | Use 1 attempt, 50% chance to clear heat | `DealersExeCore` | `removeWantedPoster(tokenId)` |

### Boosts

| Action | What Happens | Contract | Function |
|--------|--------------|----------|----------|
| **Buy Boost** | Pay ETH, get temporary multipliers | `DealersExeBoosts` | `purchaseBoost(dealerId, tierId)` |
| **Buy Boost (Batch)** | Boost multiple dealers at once | `DealersExeBoosts` | `purchaseBoostBatch(dealerIds, tierId)` |

**Default Boost Tiers:**
| Tier | Name | Price | Duration | Drugs | Rep | Attempts | Free Move | Cash |
|------|------|-------|----------|-------|-----|----------|-----------|------|
| 1 | Grinder | 0.01 ETH | 24h | 2x | 1.5x | +3 | No | 1.5x |
| 2 | Hustler | 0.05 ETH | 7d | 2x | 2x | +5 | No | 1.75x |
| 3 | Kingpin | 0.15 ETH | 30d | 2x | 2x | +10 | Yes | 2x |

**Boost Rules:**
- Can't buy if you already have an active boost
- Multipliers apply to PVE/PVP rewards
- Extra attempts added to daily limit
- Free movement skips area travel fees

### Resource Management

| Action | What Happens | Contract | Function |
|--------|--------------|----------|----------|
| **Buy Attempt Reset** | Pay 0.005 ETH, reset attempts to max | `DealersExeCore` | `purchaseAttemptReset(tokenId)` |
| **Buy $CASH** | Pay 0.001 ETH, get 100 $CASH (only if balance < 10) | `DealersExeCore` | `purchaseCash(tokenId)` |

---

## Reputation System

### How Reputation Works

**Gaining Reputation:**
- Win PVE hustles → + reputation (boosted by tier/boost)
- Tie PVE hustles → + small reputation
- Win PVP attacks → + reputation (boosted)
- Win PVP defense → + reputation

**Losing Reputation:**
- Lose PVE hustles → - reputation
- Lose PVP attacks → - reputation
- Get jailed → - 10% of current rep (max 50)

**Reputation Tiers (Currently On-Chain, Could Be Frontend):**
The contract stores tiers with:
- `minReputation`: Threshold to reach this tier
- `winBonus`: Rep gain on win
- `tieBonus`: Rep gain on tie
- `lossPenalty`: Rep loss on lose
- `tierName`: Display name
- `canHeist`: [FUTURE] Whether tier can join heists
- `pvpRange`: [UNUSED] Intended for PVP matchmaking range

### What Reputation Unlocks

| Unlock | How It Works | Implementation |
|--------|--------------|----------------|
| **Area Access** | Each area has `minReputation` requirement | `DEAreaRegistry.getMinReputation()` |
| **Better Margins** | Higher areas have better drug buy/sell spreads | Area drug pricing config |
| **NFT Metadata** | Rep shows as trait on your NFT | `DealersExeNFT.tokenURI()` |
| **Heist Access** | [FUTURE] `canHeist` flag in tier | Not implemented |
| **PVP Range** | [UNUSED] `pvpRange` in tier | Defined but not used |

---

## Area & Drug Economy

### Areas

| ID | Name | Movement Fee | Min Rep | Notes |
|----|------|--------------|---------|-------|
| 0 | Safe House | Free | 0 | Starting area, can't play here |
| 255 | Jail | 0.005 ETH (bail) | - | Can't travel here, only sent when caught |
| 1 | Manhattan | 0.001 ETH | 0 | Starter play area |
| 2+ | [Configurable] | Varies | Varies | Add via `DEAreaRegistry` |

### Drugs

| ID | Name | Rarity | Base Value | Supply Cap |
|----|------|--------|------------|------------|
| 1 | Weed | Common | 1 $CASH | 10,000,000 |
| 2 | XTC | Uncommon | 10 $CASH | 1,000,000 |
| 3 | Cocaine | Rare | 100 $CASH | 100,000 |

### Drug Pricing Per Area

Each area configures buy/sell prices per drug:

**Manhattan (Default):**
| Drug | Buy Price | Sell Price | Margin |
|------|-----------|------------|--------|
| Weed | 1 | 1 | 0 |
| XTC | 12 | 10 | -2 |
| Cocaine | 120 | 100 | -20 |

**The Arbitrage Game:**
- Area A: Cocaine buys at 100, sells at 80
- Area B: Cocaine buys at 150, sells at 120
- Strategy: Buy in A at 100, travel to B, sell at 120 = 20 profit per unit

---

## Contract Responsibilities

### Core State (DealersExeCore)
```
STORES:
  ├── dealers[tokenId] → reputation, area, heat, attempts, initialized
  ├── drugBalances[tokenId][drugId] → drug inventory
  ├── dealerCash[tokenId] → $CASH balance
  ├── dealerBoosts[tokenId] → active boost data
  ├── dealerThreatStat[tokenId] → combat offense [FUTURE: items]
  ├── dealerArmorStat[tokenId] → combat defense [FUTURE: items]
  └── reputationTiers[] → tier definitions [COULD BE FRONTEND]

DOES:
  ├── Initialize new dealers
  ├── Update reputation, drugs, cash
  ├── Handle travel between areas
  ├── Manage jail/bail/breakout
  ├── Apply and check boosts
  └── Process paid actions (bribe, reset, cash purchase)
```

### PVE Game (DealersExePVE)
```
STORES:
  └── Statistics [COULD BE INDEXED FROM EVENTS]

DOES:
  ├── Validate game prerequisites
  ├── Execute BUY/SELL hustle flow
  ├── Roll outcomes (jail check, then game outcome)
  ├── Apply rewards/penalties via Core
  └── Emit events for indexing
```

### PVP Game (DealersExePVP)
```
STORES:
  ├── lastAttackTime[attacker][defender] → cooldown tracking
  ├── attacksReceivedToday[defender] → daily limit
  └── Statistics [COULD BE INDEXED FROM EVENTS]

DOES:
  ├── Validate attack prerequisites
  ├── Execute battle flow
  ├── Calculate win chance from stats
  ├── Transfer drugs from loser to winner
  └── Apply rep changes via Core
```

### Boosts (DealersExeBoosts)
```
STORES:
  ├── boostTiers[tierId] → tier configuration
  └── Sales statistics [COULD BE INDEXED FROM EVENTS]

DOES:
  ├── Validate purchase prerequisites
  ├── Process ETH payment
  ├── Apply boost to dealer via Core
  └── Handle batch purchases
```

### NFT (DealersExeNFT)
```
STORES:
  ├── Token ownership (ERC721)
  ├── tokenSeeds[tokenId] → random seed for traits
  └── Mint tracking

DOES:
  ├── Mint with phase restrictions (Family/Whitelist/Public)
  ├── Initialize dealer in Core on mint
  ├── Generate on-chain metadata with game state
  └── Handle royalties (EIP-2981)
```

### Area Registry (DEAreaRegistry)
```
STORES:
  ├── areas[areaId] → name, fee, minRep, flags
  └── areaDrugs[areaId][drugId] → buy/sell prices

DOES:
  ├── Validate area access
  ├── Provide drug pricing per area
  └── Admin: configure areas and drug prices
```

### Drug Registry (DEDrugRegistry)
```
STORES:
  ├── drugs[drugId] → name, rarity, baseValue, supply, cap
  └── Authorization for supply changes

DOES:
  ├── Track global drug supply
  ├── Enforce supply caps
  └── Admin: add/configure drugs
```

### Payment Handler (DEPaymentHandler)
```
STORES:
  ├── Fee destinations (dev wallet, bank vault)
  └── Statistics [COULD BE INDEXED FROM EVENTS]

DOES:
  ├── Split incoming ETH (5% dev, 5% bank)
  ├── Process movement fees
  ├── Process marketplace fees
  └── Handle withdrawals
```

### Randomness (DERandomness)
```
STORES:
  ├── Authorized resolvers
  └── Nonce for entropy

DOES:
  └── Provide randomness using prevrandao + entropy
```

---

## Implementation Status

| Feature | Status | Notes |
|---------|--------|-------|
| NFT Minting | DONE | Family/Whitelist/Public phases |
| Dealer Initialization | DONE | 100 $CASH, 50 Weed start |
| PVE Hustles | DONE | BUY/SELL with outcomes |
| PVP Attacks | DONE | Same-area combat |
| Area Travel | DONE | Fee + rep requirements |
| Drug Pricing Per Area | DONE | Via AreaRegistry |
| Jail/Bail System | DONE | Heat → jail → bail/breakout |
| Boosts | DONE | 3 default tiers |
| Reputation Tiers | DONE | On-chain (could simplify) |
| On-Chain Metadata | DONE | Dynamic traits from game state |
| Heists | NOT STARTED | `canHeist` flag exists but unused |
| Items/Equipment | NOT STARTED | `threat`/`armor` stats exist but no items |
| PVP Matchmaking | NOT STARTED | `pvpRange` exists but unused |

---

## Fee Structure

| Action | Fee | Split |
|--------|-----|-------|
| Mint NFT | 0.01 ETH | To NFT contract (withdrawable) |
| Travel to Area | 0.001+ ETH | 5% dev, 5% bank |
| Pay Bail | 0.005 ETH | 5% dev, 5% bank |
| Bribe Cop | 0.002 ETH | 5% dev, 5% bank |
| Reset Attempts | 0.005 ETH | 5% dev, 5% bank |
| Buy $CASH | 0.001 ETH | 5% dev, 5% bank |
| Buy Boost | 0.01-0.15 ETH | 5% dev, 5% bank |

---

## Simplification Opportunities

Based on "core state on-chain, stats indexed from events":

| What | Current | Recommendation |
|------|---------|----------------|
| Reputation Tiers | On-chain struct array | Move to frontend mapping |
| Statistics | On-chain mappings | Index from events |
| Stash Bonus Calc | On-chain loop | Calculate frontend |
| Tier Names | On-chain strings | Frontend lookup |
| Combat Stats | On-chain (unused) | Keep for items, or defer |
| Previous Area | On-chain | Could hardcode return to area 1 |
| PVP Daily Limits | On-chain per-defender | Consider if needed |

---

## Quick Reference: "Can I Do X?"

| Question | Answer | Why |
|----------|--------|-----|
| Can I add more drugs? | Yes | `DEDrugRegistry.createDrug()` |
| Can I add more areas? | Yes | `DEAreaRegistry.createArea()` |
| Can I change drug prices? | Yes | `DEAreaRegistry.updateDrugPricing()` |
| Can I change boost prices? | Yes | `DealersExeBoosts.setTierPrice()` |
| Can I change win/tie/lose odds? | Yes | `DealersExePVE.setOutcomeOdds()` |
| Can I pause the game? | Yes | `DealersExeCore.pause()` |
| Can I add heists? | Need new contract | Hooks exist (`canHeist`) |
| Can I add items? | Need new contract | Stats exist (`threat`/`armor`) |

---

## Event Reference (For Indexing)

**Key events to index for statistics/history:**

```solidity
// PVE
event GamePlayed(tokenId, player, choice, houseChoice, outcome, hustleType, drugId, drugAmount, cashChange, repChange)
event DealerArrested(tokenId, player, heatLevel)

// PVP
event PVPBattleResult(attacker, defender, attackerWon, drugsStolen, attackerRepChange, defenderRepChange)
event DealerArrested(tokenId, heatLevel)

// Core
event ReputationUpdated(tokenId, newReputation, change)
event DrugBalanceUpdated(tokenId, drugId, newBalance, change)
event CashUpdated(tokenId, newBalance, change)
event DealerJailed(tokenId, previousArea, repLost)
event DealerBailed(tokenId, bailPaid, newArea)
event BoostApplied(tokenId, expiresAt)

// Boosts
event BoostPurchased(dealerId, tierId, buyer, expiresAt)
```

---

*Last Updated: Based on contract analysis*
*Version: 1.0*

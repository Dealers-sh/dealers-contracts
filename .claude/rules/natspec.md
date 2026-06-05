## NatSpec Convention

The leading game contracts (`DealersCore`, `DealersPVE`, `DealersPVP`, `DealersBoosts`) define the
house style. All contracts — including new modules and their interfaces — must match it.

### Block style — always `/** */`, never `///`

```solidity
// CORRECT
/**
 * @notice Commit to a hustle round — debits stake + attempt; outcome resolved later.
 * @param tokenId The dealer NFT token ID
 * @return seq Sequence number to pass to resolveGame
 */
function commitGame(uint256 tokenId) external returns (uint64 seq) { ... }

// WRONG — triple-slash is not used anywhere in the game contracts
/// @notice Commit to a hustle round
function commitGame(uint256 tokenId) external returns (uint64 seq) { ... }
```

A one-line note may use the compact block form:

```solidity
/** @dev Heat and boost multipliers read live at resolve — pay-to-grow is by design. */
```

### File header

Every contract and interface opens with a title block: `@title`, the ASCII banner, a `@dev`
overview, and `@author Berny0x`.

```solidity
/**
 * @title DealersPVE - Player vs Environment Game Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Rock-paper-scissors style hustle game where dealers buy or sell drugs.
 * @author Berny0x
 */
```

### Section dividers

Group members under banner comments (`STORAGE`, `EVENTS`, `ERRORS`, `CONSTRUCTOR`, `MODIFIERS`,
`EXTERNAL FUNCTIONS` / domain sections, `VIEW FUNCTIONS`, `INTERNAL HELPERS`, `ADMIN`):

```solidity
// =============================================================
//                            STORAGE
// =============================================================
```

### Tag usage

- **`@notice`** — on every external/public function and on substantive events. Plain language: what it does / why a caller cares.
- **`@param` / `@return`** — on functions that take arguments or return values. Match the density of the game contracts: thorough on the main state-changing externals and views (e.g. `commitGame`, `getDealerPveStats`), light or omitted on trivial one-line getters/setters and auto-generated public-mapping getters.
- **`@dev`** — implementation detail, invariants, security rationale, or "why it's done this way." This is where non-obvious reasoning lives (the comment policy in [comments.md](comments.md) still applies: explain WHY, never restate WHAT).
- **`@title` / `@author`** — file header only.

### Interfaces

Interfaces follow the same rules — `/** */` blocks, `@notice` on the declared functions, `@param`/`@return` where useful. See `IDealersCore` / `IDealersPVE`.

### `@inheritdoc` must be multi-line

solc parses a single-line block `/** @inheritdoc IFoo */` as referencing the contract `"IFoo "`
(trailing space before `*/`) and fails with "references inexistent contract". Always use the
multi-line form:

```solidity
/**
 * @inheritdoc IEntropyConsumer
 */
function getEntropy() internal view override returns (address) { ... }
```

### Don't

- No `///` triple-slash, anywhere.
- No comment that just restates the function name (`@notice Sets the owner` on `setOwner`). If there's nothing to add beyond the signature, a short `@notice` is fine, but never pad with redundant `@param owner The owner`.
- Don't document `private`/`internal` helpers with full `@param`/`@return` unless the logic is subtle — a single `@dev` line is the norm.

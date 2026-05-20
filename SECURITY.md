# Security


## 1. Architecture Overview

Basalt Vault is a delta-neutral yield vault on Arbitrum One. Each vault is an isolated ERC721-owned clone that earns GMX v2 trading fees while hedging BTC price exposure via Dolomite Margin borrowing.

The protocol consists of:
- **VaultCore** -- minimal executor contract, cloned per user
- **VaultState** -- per-vault storage, writable only by its paired VaultCore
- **VaultCoreNftFactory** -- ERC721 (`BV-OWN`) that issues vault clones
- **ManagerContract** -- central role hub with 6 distinct roles
- **FeeSplitter** -- ERC20Votes-based fee distribution
- **Handlers** -- stateless singleton contracts containing all business logic
- **BasaltMath** -- pure math library, independently replaceable

Solidity 0.8.28 (fixed pragma, no floating version). Compiled with `via-ir` optimizer. Licensed under BUSL-1.1.

---

## 2. Immutability

Basalt Vault contracts have **no proxy pattern, no upgradeability mechanism, and no admin upgrade path**.

Every deployed contract is a plain Solidity contract at a fixed address with immutable bytecode. VaultCore clones are created via `Clones.clone()` (EIP-1167 minimal proxies pointing to a fixed implementation). The implementation contract's `initialize()` function is guarded by a one-shot `initialized` flag set in the constructor, preventing re-initialization of both the implementation and any clone.

**Why this matters:**

In most DeFi protocols, upgradeability is the largest trust assumption. A proxy admin can replace contract logic at any time, effectively holding a master key to all user funds. Basalt eliminates this entire class of risk. The code that was audited and deployed is the code that runs. There is no mechanism -- administrative, governance, or otherwise -- to replace the bytecode of any deployed contract.

The only mutable surface is handler rotation, which requires explicit dual consent (Section 4).

---

## 3. NFT-Based Access Control

Each vault is represented by an ERC721 token minted by `VaultCoreNftFactory`. The NFT holder is the vault owner.

**Trust model:**

All state mutations flow through `VaultCore.universalCall()`, which enforces two gates:

1. **Caller must be a registered handler** (`onlyHandler` modifier -- checked against 8 handler slots)
2. **Initiator must be the vault NFT owner or the protocol manager** (checked on every call)

```
universalCall(initiator, target, data, value, useDelegateCall)
  require: msg.sender is in handler slots
  require: initiator == NFT owner OR initiator == protocolManager
```

The protocol manager (`ManagerContract`) cannot withdraw user funds. Withdrawal is initiated by the NFT owner through `WithdrawHandler`, which sends WBTC directly to the NFT owner's address. The manager's operational role can only finalize pending operations (which settle to the NFT owner) and extract accrued performance fees (which are computed via a high-water mark, not arbitrary extraction).

**Implications:**
- Vault ownership is transferable via standard ERC721 transfer
- Whoever holds the NFT controls the vault -- no separate key management
- Protocol manager compromise cannot drain user vaults directly
- A compromised handler could only execute operations that pass the initiator check

---

## 4. Dual Governance for Handler Rotation

Handler rotation is the **only mutable surface** in the protocol. It follows a strict 2-step propose/accept pattern:

1. **Protocol manager proposes** a handler replacement (old handler address -> new handler address)
2. **NFT owner explicitly accepts** the proposal

Neither side can force a change unilaterally:
- The manager cannot replace a handler without the NFT owner's `acceptHandler()` call
- The NFT owner cannot propose handlers -- only accept or cancel
- Either side can cancel a pending proposal

Additional constraints enforced in `VaultCore.proposeHandler()`:
- The old handler must be in an active handler slot (`_isHandlerSlot`)
- The new handler address must not be zero
- The new handler must not already occupy any slot (prevents duplication -- INV-VC-003)

**Why this is significant:**

In typical DeFi protocols, admin keys can unilaterally change contract logic (via proxy upgrades) or parameters. Basalt's dual governance means that even if the protocol team's keys are compromised, an attacker cannot change handler logic on any vault without the cooperation of that vault's NFT owner. Conversely, a compromised NFT owner cannot install arbitrary handler code -- they can only accept proposals made by the protocol manager.

The same propose/accept pattern governs `BasaltMath` and `VaultState` address changes via `proposeBasaltAddresses()` / `acceptBasaltAddresses()`.

---

## 5. Manager Role Separation

`ManagerContract` implements 6 distinct roles with different trust assumptions and blast radii:

| Role | Set by | Blast radius |
|---|---|---|
| **owner** | `Ownable2Step` (2-step transfer) | Can assign configurator, operational, handlerProposer, addressProposer. Can update factory address book. Can add/skip FeeSplitter tracked tokens. Cannot touch vault funds or parameters directly. |
| **configurator** | owner | Can set vault target LTV (48-52% bounds), keeper deadline, rebalance slippage caps, rebalance thresholds. Falls back to owner. Cannot initiate operations or move funds. |
| **operational** | owner | Can rebalance vaults, finalize pending operations, accrue/withdraw manager fees, sweep fees to FeeSplitter, ping heartbeat. This is the hot key used by keeper bots. Falls back to owner. |
| **handlerProposer** | owner | Can propose handler rotations on individual VaultCores. Cannot force acceptance. Falls back to owner. |
| **addressProposer** | owner | Can propose BasaltMath/VaultState address changes. Cannot force acceptance. Falls back to owner. |
| **feeCollector** | self (2-step, independent of owner) | Can propose a new feeCollector. Governed independently -- owner compromise does not affect fee collection governance. |

**Key design properties:**

- **Least privilege:** The operational key (used by automated keepers) cannot change vault configuration, propose handler rotations, or modify governance.
- **Owner cannot directly operate:** Owner sets roles but does not have a fast path to execute operations -- it falls back through role modifiers, not bypasses them.
- **feeCollector independence:** The fee collection address uses its own 2-step transfer (`proposeFeeCollector` / `acceptFeeCollector`), fully independent of the owner role. This prevents a compromised owner from redirecting fee flows.
- **Protocol manager rotation** requires weighted voting through FeeSplitter (ERC20Votes). Normal path: 80% of total supply. After 180-day timeout: simple majority with 10% quorum, ties go to cancel.

---

## 6. Protection Against External Upgrade Risk

Basalt depends on two external protocols -- Dolomite Margin and GMX v2. Their upgradeability status is tracked in `docs/external-contracts-upgradeability.md`.

### Immutable external contracts (low risk)

| Contract | Notes |
|---|---|
| DolomiteMargin (`0x6Bd7...9072`) | No proxy |
| Dolomite VaultFactory (`0x1E8e...d0eF`) | No proxy |
| GMX DataStore (`0xFD70...d8`) | No proxy |
| GMX ExchangeRouter (`0x1C3f...6A41`) | No proxy |
| GMX DepositHandler / WithdrawalHandler | No proxy |

### Upgradeable external contracts (high risk)

| Contract | Risk |
|---|---|
| Dolomite GM Wrapper (`0xc58c...06D8`) | Proxy -- Dolomite can upgrade implementation |
| Dolomite GM Unwrapper (`0x2B9D...2758`) | Proxy -- Dolomite can upgrade implementation |
| Dolomite Isolation Vault (per-user) | Proxy -- implementation set by VaultFactory |

**Impact analysis:** A malicious or buggy Dolomite upgrade to Wrapper/Unwrapper could change async wrap/unwrap behavior, alter callback semantics, or modify vault storage layout. This is the primary external dependency risk.

**Mitigations:**
- The protocol monitors Dolomite governance announcements
- Re-verification commands are maintained to check implementation addresses after any upgrade
- The async recovery handler (`AsyncRecoveryHandler`) can cancel stuck Dolomite operations after the keeper deadline + 10 minutes, providing a safety valve if an upgrade breaks async settlement
- Emergency mode provides a last-resort unwind path independent of normal Dolomite async flows

---

## 7. Funds Safety and Per-User Isolation

Each vault is a separate contract clone with its own Dolomite isolation account (account #100). User positions are never commingled.

**What this eliminates:**

| Attack vector | Status | Why |
|---|---|---|
| **Donation attacks** | Eliminated | No shared pool to manipulate via direct token transfer. Each vault's NAV is computed from its own Dolomite account balances. |
| **Share price manipulation** | Eliminated | No shared ERC4626 vault. Each vault tracks its own shares independently via VaultState. Virtual share offset (1e6 virtual shares, 1 virtual asset) prevents first-depositor inflation. |
| **Cross-user contamination** | Eliminated | VaultState is writable only by its paired VaultCore (INV-VS-001). Vault A's handler calls cannot modify Vault B's state. |
| **Flash loan pool manipulation** | Eliminated | No shared liquidity pool to drain or inflate in a single transaction. |
| **Front-running deposits** | Mitigated | Async 2-phase settlement through GMX makes single-block sandwich attacks impractical. |

**Isolation enforcement:**
- `VaultState.initialize()` permanently binds a VaultState to exactly one VaultCore address
- Every mutation on VaultState checks `msg.sender == vaultCore` (the address set at initialization)
- `VaultCoreNftFactory` ensures no two tokens map to the same vault address

---

## 8. Deadman Switch

If the protocol manager becomes inactive for approximately 1 year (~2,628,000 Arbitrum blocks at ~0.25s/block), any vault's NFT owner can invoke `triggerManagerDeadman()` on their VaultCore.

**Mechanism:**

1. Every manager action (rebalance, config change, heartbeat ping) bumps `lastManagerActionBlock` on the vault's VaultState
2. After `MANAGER_DEADMAN_BLOCKS` (2,628,000) blocks of inactivity, the NFT owner can call `triggerManagerDeadman()`
3. Once triggered, `managerDeadmanTriggered` is set permanently on VaultState
4. From that point, the `onlyManager` modifier on VaultCore accepts the NFT owner as an alternative to the protocol manager

**Post-deadman NFT owner capabilities:**
- Propose and accept handler rotations (full self-governance)
- Propose and accept BasaltMath/VaultState address changes
- Execute any operation that normally requires the protocol manager

**Design rationale:** This is a self-sovereignty guarantee. Users do not need to trust that the protocol team will exist forever. If the team disappears, users can take full control of their vaults after a reasonable waiting period. The 1-year period is long enough to prevent premature triggering during normal operational gaps, but short enough to be practically useful.

The deadman flag is irreversible -- once triggered, it cannot be un-triggered. This prevents a scenario where a temporarily absent manager returns and re-locks out the NFT owner.

---

## 9. Emergency Mode

Emergency mode is an irreversible last-resort mechanism for unwinding a vault's position when normal operations are not possible.

**Properties:**
- **Irreversible** -- once activated, the vault cannot return to normal operation
- **Permissionless execution** -- anyone can execute emergency operations; no single point of failure
- **Decaying slippage tolerance** -- starts at 5%, decays by 1% per day, with a 1% floor. This prevents immediate MEV extraction while gradually relaxing constraints to ensure eventual execution
- **Chunked unwind** -- large positions (>1% of GM supply) are unwound in chunks (1/10th per step) to minimize market impact

**Slippage curve:**
```
Day 0:   5.0% max slippage
Day 1:   4.0%
Day 2:   3.0%
Day 3:   2.0%
Day 4+:  1.0% (floor)
```

**Emergency swap path:** WBTC to USDC uses Uniswap V3 with a 30-minute TWAP oracle (flash-loan resistant) and a 1% slippage cap against the TWAP price.

---

## 10. Oracle Security

The protocol uses a layered oracle architecture:

### Chainlink price feeds

- **BTC/USD:** `0xd0C7...0c57` (max staleness: 90,000s, max price: $10M equivalent)
- **USDC/USD:** `0x5083...34aD3` (max staleness: 90,000s, max price: $1,000 equivalent)

Every Chainlink read (`OracleGuard.readChainlinkPrice`) enforces:
1. **Round completeness:** `answeredInRound >= roundId` (rejects incomplete rounds)
2. **Positive price:** `answer > 0` (rejects zero/negative)
3. **Staleness:** `block.timestamp - updatedAt <= maxAge` (rejects stale data)
4. **Hard ceiling:** `answer <= maxPrice` (rejects absurd values, fail-closed)

### L2 Sequencer check

Before any price-sensitive operation (rebalance, deposit, withdraw):
- Checks Arbitrum sequencer uplink via `0xFdB6...77fd`
- Reverts if sequencer is down (`answer != 0`)
- Enforces 1-hour grace period after sequencer recovery (prevents stale-price exploitation during sequencer restart)

### Dolomite cross-check

WBTC prices from Dolomite's oracle are cross-checked against direct Chainlink reads. If the spread exceeds 0.25% (`ORACLE_PRICE_SPREAD_BPS = 25`), the operation reverts. This catches oracle divergence, manipulation, or Dolomite oracle misconfiguration.

### On-chain GM price calculation

Rather than trusting a single oracle for GM token pricing, `GMCalculator.sol` replicates GMX v2's full pool value formula on-chain -- including pool amounts, borrowing fees, capped PnL, and impact pool with time-based distribution. This is cross-referenced against Dolomite's GM valuation.

---

## 11. Formally Tested Invariants

The following invariants are verified through stateful fuzz testing (256 runs, depth 100) and targeted audit tests:

### Fee accounting

| ID | Invariant |
|---|---|
| INV-FS-001 | FeeSplitter rewards are conserved across releases and transfers. Paid balances plus splitter residue equal all inflows. |
| INV-FS-002 | Share transfers cannot steal previously attributed rewards. Covers post-notify and pre-release transfer ordering. |
| INV-FS-003 | New rewards after a transfer accrue to current holders only. |

### Access control

| ID | Invariant |
|---|---|
| INV-VC-001 | Only configured handlers can execute `VaultCore.universalCall`. |
| INV-VC-002 | `universalCall` initiator must be vault NFT owner or protocol manager. |
| INV-VC-003 | Handler rotation cannot duplicate handler slots. |
| INV-VS-001 | Only the paired VaultCore can mutate VaultState. |

### Factory and isolation

| ID | Invariant |
|---|---|
| INV-FAC-001 | Factory address-book cooldown (24 hours) blocks vault creation after any address book update. |
| INV-FAC-002 | Multiple vault clones remain fully isolated under one factory. |

### Governance

| ID | Invariant |
|---|---|
| INV-MGR-001 | Protocol manager rotation requires sufficient voting support (80% normal / majority+10% quorum after 180 days). No double-counting of votes. |

### Oracle integrity

| ID | Invariant |
|---|---|
| INV-ORACLE-001 | Chainlink prices must be fresh, positive, and below hard caps. |
| INV-ORACLE-002 | GMX DataStore pool keys for the configured GM market are non-zero (detects key/schema drift on pinned fork). |

### Additional audit test coverage

17 targeted audit test files cover specific attack scenarios:
- Delegatecall abuse (handler attempting calls to unauthorized targets)
- Cross-vault contamination (Vault A operations affecting Vault B)
- Donation attacks (direct token transfers to manipulate accounting)
- Oracle manipulation (stale prices, zero prices, ceiling breaches, sequencer down)
- MEV/keeper griefing (front-running finalization, sandwiching async operations)
- Governance frontrunning (FeeSplitter vote manipulation, dual-signing prevention)
- Implementation initialization (disabled on implementation contracts)

---

## 12. Risk Parameters

| Parameter | Value | Bounds |
|---|---|---|
| Target LTV | 50% (default) | 48% -- 52% (configurable) |
| Hard cap LTV | 70% | Fixed in `BasaltConstants` |
| Dolomite liquidation threshold | ~83.8% | Set by Dolomite (external) |
| Safety buffer to liquidation | ~13.8% | Derived (83.8% - 70%) |
| Performance fee | 20% of profits above HWM | Fixed in `BasaltConstants` |
| Async recovery grace | 10 min after keeper deadline | Fixed |
| Post-deposit cooldown | 1 block | Fixed |
| Sequencer grace period | 1 hour | Fixed |
| Oracle price spread guard | 0.25% (Chainlink vs Dolomite) | Fixed |
| Deadman period | ~2,628,000 blocks (~1 year) | Fixed |
| Emergency initial slippage | 5% | Fixed |
| Emergency slippage floor | 1% | Fixed |
| Emergency slippage decay | 1% per day | Fixed |
| Address book cooldown | 24 hours | Fixed |
| Protocol manager vote threshold | 80% of total supply (normal) | Fixed |
| Protocol manager timeout vote | Simple majority, 10% quorum (after 180 days) | Fixed |

---

## 13. Known Limitations and External Dependencies

1. **Dolomite upgrade risk** -- Dolomite's GM Wrapper, GM Unwrapper, and Isolation Vault implementations are upgradeable proxies. A Dolomite upgrade could break Basalt's async settlement flow. See Section 6.

2. **GMX v2 market concentration** -- All yield is sourced from a single GMX v2 market (BTC/USDC). There is no diversification across markets.

3. **Keeper dependency** -- Normal operation requires an active keeper to finalize async operations. If the keeper is down, operations remain in PENDING state until the recovery grace period elapses (keeper deadline + 10 minutes), after which anyone can cancel via the AsyncRecoveryHandler.

4. **Arbitrum L2 assumptions** -- The protocol assumes Arbitrum block times of ~0.25s for the deadman switch calculation. Changes to Arbitrum's block production rate would affect the deadman period.

5. **No global pause** -- By design, there is no admin pause function. This is a deliberate trade-off: immutability and censorship resistance over the ability to halt operations in an emergency. Emergency mode provides the alternative.

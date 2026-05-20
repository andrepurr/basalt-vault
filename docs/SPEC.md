# Basalt Vault — Spec (derived strictly from `src/`)

> **5-minute read on top** (TL;DR + schemas) → **deep dive below** (FR, ADR, formulas, algorithms, invariants, per-module).

---

## 0. TL;DR

One NFT = one `VaultCore` clone. The vault holds a leveraged GM-BTC/USDC position on Dolomite (isolation account 100), financed by WBTC debt, target LTV 50 % (safe cap 70 %). Every leg (deposit / withdraw / rebalance) is routed through a **handler** that mutates state only via `VaultCore.universalCall` — `VaultCore` is a dumb executor, `VaultState` is a storage bag, `BasaltMath` is stateless math. Handlers can be rotated via a 2-step handler proposal (manager proposes, NFT owner accepts). A separate `ManagerContract` owns protocol-wide roles and routes fees to `FeeSplitter` (ERC20Votes share token, MasterChef-style accumulator).

- **Asset** — GM token of GMX v2 BTC/USDC market, wrapped into Dolomite isolation-mode position.
- **Debt** — WBTC borrowed on Dolomite against the GM collateral.
- **Safety** — Dolomite LT ~ 83.8 %, Basalt hard cap 70 %, default target 50 %.
- **Async everywhere** — GMX wrap/unwrap settle in a second tx (`finalize*`). Cooldown 1 block, keeper deadline 60 s (default).
- **Fees** — 20 % HWM performance fee on absolute profit, accrued in `FeeAccountingHandler`, withdrawn as shares via `WithdrawHandler.withdrawManagerFeeShares`, distributed via `FeeSplitter` (token-agnostic MasterChef).
- **Oracles** — Price source = Dolomite (chained from Chainlink under the hood), cross-checked against Chainlink with 0.25 % spread guard. Chainlink sequencer uptime is gated on deposit, withdraw, rebalance, and fee accrual paths.
- **Deadman switch** — If protocol manager is inactive for ~1 year (`MANAGER_DEADMAN_BLOCKS = 2_628_000` blocks), NFT owner can trigger deadman and assume manager privileges.

```
                                    +------------------+
                                    |  ManagerContract | (Ownable2Step, 5 roles)
                                    +------------------+
                                 /      |       |        \
                       configurator  operational  handlerProp  addressProp
                                 \      |       |        /
                                 sets params / rebalances / proposes
                                             |
                          +------------- VaultCoreNftFactory -----------+
                          | ERC721  (1 NFT = 1 VaultCore)              |
                          | holds `protocolManager` + addressBook      |
                          +--------------------------------------------+
                                             | clones
                              +--------------+---------------+
                              |                              |
                          VaultCore                      VaultState
                          (exec + ACL)                   (storage + config)
                              |
          +----------+--------+------------+---------------+
          v          v        v            v               v
      Deposit    Withdraw  Manager    AsyncRecovery   FeeAccounting       + 3 extension slots
      Handler    Handler   Handler      Handler          Handler
          \       |          |            |               /
           \      v          v            v              /
            \   Dolomite isolation account #100  <------/
             \   (GM collateral <-> WBTC debt)
              \
               > GMX async wrap/unwrap (keeper-driven settlement)
```

---

## 1. System Overview (schemas first)

### 1.1 Contract map

| Contract | Role | Replaceable? |
|---|---|---|
| `VaultCore` (per-vault clone) | Dumb executor + ACL + `universalCall` dispatcher + deadman switch | yes — 2-step governance |
| `VaultState` (per-vault clone) | Storage bag: per-vault state + config + pending accounting + deadman flag | yes — swapped together with `BasaltMath` via `proposeBasaltAddresses` |
| `BasaltMath` | Stateless math (deposit / withdraw / rebalance / fee) | yes — ditto |
| `DepositHandler` | Deposit branch router (5 branches) | yes — `proposeHandler` |
| `WithdrawHandler` | Withdraw branch router (4 branches) + manager-fee leg | yes |
| `ManagerHandler` | Target LTV config + LTV rebalance + heartbeat ping | yes |
| `AsyncRecoveryHandler` | Cancel stuck GMX wrap/unwrap after deadline + grace | yes |
| `FeeAccountingHandler` | Compute + persist HWM performance fee into `VaultState` | yes |
| `VaultCoreNftFactory` | ERC721, clones `VaultCore`+`VaultState`, holds `protocolManager` | **immutable** |
| `ManagerContract` | 5 roles, fee hub entry, protocol-manager vote coordinator | **immutable** |
| `FeeSplitter` | ERC20Votes fee share (1e18 total), MasterChef-per-token accumulator, max 20 tracked tokens, skippable tokens | **immutable** |
| `InitialCoreAddressBook` | Immutable bundle of addresses used at vault creation (includes `dolomiteVault`) | replace w/ 24 h cooldown |
| `BasaltZapIn` | USDC/stablecoin -> GM conversion (pool-imbalance route selection, async GMX) | **immutable** |
| `BasaltZapOut` | WBTC -> USDC conversion (sync Uniswap V3 swap) | **immutable** |
| `BasaltGmUnwrapper` | GM -> (WBTC+USDC) unwrap via GMX withdrawal (emergency/standalone) | **immutable** |

Libraries: `BasaltConstants` (all magic numbers), `BasaltAddresses` (Arbitrum mainnet addrs), `DolomiteReader` (prices/NAV/borrow index, Chainlink cross-check), `OracleGuard` (Chainlink staleness + round completeness + L2 sequencer), `GMCalculator` (on-chain GM NAV), `ZapInMath`, `BasaltPrecision`.

### 1.2 Control-flow cheat-sheet (who can call what)

```
                    +-------------------------------------------------------------+
                    |                   AUTHORIZED INITIATORS                      |
                    +-------------------------------------------------------------+
                      vault NFT owner            protocolManager (ManagerContract)
                         | deposit                         | rebalance (anytime)
                         | withdraw                        | set* config (via configurator role)
                         | withdraw fee? NO                | finalize{Deposit,Withdraw,Rebalance}
                         | rebalance if |LTV-target|>=band | withdrawManagerFeeShares
                         | accept handler / accept math    | accrueManagerFee
                         | finalize{Deposit,Withdraw,Reb.} | unstuckPending
                         | unstuckPending                  | pingHeartbeat
                         | triggerManagerDeadman (if       |
                         |  manager inactive > ~1 year)    |
                         v                                 v
                    +--------------- Handler --------------------------+
                    | requireVaultNftOwner / requireProtocolManager /  |
                    | requireCallerIsProtocolManagerOrVaultNftOwner    |
                    +-------------------------------------------------+
                                       |
                                       | targetVaultCore.universalCall(initiator, target, data, value, delegate)
                                       v
                        onlyHandler + initiator in {nftOwner, protocolManager}
```

### 1.3 State machine (per vault)

```
        +-------------- depositState ---------------+
        |                                            |
  IDLE --- deposit() ---> PENDING -- finalizeDeposit() --> IDLE (success | refund)
                                |
                                +-- success path: totalDepositedGm/Usd += , fee accrued, cooldown starts

        +------------- withdrawState ---------------+
        |                                            |
  IDLE --- withdraw() --> (sync paths return immediately, state stays IDLE)
  IDLE --- withdraw() --> PENDING (AsyncDebt) -- finalizeWithdraw() --> IDLE

        +----------- rebalanceState ----------------+
        |                                            |
  IDLE --- rebalance() --> PENDING -- finalizeRebalance() --> IDLE
```

All three sub-state-machines share one rule: **all-idle + cooldown-passed** before any new entrypoint.

Global cooldown = 1 block (`GLOBAL_ACTION_COOLDOWN_BLOCKS`), armed after each successful deposit finalize and deposit refund. Withdraw/rebalance do not arm it.

### 1.4 Deposit branch router (5 branches)

```
                              +- isolationVault == 0 ------> CreateIsolationVault  (new position at target LTV)
                              |
      DepositHandler.deposit -+  gmColl>0 & wbtcDebt>0   --> Standard              (ratio-preserving borrow)
                              |
                              |  gmColl>0 & debt==0 & sg==0 > CollateralOnly      (lever up to target LTV)
                              |
                              |  gmColl==0 & debt==0 & sg==0 > EmptyIsolationVault (fresh position at target LTV)
                              |
                              +- debt==0 & surplusGm>0      > DebtFreeSurplus (revert NeedToAbsorbSurplus)
```

Auxiliary deposit paths: `absorbSurplus` (wraps WBTC surplus into GM collateral), `addWbtcAsDeposit` (top-up WBTC surplus <= $10).

### 1.5 Withdraw branch router (4 branches)

```
  gmColl>0  & wbtcDebt>0                 --> AsyncDebt           (async unwrap + later borrow back to restore ratio)
  gmColl>0  & debt==0 & surplus>0        --> SyncGmWithSurplus   (pro-rata GM + pro-rata WBTC)
  gmColl>0  & debt==0                    --> SyncGmOnly          (pro-rata GM)
  debt==0   & surplus>0                  --> SyncWbtcSurplusOnly (pro-rata WBTC)
  nothing                                --> revert NothingToWithdraw
```

Two share caps (`WithdrawSharePolicy`):
- `OwnerEligible` — for NFT owner: `shares <= totalShares * (NAV - managerAccruedFee) / NAV`.
- `ManagerFee` — for `protocolManager.withdrawManagerFeeShares`: bounded by pro-rata fee and by complement of owner-eligible.

### 1.6 Rebalance branches (2)

```
  currentLTV > targetLTV --> _rebalanceDownToLtv --> async unwrap GM, get WBTC, repay debt
  currentLTV < targetLTV --> _rebalanceUpToLtv   --> borrow WBTC, async wrap to GM collateral
```

- **Protocol manager** can rebalance whenever LTV != target.
- **NFT owner** can rebalance only when `|currentLTV - targetLTV|` exceeds `rebalanceThresholdUp/DownBps` (defaults: both 20 %, bounded 5-20 %).
- Post-settlement LTV must pass Dolomite premium-adjusted LTV <= 70 %.

### 1.7 Async recovery path

```
  pending{Deposit|Withdraw|Rebalance} with deadline D
           |
           +- wait until block.timestamp >= D + UNSTUCK_GRACE_AFTER_DEADLINE (10 min)
           +- Dolomite isolation vault must still be frozen (isVaultFrozen() == true)
           +- GMX wrapper/unwrapper must be registered on GmxV2Registry
           v
  unstuckPending(key) --> cancelDeposit() | cancelWithdrawal() on Dolomite -> vault back to IDLE
```

Who can call: `protocolManager` **or** vault NFT owner.

### 1.8 Governance / role matrix

```
+-------------------------------------------------------------------------------+
| ROLE                  | LIVES ON              | DOES                           |
|-----------------------|-----------------------|--------------------------------|
| factory owner         | VaultCoreNftFactory   | setInitialCoreAddressBook (24h |
|  (multisig admin)     |  (Ownable2Step)       |   cooldown), cancel proposals  |
| protocolManager       | VaultCoreNftFactory   | rebalance, finalize, accrue/   |
|                       |  (= ManagerContract)  |  withdraw manager fee,         |
|                       |                       |  propose handler, propose      |
|                       |                       |  math/state, unstuckPending,   |
|                       |                       |  pingHeartbeat                 |
| vault NFT owner       | VaultCoreNftFactory   | deposit, withdraw, rebalance   |
|  (ERC721 tokenId -> v)|  (ERC721)             |  (only past band), accept      |
|                       |                       |  handler/math, unstuckPending, |
|                       |                       |  cancel proposals,             |
|                       |                       |  triggerManagerDeadman         |
| configurator          | ManagerContract       | set vault risk params (TargetLtv|
|                       |                       |  KeeperDeadline, slippage caps,|
|                       |                       |  thresholds, unwrap share)     |
| operational           | ManagerContract       | hot path: rebalance,finalize,  |
|                       |                       |  accrueManagerFee,             |
|                       |                       |  withdrawManagerFee, sweeps,   |
|                       |                       |  pingHeartbeat, notifyReward   |
| handlerProposer       | ManagerContract       | proposeHandler / cancel        |
| addressProposer       | ManagerContract       | proposeBasaltAddresses / cancel|
| feeCollector          | ManagerContract       | 2-step rotation of itself only |
| fee-share holders     | FeeSplitter           | vote (80 %) to rotate          |
|  (snapshot weight)    |  (ERC20Votes)         |  protocolManager               |
+-------------------------------------------------------------------------------+
```

### 1.9 Fee pipeline

```
  performance accrues (HWM on absolute profit)
    profit = NAV + totalWithdrawn - totalDeposited
    fee = (profit - prevHwmProfit) * managementFeeBps / BPS  (only if profit > prevHwm)
                                               |
                                               v
    managerAccruedFeeUsdE18  (VaultState)
                                               |
  ManagerContract.operational:                 v
    withdrawManagerFeeShares  ->  _executeWithdrawBranch (ManagerFee cap)
                                               |
                    (tokens land on ManagerContract)
                                               |
                       collectFees / sweep     v
                                        FeeSplitter.notifyReward(token)
                                               |
  fee-share holder:  release(token, me)  <-----+   (MasterChef-style pro-rata)
```

### 1.10 Oracles & NAV

```
  GM price   -- DolomiteMargin.getMarketPrice(GM).value      (E18, 36-18 dec)
  WBTC price -- DolomiteMargin.getMarketPrice(WBTC).value    (E28, 36- 8 dec)
               cross-checked against Chainlink WBTC/USD within ORACLE_PRICE_SPREAD_BPS (0.25%)
  NAV(USD,E18) = gmColl*P_gm + wbtcSurplus*P_wbtc - wbtcDebt*P_wbtc   (clamped >=0)

  Sequencer guard: Chainlink L2-sequencer feed; startedAt must be old
                     enough (`ORACLE_SEQUENCER_GRACE_PERIOD` = 3600 s).
  Required on: deposit, absorbSurplus, withdraw, finalizeDeposit, finalizeWithdraw, rebalance, accrueManagerFee.
```

---

## 2. Functional Requirements (FR)

Indexed by module. Each FR traces to the implementing function in `src/`.

### FR-CORE — Vault core / governance

| ID | Statement | Source |
|---|---|---|
| FR-CORE-1 | Each vault is a clone of `VaultCore` + `VaultState`, minted 1 NFT per vault. | `VaultCoreNftFactory.createVaultCore` |
| FR-CORE-2 | `VaultCore` executes arbitrary calls on behalf of the vault only via `universalCall` gated by `onlyHandler` + initiator in {nftOwner, protocolManager}. | `VaultCore.universalCall` |
| FR-CORE-3 | Handler slot rotation is two-step: `proposeHandler` (manager) -> `acceptHandler` (NFT owner). Either side can cancel. | `VaultCore.proposeHandler/acceptHandler/cancelHandlerProposal` |
| FR-CORE-4 | `basaltMath` / `basaltState` pointers rotate the same way via `proposeBasaltAddresses` / `acceptBasaltAddresses`. | `VaultCore` |
| FR-CORE-5 | A handler address may sit in at most one slot (`DuplicateHandler`). | `VaultCore.proposeHandler` |
| FR-CORE-6 | Factory `owner()` may replace `InitialCoreAddressBook` only after a 24 h cooldown; new vaults refuse to be minted during the cooldown. | `VaultCoreNftFactory.setInitialCoreAddressBook`, `createVaultCore` |
| FR-CORE-7 | `protocolManager` on the factory can only be rotated by the current `protocolManager`; rotation itself is gated off-chain by an 80 %-weighted fee-share vote inside `ManagerContract`. | `VaultCoreNftFactory.setProtocolManager`, `ManagerContract.*ProtocolManagerChange` |
| FR-CORE-8 | `onlyManager` modifier allows the protocol manager, OR the NFT owner if `managerDeadmanTriggered` is true on `VaultState`. | `VaultCore.onlyManager` |
| FR-CORE-9 | `triggerManagerDeadman` can be called by the NFT owner only after `block.number > lastManagerActionBlock + MANAGER_DEADMAN_BLOCKS (2_628_000)`. Once triggered, cannot be re-triggered. | `VaultCore.triggerManagerDeadman` |

### FR-MGR — ManagerContract

| ID | Statement | Source |
|---|---|---|
| FR-MGR-1 | 5 mutable roles on `ManagerContract`: `configurator`, `operational`, `handlerProposer`, `addressProposer`, `feeCollector`; first four rotated by `owner()`, `feeCollector` uses 2-step. | `setConfigurator/setOperational/...`, `proposeFeeCollector/acceptFeeCollector` |
| FR-MGR-2 | Configurator routes vault risk params through `ManagerHandler`. | `setVault*` |
| FR-MGR-3 | Operational controls rebalance / finalize / accrue / fee-withdraw / sweep-to-splitter / pingHeartbeat / notifyReward. | `rebalanceVault`, `finalizeRebalance`, `finalize{Deposit,Withdraw}`, `accrueManagerFee`, `withdrawManagerFee`, `collectManagerFeesFromVaultAndSweep`, `finalizeManagerFeeWithdrawAndSweep`, `pingVaultHeartbeat`, `notifyFeeSplitterReward` |
| FR-MGR-4 | Protocol-manager rotation is proposal + weighted sign (yes/cancel) + execution by snapshot-holder-or-operational at 80 % of past total supply. One proposal at a time. Signing one side blocks signing the other (`AlreadySignedOpposite`). | `proposeProtocolManagerChange`, `sign*`, `executeProtocolManagerChange`, `cancelProtocolManagerChange` |
| FR-MGR-5 | `collectFees` requires caller to be `operational` or hold a FeeSplitter balance > 0; moves balances already sitting on `ManagerContract` to `FeeSplitter`, followed by `notifyReward`. Sweeps only tracked tokens; including a tracked-but-skipped token in the array will cause `notifyReward` to revert with `TokenIsSkipped` (hard revert, not silent skip). | `collectFees`, `_sweepTokensToFeeSplitter` |
| FR-MGR-6 | Owner can call `setInitialCoreAddressBook` on a factory, `addFeeSplitterTrackedToken`, and `setFeeSplitterTokenSkipped` on the FeeSplitter via the ManagerContract. | `ManagerContract.setInitialCoreAddressBook/addFeeSplitterTrackedToken/setFeeSplitterTokenSkipped` |

### FR-DEP — DepositHandler

| ID | Statement | Source |
|---|---|---|
| FR-DEP-1 | Only the vault NFT owner can call `deposit`, `absorbSurplus`, `addWbtcAsDeposit`. | `onlyVaultNftOwner` |
| FR-DEP-2 | `deposit` requires: all-idle, cooldown passed, `amountGmE18 >= 1e18`, slippage in `[MIN_DEPOSIT_SLIPPAGE, MAX_DEPOSIT_SLIPPAGE] = [50, 500]` bps, sequencer up. | `DepositHandlerRequirements.*` |
| FR-DEP-3 | Deposit routes through 5 branches based on `(gmCollateral, wbtcDebt, surplusGm)`; `DebtFreeSurplus` reverts (caller must `absorbSurplus` first). | `selectDepositBranch` |
| FR-DEP-4 | Post-deposit projected LTV <= `MAX_POST_DEPOSIT_LTV_BPS = 7000`. | `DepositHandlerRequirements.requireLtvBelowCap` |
| FR-DEP-5 | Async wrap is initiated on GMX via Dolomite isolation vault, with `keeperDeadline` and `minGmOut`; `finalizeDeposit` decides success/failure from `gmCollateral` delta and either finalizes accounting (+ accrues manager fee + arms cooldown) or refunds the depositor's GM. | `startAsyncDeposit`, `finalizeDeposit`, `decideDepositSuccessOrFail`, `_execRefundDepositPath` |
| FR-DEP-6 | `finalizeDeposit` can be called by protocol manager OR NFT owner while vault is not frozen, deposit is PENDING, and sequencer is up. | `finalizeDeposit` |
| FR-DEP-7 | `addWbtcAsDeposit` enforces both the existing WBTC surplus USD value **and** the new deposit USD value <= `MAX_WBTC_SURPLUS_AS_DEPOSIT_USD_E18 = 10e18` (dust-top-up). | `requireWbtcSurplusValueWithinDustLimit` x 2 |
| FR-DEP-8 | `absorbSurplus` reverts if `surplusWbtcE8 == 0` or slippage-adjusted expected GM is 0. | `absorbSurplus` |

### FR-WIT — WithdrawHandler

| ID | Statement | Source |
|---|---|---|
| FR-WIT-1 | `withdraw` only NFT owner; `withdrawManagerFeeShares` only `protocolManager`. Both require sequencer up. | modifiers + `requireProtocolManager` + `requireSequencerUp` |
| FR-WIT-2 | `sharesToWithdrawE18 in (0, SHARE_UNIT = 1e18]`. | `requireValidPositionShareToWithdraw` |
| FR-WIT-3 | Before branching, the handler calls `accrueManagerFeeBeforeWithdraw` so eligibility uses up-to-date `managerAccruedFeeUsdE18`. | `withdraw/withdrawManagerFeeShares` |
| FR-WIT-4 | Owner share cap: `shares <= totalShares * (NAV - managerFee) / NAV`. Manager share cap: `min(totalShares * managerFee / NAV, totalShares - ownerEligible)`. | `calcOwnerEligibleWithdrawShares`, `calcManagerMaxFeeWithdrawShares` |
| FR-WIT-5 | `AsyncDebt` branch snapshots `rawRatioInitial = ceil(gmColl * 1e18 / debt)` and WBTC borrow index; `finalizeWithdraw` borrows exactly enough WBTC to restore the original GM/WBTC ratio, accounting for accrued interest. | `_execAsyncWithdraw`, `_finalizeWithDebt`, `calcWbtcToBorrowForRatio`, `calcAdjustedDebtForBorrowIndex` |
| FR-WIT-6 | If a pending async withdraw never moved GM collateral (keeper didn't execute), `finalizeWithdraw` clears pending without paying out and emits `success=false`. | `finalizeWithdraw` (`currentCollateralE18 == snapshotCollateralE18`) |
| FR-WIT-7 | Sync branches (`SyncGmOnly`, `SyncGmWithSurplus`, `SyncWbtcSurplusOnly`) forbid ETH value (`requireNoValue`). | `_executeWithdrawBranch` |
| FR-WIT-8 | `finalizeWithdraw` can be called by protocol manager OR NFT owner while vault not frozen, cooldown passed, withdraw state != IDLE, and sequencer up. | `finalizeWithdraw` |
| FR-WIT-9 | Sync and finalized withdrawals record withdrawn USD via `addWithdrawnUsdE18` (owner leg) or `subAccruedManagerFeeUsdE18` (manager fee leg), used for profit-based HWM accounting. | `_recordWithdrawnUsdByPolicy` |

### FR-MGR-HANDLER — ManagerHandler

| ID | Statement | Source |
|---|---|---|
| FR-MGR-H-1 | Config setters (`setTargetLtv`, `setKeeperDeadline`, `setRebalanceSlippageCapBps`, `setUnwrapLongShareBps`, `setRebalanceThresholdUpBps`, `setRebalanceThresholdDownBps`) are only callable by factory `protocolManager`; require all-idle + cooldown; each parameter has hard-coded bounds. All bump `lastManagerActionBlock`. | `onlyProtocolManager`, `requireAllIdle`, `requireCooldownPassed`, `require*InBounds`, `bumpLastManagerAction` |
| FR-MGR-H-2 | `rebalance` requires all-idle, cooldown, slippage in `[MANAGER_MIN_SLIPPAGE_BPS, MANAGER_MAX_SLIPPAGE_BPS] = [50, 1000]` bps AND <= vault-configured cap, sequencer up, GM collateral > 0. | `requireValidSlippage`, `requireSequencerUp`, `NoCollateral` |
| FR-MGR-H-3 | Manager can rebalance any time LTV != target; NFT owner must exceed `rebalanceThresholdUpBps` (LTV above target) or `rebalanceThresholdDownBps` (below). | `requireNftOwnerRebalanceDeviation` |
| FR-MGR-H-4 | Post-settlement LTV (Dolomite premium-adjusted) must be <= `MAX_SAFE_LTV_BPS = 7000`; zero debt skips the check. | `requirePostLtvSafe` |
| FR-MGR-H-5 | `finalizeRebalance` requires rebalance state PENDING, `pendingRebalanceKind == REBALANCE_KIND_LTV`, and the vault is no longer frozen. | `finalizeRebalance` |
| FR-MGR-H-6 | `pingHeartbeat` is callable only by `protocolManager`; it bumps `lastManagerActionBlock` on VaultState, proving liveness for the deadman switch. | `ManagerHandler.pingHeartbeat` |

### FR-ASYNC — AsyncRecoveryHandler

| ID | Statement | Source |
|---|---|---|
| FR-ASYNC-1 | `unstuckPending` callable only by `protocolManager` or NFT owner. | `requireCallerIsProtocolManagerOrVaultNftOwner` |
| FR-ASYNC-2 | Requires: pending {deposit|withdraw|rebalance} on `VaultState`, `block.timestamp >= deadline + UNSTUCK_GRACE_AFTER_DEADLINE (10 min)`, Dolomite isolation vault still frozen, the relevant GMX wrapper/unwrapper registered on `GmxV2Registry`, and the provided `key` references this vault + isolation account (`=100`). | `requireUnstuckAllowedForWrite`, `requireDolomiteIsolationVaultStillFrozen`, `require*TraderConfigured`, `require*AsyncKeyTargetsThisVaultAndAccount` |
| FR-ASYNC-3 | Withdraw keys marked `isLiquidation` cannot be cancelled by Basalt (Dolomite owns that path). | `requireWithdrawalAsyncKeyTargetsThisVaultAndAccount` |
| FR-ASYNC-4 | Rebalance direction mapping: `REBALANCE_KIND_LTV + DIR_UP` -> Wrap-cancel; `REBALANCE_KIND_LTV + DIR_DOWN` -> Unwrap-cancel; any other combination reverts `InvalidRebalanceDirection`. Note: `REBALANCE_KIND_ABSORB_SURPLUS` is defined but unreachable in practice — `absorbSurplus` sets deposit-pending (not rebalance-pending), so the deposit path is resolved first in `resolvePendingOperation`. | `resolvePendingOperation` |

### FR-FEE — FeeAccountingHandler

| ID | Statement | Source |
|---|---|---|
| FR-FEE-1 | `accrueManagerFee(vault, basaltMath, initiator)` can be invoked by anyone if `msg.sender == initiator` or by any vault handler; `initiator` must be NFT owner OR `protocolManager`. Requires sequencer up. | `_requireInitiatorAndCaller`, `_isVaultHandlerSlot`, `OracleGuard.requireSequencerUp` |
| FR-FEE-2 | Fee is HWM-style over absolute profit: `profit = max(NAV + totalWithdrawn - totalDeposited, 0)`. If `profit > prevHwmProfit`, `profitDelta = profit - prevHwmProfit`; `fee = profitDelta * managementFeeBps / BPS`; HWM bumps to `profit` monotonically. No claw-back below HWM. | `calculateManagerFee`, `BasaltMath.calcProfitUsdE18`, `BasaltMath.calcPerformanceFeeByHwmProfit` |
| FR-FEE-3 | `managementFeeBps` lives on `VaultState` (monotonically non-increasing, bounded by `MANAGER_FEE_BPS=2000`). It serves as the performance fee rate parameter. | `VaultState.setManagementFeeBps`, `VaultState.managementFeeBps` |

### FR-SPLIT — FeeSplitter

| ID | Statement | Source |
|---|---|---|
| FR-SPLIT-1 | Fixed `TOTAL_SHARES = 1e18`, minted once to the constructor-supplied holder and self-delegated; no further mint/burn. | constructor |
| FR-SPLIT-2 | On every share transfer all tracked non-skipped tokens are settled first (pro-rata to *old* balances), then reward debt is reset to new balances. New receivers with no delegate are auto-self-delegated. | `_update` |
| FR-SPLIT-3 | `release(token, account)` pays everything owed; `_lastSeenReceived` stays invariant because balance drops and `totalReleased` rises by the same amount. Requires caller to hold shares OR be the ManagerContract operational role. Reverts on skipped tokens. | `release`, `_requireHolderOrOperational` |
| FR-SPLIT-4 | Donations that skip `notifyReward` risk being re-attributed to later holders — `ManagerContract` always calls `notifyReward` after every sweep. `notifyReward` requires caller to be `managerContract` or hold shares. Reverts on skipped tokens. | `_sweepTokensToFeeSplitter`, `notifyReward` |
| FR-SPLIT-5 | `MAX_TRACKED_TOKENS = 20`. Tokens can be added by ManagerContract owner via `addTrackedToken`. Tokens can be skipped (soft-disabled) via `setTokenSkipped`. | `addTrackedToken`, `setTokenSkipped`, `MAX_TRACKED_TOKENS` |
| FR-SPLIT-6 | `managerContract` is set once by `initialOwner` via `setManagerContract`. | `setManagerContract` |

---

## 3. Architectural Decisions (ADR)

### ADR-1 — Clones-as-vaults, 1 NFT = 1 VaultCore
`VaultCoreNftFactory.createVaultCore` clones `VaultCore` + `VaultState` and mints an ERC721 to the owner. Ownership is literally the NFT; transferring the NFT transfers all vault control.

### ADR-2 — `universalCall` + stateless handlers
`VaultCore` has no vault logic: handlers encode logic and mutate state via `universalCall` (either `call` or `delegatecall`). Benefit: handlers are upgradable without touching the per-vault contract. Constraint: `universalCall` enforces `onlyHandler` + initiator-must-be-in-ACL — no free arbitrary calls.

### ADR-3 — Two-step handler / math upgrade (proposal + NFT owner accept)
Neither protocol manager nor NFT owner can unilaterally change handlers or math pointers. Either side can cancel. Prevents rug-like upgrades.

### ADR-4 — Pricing from Dolomite, cross-checked against Chainlink
`DolomiteReader.getMarketPrice` is the single price source for NAV, LTV, deposit/withdraw/rebalance math. WBTC price is cross-checked against Chainlink — if the spread exceeds `ORACLE_PRICE_SPREAD_BPS = 25` (0.25 %), the read reverts with `OraclePriceSpreadTooWide`. Chainlink is also used for the L2-sequencer-up check (`OracleGuard.requireSequencerUp`).

### ADR-5 — Dolomite isolation account `#100`
A single hardcoded account number (`DOLOMITE_ISOLATION_ACCOUNT = 100`) holds all vault GM collateral + WBTC debt. Simplifies finality (one account to snapshot) and makes `AsyncRecoveryHandler` key-matching unambiguous.

### ADR-6 — 70 % hard cap, 50 % default target, 48-52 % configurable band
Dolomite LT ~ 83.8 %. `MAX_SAFE_LTV_BPS = 7000` gives ~13.8 % safety buffer against volatility + Dolomite premium math. `targetLtvBps` is clamped to `[4800, 5200]`, defaults 5000.

### ADR-7 — Async everything through GMX; permissionless recovery after deadline + 10 min
Wrap/unwrap on GMX is asynchronous. Handlers set `pending*Deadline = block.timestamp + keeperDeadline`. If the keeper never settles, `AsyncRecoveryHandler.unstuckPending` can cancel once `deadline + 10 min` has passed AND Dolomite still reports the isolation vault frozen.

### ADR-8 — Pending-deposit accounting is provisional; success decided by on-chain delta, not keeper report
`decideDepositSuccessOrFail(basaltMath, vaultState, currentGmCollateralE18) = currentGmCollateralE18 > pendingDepositGmCollateralSnapshotE18 + pendingDepositAmountGmE18`. Keeper reports / events are not trusted; we read Dolomite directly.

### ADR-9 — AsyncDebt withdrawal restores the ratio, not the debt
On withdraw the handler snapshots `rawRatio = ceil(gmColl * 1e18 / debt)`. In `finalizeWithdraw` (with debt present) the handler borrows `currentCollateral * 1e18 / rawRatio` WBTC to restore the ratio. It adjusts the compared debt for Dolomite borrow-index drift so accrued interest in the meantime doesn't skew the target.

### ADR-10 — HWM performance fee on absolute profit
`profit = max(NAV + totalWithdrawn - totalDeposited, 0)`. HWM tracks the profit watermark (`highWaterMarkProfitUsdE18`). Fee is only charged on `profitDelta = max(profit - prevHwmProfit, 0)`. This ensures withdrawals don't reset the fee base, and the manager only earns fees on genuine new profit above the previous high-water mark.

### ADR-11 — MasterChef-per-token fee distribution with transfer-time settlement
`FeeSplitter` uses `_accPerShare[token]`, `_rewardDebt[token][user]`, `_pending[token][user]`. Every share transfer pre-settles both sides on every tracked non-skipped token before moving shares. Donations must be followed by `notifyReward` to lock the pre-transfer attribution. Tokens can be skipped to avoid gas griefing on transfer.

### ADR-12 — Protocol-manager rotation = 80 % weighted vote on `FeeSplitter` snapshots
`proposeProtocolManagerChange` snapshots `block.number - 1`; `sign` weights are `getPastVotes` at that snapshot. Both execute and cancel require 80 % of past total supply and can only be called by snapshot holders or the operational role. Signing yes blocks signing cancel and vice versa (`AlreadySignedOpposite`). One active proposal at a time.

### ADR-13 — `VaultCore` exposes no custom view helpers
Handlers source every data point directly (Dolomite for position/prices, `VaultState` for config, GMX for pending info). `VaultCore` stays minimal — any new view lives in a handler or in `DolomiteReader`. Note: public state variables (`basaltMath`, `basaltState`, `FACTORY`, handler slots, etc.) have auto-generated getters but no hand-written view functions.

### ADR-14 — `BasaltConstants` is the single literals source
Every tunable literal (bps, timeouts, LTV ranges, oracle max ages, etc.) is defined once in `BasaltConstants` and forwarded by local aliases.

### ADR-15 — `VIRTUAL_SHARES = 1e6`, `VIRTUAL_ASSETS = 1`
ERC4626-style asymmetric offsets. Initial share price pinned to exactly \$1 (so `V` USD -> `V * 1e6` raw shares, `V` displayed shares), and first-depositor inflation hardening.

### ADR-16 — Fee path: vault -> `ManagerContract` -> `FeeSplitter`
Handlers route performance-fee withdraws to `ManagerContract` (the `protocolManager`). `collectFees` / the `*AndSweep` helpers forward tokens to `FeeSplitter` and fire `notifyReward` atomically. Rationale: no direct vault <-> splitter coupling, splitter is fee-token-agnostic.

### ADR-17 — `InitialCoreAddressBook` change requires a 24 h cooldown
Factory-owner changes on the address book block `createVaultCore` for 24 h. Gives users a window to opt out of new vault creation if addresses change.

### ADR-18 — No extension handlers by default (three empty slots)
`extensionHandler{1,2,3}` are initialized from the address book; recognized by `_isHandlerSlot` and upgradable via `proposeHandler`. This gives room for new handlers (e.g. emergency unwind) without a factory redeploy.

### ADR-19 — Cooldown semantics: 1 block after deposit finalize/refund
`GLOBAL_ACTION_COOLDOWN_BLOCKS = 1`. Withdraw and rebalance do **not** arm the cooldown; the single-block gap exists mostly to prevent same-tx oracle abuse after a deposit.

### ADR-20 — Unwrap long-share bounded 40-50 %
`unwrapLongShareBps` controls the expected WBTC output share from an async unwrap (the long leg). Default 50 % (full-parity proportionality), range 4000-5000 bps, used for slippage sizing.

### ADR-21 — Deadman switch for manager liveness
If the protocol manager does not interact with a vault (any config change, rebalance, or `pingHeartbeat`) for `MANAGER_DEADMAN_BLOCKS = 2_628_000` blocks (~1 year at 3s/block), the NFT owner can call `triggerManagerDeadman`. Once triggered, `onlyManager` on VaultCore also accepts the NFT owner, giving them full manager privileges over their vault. This protects users from a permanently absent manager.

---

## 4. Formulas

All math lives in `BasaltMath` (pure). Scales: E18 for GM amounts + GM price + USD; E8 for WBTC amounts; E28 for Dolomite WBTC price; E36 for premium-adjusted products.

### 4.1 Conversions

```
P_wbtc_E18 = P_wbtc_E28 / 1e10
P_wbtc_E8  = P_wbtc_E28 / 1e20
```

### 4.2 Values

```
gmValueUsdE18    = gmAmountE18 * gmPriceE18 / 1e18
collUsdE18       = gmCollE18  * gmPriceE18 / 1e18
debtUsdE18       = wbtcDebtE8 * wbtcPriceE18 / 1e8
```

### 4.3 Deposit

```
borrowValueForTargetLtv     = collateralValue * targetLtv / (BPS - targetLtv)
borrowValueForCollateralOnly = (gmColl + depositGm) * gmPrice * targetLtv / (BPS - targetLtv)
borrowWbtcE8                = borrowValueE18 * 1e8 / wbtcPriceE18
gmReceivedMinE18            = borrowWbtcE8 * wbtcPriceE8 * 1e2 * (BPS - userSlippage) * 1e18 / (gmPriceE18 * BPS)
calcRatioPreservingBorrow   = amountGm * wbtcDebt / gmCollateral     // Standard branch
calcExpectedGmOutE18        = borrowWbtc * wbtcPriceE18 * 1e10 / gmPriceE18

postDepositLtvBps = (wbtcDebt + borrowWbtc) * wbtcPriceE18 * BPS / [(gmColl + depositGm + minGmFromWrap) * gmPriceE18]
```

### 4.4 Withdraw

```
ownerEligibleShares = totalShares * (NAV - managerAccruedFee) / NAV                 (0 if NAV==0 or fee>=NAV)
managerMaxFeeShares = min( totalShares * managerAccruedFee / NAV,
                           totalShares - ownerEligibleShares )
proRataGm           = gmColl * shares / totalShares
proRataRedeem       = tokenBalance * shares / totalShares
rawRatioInitial     = ceil( gmColl * 1e18 / debt )                      // snapshot on async withdraw
adjustedDebt        = currentDebt * snapshotIndex / currentIndex        // only if currentIndex > snapshotIndex
targetDebtForRatio  = currentCollateral * 1e18 / rawRatio
wbtcToBorrowForRatio= currentCollateral * 1e18 / rawRatio               // surplus branch
wbtcToUserFromDebtRepay = max(targetDebt - adjustedDebt, 0)
wbtcToUserFromSurplus   = currentSurplus + wbtcToBorrow
```

### 4.5 Rebalance

```
coll_E36         = gmColl_E18 * gmPrice_E18
debt_E36         = wbtcDebt_E8 * wbtcPrice_E28
adjColl_E36      = coll_E36 * 1e18 / (1e18 + collateralPremium_E18)
adjDebt_E36      = debt_E36 * (1e18 + debtPremium_E18) / 1e18
ltv_E36_bps      = adjDebt_E36 * BPS / adjColl_E36                      (uint_max if no collateral)

targetDebtUsd   = targetLtv * collUsd / BPS
gap             = debtUsd - targetDebtUsd         (down) | targetDebtUsd - debtUsd   (up)
rebalanceDelta  = gap * BPS / (BPS - targetLtv)
gmToSell (down) = rebalanceDelta * 1e18 / gmPrice          (clamped <= gmColl)
borrowWbtc(up)  = rebalanceDelta * 1e8  / wbtcPrice

expectedWbtcOutLongSide = (gmToSell * gmPrice / (wbtcPrice * 1e10)) * longShareBps / BPS
applySlippage(x, bps)   = x * (BPS - bps) / BPS
```

### 4.6 Fee

```
profit       = max(NAV + totalWithdrawn - totalDeposited, 0)
profitDelta  = max(profit - prevHwmProfit, 0)
perfFee      = profitDelta * managementFeeBps / BPS
nextHwmProfit = max(profit, prevHwmProfit)       (monotonically non-decreasing)
nextAccrued   = prevAccrued + perfFee
```

### 4.7 Async recovery

```
unstuckNotBefore = pendingOperation.deadline + UNSTUCK_GRACE_AFTER_DEADLINE   (= +10 min)
```

### 4.8 Constants (selected)

| Constant | Value | Source |
|---|---|---|
| `BPS` | 10 000 | `BasaltConstants` |
| `SHARE_UNIT` | 1e18 | `BasaltConstants` |
| `VIRTUAL_SHARES / VIRTUAL_ASSETS` | 1e6 / 1 | `BasaltConstants` |
| `MANAGER_FEE_BPS` | 2 000 (20 %) | `BasaltConstants` |
| `MAX_DEPOSIT_FEE` | 0.1 ether | `BasaltConstants` |
| `MAX_SAFE_LTV_BPS` | 7 000 | `BasaltConstants` |
| `MAX_POST_DEPOSIT_LTV_BPS` | 7 000 | `BasaltConstants` |
| `MIN/MAX_TARGET_LTV_BPS` | 4 800 / 5 200 | `BasaltConstants` |
| `DEFAULT_TARGET_LTV_BPS` | 5 000 | `BasaltConstants` |
| `MIN/MAX_REBALANCE_THRESHOLD_BPS` | 500 / 2 000 | `BasaltConstants` |
| `DEFAULT_REBALANCE_THRESHOLD_{UP,DOWN}_BPS` | 2 000 | `BasaltConstants` |
| `MIN/MAX_REBALANCE_SLIPPAGE_CAP_BPS` | 100 / 1 000 | `BasaltConstants` |
| `DEFAULT_REBALANCE_SLIPPAGE_CAP_BPS` | 500 | `BasaltConstants` |
| `DEFAULT_UNWRAP_LONG_SHARE_BPS` | 5 000 | `BasaltConstants` |
| `MANAGER_MIN/MAX_SLIPPAGE_BPS` | 50 / 1 000 | `BasaltConstants` |
| `MIN/MAX_DEPOSIT_SLIPPAGE_BPS` | 50 / 500 | `BasaltConstants` |
| `MIN/MAX_UNWRAP_LONG_SHARE_BPS` | 4 000 / 5 000 | `BasaltConstants` |
| `MAX_WBTC_SURPLUS_AS_DEPOSIT_USD_E18` | 10e18 ($10) | `BasaltConstants` |
| `MIN_WITHDRAW_SHARES` | 1e18 (whole share) | `BasaltConstants` (defined but unused — validation uses `SHARE_UNIT`) |
| `RAW_RATIO_SCALE` | 1e18 | `BasaltConstants` |
| `GLOBAL_ACTION_COOLDOWN_BLOCKS` | 1 | `BasaltConstants` |
| `MIN/MAX_KEEPER_DEADLINE` | 60 s / 60 min | `BasaltConstants` |
| `DEFAULT_KEEPER_DEADLINE` | 60 s | `BasaltConstants` |
| `UNSTUCK_GRACE_AFTER_DEADLINE` | 10 min | `BasaltConstants` |
| `MANAGER_DEADMAN_BLOCKS` | 2 628 000 | `BasaltConstants` |
| `DOLOMITE_ISOLATION_ACCOUNT` | 100 | `BasaltConstants` |
| `DOLOMITE_MARKET_{WBTC,USDC,GM}` | 4 / 17 / 32 | `BasaltConstants` |
| `DOLOMITE_PRECISION` | 1e18 | `BasaltConstants` |
| `ORACLE_WBTC_MAX_AGE / USDC_MAX_AGE` | 90 000 s (24 h + 1 h buf) | `BasaltConstants` |
| `ORACLE_SEQUENCER_GRACE_PERIOD` | 3 600 s | `BasaltConstants` |
| `ORACLE_PRICE_SPREAD_BPS` | 25 (0.25 %) | `BasaltConstants` |
| `ORACLE_CL_TO_GMX` | 1e22 | `BasaltConstants` |
| `ORACLE_WBTC_MAX_PRICE_E8` | 1e15 | `BasaltConstants` |
| `ORACLE_USDC_MAX_PRICE_E8` | 1e9 | `BasaltConstants` |
| `EMERGENCY_INITIAL_SLIPPAGE_BPS` | 500 (5 %) | `BasaltConstants` |
| `EMERGENCY_DAILY_SLIPPAGE_REDUCTION_BPS` | 100 (1 %/day) | `BasaltConstants` |
| `EMERGENCY_MIN_SLIPPAGE_BPS` | 100 (1 %) | `BasaltConstants` |
| `EMERGENCY_CHUNKED_UNWIND_THRESHOLD_BPS` | 100 (1 %) | `BasaltConstants` |
| `EMERGENCY_CHUNK_DIVISOR` | 10 | `BasaltConstants` |
| `REDEEM_TOKEN_COUNT` | 4 | `BasaltConstants` |
| `EMERGENCY_SWAP_SLIPPAGE_BPS` | 100 (1 %) | `BasaltConstants` |
| `EMERGENCY_TWAP_WINDOW` | 1800 (30 min) | `BasaltConstants` |
| `UNI_V3_FEE_WBTC_USDC / WETH_USDC` | 500 (0.05 %) | `BasaltConstants` |
| `STABLE_POOL_FEE` | 100 (0.01 %) | `BasaltConstants` |
| `WBTC_POOL_FEE` | 500 (0.05 %) | `BasaltConstants` |
| `ZAP_MIN/MAX_SWAP_SLIPPAGE_BPS` | 10 / 1 000 | `BasaltConstants` |
| `ZAP_MIN/MAX_RETRY_WINDOW` | 60 s / 20 min | `BasaltConstants` |
| `ZAP_DEFAULT_RETRY_WINDOW` | 60 s | `BasaltConstants` |
| `ZAPIN_MIN/MAX_POOL_IMBALANCE_BPS` | 10 / 200 | `BasaltConstants` |
| `ZAPIN_MIN_DEPOSIT_GM_BUFFER_BPS` | 500 (5 %) | `BasaltConstants` |
| `ZAPIN_CALLBACK_GAS_LIMIT` | 1 600 000 | `BasaltConstants` |
| `GM_UNWRAPPER_MAX_SLIPPAGE_BPS` | 5 000 (50 %) | `BasaltConstants` |
| `GM_UNWRAPPER_MAX_PERMISSIONLESS_SLIPPAGE_BPS` | 200 (2 %) | `BasaltConstants` |
| `GM_UNWRAPPER_CALLBACK_GAS_LIMIT` | 2 000 000 | `BasaltConstants` |
| `PROTOCOL_MANAGER_CHANGE_THRESHOLD_BPS` | 8 000 | `ManagerContract` |
| `ADDRESS_BOOK_COOLDOWN_CHANGE_PERIOD` | 24 h | `VaultCoreNftFactory` |
| `TOTAL_SHARES` | 1e18 | `FeeSplitter` |
| `MAX_TRACKED_TOKENS` | 20 | `FeeSplitter` |
| `ACC_PRECISION` | 1e30 | `FeeSplitter` |

---

## 5. Algorithms

### 5.1 `DepositHandler.deposit`

```
1. require onlyVaultNftOwner
2. requireAllIdle / requireCooldownPassed / requireValidDepositParams / requireSequencerUp
3. selectDepositBranch(amountGm, slippage)  // reads gmColl, wbtcDebt, surplusGm, isoVaultCreated
4. switch (branch):
   CreateIsolationVault     -> clone Dolomite isolation vault + setDolomiteIsolationVault
   EmptyIsolationVault      -> (vault exists but empty position)
   Standard                 -> ratio-preserving borrow (amountGm * debt / coll)
   CollateralOnly           -> lever up to target LTV using (coll + deposit) * gmPrice
   DebtFreeSurplus          -> revert NeedToAbsorbSurplus
5. depositContext.borrowValue / borrowWbtc / gmReceivedMin are filled;
   requireLtvBelowCap enforces post-deposit projected LTV <= 7000 bps
6. transfer GM from depositor -> VaultCore
7. depositIntoVaultForDolomiteMargin (account 0)
8. transferIntoPositionWithUnderlyingToken (account 100) or openBorrowPosition if first entry
   (openBorrowPosition costs `IVaultFactory.executionFee()` in ETH)
9. setPendingDepositAccounting(amountGm, gmPrice, gmCollateralSnapshot, deadline)
10. setDepositState(PENDING)
11. asyncWrap via swapExactInputForOutput (WBTC->GM) with minGmOut
12. emit DepositInitiated
```

### 5.2 `DepositHandler.finalizeDeposit`

```
1. requireCallerIsProtocolManagerOrVaultNftOwner
2. requireDepositPending
3. requireVaultNotFrozen
4. requireSequencerUp
5. read navUsd, gmColl, wbtcDebt
6. success <=> gmColl > pendingDepositGmCollateralSnapshot + pendingDepositAmountGm
7a. fail -> refund GM from isolation position to user via
          transferFromPositionWithUnderlyingToken(100->0, amount)
          + withdrawFromVaultForDolomiteMargin(0, amount)
          + IERC20(GM).transfer(user, amount)
          + clearPendingDepositAccounting + startGlobalActionCooldown
7b. success -> finalizeDepositAccounting(depositedUsd, nav, gmColl, wbtcDebt)
               + accrueManagerFee (via FeeAccountingHandler)
               + startGlobalActionCooldown
```

### 5.3 `DepositHandler.absorbSurplus`

```
1. onlyVaultNftOwner + all-idle + cooldown + validSlippage + sequencerUp
2. surplusWbtcE8 = DolomiteReader.getActualWbtcSurplusE8  (must be > 0)
3. expectedGm = surplus * wbtcPrice / gmPrice
4. minGm      = expectedGm * (1 - slippage)
5. setDepositState(PENDING) + asyncWrap(surplus, minGm) (no new accounting row — amountGm=0)
```

### 5.4 `DepositHandler.addWbtcAsDeposit`

```
1. onlyVaultNftOwner + all-idle + cooldown + sequencerUp
2. existing surplus USD in (0, $10]  AND  new deposit USD in (0, $10]      // dust top-up
3. safeTransferFrom(WBTC, user -> VaultCore)
4. Dolomite operate: deposit WBTC to account 0, then transferIntoPositionWithOtherToken -> account 100
5. addDepositedUsdE18(amount * wbtcPrice)
```

### 5.5 `WithdrawHandler.withdraw`

```
1. onlyVaultNftOwner + all-idle + cooldown + validShare (in(0, 1e18]) + sequencerUp
2. accrueManagerFeeBeforeWithdraw               // refreshes managerAccruedFeeUsd
3. requireSharesWithinOwnerEligibleWithdraw
4. selectWithdrawBranch -> {AsyncDebt | SyncGmWithSurplus | SyncGmOnly | SyncWbtcSurplusOnly}
5a. AsyncDebt -> calc gmToSell = proRataGm, snapshot rawRatioInitial = ceil(gmColl * 1e18 / debt)
               snapshot current wbtc borrow index
               setPendingWithdraw(..., isManagerFee=false) + asyncUnwrap(gmToSell, minWbtcOut)
5b. SyncGmOnly / SyncGmWithSurplus -> pro-rata GM  (+ pro-rata WBTC surplus) directly to user
5c. SyncWbtcSurplusOnly -> pro-rata WBTC surplus to user
6. Sync branches: recordWithdrawnUsd (owner) or recordManagerFeeWithdrawnUsd (manager)
7. Sync branches arm nothing (state stays IDLE)
```

### 5.6 `WithdrawHandler.finalizeWithdraw`

```
1. requireCallerIsProtocolManagerOrVaultNftOwner
2. requireWithdrawPending / requireCooldownPassed / requireVaultNotFrozen / requireSequencerUp
3. readCurrent gmColl; if unchanged from snapshot -> clearPendingWithdraw + emit success=false
4. if currentDebt > 0  ("with debt" path)
     adjustedDebt = debt * snapIndex / currentIndex   (only if currentIndex > snapIndex)
     targetDebt   = currentCollateral * 1e18 / rawRatio
     wbtcToUser   = max(targetDebt - adjustedDebt, 0)
     if wbtcToUser > 0 -> withdrawWbtcToUser + recordWithdrawnUsd/recordManagerFee
   else ("surplus" path)
     wbtcToBorrow = currentCollateral * 1e18 / rawRatio
     wbtcToUser   = currentSurplus + wbtcToBorrow
     withdrawWbtcToUser + recordWithdrawnUsd/recordManagerFee
5. clearPendingWithdraw
```

### 5.7 `ManagerHandler.rebalance`

```
1. all-idle + cooldown + validSlippage(mgrSlip in [50, 1000] AND <= rebalanceSlippageCapBps) + sequencerUp
2. if caller != protocolManager -> requireVaultNftOwner
3. snapshot (gmColl, wbtcDebt, gmPrice, wbtcPrice)  via DolomiteReader
4. if gmColl == 0 -> revert NoCollateral
5. currentLtv = calcLtvBps(debt, coll)
6. if currentLtv == target -> revert LtvAlreadyAtTarget
7. if caller != protocolManager -> requireNftOwnerRebalanceDeviation
8. if currentLtv > target:
     gmToSell = rebalanceDelta(debtUsd - targetDebtUsd, target) / gmPrice     (clamped <= gmColl)
     _rebalanceDownToLtv:
        requireAsyncPreChecks (vault not frozen, slip >= MIN)
        expectedWbtcOut = gmToSell * gmPrice / (wbtcPrice * 1e10) * longShare/BPS
        minWbtcOut = applySlippage(expectedWbtcOut, mgrSlip)
        requirePostLtvSafe(coll - gmToSell, max(0, debt - minWbtcOut))
        setPendingRebalance(kind=LTV, direction=DOWN, ...)
        dolomiteAsyncUnwrap(gmToSell, minWbtcOut)
9. else:
     borrowWbtc = rebalanceDelta(targetDebtUsd - debtUsd, target) / wbtcPrice
     _rebalanceUpToLtv:
        expectedGmOut = borrowWbtc * wbtcPrice / gmPrice
        minGmOut = applySlippage(expectedGmOut, mgrSlip)
        requirePostLtvSafe(coll + minGmOut, debt + borrowWbtc)
        setPendingRebalance(kind=LTV, direction=UP, ...)
        dolomiteAsyncWrap(borrowWbtc, minGmOut)
```

### 5.8 `ManagerHandler.finalizeRebalance`

```
1. requireCallerIsProtocolManagerOrVaultNftOwner
2. rebalance state PENDING + kind == LTV + vault not frozen
3. read snapshot, compute ltvAfter
4. clearPendingRebalance
5. emit RebalanceFinalized(before, after)
```

### 5.9 `AsyncRecoveryHandler.unstuckPending`

```
1. requireCallerIsProtocolManagerOrVaultNftOwner
2. resolvePendingOperation (from VaultState: deposit/withdraw/rebalance PENDING -> Wrap|Unwrap)
3. require pending != None + block.timestamp >= deadline + 10 min
4. require Dolomite isolation vault still frozen
5. Wrap:   require wrapper registered on GmxV2Registry + depositInfo.vault matches + accountNumber == 100
          -> cancelDeposit(key)
   Unwrap: same but with unwrapper + withdrawalInfo + not isLiquidation
          -> cancelWithdrawal(key)
```

### 5.10 `FeeAccountingHandler.accrueManagerFee`

```
1. initiator in {nftOwner, protocolManager} AND msg.sender in {initiator, any vault handler}
2. requireSequencerUp
3. currentNav = DolomiteReader.getActualNavUsdE18(...)
4. profit = max(NAV + totalWithdrawn - totalDeposited, 0)
5. profitDelta = max(profit - prevHwmProfit, 0)
6. perfFee = profitDelta * managementFeeBps / BPS
7. nextHwmProfit = max(profit, prevHwmProfit)
8. if perfFee > 0: setFeeAccounting(nextHwmProfit, prevAccrued + perfFee) via universalCall
9. emit ManagerFeeAccrued
```

### 5.11 `ManagerContract.proposeProtocolManagerChange` -> `execute/cancel`

```
1. propose:
     factory != 0 AND next != 0
     block.number > 1     (snapshot = block.number - 1)
     factory.protocolManager() == address(this)
     no active proposal
     getPastVotes(proposer, snapshot) > 0
     ->  proposals[id] = {factory, next, snapshot, 0, 0, false, false}
        activeProtocolManagerProposalId = id

2. sign / signCancel:
     getPastVotes(msg.sender, snapshot) > 0
     first time -> add weight to yes/cancelWeight
     signing one side blocks signing the other (AlreadySignedOpposite)

3. execute (snapshot holder or operational):
     requireSnapshotHolderOrOperational
     yesWeight * 10_000 >= pastTotalSupply * 8_000
     set executed = true, clear active, factory.setProtocolManager(next)

4. cancel (snapshot holder or operational, same 80 %):
     requireSnapshotHolderOrOperational
     cancelWeight * 10_000 >= pastTotalSupply * 8_000
     set cancelled = true, clear active
```

### 5.12 `FeeSplitter` accumulator

```
_syncAccumulator(token):
   if token not tracked -> return acc
   received = balanceOf(this) + totalReleasedByToken[token]
   if received > lastSeen: delta = received - lastSeen
       acc += delta * 1e30 / totalSupply
       lastSeen = received
       emit RewardNotified

_update(from, to):
   for each tracked non-skipped token:
       _syncAccumulator
       _settle(token, from); _settle(token, to)      // snapshots accrued into _pending
   super._update(from, to)
   for each tracked non-skipped token:
       reset _rewardDebt[token][from] = acc * balanceOf(from) / 1e30 (same for to)
   if to has balance > 0 and no delegate -> self-delegate

release(token, account):
   requireHolderOrOperational
   require token not skipped
   _syncAccumulator + _settle
   pay out _pending[token][account]
   totalReleasedByToken[token] += payment  (lastSeen invariant)
```

---

## 6. Invariants

Grouped by layer. Each invariant names its enforcement site.

### 6.1 Access & lifecycle

1. **I-ACL-universalCall** — `VaultCore.universalCall` reverts unless `msg.sender` is a handler slot AND `initiator in {nftOwner, protocolManager}`.
2. **I-ACL-mutation** — Only `VaultCore` can mutate `VaultState` (`onlyVaultCore` on every setter). Handlers can only mutate state via `universalCall -> VaultState.setX`.
3. **I-LIFE-singleProposal** — At most one in-flight `HandlerProposal` / `BasaltAddressesProposal` / protocol-manager proposal at a time.
4. **I-LIFE-twoStepUpgrade** — Any change to `depositHandler`, `withdrawHandler`, `managerHandler`, `asyncRecoveryHandler`, `feeAccountingHandler`, `extensionHandler1/2/3`, `basaltMath`, `basaltState` requires both protocol-manager propose AND NFT owner accept.
5. **I-LIFE-uniqueHandlerSlot** — A handler address can occupy at most one slot in `VaultCore` (`DuplicateHandler`).
6. **I-LIFE-factoryCooldown** — `createVaultCore` fails if `block.timestamp < addressBookCooldownEndsAt`.
7. **I-LIFE-nftBijection** — `tokenIdByVault` and `vaultByTokenId` are a bijection; NFT owner of the vault always equals the handler's `factory.ownerOfVault(address(this))`.
8. **I-LIFE-deadmanOnce** — `triggerManagerDeadman` can only succeed once per vault (`managerDeadmanTriggered` is a one-way flag).

### 6.2 State machine

9. **I-SM-allIdle** — `deposit`, `absorbSurplus`, `addWbtcAsDeposit`, `withdraw`, `withdrawManagerFeeShares`, `rebalance`, and every config setter require `depositState == withdrawState == rebalanceState == IDLE`.
10. **I-SM-cooldown** — The same entrypoints require `block.number >= globalActionCooldownEndBlock`.
11. **I-SM-depositRefundPath** — On `decideDepositSuccessOrFail == false`, the refund path exactly returns `pendingDepositAmountGmE18` of GM to the NFT owner and does NOT bump `totalDepositedGm/Usd`, HWM, or manager fee.
12. **I-SM-pendingClearedOnFinalize** — `finalizeDeposit`, `finalizeWithdraw`, `finalizeRebalance` always clear their respective pending accounting on success.
13. **I-SM-withdrawIdleAfterSync** — Sync withdraw branches never set `withdrawState = PENDING` (no `finalize` needed).
14. **I-SM-noValueOnSync** — `SyncGmOnly/SyncGmWithSurplus/SyncWbtcSurplusOnly` revert if `msg.value != 0`.

### 6.3 Risk / LTV

15. **I-LTV-post-deposit-cap** — After any deposit branch that touches target LTV, the projected LTV (with `minGmFromWrap`) is <= `MAX_POST_DEPOSIT_LTV_BPS = 7000`.
16. **I-LTV-post-rebalance-cap** — After any rebalance leg, premium-adjusted LTV `(debt*(1+debtPremium)) / (coll/(1+collPremium))` is <= `MAX_SAFE_LTV_BPS = 7000` (skipped iff projected debt == 0).
17. **I-LTV-configBounds** — `targetLtvBps in [4800, 5200]`, `rebalanceThreshold{Up,Down}Bps in [500, 2000]`, `rebalanceSlippageCapBps in [100, 1000]`, `unwrapLongShareBps in [4000, 5000]`, `keeperDeadline in [60 s, 60 min]`.
18. **I-LTV-nftOwnerBand** — Vault NFT owner can only rebalance when `|currentLtv - targetLtv| >= rebalanceThreshold{Up|Down}Bps` (side-aware).
19. **I-LTV-noCollateral** — `rebalance` reverts with `NoCollateral` if `totalGmCollateralE18 == 0`.
20. **I-LTV-notAtTarget** — `rebalance` reverts with `LtvAlreadyAtTarget` if `currentLtv == targetLtv`.

### 6.4 Withdraw

21. **I-WIT-shareRange** — `sharesToWithdraw in (0, SHARE_UNIT]`.
22. **I-WIT-ownerCap** — Owner withdraw shares <= `totalShares * (NAV - managerFee) / NAV`; reverts otherwise.
23. **I-WIT-managerCap** — Manager-fee withdraw shares <= `min(totalShares * managerFee / NAV, totalShares - ownerEligible)`.
24. **I-WIT-ratioPreservationOnFinalize** — On `_finalizeWithDebt`, the handler borrows WBTC so that post-finalize GM/WBTC ratio equals (or improves upon) `rawRatioInitial` (accounting for borrow-index drift).
25. **I-WIT-emptyFinalizeNoop** — If the keeper never moved GM collateral (`currentCollateral == snapshotCollateral`), `finalizeWithdraw` pays out 0 and emits `success=false`.

### 6.5 Async recovery

26. **I-ASYNC-timeGate** — `unstuckPending` enforces `block.timestamp >= pending.deadline + UNSTUCK_GRACE_AFTER_DEADLINE`.
27. **I-ASYNC-dolomiteStillFrozen** — `unstuckPending` requires `isVaultFrozen()` still true.
28. **I-ASYNC-ourKeyOnly** — `unstuckPending` checks `depositInfo.vault == dolomiteIsolationVault` (or withdrawalInfo) and `accountNumber == 100`.
29. **I-ASYNC-noLiquidationCancel** — `unstuckPending` reverts with `LiquidationOnlyDolomite` if the withdrawal key is marked liquidation.

### 6.6 Fee / HWM

30. **I-FEE-hwmMonotonic** — `highWaterMarkProfitUsdE18` is monotonically non-decreasing: `nextHwmProfit = max(profit, prevHwmProfit)`.
31. **I-FEE-profitBased** — Fee is only charged on new absolute profit above the HWM: `profitDelta = max(profit - prevHwmProfit, 0)`, where `profit = max(NAV + totalWithdrawn - totalDeposited, 0)`.
32. **I-FEE-mgmtMonotone** — `managementFeeBps` is monotonically non-increasing and never exceeds `MANAGER_FEE_BPS = 2000`.
33. **I-FEE-accrueOnFinalize** — Every successful `finalizeDeposit` calls `accrueManagerFee`; every successful `withdraw*` accrues before capping eligibility.
34. **I-FEE-splitterConservation** — In `FeeSplitter`, `balanceOf(this) + totalReleasedByToken[t] == _lastSeenReceived[t]` immediately after `_syncAccumulator` or `release`.
35. **I-FEE-splitterHandoff** — On any share transfer, the transferred shares cannot retroactively claim rewards that accrued before the transfer (pre-transfer `_settle` guarantees this).

### 6.7 Oracle / pricing

36. **I-ORA-sequencer** — `DepositHandler.deposit`, `DepositHandler.absorbSurplus`, `DepositHandler.finalizeDeposit`, `WithdrawHandler.withdraw`, `WithdrawHandler.withdrawManagerFeeShares`, `WithdrawHandler.finalizeWithdraw`, `ManagerHandler.rebalance`, `FeeAccountingHandler.accrueManagerFee` require `OracleGuard.requireSequencerUp` (answer==0, startedAt>0, elapsed > 3600 s).
37. **I-ORA-singleSource** — NAV/LTV/deposit/withdraw math all use Dolomite prices; Chainlink gates sequencer and cross-checks WBTC price within 0.25 % spread.
38. **I-ORA-roundComplete** — `OracleGuard.readChainlinkPrice` verifies `answeredInRound >= roundId` (`OracleIncompleteRound`).
39. **I-ORA-priceCeiling** — Chainlink prices are capped: WBTC <= `1e15`, USDC <= `1e9` (`OraclePriceTooHigh`).

### 6.8 Governance vote

40. **I-GOV-threshold** — Both `executeProtocolManagerChange` and `cancelProtocolManagerChange` require `weight * 10_000 >= pastSupply * 8_000`.
41. **I-GOV-snapshot** — Voting weight is `FeeSplitter.getPastVotes(account, snapshot)` at the snapshot set at proposal creation.
42. **I-GOV-onePending** — New propose is blocked if there is an active proposal that is neither executed nor cancelled.
43. **I-GOV-selfManaged** — `proposeProtocolManagerChange` requires the target factory's current `protocolManager() == address(this)` (cannot vote on foreign factories).
44. **I-GOV-noFlipSign** — A signer who signed `yes` cannot sign `cancel` and vice versa (`AlreadySignedOpposite`).
45. **I-GOV-executeAuth** — Execute/cancel requires caller to be a snapshot holder with voting power or the operational role.

---

## 7. Module deep-dives

### 7.1 `VaultCore`
- Storage: FACTORY, basaltMath, basaltState, accountedCapital, 8 handler slots, `HandlerProposal`, `BasaltAddressesProposal`.
- Entrypoints: `initialize` (once), `universalCall(initiator, target, data, value, delegate)`, `proposeHandler`, `acceptHandler`, `cancelHandlerProposal`, `proposeBasaltAddresses`, `acceptBasaltAddresses`, `cancelBasaltAddressesProposal`, `triggerManagerDeadman`.
- `onlyManager` modifier: allows protocol manager, OR NFT owner if `managerDeadmanTriggered` is true on VaultState.
- Delegate call is supported by `universalCall` but handlers in-repo only use plain `call` (`delegate = false`). This keeps storage ownership clear (`VaultState` stores everything; `VaultCore` is ACL + proxy).
- Errors: `NotManager`, `NotHandler`, `NotNftOwner`, `NotManagerOrNftOwner`, `NoHandlerProposal`, `NoBasaltAddressesProposal`, `UnknownHandler`, `AlreadyInitialized`, `ZeroHandler`, `DuplicateHandler`, `DeadmanAlreadyTriggered`, `DeadmanPeriodNotElapsed`.

### 7.2 `VaultState`
- `State { IDLE, PENDING }` for deposit / withdraw / rebalance.
- Pending slot groups: deposit (`amountGm`, `gmPrice`, `gmCollateralSnapshot`, `deadline`), withdraw (`withdrawer`, `shares`, `gmToSell`, `collateralSnapshot`, `wbtcDebtSnapshot`, `rawRatioInitial`, `minWbtcOut`, `borrowIndex`, `deadline`, `isManagerFee`), rebalance (`kind`, `direction`, `initiator`, `ltvSnapshotBps`, `deadline`).
- Accounting: `totalDepositedGmE18`, `totalDepositedUsdE18`, `totalWithdrawnUsdE18`, `highWaterMarkProfitUsdE18`, `managerAccruedFeeUsdE18`, `lastFinalized{NavUsd, GmCollateral, WbtcDebt}`.
- Config: `managementFeeBps`, `keeperDeadline`, `targetLtvBps`, `rebalanceThresholdUpBps`, `rebalanceThresholdDownBps`, `rebalanceSlippageCapBps`, `unwrapLongShareBps`, `globalActionCooldownEndBlock`, `dolomiteIsolationVault`.
- Deadman: `lastManagerActionBlock`, `managerDeadmanTriggered`.
- Defaults are seeded by `initialize` from `BasaltConstants`.

### 7.3 `ManagerContract`
- Roles: owner (Ownable2Step), configurator, operational, handlerProposer, addressProposer, feeCollector (2-step rotation).
- Structured proposal storage: `ProtocolManagerProposal { factory, nextProtocolManager, snapshot, yesWeight, cancelWeight, executed, cancelled }` + signed/signedCancel mappings.
- `collectManagerFeesFromVaultAndSweep`: withdraws fee shares, if `withdrawState == PENDING` and `currentGmColl != collateralAtPendingStart` it calls `finalizeWithdraw` inline; then sweeps listed tokens to `FeeSplitter` via `_sweepTokensToFeeSplitter` (safeTransfer + `notifyReward`, only tracked non-skipped tokens).
- `collectFees`: requires caller to be `operational` or hold FeeSplitter balance > 0.
- Additional owner functions: `setInitialCoreAddressBook` (on a factory), `addFeeSplitterTrackedToken`, `setFeeSplitterTokenSkipped`.
- Additional operational functions: `pingVaultHeartbeat`, `notifyFeeSplitterReward`.

### 7.4 `FeeSplitter`
- Fixed supply `1e18`, minted to the initial holder and self-delegated.
- `_trackedTokens` set at construction and can grow via `addTrackedToken` (called by `managerContract`), up to `MAX_TRACKED_TOKENS = 20`.
- Tokens can be skipped via `setTokenSkipped` (called by `managerContract`). Skipped tokens are excluded from transfer settlement loops, `notifyReward` reverts on them, and `release` reverts on them.
- `managerContract` is set once by `initialOwner` via `setManagerContract`. Cannot be changed after set.
- Precision: `ACC_PRECISION = 1e30` keeps ~30 decimals of headroom for `delta * 1e30 / totalSupply`.
- `nonces` override resolves `ERC20Permit` + `Nonces`.
- Voting (`ERC20Votes`): power is checkpointed at every transfer; `getPastVotes(account, blockNumber)` is the source of truth for `ManagerContract` governance. New recipients with balance > 0 and no delegate are auto-self-delegated in `_update`.
- `release` requires caller to hold shares or be the ManagerContract operational role.
- `notifyReward` requires caller to be `managerContract` or hold shares.
- Errors: `NoPaymentDue`, `ZeroTokenAddress`, `TokenAlreadyTracked`, `MaxTrackedTokensReached`, `ZeroManagerContract`, `ManagerContractAlreadySet`, `NotManagerContract`, `NotAuthorisedToNotify`, `NotInitialOwner`, `NotAuthorisedToRelease`, `TokenIsSkipped`.

### 7.5 `VaultCoreNftFactory`
- `createVaultCore`: clones, initializes both, mints NFT `tokenId = ++nextTokenId`, records bijection. Uses `ReentrancyGuard`.
- `setProtocolManager`: only callable by the **current** protocolManager — orchestrated by `ManagerContract.executeProtocolManagerChange` (which is, itself, the current protocolManager).
- `setInitialCoreAddressBook`: only owner; arms 24 h cooldown that blocks new vault creation.

### 7.6 `InitialCoreAddressBook`
- Immutable tuple: `vaultCore`, 5 handler addresses, 3 extension slots, `basaltState`, `basaltMath`, `dolomiteVault`. Used only by `VaultCoreNftFactory.createVaultCore` and reachable via `initialCoreAddresses()`.

### 7.7 `DepositHandler`
- Events: `DepositInitiated`, `DepositFinalized`, `DepositRefunded`, `DepositBranchSelected`, `SurplusAbsorbInitiated`, `WbtcAddedAsDeposit`.
- Branches, rules and math covered in SS4.3 / SS5.1-5.4 / `DepositHandlerCalculations`.
- `_execRefundDepositPath` is the only write path that moves GM out of the position without a price/LTV check — it's protected by `decideDepositSuccessOrFail`.
- `finalizeDeposit` requires sequencer up in addition to other checks.

### 7.8 `WithdrawHandler`
- Events: `AsyncWithdrawInitiated`, `SyncGmWithdraw`, `SyncGmWithSurplusWithdraw`, `SyncWbtcSurplusWithdraw`, `WithdrawFinalized`.
- Helpers: `previewWithdraw` (read-only: eligibility + projected manager-fee + output amounts), `managerMaxFeeWithdrawShares`, `selectWithdrawBranch`.
- Executors isolate Dolomite calls: `asyncUnwrap` (swapExactInput OUT), `withdrawGmToUser`, `withdrawWbtcToUser`.
- Withdrawn USD tracking via `_recordWithdrawnUsdByPolicy`: owner withdrawals call `recordWithdrawnUsd` (adds to `totalWithdrawnUsdE18`); manager fee withdrawals call `recordManagerFeeWithdrawnUsd` (subtracts from `managerAccruedFeeUsdE18`).
- Both `withdraw` and `withdrawManagerFeeShares` require sequencer up.

### 7.9 `ManagerHandler`
- Events: `RebalanceInitiated(caller, isLoopUp, amount, minOut, isInitiatedByNftOwner)`, `RebalanceFinalized(caller, success, ltvBefore, ltvAfter)`, `PendingRebalanceCleared`, 6x config-updated, `ManagerHeartbeat`.
- `RebalanceSnapshot` (per call): `{ totalGmCollateralE18, totalWbtcDebtE8, gmPriceUsdE18, wbtcPriceUsdE18 }`. `readDolomiteSnapshot` assembles it from `DolomiteReader`.
- Dolomite premium applied via `getMarketMarginPremium(GM / WBTC)` in `requirePostLtvSafe`.
- All config setters and `pingHeartbeat` bump `lastManagerActionBlock`.
- View: `currentLtvBps` returns the current LTV from a fresh Dolomite snapshot.

### 7.10 `AsyncRecoveryHandler`
- Constants: `UNSTUCK_GRACE_AFTER_DEADLINE = 10 min`.
- Uses `GmxV2Registry (0xaDC1A8AD79E55Ab9E8569e497775B63e737316A8)` to locate wrapper/unwrapper for `BasaltAddresses.VAULT_FACTORY`.
- `resolvePendingOperation` maps VaultState flags to `{None, Wrap, Unwrap}` with deterministic rebalance-direction logic.
- View: `canUnstuckWith(key)` returns a human-readable reason; `nextUnstuckAt` returns `(unstuckNotBefore, 0)` (second return kept for ABI stability).

### 7.11 `FeeAccountingHandler`
- Pure view: `calculateManagerFee(vault, basaltMath)` returns `(currentNav, currentProfit, profitDelta, perfFee, nextHwmProfit, nextAccrued)` and is side-effect-free.
- Write: only actually touches `VaultState.setFeeAccounting` via `universalCall` when `perfFee > 0`.
- ACL: `_isVaultHandlerSlot` whitelists all 8 handler slots; `initiator` is always validated against `ownerOfVault` or `protocolManager`.
- Requires sequencer up (`OracleGuard.requireSequencerUp`) on every accrual call.

### 7.12 `BasaltMath`
- Stateless; all functions are `external pure`.
- Hosts the complete pricing / LTV / rebalance / fee math. Consumed by all handlers through their respective `*Calculations` libraries.
- Fee math uses profit-based HWM: `calcProfitUsdE18(nav, deposited, withdrawn)`, `calcPerformanceFeeByHwmProfit(profit, prevHwm, feeBps)`, `calcNextHighWaterMarkProfit`, `calcNextAccruedManagerFee`.

### 7.13 Libraries
- `BasaltConstants` — single source of literals (see SS4.8).
- `BasaltAddresses` — Arbitrum mainnet addresses: GMX v2 (`GMX_DATA_STORE`, `GM_MARKET_TOKEN`, exchange router, deposit/withdrawal vaults & handlers, `GMX_V2_ROUTER`), tokens (`WBTC`, `USDC`, `WETH`), Dolomite (`DOLOMITE_MARGIN`, `VAULT_FACTORY`, `GMX_V2_REGISTRY`), Chainlink (`CL_WBTC_USD`, `CL_USDC_USD`, `CL_SEQUENCER`), Uniswap V3 (`UNI_V3_SWAP_ROUTER`, WBTC/USDC + WETH/USDC 0.05 % pools).
- `DolomiteReader` — `getGmPriceE18`, `getWbtcPriceE28` (with Chainlink cross-check), `getWbtcBorrowIndexE18`, `getActualGmCollateralE18`, `getActualWbtcDebtE8`, `getActualWbtcSurplusE8`, `getActualNavUsdE18`. Returns `0` for empty / inverted positions. Error: `OraclePriceSpreadTooWide`.
- `OracleGuard` — `readChainlinkPrice` (staleness + positivity + round completeness + hard ceiling) and `requireSequencerUp` (Arbitrum L2-sequencer feed, checks `answer == 0`, `startedAt > 0`, elapsed > grace period). Errors: `OracleStalePrice`, `OracleNonPositivePrice`, `OraclePriceTooHigh`, `OracleIncompleteRound`, `SequencerDown`, `SequencerGracePeriod`.
- `GMCalculator` — self-contained GMX v2 pool-value / PnL math (read-only), used by `BasaltZapIn` to compute on-chain GM price with GMX DataStore keys (`POOL_AMOUNT`, `OPEN_INTEREST`, `OPEN_INTEREST_IN_TOKENS`, `CUMULATIVE_BORROWING_FACTOR`, `TOTAL_BORROWING`, `BORROWING_FEE_RECEIVER_FACTOR`, `POSITION_IMPACT_POOL_AMOUNT`, `LENT_POSITION_IMPACT_POOL_AMOUNT`, `MIN_POSITION_IMPACT_POOL_AMOUNT`, `POSITION_IMPACT_POOL_DISTRIBUTION_RATE`, `POSITION_IMPACT_POOL_DISTRIBUTED_AT`, `MAX_PNL_FACTOR`, `MAX_PNL_FACTOR_FOR_DEPOSITS`). Errors: `GmPriceNonPositive`, `GmxDataStoreZero`.
- `BasaltPrecision` — mirrors GMX Synthetics `Precision.sol`: `FLOAT_PRECISION = 1e30`, `WEI_PRECISION = 1e18`, `FLOAT_TO_WEI_DIVISOR = 1e12`, `applyFactor(value, factor) = value * factor / FLOAT_PRECISION`.
- `ZapInMath` — consumed by `BasaltZapIn`: `calcStableMinOut` (cross-decimal scaling), `quoteWbtcFromUsdc`, `calcUsdcValueE18`, `calcWbtcValueE18`, `calcMinMarketTokens`.

### 7.14 `src/ux/*` (thin UX layer)
- `BasaltZapIn` — stateless USDC -> GM router. Takes a price snapshot (sequencer-guarded Chainlink for WBTC/USDC, GMCalculator for GM price), selects a route based on pool imbalance (`_selectRoute`: if long pool USD > short pool USD by `POOL_IMBALANCE_BPS`, route `GM_SHORT` (USDC direct); if opposite, `GM_LONG` (USDC -> WBTC via UniV3, then WBTC -> GM); default `GM_SHORT`), submits a GMX v2 `createDeposit` with `receiver = msg.sender`. Minimum deposit must clear `1 GM + ZAPIN_MIN_DEPOSIT_GM_BUFFER_BPS (5 %)`. Swap slippage bounded by `ZAP_MAX_SWAP_SLIPPAGE_BPS = 1000`. Errors: `ZeroAddress`, `ZeroAmount`, `InvalidSwapSlippage`, `MissingExecutionFee`, `BelowMinimumDeposit`, `GmxPoolAmountZero`.
- `BasaltZapOut` — stateless WBTC -> USDC router via Uniswap V3 (`WBTC_POOL_FEE = 500`). Pulls WBTC, oracle-prices the min USDC out (sequencer + Chainlink guarded), swaps to USDC for the caller. Swap slippage bounded by `[ZAP_MIN_SWAP_SLIPPAGE_BPS, ZAP_MAX_SWAP_SLIPPAGE_BPS] = [10, 1000]`. Errors: `ZeroAddress`, `ZeroAmount`, `InvalidSwapSlippage`.
- `BasaltGmUnwrapper` — standalone GM -> (WBTC + USDC) unwrapper. Pulls GM, computes pool-composition-based minimum long (WBTC) and short (USDC) legs from current pool ratios and total supply, submits GMX v2 `createWithdrawal` with `receiver = msg.sender`. Slippage bounded by `GM_UNWRAPPER_MAX_SLIPPAGE_BPS = 5000` (50 %). Sequencer and oracle sanity checks before submission. Errors: `ZeroAddress`, `ZeroAmount`, `MissingExecutionFee`, `InvalidSlippage`, `GmxPoolAmountZero`, `GmxTotalSupplyZero`.

---

## 8. Error index (cross-module)

Grouped by handler. Listed once; see module for context.

```
DepositHandler:           NotIdle, CooldownNotPassed, DepositTooSmall, VaultStillFrozen,
                          InvalidSlippage, PostDepositLtvTooHigh, NotVaultNftOwner,
                          NotManagerOrNftOwner, DepositNotPending, NeedToAbsorbSurplus,
                          NoSurplusToAbsorb, InvalidWbtcAsDepositValue, ZeroAbsorbAmount,
                          InvalidDepositBranch
WithdrawHandler:          NotIdle, CooldownNotPassed, InvalidPositionShareToWithdraw,
                          NothingToWithdraw, WithdrawNotPending, VaultStillFrozen,
                          UnexpectedValue, SlippageExceeded, WithdrawTransferFailed,
                          NotVaultNftOwner, NotManagerOrNftOwner, NotProtocolManager,
                          WithdrawExceedsOwnerEligibleShares, WithdrawExceedsManagerFeeShares
ManagerHandler:           NotIdle, CooldownNotPassed, PostSettlementLtvTooHigh, NoCollateral,
                          InvalidSlippage, SlippageExceedsCap, RebalanceNotPending,
                          SlippageTooTight, WrongRebalanceKind, NotVaultNftOwner,
                          NotManagerOrNftOwner, LtvAlreadyAtTarget,
                          RebalanceWithinNftOwnerBand, ZeroRebalanceAmount,
                          RebalanceStillPending, AsyncOperationPending, NotProtocolManager,
                          InvalidTargetLtv, InvalidSlippageCap, InvalidThreshold,
                          InvalidUnwrapLongShare
AsyncRecoveryHandler:     ZeroAddress, NothingPending, TooEarly, NotFrozenAnymore,
                          InvalidRebalanceDirection, NotOurKey, WrongAccount,
                          LiquidationOnlyDolomite, UnwrapperNotRegistered, WrapperNotRegistered,
                          NotVaultNftOwner, NotManagerOrNftOwner
FeeAccountingHandler:     InvalidInitiator, NotAuthorizedCaller
VaultCore:                NotManager, NotHandler, NotNftOwner, NotManagerOrNftOwner,
                          NoHandlerProposal, NoBasaltAddressesProposal, UnknownHandler,
                          AlreadyInitialized, ZeroHandler, DuplicateHandler,
                          DeadmanAlreadyTriggered, DeadmanPeriodNotElapsed
VaultState:               AlreadyInitialized, DolomiteIsolationVaultAlreadyInitialized,
                          InvalidManagementFee, ManagementFeeCannotIncrease,
                          InvalidKeeperDeadline, InvalidTargetLtv, VaultNotIdle, NotVaultCore
VaultCoreNftFactory:      ZeroOwner, VaultAlreadyIssued, UnknownTokenId, ZeroAddressBook,
                          ZeroProtocolManager, NotCurrentProtocolManager,
                          AddressBookCooldownActive
ManagerContract:          NotPendingRole, NotFeeCollector, NotOperational, NotConfigurator,
                          NotHandlerProposer, NotAddressProposer, ZeroFeeSplitter, ZeroFactory,
                          ZeroProtocolManager, ZeroRole, SnapshotUnavailable, ProposalNotFound,
                          ProposalCancelled, AlreadySigned, AlreadySignedOpposite,
                          NoVotingWeight, NoPastSupply,
                          InsufficientFeeParticipantSupport, InsufficientCancelSupport,
                          AlreadyExecuted, ActiveProposalExists, NotCurrentProtocolManager,
                          NotAuthorisedToFinalizeProposal, NotAuthorisedToCollectFees
FeeSplitter:              NoPaymentDue, ZeroTokenAddress, TokenAlreadyTracked,
                          MaxTrackedTokensReached, ZeroManagerContract,
                          ManagerContractAlreadySet, NotManagerContract,
                          NotAuthorisedToNotify, NotInitialOwner,
                          NotAuthorisedToRelease, TokenIsSkipped
OracleGuard:              OracleStalePrice, OracleNonPositivePrice, OraclePriceTooHigh,
                          OracleIncompleteRound, SequencerDown, SequencerGracePeriod
DolomiteReader:           OraclePriceSpreadTooWide
GMCalculator:             GmPriceNonPositive, GmxDataStoreZero
BasaltZapIn:              ZeroAddress, ZeroAmount, InvalidSwapSlippage,
                          MissingExecutionFee, BelowMinimumDeposit, GmxPoolAmountZero
BasaltZapOut:             ZeroAddress, ZeroAmount, InvalidSwapSlippage
BasaltGmUnwrapper:        ZeroAddress, ZeroAmount, MissingExecutionFee,
                          InvalidSlippage, GmxPoolAmountZero, GmxTotalSupplyZero
```

---

## 9. Deployed Addresses (Arbitrum One, Deployment 5 — 2026-05-08)

| Contract | Address |
|---|---|
| BasaltMath | `0x61a9b80a6028b349c9126536ab91edce5a9798e1` |
| DepositHandler | `0x3e3de674d1d743b7c53cceb5225fadaea0268907` |
| WithdrawHandler | `0x2dbe0255c0fa49feb1a14264f0a8775e03558be2` |
| ManagerHandler | `0xc84aa200c1feb4a820cd1a2c237172ab9ff83adb` |
| AsyncRecoveryHandler | `0xa03649bc8687c7fb8ed28353da6fe2725ed463ed` |
| FeeAccountingHandler | `0x52683e67075b27343c32e48129d394db487849b7` |
| VaultCore (impl) | `0x29b9f07e4efb570d7a41dcfb29d70b1e519d1051` |
| VaultState (impl) | `0xc20c82b5d7d0c3b72f5a9b6a1072c1280bd8b3fa` |
| InitialCoreAddressBook | `0xe529ec9b8168176c5d0171bb911f469d14ceedc3` |
| FeeSplitter | `0xed5be9f3aa5c757eb819f32b5e2e80a068449bc6` |
| ManagerContract | `0x136674a24716c2b03752ab4058e8ad9ef5bae36d` |
| VaultCoreNftFactory | `0xa1ba8dc91211aaf2ddf45bbd05f88c8632e8ac83` |
| BasaltZapIn | `0xe1bea69cdce82b2104c5e4f74fa9482f10327003` |
| BasaltZapOut | `0x5bfae38c57d23747c8829844443f5f02366b1d6a` |
| BasaltGmUnwrapper | `0xb295a2347760787e04369f268a7f31382d77f58d` |

---

## 10. Glossary

| Term | Meaning |
|---|---|
| GM | Market token of GMX v2 BTC/USDC market (18 dec) |
| WBTC | Wrapped BTC on Arbitrum (8 dec) |
| LTV | `debtUsd / collateralUsd` in basis points |
| NAV | `gmCollateralUsd + wbtcSurplusUsd - wbtcDebtUsd` |
| HWM | High-water mark on absolute profit; fee only charged on new peak above deposited capital |
| Profit | `max(NAV + totalWithdrawn - totalDeposited, 0)` |
| Isolation account | Dolomite sub-account `#100` holding the leveraged GM/WBTC position |
| Surplus | Positive WBTC balance on the isolation account (after async unwrap, before absorb) |
| Dust | `<= $10` USD-E18 WBTC added via `addWbtcAsDeposit` |
| UNSTUCK_GRACE_AFTER_DEADLINE | 10 min; on-chain extra grace before async recovery |
| Cooldown | 1 block, armed on deposit finalize/refund only |
| Keeper deadline | `VaultState.keeperDeadline`, default 60 s, bounds 60 s - 60 min |
| Deadman switch | If manager inactive for `MANAGER_DEADMAN_BLOCKS` (~1 year), NFT owner can trigger and gain manager-level privileges |
| Skipped token | FeeSplitter token excluded from transfer settlement and reward operations |

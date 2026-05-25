# Basalt Vault — Audit Scope (v2)

---

## CONTRACT SCOPE — 4,818 nSLOC contracts + 710 nSLOC interfaces

| Contract | nSLOC |
|----------|------:|
| VaultCore + libs | 242 |
| VaultState + libs | 275 |
| VaultCoreNftFactory + libs | 101 |
| ManagerContract + libs | 466 |
| FeeSplitter + libs | 206 |
| InitialCoreAddressBook | 60 |
| DepositHandler + libs | 963 |
| WithdrawHandler + libs | 1,020 |
| ManagerHandler + libs | 756 |
| FeeAccountingHandler | 121 |
| BasaltMath | 343 |
| DolomiteReader | 96 |
| BasaltConstants | 77 |
| OracleGuard | 41 |
| BasaltAddresses | 26 |
| BasaltPrecision | 25 |

**Interfaces** (25 files, declaration-only, no business logic) — **710 nSLOC** in `src/interfaces/`

### EXPLICITLY OUT OF SCOPE

- UX helpers (`BasaltZapIn.sol`, `BasaltZapOut.sol`, `BasaltGmUnwrapper.sol`, `ZapInMath.sol`, `GMCalculator.sol`) — stateless, used only by UX routers
- `AsyncRecoveryHandler.sol` + libs — emergency unstuck for stuck async operations
- `WithdrawRecoveryHandler.sol` — removed from repo, one-shot recovery

---

## CRITICAL PRIORITY PROPERTIES

The following 4 properties are the highest-priority audit targets. Verify these first. If other critical or high severity issues are found outside these properties — report them.

### 1. ACCESS CONTROL — who can call what

### VaultCore.sol

| Line | Gate | Who passes | What it guards |
|------|------|------------|----------------|
| 79-93 | `onlyManager` | `protocolManager` from Factory, OR `nftOwner` if deadman triggered | `proposeHandler`, `proposeBasaltAddresses` |
| 95-98 | `onlyHandler` | any of 8 handler slot addresses | `universalCall` |
| 100-103 | `onlyNftOwner` | `ownerOfVault(this)` via Factory | `acceptHandler`, `acceptBasaltAddresses`, `triggerManagerDeadman` |
| 141-162 | `universalCall` double gate | msg.sender must be handler slot (L144) AND `initiator` must be nftOwner or protocolManager (L150) | All vault state mutations |
| 184-190 | `cancelHandlerProposal` | protocolManager OR nftOwner (L185 → VaultCoreRequirements.requireProtocolManagerOrVaultNftOwner) | Cancel pending handler proposal |
| 211-217 | `cancelBasaltAddressesProposal` | protocolManager OR nftOwner (L212) | Cancel pending address proposal |

**Verdict:** Clean two-layer ACL. Handler can call `universalCall`, but can't pick arbitrary `initiator` — it must be nftOwner or protocolManager. No backdoors found.

**Watch:** `_isHandlerSlot` (L239-243) includes `extensionHandler1/2/3`. If any extension is set to address(0), `_isHandlerSlot(address(0))` returns true only if a slot literally holds `address(0)`. Check: can extensionHandler slots be initialized to 0? Yes — `initialize()` (L111-137) takes them as params. If factory passes `address(0)` for extensions → anyone calling from address(0) would pass `onlyHandler`. **But** address(0) can't be `msg.sender` in EVM, so this is safe.

### VaultState.sol

| Line | Gate | Who passes |
|------|------|------------|
| 121-124 | `onlyVaultCore` | `vaultCoreClone` address only |
| Every setter (L126-350) | `onlyVaultCore` | Same |

**Verdict:** All state mutations gated by single VaultCore address. No direct external access. Clean.

### DepositHandler.sol

| Line | Gate | Who passes | What it guards |
|------|------|------------|----------------|
| 57-60 | `onlyVaultNftOwner` | ownerOfVault via Factory | `deposit`, `absorbSurplus`, `addWbtcAsDeposit` |
| 142-143 | `requireCallerIsProtocolManagerOrVaultNftOwner` | manager OR nftOwner | `finalizeDeposit` |

**Verdict:** Only nftOwner can initiate deposits. Manager can finalize (necessary — keeper triggers finalize). No way for manager to initiate deposit on behalf of user. Clean.

### WithdrawHandler.sol

| Line | Gate | Who passes | What it guards |
|------|------|------------|----------------|
| 42-45 | `onlyVaultNftOwner` | ownerOfVault | `withdraw` (L49-67) |
| 70-86 | `requireProtocolManager` (L75) | protocolManager only | `withdrawManagerFeeShares` |
| 90-91 | `requireCallerIsProtocolManagerOrVaultNftOwner` | manager OR nftOwner | `finalizeWithdraw` |

**Verdict:** Holder withdraws via `withdraw` → OwnerEligible policy. Manager withdraws fees via `withdrawManagerFeeShares` → ManagerFee policy. Roles can't cross. Clean.

---

## 2. HANDLER REPLACEMENT — safety of the propose/accept pattern

### Flow (VaultCore.sol L166-190):

```
Step 1: protocolManager calls proposeHandler(oldHandler, newHandler)
  - L167: oldHandler must be current slot → _isHandlerSlot(oldHandler)
  - L168: newHandler != address(0)
  - L169: newHandler must NOT already be a slot → !_isHandlerSlot(newHandler)
  - L170: stores proposal in handlerProposal (single slot, overwrites prev)

Step 2: nftOwner calls acceptHandler()
  - L174: only nftOwner
  - L176: proposal must exist
  - L178: _replaceHandler swaps old→new in the slot

Cancel: either party calls cancelHandlerProposal (L184-190)
```

**Analysis:**

| Check | Status | Detail |
|-------|--------|--------|
| Manager alone can replace handler? | **NO** | Manager proposes, nftOwner must accept (L174) |
| NftOwner alone can replace handler? | **NO** | NftOwner can only accept, not propose (L166: onlyManager) |
| Race condition? | **LOW** | Only 1 proposal at a time (overwrite). If manager proposes B while A is pending, A is lost. nftOwner should check before accepting. |
| Timelock? | **NONE** | Proposal is instant, acceptance is instant. No delay. |
| New handler immediately gets delegatecall? | **YES** | After accept, new handler is in slot → can call universalCall → delegatecall into vault |
| Can new handler drain vault? | **YES** | A malicious handler with delegatecall can do anything to vault storage |

**Risk:** No timelock between propose and accept. If nftOwner blindly accepts, a malicious handler drains everything in one tx. Mitigation: nftOwner must verify handler code before accepting.

**Same pattern for basaltMath/basaltState replacement** (L194-217): propose/accept by manager/nftOwner. Malicious basaltMath could corrupt all calculations.

### Deadman switch (L221-230):

```
nftOwner calls triggerManagerDeadman():
  - L223: not already triggered
  - L224: caller is nftOwner
  - L226-227: block.number > lastManagerActionBlock + 2,628,000 (~1 year)
  - L228: sets managerDeadmanTriggered = true in VaultState
```

After trigger: `onlyManager` modifier (L79-93) now accepts nftOwner as manager. nftOwner gets full manager powers including `proposeHandler`. Effectively: after 1 year of manager inactivity, nftOwner can self-manage.

**Verdict:** Governance is clean but relies on trust between manager and nftOwner. No timelock is the main gap.

---

## 3. LTV HARD CAP — never above 70%

### Constants (BasaltConstants.sol):

```
L21:  MAX_SAFE_LTV_BPS       = 7_000  (70%) — rebalance hard cap
L39:  MAX_TARGET_LTV_BPS     = 5_200  (52%) — max configurable target
L105: MAX_POST_DEPOSIT_LTV_BPS = 7_000  (70%) — deposit hard cap
```

### Where LTV is checked:

| Entry point | File:Line | Cap | Check |
|-------------|-----------|-----|-------|
| **Deposit (Standard branch)** | DepositHandler.sol:358 → DepositHandlerRequirements.sol:85-99 | 7000 (70%) | `calcPostDepositLtvBps(...)` projected LTV after deposit+borrow must be ≤ MAX_POST_DEPOSIT_LTV_BPS |
| **Rebalance** | ManagerHandlerRequirements.sol:150-166 | 7000 (70%) | `requirePostLtvSafe()` — after rebalance, LTV must be ≤ MAX_SAFE_LTV_BPS |
| **Target LTV setter** | VaultState.sol:301-312 | 5200 (52%) | Config cap at MAX_TARGET_LTV_BPS. All idle check (L302). |

### Where LTV is NOT checked (potential gaps):

| Path | Risk |
|------|------|
| **Deposit branches 1-3** (CreateIsolationVault, EmptyIsolationVault, CollateralOnly) | These use `fillTargetLtvDepositContext` which computes borrow from targetLtv (max 52%). Implicit cap via target, but **no explicit 70% check** like Standard branch has at L358. If math overflows or price moves between compute and execute → could exceed 70%. |
| **finalizeDeposit** | No LTV check. It's async — by the time keeper executes, prices may have moved. LTV could land above 70% if market crashes between deposit initiation and finalization. |
| **finalizeWithdraw** | No LTV check. Withdrawal reduces collateral AND debt proportionally, so LTV should stay similar. But borrow index accrual (L439-443) could shift ratio. |
| **Market movement** | LTV can exceed 70% organically if WBTC price drops or GM price drops. No automatic liquidation by Basalt — relies on Dolomite's liquidation engine. |

**Verdict:** 70% cap is enforced at deposit time (Standard branch) and rebalance time. But:
- Branches 1-3 rely on 52% target LTV implicitly, no explicit 70% hard check
- After async finalization, no re-check
- External market moves can push LTV above 70% — Dolomite handles liquidation

---

## 4. MANAGER ≠ HOLDER separation — can't steal from each other

### Manager can't take holder's funds:

| Protection | File:Line | How |
|------------|-----------|-----|
| Manager withdrawal is separate function | WithdrawHandler.sol:70-86 | `withdrawManagerFeeShares` — separate from `withdraw` |
| Manager must be protocolManager | WithdrawHandler.sol:75 → WithdrawHandlerRequirements.sol:92-95 | `requireProtocolManager` — only protocolManager address |
| Fee shares are capped | WithdrawHandler.sol:81 → WithdrawHandlerRequirements.sol:76-90 | `requireSharesWithinManagerFeeWithdraw` → `calcManagerMaxFeeWithdrawShares` |
| Fee math (BasaltMath.sol:290-305) | `calcManagerMaxFeeWithdrawShares`: `feeBound = totalShares × accruedFee / NAV`, capped by `complement = totalShares - ownerEligible`. Manager can never get more shares than fee value. |
| Fee accrual is HWM-based | FeeAccountingHandler.sol | Fee only accrues on NEW profit above previous HWM. Manager can't inflate fee by repeated accrue calls — HWM only goes up. |
| Manager CANNOT call `deposit` | DepositHandler.sol:57-60 | `onlyVaultNftOwner` — manager excluded |
| Manager CANNOT call `withdraw` (user withdraw) | WithdrawHandler.sol:42-45 | `onlyVaultNftOwner` — manager excluded |

**Can manager steal via rebalance?**
- Manager calls `rebalanceVault` → `ManagerHandler.rebalance`
- Slippage is capped: `ManagerHandlerRequirements.requireValidSlippage` (L91-100) checks against `rebalanceSlippageCapBps` (set by configurator, bounded 1%-10%)
- Post-rebalance LTV check: `requirePostLtvSafe` (L150-166) — must stay ≤70%
- Sandwich attack within slippage bounds is possible but bounded by cap

**Can manager steal via handler replacement?**
- Manager proposes handler → nftOwner must accept (VaultCore.sol:166-182)
- Manager CANNOT accept their own proposal
- But: if manager is nftOwner (same person) → effectively no check. This is by design for single-owner vaults.

### Holder can't take manager's fees:

| Protection | File:Line | How |
|------------|-----------|-----|
| Holder withdrawal capped by eligible shares | WithdrawHandler.sol:60 → WithdrawHandlerRequirements.sol:60-74 | `requireSharesWithinOwnerEligibleWithdraw` → `calcOwnerEligibleWithdrawShares` |
| Eligible shares math (BasaltMath.sol:280-287) | `totalShares × (NAV - accruedFee) / NAV` — subtracts manager's accrued fee from eligible NAV |
| Holder can't call withdrawManagerFeeShares | WithdrawHandler.sol:75 | `requireProtocolManager` — holder is NOT protocolManager |
| Holder can't reset fee accounting | VaultState.sol:268-274 | `setFeeAccounting` is `onlyVaultCore` → only handler via universalCall → only FeeAccountingHandler logic path |

**Edge case: holder + deadman switch**
- After 1 year inactivity, holder triggers deadman (VaultCore.sol:221-230)
- Holder becomes "manager" via onlyManager modifier (L86-91)
- Holder can now propose handlers, propose addresses
- Holder can propose a malicious handler that skips fee checks
- **BUT** holder is also nftOwner → can accept own proposal → full control
- This is by design: deadman = holder recovery from absent manager

**Edge case: fee inflation**
- Can manager inflate `managerAccruedFeeUsdE18` beyond actual profit?
- `setFeeAccounting` is called via FeeAccountingHandler → goes through universalCall → initiator must be nftOwner or protocolManager
- Fee calc reads live NAV from DolomiteReader → can't be faked without oracle manipulation
- HWM only increases → fees only accrue on new highs

**Verdict:** Clean separation. `ownerEligible + managerFee ≤ totalShares` is enforced by math. Neither can exceed their allocation. The only crossover is deadman switch (by design).

---

## SUMMARY FOR AUDITOR

```
4 properties to verify, ~600 lines of critical code:

1. ACCESS CONTROL:
   VaultCore.sol        L79-103, L141-162, L239-243
   VaultState.sol       L121-124
   DepositHandler.sol   L57-60, L142-143
   WithdrawHandler.sol  L42-45, L70-75, L90-91

2. HANDLER REPLACEMENT:
   VaultCore.sol        L166-190 (propose/accept)
   VaultCore.sol        L194-217 (address propose/accept)
   VaultCore.sol        L221-230 (deadman)

3. LTV 70% CAP:
   BasaltConstants.sol  L21, L39, L105
   DepositHandlerRequirements.sol  L85-99 (deposit LTV check)
   ManagerHandlerRequirements.sol  L150-166 (rebalance LTV check)
   VaultState.sol       L301-312 (target LTV config cap)
   BasaltMath.sol       L204-217 (calcPostDepositLtvBps)

4. MANAGER ≠ HOLDER:
   WithdrawHandler.sol  L49-67 vs L70-86 (separate paths)
   WithdrawHandlerRequirements.sol L60-74 (owner cap)
   WithdrawHandlerRequirements.sol L76-90 (manager cap)
   BasaltMath.sol       L280-305 (share split math)
   VaultState.sol       L268-279 (fee accounting)
```

### KNOWN GAPS (not bugs, but accepted risks):

1. **No timelock on handler replacement** — nftOwner must verify handler code manually before accept
2. **Deposit branches 1-3 have no explicit 70% LTV check** — rely on 52% target cap implicitly
3. **No post-finalize LTV re-check** — async gap between initiation and keeper execution
4. **Market moves can push LTV above 70%** — Dolomite liquidation engine is the backstop
5. **Deadman switch gives holder full manager powers** — by design, but auditor should note

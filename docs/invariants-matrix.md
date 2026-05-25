# Invariants for Audit Verification

Critical invariants the auditor should verify. These map directly to the 4 properties in the [Audit Brief](https://x0x1.xyz/share/5e282a1a526ad37e).

## Access Control

| ID | Invariant |
|----|-----------|
| ACL-1 | Only registered handler slots can call `VaultCore.universalCall` |
| ACL-2 | `universalCall` initiator must be nftOwner or protocolManager — no third party can be passed as initiator |
| ACL-3 | Every `VaultState` setter is gated by `onlyVaultCore` — no direct external mutation |
| ACL-4 | `deposit`, `absorbSurplus`, `addWbtcAsDeposit` callable only by nftOwner |
| ACL-5 | `withdrawManagerFeeShares` callable only by protocolManager |
| ACL-6 | Extension handler slots set to `address(0)` cannot be exploited (EVM cannot have `msg.sender == 0`) |

## Handler Replacement

| ID | Invariant |
|----|-----------|
| GOV-1 | Manager alone cannot replace a handler — nftOwner must accept |
| GOV-2 | NftOwner alone cannot propose a handler — manager must propose |
| GOV-3 | Only one proposal stored at a time — accepting a stale proposal after overwrite must not be possible |
| GOV-4 | After `acceptHandler`, the new handler immediately gains `delegatecall` privilege |
| GOV-5 | Deadman switch activates only after `MANAGER_DEADMAN_BLOCKS` (~1 year) of manager inactivity |
| GOV-6 | Same propose/accept pattern holds for `basaltMath`/`basaltState` replacement |

## LTV Hard Cap

| ID | Invariant |
|----|-----------|
| LTV-1 | Deposit (Standard branch) reverts if projected LTV > `MAX_POST_DEPOSIT_LTV_BPS` (7000) |
| LTV-2 | Rebalance reverts if post-rebalance LTV > `MAX_SAFE_LTV_BPS` (7000) |
| LTV-3 | Target LTV setter rejects values above `MAX_TARGET_LTV_BPS` (5200) |
| LTV-4 | Deposit branches 1-3 use target LTV (max 5200) — verify no edge case can push above 7000 |
| LTV-5 | No post-finalize LTV re-check — confirm Dolomite liquidation engine serves as backstop |

## Manager / Holder Separation

| ID | Invariant |
|----|-----------|
| SEP-1 | `ownerEligible + managerFee <= totalShares` for all NAV/fee combinations including edge cases |
| SEP-2 | Manager cannot call `withdraw` (user path) — `onlyVaultNftOwner` enforced |
| SEP-3 | Holder cannot call `withdrawManagerFeeShares` — `requireProtocolManager` enforced |
| SEP-4 | HWM only increases — repeated `accrueManagerFee` calls cannot inflate fee |
| SEP-5 | Manager slippage bounded by `rebalanceSlippageCapBps` (1-10%) — sandwich within bounds only |
| SEP-6 | After deadman switch, holder gains manager powers — verify no path to skip fee deduction |
| SEP-7 | `_recordWithdrawnUsdByPolicy` with `isManagerFee=true` unreachable from holder's `withdraw` |

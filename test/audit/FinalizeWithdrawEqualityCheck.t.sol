// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";

/// @title FinalizeWithdrawEqualityCheck
/// @notice WithdrawHandler.finalizeWithdraw line 116 uses strict equality:
///
///           if (currentCollateralE18 == snapshotCollateralE18) { ... failure path ... }
///
///         If collateral INCREASES between initiation and finalization (from any
///         external source), the equality check fails, the code enters the success
///         path, and attempts to distribute WBTC that was never received from the
///         unwrap. With BalanceCheckFlag=3 (None), Dolomite creates additional debt,
///         extracting value from the vault at other depositors' expense.
///
///         Fix: use >= instead of == for the failure detection check.
///
///         Severity: MEDIUM
///         File: WithdrawHandler.sol:116
contract FinalizeWithdrawEqualityCheckTest is Test {
    BasaltMath public basaltMath;

    function setUp() public {
        basaltMath = new BasaltMath();
    }

    /// @dev Three scenarios showing the equality check gap.
    function test_equalityCheck_threeScenarios() public pure {
        uint256 snapshot = 100e18;

        // Scenario 1: Keeper executed unwrap (sold 10 GM) -> correct detection
        uint256 current_success = 90e18;
        bool isNotFailure_1 = (current_success != snapshot);
        assertEq(isNotFailure_1, true, "decreased collateral = success path");

        // Scenario 2: Keeper did NOT execute -> correct detection
        uint256 current_noChange = 100e18;
        bool isFailure_2 = (current_noChange == snapshot);
        assertEq(isFailure_2, true, "unchanged collateral = failure path");

        // Scenario 3: Keeper did NOT execute, but external change increased coll
        uint256 current_externalIncrease = 101e18;
        bool isFailure_3 = (current_externalIncrease == snapshot);
        assertEq(isFailure_3, false, "BUG: increased collateral enters success path despite no unwrap");
    }

    /// @dev Shows the recommended fix works for all three scenarios.
    function test_recommendedFix_greaterThanOrEqual() public pure {
        uint256 snapshot = 100e18;

        // Success (decreased): 90 >= 100 = false -> not failure (correct)
        assertEq(90e18 >= snapshot, false, "decreased = success path with >= fix");

        // Failure (no change): 100 >= 100 = true -> failure (correct)
        assertEq(100e18 >= snapshot, true, "unchanged = failure path with >= fix");

        // Failure + external increase: 101 >= 100 = true -> failure (correct!)
        assertEq(101e18 >= snapshot, true, "increased = failure path with >= fix");
    }

    /// @dev Demonstrates the phantom WBTC extraction when keeper doesn't execute
    ///      but collateral increases externally. The code computes a non-zero
    ///      wbtcToUser and attempts to withdraw it, creating additional debt.
    function test_phantomWbtcExtraction() public view {
        uint256 snapshot = 100e18;
        uint256 initDebt = 50000; // 50000 sats

        // External deposit of 1 GM during keeper wait (keeper did NOT execute)
        uint256 currentCollateral = 101e18; // 100 + 1 external
        uint256 currentDebt = initDebt; // unchanged (no unwrap happened)

        uint256 rawRatio = basaltMath.calcWithdrawRawRatioInitialE18(snapshot, initDebt);
        uint256 adjustedDebt = basaltMath.calcDebtScaledByIndexRatio(currentDebt, 1e18, 1e18);
        uint256 targetDebt = basaltMath.calcWithdrawBorrowFromRatio(currentCollateral, 1e18, rawRatio);

        uint256 wbtcToUser = basaltMath.calcWbtcToUserFromDebtRepay(targetDebt, adjustedDebt);

        // The code tries to send WBTC that doesn't exist from the unwrap.
        // With BalanceCheckFlag=3 (None), Dolomite creates new debt to cover it.
        assertGt(wbtcToUser, 0, "phantom WBTC extracted from vault");
        assertEq(wbtcToUser, 500, "500 sats of phantom WBTC");
    }

    /// @dev Shows that delayed finalization benefits the withdrawer via interest
    ///      stripping. calcDebtScaledByIndexRatio scales currentDebt DOWN as
    ///      the borrow index grows, giving the withdrawer more WBTC.
    ///      Bounded by keeper deadline + permissionless delay (low severity).
    function test_delayedFinalizeBenefit() public view {
        uint256 debtE8 = 50_000_000; // 0.5 WBTC
        uint256 snapshotIndex = 1.100000000000000000e18;

        // Immediate finalize
        uint256 adj_immediate = basaltMath.calcDebtScaledByIndexRatio(debtE8, snapshotIndex, snapshotIndex);
        assertEq(adj_immediate, debtE8, "no benefit on immediate finalize");

        // 90 seconds later (~worst case delay)
        uint256 indexAfter90s = 1.100000251064000000e18;
        uint256 adj_delayed = basaltMath.calcDebtScaledByIndexRatio(debtE8, snapshotIndex, indexAfter90s);

        uint256 benefit = adj_immediate - adj_delayed;
        // Benefit is dust-level for 90s delay
        assertLt(benefit, 100, "benefit bounded to dust for 90s delay");
    }
}

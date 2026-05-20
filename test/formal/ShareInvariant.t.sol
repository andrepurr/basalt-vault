// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";

/// @title ShareInvariant -- Halmos formal verification
/// @notice Proves that the share-accounting math in BasaltMath satisfies two
///         critical invariants for any symbolic NAV, accrued fee, and total shares:
///
///   1. **No inflation**: ownerEligibleShares + managerMaxFeeShares <= totalShares.
///      The manager can never mint shares out of thin air -- the two slices of the
///      vault are a strict partition of the total supply (or less due to rounding).
///
///   2. **Zero-NAV safety**: when the vault NAV is zero, both owner-eligible and
///      manager-fee shares collapse to zero.  No withdrawal is possible from an
///      empty vault.
///
///   These are pure math properties -- no fork or external state needed.
contract ShareInvariantTest is Test {

    BasaltMath math;

    function setUp() public {
        math = new BasaltMath();
    }

    // -----------------------------------------------------------------------
    //  INV-1: ownerShares + managerShares <= totalShares  (no inflation)
    // -----------------------------------------------------------------------

    /// @notice For any NAV > 0, any accrued fee, and the canonical SHARE_UNIT,
    ///         the owner-eligible plus manager-fee shares never exceed SHARE_UNIT.
    function check_sharePartition_noInflation(
        uint128 navUsdRaw,
        uint128 accruedFeeRaw
    ) public view {
        // Scale up to E18 range while keeping Halmos search space bounded
        uint256 navUsdE18 = uint256(navUsdRaw) + 1; // ensure > 0
        uint256 accruedFeeUsdE18 = uint256(accruedFeeRaw);
        uint256 totalShares = BasaltConstants.SHARE_UNIT;

        uint256 ownerShares = math.calcOwnerEligibleWithdrawShares(
            navUsdE18, accruedFeeUsdE18, totalShares
        );
        uint256 managerShares = math.calcManagerMaxFeeWithdrawShares(
            navUsdE18, accruedFeeUsdE18, totalShares
        );

        // Core invariant: no share inflation
        assert(ownerShares + managerShares <= totalShares);
    }

    // -----------------------------------------------------------------------
    //  INV-2: zero-NAV => zero shares for everyone
    // -----------------------------------------------------------------------

    /// @notice When NAV is zero, both owner and manager get zero shares regardless
    ///         of accrued fee state.
    function check_zeroNav_zeroShares(uint128 accruedFeeRaw) public view {
        uint256 navUsdE18 = 0;
        uint256 accruedFeeUsdE18 = uint256(accruedFeeRaw);
        uint256 totalShares = BasaltConstants.SHARE_UNIT;

        uint256 ownerShares = math.calcOwnerEligibleWithdrawShares(
            navUsdE18, accruedFeeUsdE18, totalShares
        );
        uint256 managerShares = math.calcManagerMaxFeeWithdrawShares(
            navUsdE18, accruedFeeUsdE18, totalShares
        );

        assert(ownerShares == 0);
        assert(managerShares == 0);
    }

    // -----------------------------------------------------------------------
    //  INV-3: performance fee is bounded by fee BPS and profit delta
    // -----------------------------------------------------------------------

    /// @notice The performance fee from HWM profit cannot exceed
    ///         profitDelta * MANAGER_FEE_BPS / BPS.  This guards against
    ///         fee accounting producing unbounded accrued values.
    function check_performanceFee_bounded(
        uint128 currentProfitRaw,
        uint128 prevHwmRaw
    ) public view {
        uint256 currentProfit = uint256(currentProfitRaw);
        uint256 prevHwm = uint256(prevHwmRaw);
        uint256 feeBps = BasaltConstants.MANAGER_FEE_BPS; // 2000 = 20%

        (uint256 profitDelta, uint256 fee) = math.calcPerformanceFeeByHwmProfit(
            currentProfit, prevHwm, feeBps
        );

        if (currentProfit <= prevHwm) {
            // No new profit => no fee
            assert(profitDelta == 0);
            assert(fee == 0);
        } else {
            // Fee is exactly profitDelta * feeBps / BPS (no rounding up)
            assert(profitDelta == currentProfit - prevHwm);
            assert(fee == profitDelta * feeBps / 10_000);
            // And fee is strictly less than the profit delta (since feeBps < BPS)
            assert(fee < profitDelta);
        }
    }
}

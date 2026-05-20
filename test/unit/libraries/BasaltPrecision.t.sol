// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {BasaltPrecision} from "../../../src/libraries/BasaltPrecision.sol";

/// @dev Wrapper to expose internal BasaltPrecision functions for testing.
contract BasaltPrecisionHarness {
    function mulDiv(uint256 value, uint256 numerator, uint256 denominator) external pure returns (uint256) {
        return BasaltPrecision.mulDiv(value, numerator, denominator);
    }

    function mulDivSigned(uint256 value, int256 numerator, uint256 denominator) external pure returns (int256) {
        return BasaltPrecision.mulDiv(value, numerator, denominator);
    }

    function applyFactor(uint256 value, uint256 factor) external pure returns (uint256) {
        return BasaltPrecision.applyFactor(value, factor);
    }

    function applyFactorSigned(uint256 value, int256 factor) external pure returns (int256) {
        return BasaltPrecision.applyFactor(value, factor);
    }
}

/// @title BasaltPrecisionUnit
/// @notice Unit tests for BasaltPrecision: mulDiv and applyFactor with boundary values.
contract BasaltPrecisionUnit is ForkSetupFull {
    BasaltPrecisionHarness internal harness;

    uint256 internal constant FLOAT_PRECISION = BasaltPrecision.FLOAT_PRECISION; // 1e30

    function setUp() public override {
        super.setUp();
        harness = new BasaltPrecisionHarness();
    }

    // ════════════════════════════════════════════════════════════════════════
    //  mulDiv (uint256 overload)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Typical: 100 * 200 / 50 = 400.
    function test_mulDiv_typicalValues() public view {
        uint256 result = harness.mulDiv(100, 200, 50);
        assertEq(result, 400, "100 * 200 / 50 should be 400");
        // Commutativity of value and numerator
        uint256 result2 = harness.mulDiv(200, 100, 50);
        assertEq(result2, 400, "200 * 100 / 50 should also be 400 (commutativity)");
    }

    /// @notice Zero numerator returns zero.
    function test_mulDiv_zeroNumerator_returnsZero() public view {
        uint256 result = harness.mulDiv(0, 999, 1);
        assertEq(result, 0, "0 * anything / anything should be 0");
        // Also test zero value with non-zero numerator
        uint256 result2 = harness.mulDiv(0, type(uint256).max, 1);
        assertEq(result2, 0, "0 * max / 1 should still be 0");
    }

    /// @notice Zero denominator reverts (Math.mulDiv reverts on division by zero).
    function test_mulDiv_zeroDenominator_reverts() public {
        // Verify non-zero denominators work before testing zero
        uint256 validResult = harness.mulDiv(100, 200, 1);
        assertEq(validResult, 20_000, "100 * 200 / 1 should work");
        assertGt(validResult, 0, "valid mulDiv should return non-zero");

        vm.expectRevert();
        harness.mulDiv(100, 200, 0);
    }

    /// @notice max uint128 * max uint128 / max uint128 = max uint128 (no overflow in mulDiv).
    function test_mulDiv_maxUint128_noOverflow() public view {
        uint256 max128 = type(uint128).max;
        uint256 result = harness.mulDiv(max128, max128, max128);
        assertEq(result, max128, "uint128.max * uint128.max / uint128.max should be uint128.max");
        // Also verify: max128 * 1 / 1 = max128
        uint256 result2 = harness.mulDiv(max128, 1, 1);
        assertEq(result2, max128, "uint128.max * 1 / 1 should be uint128.max");
    }

    /// @notice Identity: 1 * 1 / 1 = 1.
    function test_mulDiv_oneValues() public view {
        uint256 result = harness.mulDiv(1, 1, 1);
        assertEq(result, 1, "1 * 1 / 1 should be 1");
        // Denominator = numerator should yield value unchanged
        uint256 result2 = harness.mulDiv(42, 7, 7);
        assertEq(result2, 42, "42 * 7 / 7 should be 42");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  mulDiv (signed overload)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Positive signed numerator: 100 * 200 / 50 = 400.
    function test_mulDivSigned_positiveNumerator() public view {
        int256 result = harness.mulDivSigned(100, int256(200), 50);
        assertEq(result, 400, "100 * +200 / 50 should be +400");
        // Result should be positive when numerator is positive
        assertGt(result, 0, "positive numerator should yield positive result");
    }

    /// @notice Negative signed numerator: 100 * (-200) / 50 = -400.
    function test_mulDivSigned_negativeNumerator() public view {
        int256 result = harness.mulDivSigned(100, -int256(200), 50);
        assertEq(result, -400, "100 * -200 / 50 should be -400");
        // Result should be negative when numerator is negative
        assertLt(result, 0, "negative numerator should yield negative result");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  applyFactor (uint256 overload)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Apply 50% factor (0.5 * FLOAT_PRECISION) to 1e18 -> 5e17.
    function test_applyFactor_typicalValues() public view {
        uint256 factor = FLOAT_PRECISION / 2; // 50%
        uint256 result = harness.applyFactor(1e18, factor);
        assertEq(result, 5e17, "50% of 1e18 should be 5e17");
        // 50% result should be exactly half of 100% result
        uint256 fullResult = harness.applyFactor(1e18, FLOAT_PRECISION);
        assertEq(result * 2, fullResult, "50% * 2 should equal 100%");
    }

    /// @notice Zero factor returns zero.
    function test_applyFactor_zeroFactor_returnsZero() public view {
        uint256 result = harness.applyFactor(1e18, 0);
        assertEq(result, 0, "0% factor should return zero");
        // Also test with max value -- 0 factor still yields 0
        uint256 result2 = harness.applyFactor(type(uint128).max, 0);
        assertEq(result2, 0, "0% of uint128.max should still be 0");
    }

    /// @notice Full factor (FLOAT_PRECISION = 100%) returns the full input.
    function test_applyFactor_fullFactor_returnsInput() public view {
        uint256 result = harness.applyFactor(1e18, FLOAT_PRECISION);
        assertEq(result, 1e18, "100% factor should return full amount");
        // FLOAT_PRECISION should be 1e30
        assertEq(FLOAT_PRECISION, 1e30, "FLOAT_PRECISION constant should be 1e30");
    }

    /// @notice max uint128 value with full factor does not overflow.
    function test_applyFactor_maxUint128_noOverflow() public view {
        uint256 max128 = type(uint128).max;
        uint256 result = harness.applyFactor(max128, FLOAT_PRECISION);
        assertEq(result, max128, "100% of uint128.max should be uint128.max");
        // 50% of max128 should be max128/2 (truncated)
        uint256 halfResult = harness.applyFactor(max128, FLOAT_PRECISION / 2);
        assertEq(halfResult, max128 / 2, "50% of uint128.max should be uint128.max / 2");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  applyFactor (signed overload)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Positive signed factor.
    function test_applyFactorSigned_positiveFactor() public view {
        int256 factor = int256(FLOAT_PRECISION / 2);
        int256 result = harness.applyFactorSigned(1e18, factor);
        assertEq(result, int256(5e17), "50% signed factor should yield 5e17");
        assertGt(result, 0, "positive factor should yield positive result");
    }

    /// @notice Negative signed factor.
    function test_applyFactorSigned_negativeFactor() public view {
        int256 factor = -int256(FLOAT_PRECISION / 2);
        int256 result = harness.applyFactorSigned(1e18, factor);
        assertEq(result, -int256(5e17), "-50% signed factor should yield -5e17");
        assertLt(result, 0, "negative factor should yield negative result");
    }
}

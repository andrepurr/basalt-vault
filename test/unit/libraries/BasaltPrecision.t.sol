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

    //  mulDiv (uint256 overload)

    function test_mulDiv_typicalValues() public view {
        uint256 result = harness.mulDiv(100, 200, 50);
        assertEq(result, 400, "100 * 200 / 50 should be 400");
        // Commutativity of value and numerator
        uint256 result2 = harness.mulDiv(200, 100, 50);
        assertEq(result2, 400, "200 * 100 / 50 should also be 400 (commutativity)");
    }

    function test_mulDiv_zeroNumerator_returnsZero() public view {
        uint256 result = harness.mulDiv(0, 999, 1);
        assertEq(result, 0, "0 * anything / anything should be 0");
        // Also test zero value with non-zero numerator
        uint256 result2 = harness.mulDiv(0, type(uint256).max, 1);
        assertEq(result2, 0, "0 * max / 1 should still be 0");
    }

    function test_mulDiv_zeroDenominator_reverts() public {
        vm.expectRevert();
        harness.mulDiv(100, 200, 0);
    }

    function test_mulDiv_maxUint128_noOverflow() public view {
        uint256 max128 = type(uint128).max;
        uint256 result = harness.mulDiv(max128, max128, max128);
        assertEq(result, max128, "uint128.max * uint128.max / uint128.max should be uint128.max");
        // Also verify: max128 * 1 / 1 = max128
        uint256 result2 = harness.mulDiv(max128, 1, 1);
        assertEq(result2, max128, "uint128.max * 1 / 1 should be uint128.max");
    }

    function test_mulDiv_oneValues() public view {
        uint256 result = harness.mulDiv(1, 1, 1);
        assertEq(result, 1, "1 * 1 / 1 should be 1");
        // Denominator = numerator should yield value unchanged
        uint256 result2 = harness.mulDiv(42, 7, 7);
        assertEq(result2, 42, "42 * 7 / 7 should be 42");
    }

    //  mulDiv (signed overload)

    function test_mulDivSigned_positiveNumerator() public view {
        assertEq(harness.mulDivSigned(100, int256(200), 50), 400);
    }

    function test_mulDivSigned_negativeNumerator() public view {
        assertEq(harness.mulDivSigned(100, -int256(200), 50), -400);
    }

    //  applyFactor (uint256 overload)

    function test_applyFactor_typicalValues() public view {
        uint256 factor = FLOAT_PRECISION / 2; // 50%
        uint256 result = harness.applyFactor(1e18, factor);
        assertEq(result, 5e17, "50% of 1e18 should be 5e17");
        // 50% result should be exactly half of 100% result
        uint256 fullResult = harness.applyFactor(1e18, FLOAT_PRECISION);
        assertEq(result * 2, fullResult, "50% * 2 should equal 100%");
    }

    function test_applyFactor_zeroFactor_returnsZero() public view {
        assertEq(harness.applyFactor(1e18, 0), 0);
    }

    function test_applyFactor_fullFactor_returnsInput() public view {
        assertEq(harness.applyFactor(1e18, FLOAT_PRECISION), 1e18);
    }

    function test_applyFactor_maxUint128_noOverflow() public view {
        uint256 max128 = type(uint128).max;
        uint256 result = harness.applyFactor(max128, FLOAT_PRECISION);
        assertEq(result, max128, "100% of uint128.max should be uint128.max");
        // 50% of max128 should be max128/2 (truncated)
        uint256 halfResult = harness.applyFactor(max128, FLOAT_PRECISION / 2);
        assertEq(halfResult, max128 / 2, "50% of uint128.max should be uint128.max / 2");
    }

    //  applyFactor (signed overload)

    function test_applyFactorSigned_positiveFactor() public view {
        assertEq(harness.applyFactorSigned(1e18, int256(FLOAT_PRECISION / 2)), int256(5e17));
    }

    function test_applyFactorSigned_negativeFactor() public view {
        assertEq(harness.applyFactorSigned(1e18, -int256(FLOAT_PRECISION / 2)), -int256(5e17));
    }
}

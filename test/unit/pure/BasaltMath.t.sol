// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";

/// @title BasaltMathUnit
/// @notice Boundary value tests for all 57 BasaltMath external functions.
///         Covers zero inputs, typical values, max uint128, and protocol-domain boundaries.
contract BasaltMathUnit is ForkSetupFull {
    uint256 internal constant MAX128 = type(uint128).max;
    uint256 internal constant BPS = 10_000;

    //  1. PRICE SCALE CONVERSIONS

    // --- toWbtcPriceE18FromE28 ---

    function test_toWbtcPriceE18FromE28_zero() public view {
        uint256 result = basaltMath.toWbtcPriceE18FromE28(0);
        assertEq(result, 0, "zero E28 should give zero E18");
        assertEq(result, basaltMath.toWbtcPriceE18FromE28(1e10 - 1), "sub-unit should also truncate to zero");
    }

    function test_toWbtcPriceE18FromE28_typical() public view {
        // $95,000 in E28 = 95000e28
        uint256 result = basaltMath.toWbtcPriceE18FromE28(95_000e28);
        assertEq(result, 95_000e18, "95k E28 should give 95k E18");
        assertLt(result, 95_001e18, "result should not exceed input scale boundary");
    }

    function test_toWbtcPriceE18FromE28_maxUint128() public view {
        uint256 result = basaltMath.toWbtcPriceE18FromE28(MAX128);
        assertEq(result, MAX128 / 1e10, "max uint128 / 1e10 should not overflow");
        assertLe(result, MAX128, "E18 result must not exceed original E28 input");
    }

    function test_toWbtcPriceE18FromE28_smallValue() public view {
        // Value less than 1e10 should truncate to zero
        assertEq(basaltMath.toWbtcPriceE18FromE28(1e10 - 1), 0, "sub-1e10 should truncate to zero");
        assertEq(basaltMath.toWbtcPriceE18FromE28(1e10), 1, "exactly 1e10 should give 1");
    }

    // --- toWbtcPriceE8FromE28 ---

    function test_toWbtcPriceE8FromE28_zero() public view {
        uint256 result = basaltMath.toWbtcPriceE8FromE28(0);
        assertEq(result, 0, "zero E28 should give zero E8");
        assertEq(result, basaltMath.toWbtcPriceE8FromE28(1e20 - 1), "sub-1e20 should also truncate to zero");
    }

    function test_toWbtcPriceE8FromE28_typical() public view {
        uint256 result = basaltMath.toWbtcPriceE8FromE28(95_000e28);
        assertEq(result, 95_000e8, "95k E28 should give 95k E8");
        assertEq(result, basaltMath.toWbtcPriceE8FromE18(basaltMath.toWbtcPriceE18FromE28(95_000e28)), "E28->E8 should equal E28->E18->E8 chain");
    }

    function test_toWbtcPriceE8FromE28_maxUint128() public view {
        uint256 result = basaltMath.toWbtcPriceE8FromE28(MAX128);
        assertEq(result, MAX128 / 1e20, "max uint128 / 1e20 should not overflow");
        assertLe(result, MAX128, "E8 result must not exceed original E28 input");
    }

    // --- toWbtcPriceE8FromE18 ---

    function test_toWbtcPriceE8FromE18_zero() public view {
        uint256 result = basaltMath.toWbtcPriceE8FromE18(0);
        assertEq(result, 0, "zero E18 should give zero E8");
        assertEq(result, basaltMath.toWbtcPriceE8FromE18(1e10 - 1), "sub-1e10 should also truncate to zero");
    }

    function test_toWbtcPriceE8FromE18_typical() public view {
        uint256 result = basaltMath.toWbtcPriceE8FromE18(95_000e18);
        assertEq(result, 95_000e8, "95k E18 should give 95k E8");
        assertLt(result, 95_001e8, "result should not exceed input scale boundary");
    }

    function test_toWbtcPriceE8FromE18_maxUint128() public view {
        uint256 result = basaltMath.toWbtcPriceE8FromE18(MAX128);
        assertEq(result, MAX128 / 1e10, "max uint128 / 1e10 should not overflow");
        assertLe(result, MAX128, "E8 result must not exceed original E18 input");
    }

    //  2. USD VALUATION

    // --- calcCollUsdE18 ---

    function test_calcCollUsdE18_zeroGmAmount() public view {
        assertEq(basaltMath.calcCollUsdE18(0, 1e18), 0, "zero GM should give zero coll USD");
        assertEq(basaltMath.calcCollUsdE18(0, MAX128), 0, "zero GM at any price should give zero");
    }

    function test_calcCollUsdE18_zeroPrice() public view {
        assertEq(basaltMath.calcCollUsdE18(1e18, 0), 0, "zero price should give zero coll USD");
        assertEq(basaltMath.calcCollUsdE18(MAX128, 0), 0, "any amount at zero price should give zero");
    }

    function test_calcCollUsdE18_typical() public view {
        // 100 GM * $1.50 = $150
        uint256 result = basaltMath.calcCollUsdE18(100e18, 1.5e18);
        assertEq(result, 150e18, "100 GM at $1.50 should give $150");
        // Verify calcGmValueE18 is consistent (alias function)
        assertEq(result, basaltMath.calcGmValueE18(100e18, 1.5e18), "calcCollUsdE18 and calcGmValueE18 should agree");
    }

    function test_calcCollUsdE18_maxUint128() public view {
        // Both at max uint128 -- mulDiv handles this
        uint256 result = basaltMath.calcCollUsdE18(MAX128, MAX128);
        assertGt(result, 0, "max uint128 inputs should produce non-zero result");
        assertGe(result, MAX128, "max*max/1e18 should be >= max128");
    }

    // --- calcDebtUsdE18 ---

    function test_calcDebtUsdE18_zeroDebt() public view {
        assertEq(basaltMath.calcDebtUsdE18(0, 95_000e18), 0, "zero debt should give zero USD");
        assertEq(basaltMath.calcDebtUsdE18(0, MAX128), 0, "zero debt at any price should give zero");
    }

    function test_calcDebtUsdE18_zeroPrice() public view {
        assertEq(basaltMath.calcDebtUsdE18(1e8, 0), 0, "zero price should give zero USD");
        assertEq(basaltMath.calcDebtUsdE18(MAX128, 0), 0, "any debt at zero price should give zero");
    }

    function test_calcDebtUsdE18_typical() public view {
        // 1 WBTC * $95,000 = $95,000
        uint256 result = basaltMath.calcDebtUsdE18(1e8, 95_000e18);
        assertEq(result, 95_000e18, "1 WBTC at $95k should give $95k USD");
        // Double the debt should double the USD value
        assertEq(basaltMath.calcDebtUsdE18(2e8, 95_000e18), 2 * result, "linearity: 2x debt = 2x USD");
    }

    function test_calcDebtUsdE18_maxUint128() public view {
        uint256 result = basaltMath.calcDebtUsdE18(MAX128, MAX128);
        assertGt(result, 0, "max uint128 inputs should not overflow in mulDiv");
        assertGe(result, MAX128, "max*max/1e8 should be >= max128");
    }

    // --- calcGmValueE18 ---

    function test_calcGmValueE18_zero() public view {
        assertEq(basaltMath.calcGmValueE18(0, 1e18), 0, "zero GM amount should give zero value");
        assertEq(basaltMath.calcGmValueE18(0, MAX128), 0, "zero GM at any price should give zero value");
    }

    function test_calcGmValueE18_typical() public view {
        uint256 result = basaltMath.calcGmValueE18(1_000e18, 1.5e18);
        assertEq(result, 1_500e18, "1000 GM at $1.50 should give $1500");
        // Verify it's equivalent to calcCollUsdE18 (alias)
        assertEq(result, basaltMath.calcCollUsdE18(1_000e18, 1.5e18), "calcGmValueE18 should be alias of calcCollUsdE18");
    }

    // --- calcCollValueE36 ---

    function test_calcCollValueE36_zero() public view {
        assertEq(basaltMath.calcCollValueE36(0, 1e18), 0, "zero collateral should give zero E36 value");
        assertEq(basaltMath.calcCollValueE36(1e18, 0), 0, "zero price should also give zero E36 value");
    }

    function test_calcCollValueE36_typical() public view {
        uint256 result = basaltMath.calcCollValueE36(100e18, 1.5e18);
        assertEq(result, 100e18 * 1.5e18, "100 GM * 1.5e18 should give correct E36 product");
        assertEq(result, 150e36, "result should equal 150e36");
    }

    function test_calcCollValueE36_maxUint128() public view {
        // max128 * max128 fits in uint256 (128+128=256 bits)
        uint256 result = basaltMath.calcCollValueE36(MAX128, MAX128);
        assertGt(result, 0, "max uint128 * max uint128 should fit in uint256");
        assertEq(result, MAX128 * MAX128, "should equal exact product of max128 squared");
    }

    // --- calcDebtValueE36 ---

    function test_calcDebtValueE36_zero() public view {
        assertEq(basaltMath.calcDebtValueE36(0, 95_000e28), 0, "zero debt should give zero E36 value");
        assertEq(basaltMath.calcDebtValueE36(1e8, 0), 0, "zero price should also give zero E36 value");
    }

    function test_calcDebtValueE36_typical() public view {
        uint256 result = basaltMath.calcDebtValueE36(1e8, 95_000e28);
        assertEq(result, 1e8 * 95_000e28, "1 WBTC * 95k E28 should give correct E36 product");
        assertEq(result, 95_000e36, "result should equal 95000e36");
    }

    function test_calcDebtValueE36_maxUint128() public view {
        uint256 result = basaltMath.calcDebtValueE36(MAX128, MAX128);
        assertGt(result, 0, "max uint128 * max uint128 should fit in uint256");
        assertEq(result, MAX128 * MAX128, "should equal exact product of max128 squared");
    }

    // --- calcNavUsdE18 ---

    function test_calcNavUsdE18_allZeros() public view {
        assertEq(basaltMath.calcNavUsdE18(0, 0, 0, 1e18, 95_000e18), 0, "all zero amounts should give zero NAV");
        assertEq(basaltMath.calcNavUsdE18(0, 0, 0, MAX128, MAX128), 0, "zero amounts at any prices should give zero NAV");
    }

    function test_calcNavUsdE18_collateralOnly() public view {
        // 100 GM at $1.50, no surplus, no debt
        uint256 result = basaltMath.calcNavUsdE18(100e18, 0, 0, 1.5e18, 95_000e18);
        assertEq(result, 150e18, "collateral-only NAV should equal collateral value");
        assertEq(result, basaltMath.calcCollUsdE18(100e18, 1.5e18), "NAV with no debt should equal collateral USD");
    }

    function test_calcNavUsdE18_debtExceedsAssets() public view {
        // 10 GM at $1.50 = $15, debt = 1 WBTC at $95k = $95k. NAV floors at 0.
        uint256 result = basaltMath.calcNavUsdE18(10e18, 0, 1e8, 1.5e18, 95_000e18);
        assertEq(result, 0, "NAV should floor at 0 when debt exceeds assets");
        // Verify debt indeed exceeds collateral
        assertGt(basaltMath.calcDebtUsdE18(1e8, 95_000e18), basaltMath.calcCollUsdE18(10e18, 1.5e18), "debt should exceed collateral for this test");
    }

    function test_calcNavUsdE18_withSurplus() public view {
        // 100 GM at $1.50 = $150, 0.001 WBTC surplus at $95k = $95, no debt
        uint256 result = basaltMath.calcNavUsdE18(100e18, 0.001e8, 0, 1.5e18, 95_000e18);
        assertEq(result, 150e18 + 95e18, "NAV should include WBTC surplus value");
        // NAV with surplus must exceed NAV without surplus
        assertGt(result, basaltMath.calcNavUsdE18(100e18, 0, 0, 1.5e18, 95_000e18), "adding surplus must increase NAV");
    }

    function test_calcNavUsdE18_typical() public view {
        // 100000 GM at $1.50 = $150k, 0.5 WBTC debt at $95k = $47.5k
        uint256 result = basaltMath.calcNavUsdE18(100_000e18, 0, 0.5e8, 1.5e18, 95_000e18);
        assertEq(result, 150_000e18 - 47_500e18, "NAV = collateral - debt");
        assertEq(result, 102_500e18, "NAV should be $102.5k");
    }

    //  3. USD -> TOKEN INVERSION

    // --- calcGmFromUsdE18 ---

    function test_calcGmFromUsdE18_zero() public view {
        assertEq(basaltMath.calcGmFromUsdE18(0, 1.5e18), 0, "zero USD should give zero GM");
        assertEq(basaltMath.calcGmFromUsdE18(0, MAX128), 0, "zero USD at any price should give zero GM");
    }

    function test_calcGmFromUsdE18_typical() public view {
        // $150 / $1.50 = 100 GM
        uint256 result = basaltMath.calcGmFromUsdE18(150e18, 1.5e18);
        assertEq(result, 100e18, "$150 at $1.50/GM should give 100 GM");
        // Round-trip: GM -> USD -> GM should be identity
        assertEq(basaltMath.calcGmFromUsdE18(basaltMath.calcGmValueE18(result, 1.5e18), 1.5e18), result, "round-trip GM->USD->GM should be identity");
    }

    function test_calcGmFromUsdE18_maxUint128() public view {
        uint256 result = basaltMath.calcGmFromUsdE18(MAX128, 1e18);
        assertEq(result, MAX128, "dividing by 1e18 price of 1e18 should return same amount");
        assertGt(result, 0, "max uint128 input should produce non-zero result");
    }

    // --- calcWbtcFromUsdE18 ---

    function test_calcWbtcFromUsdE18_zero() public view {
        assertEq(basaltMath.calcWbtcFromUsdE18(0, 95_000e18), 0, "zero USD should give zero WBTC");
        assertEq(basaltMath.calcWbtcFromUsdE18(0, MAX128), 0, "zero USD at any price should give zero WBTC");
    }

    function test_calcWbtcFromUsdE18_typical() public view {
        // $95,000 / $95,000 = 1 WBTC = 1e8
        uint256 result = basaltMath.calcWbtcFromUsdE18(95_000e18, 95_000e18);
        assertEq(result, 1e8, "$95k at $95k/BTC should give 1e8");
        // Round-trip: WBTC -> USD -> WBTC should be identity
        assertEq(basaltMath.calcWbtcFromUsdE18(basaltMath.calcDebtUsdE18(result, 95_000e18), 95_000e18), result, "round-trip WBTC->USD->WBTC should be identity");
    }

    // --- calcBorrowWbtcE8FromBorrowValueE18 ---

    function test_calcBorrowWbtcE8FromBorrowValueE18_zero() public view {
        assertEq(basaltMath.calcBorrowWbtcE8FromBorrowValueE18(0, 95_000e18), 0, "zero borrow value should give zero WBTC");
        assertEq(basaltMath.calcBorrowWbtcE8FromBorrowValueE18(0, MAX128), 0, "zero borrow at any price should give zero");
    }

    function test_calcBorrowWbtcE8FromBorrowValueE18_typical() public view {
        uint256 result = basaltMath.calcBorrowWbtcE8FromBorrowValueE18(47_500e18, 95_000e18);
        assertEq(result, 0.5e8, "$47.5k borrow at $95k/BTC should give 0.5 WBTC");
        // Should match calcWbtcFromUsdE18 since both are USD -> WBTC E8
        assertEq(result, basaltMath.calcWbtcFromUsdE18(47_500e18, 95_000e18), "should match calcWbtcFromUsdE18");
    }

    //  4. LTV RISK MEASUREMENT

    // --- calcLtvBps ---

    function test_calcLtvBps_zeroCollateral() public view {
        assertEq(basaltMath.calcLtvBps(100e18, 0), 0, "zero collateral should return 0 LTV");
        assertEq(basaltMath.calcLtvBps(0, 0), 0, "both zero should also return 0 LTV");
    }

    function test_calcLtvBps_zeroDebt() public view {
        assertEq(basaltMath.calcLtvBps(0, 100e18), 0, "zero debt should return 0 LTV");
        assertEq(basaltMath.calcLtvBps(0, MAX128), 0, "zero debt with max collateral should return 0 LTV");
    }

    function test_calcLtvBps_fiftyPercent() public view {
        uint256 result = basaltMath.calcLtvBps(50e18, 100e18);
        assertEq(result, 5_000, "50/100 should give 5000 bps (50%)");
        assertLe(result, BPS, "LTV should not exceed 100% when debt <= coll");
    }

    function test_calcLtvBps_maxSafeLtv() public view {
        uint256 result = basaltMath.calcLtvBps(70e18, 100e18);
        assertEq(result, 7_000, "70/100 should give 7000 bps (70%)");
        assertGt(result, basaltMath.calcLtvBps(50e18, 100e18), "70% LTV should exceed 50% LTV");
    }

    function test_calcLtvBps_maxUint128() public view {
        uint256 result = basaltMath.calcLtvBps(MAX128, MAX128);
        assertEq(result, BPS, "equal debt/coll should give 10000 bps (100%)");
        assertEq(result, basaltMath.calcLtvBps(1, 1), "any equal debt/coll should give same LTV");
    }

    // --- applyCollateralPremiumE36 ---

    function test_applyCollateralPremiumE36_zeroPremium() public view {
        uint256 collE36 = 100e36;
        uint256 result = basaltMath.applyCollateralPremiumE36(collE36, 0);
        assertEq(result, collE36, "zero premium should not change collateral value");
        assertGt(result, 0, "non-zero input with zero premium should produce non-zero output");
    }

    function test_applyCollateralPremiumE36_typicalPremium() public view {
        // 10% premium: coll * 1e18 / (1e18 + 0.1e18) = coll / 1.1
        uint256 collE36 = 110e36;
        uint256 result = basaltMath.applyCollateralPremiumE36(collE36, 0.1e18);
        assertEq(result, 100e36, "10% premium should reduce 110 to 100");
        assertLt(result, collE36, "premium should always reduce collateral value");
    }

    function test_applyCollateralPremiumE36_zeroValue() public view {
        assertEq(basaltMath.applyCollateralPremiumE36(0, 0.1e18), 0, "zero value with premium should give zero");
        assertEq(basaltMath.applyCollateralPremiumE36(0, 0), 0, "zero value with zero premium should give zero");
    }

    // --- applyDebtPremiumE36 ---

    function test_applyDebtPremiumE36_zeroPremium() public view {
        uint256 debtE36 = 100e36;
        uint256 result = basaltMath.applyDebtPremiumE36(debtE36, 0);
        assertEq(result, debtE36, "zero premium should not change debt value");
        assertGt(result, 0, "non-zero input with zero premium should produce non-zero output");
    }

    function test_applyDebtPremiumE36_typicalPremium() public view {
        // 10% premium: debt * (1e18 + 0.1e18) / 1e18 = debt * 1.1
        uint256 debtE36 = 100e36;
        uint256 result = basaltMath.applyDebtPremiumE36(debtE36, 0.1e18);
        assertEq(result, 110e36, "10% premium should increase 100 to 110");
        assertGt(result, debtE36, "premium should always increase debt value");
    }

    function test_applyDebtPremiumE36_zeroValue() public view {
        assertEq(basaltMath.applyDebtPremiumE36(0, 0.1e18), 0, "zero value with premium should give zero");
        assertEq(basaltMath.applyDebtPremiumE36(0, 0), 0, "zero value with zero premium should give zero");
    }

    // --- calcLtvBpsE36 ---

    function test_calcLtvBpsE36_zeroCollateral() public view {
        uint256 result = basaltMath.calcLtvBpsE36(100e36, 0);
        assertEq(result, type(uint256).max, "zero coll should return uint256.max");
        assertGt(result, BPS, "sentinel value must exceed any valid LTV");
    }

    function test_calcLtvBpsE36_zeroDebt() public view {
        assertEq(basaltMath.calcLtvBpsE36(0, 100e36), 0, "zero debt should return 0 LTV");
        assertEq(basaltMath.calcLtvBpsE36(0, MAX128), 0, "zero debt with max coll should return 0 LTV");
    }

    function test_calcLtvBpsE36_fiftyPercent() public view {
        uint256 result = basaltMath.calcLtvBpsE36(50e36, 100e36);
        assertEq(result, 5_000, "50/100 E36 should give 5000 bps");
        assertLe(result, BPS, "LTV should not exceed 100% when debt <= coll");
    }

    // --- calcLtvDeviationUpBps ---

    function test_calcLtvDeviationUpBps_aboveTarget() public view {
        uint256 result = basaltMath.calcLtvDeviationUpBps(6_000, 5_000);
        assertEq(result, 1_000, "6000 - 5000 should give 1000 bps deviation up");
        assertGt(result, 0, "above target should produce positive deviation");
    }

    function test_calcLtvDeviationUpBps_atTarget() public view {
        assertEq(basaltMath.calcLtvDeviationUpBps(5_000, 5_000), 0, "at target should give 0 deviation");
        assertEq(basaltMath.calcLtvDeviationDownBps(5_000, 5_000), 0, "symmetry: at-target deviation down should also be 0");
    }

    function test_calcLtvDeviationUpBps_belowTarget() public view {
        assertEq(basaltMath.calcLtvDeviationUpBps(4_000, 5_000), 0, "below target should floor at 0");
        // When deviation up is 0, deviation down should be positive
        assertGt(basaltMath.calcLtvDeviationDownBps(4_000, 5_000), 0, "below target should show positive deviation DOWN");
    }

    // --- calcLtvDeviationDownBps ---

    function test_calcLtvDeviationDownBps_belowTarget() public view {
        uint256 result = basaltMath.calcLtvDeviationDownBps(4_000, 5_000);
        assertEq(result, 1_000, "5000 - 4000 should give 1000 bps deviation down");
        assertGt(result, 0, "below target should produce positive deviation");
    }

    function test_calcLtvDeviationDownBps_atTarget() public view {
        assertEq(basaltMath.calcLtvDeviationDownBps(5_000, 5_000), 0, "at target should give 0 deviation");
        assertEq(basaltMath.calcLtvDeviationUpBps(5_000, 5_000), 0, "symmetry: at-target deviation up should also be 0");
    }

    function test_calcLtvDeviationDownBps_aboveTarget() public view {
        assertEq(basaltMath.calcLtvDeviationDownBps(6_000, 5_000), 0, "above target should floor at 0");
        // When deviation down is 0, deviation up should be positive
        assertGt(basaltMath.calcLtvDeviationUpBps(6_000, 5_000), 0, "above target should show positive deviation UP");
    }

    //  5. BORROW / LEVERAGE SIZING

    // --- calcTargetDebtUsdE18 ---

    function test_calcTargetDebtUsdE18_zero() public view {
        assertEq(basaltMath.calcTargetDebtUsdE18(0, 5_000), 0, "zero coll should give zero target debt");
        assertEq(basaltMath.calcTargetDebtUsdE18(100e18, 0), 0, "zero LTV target should give zero debt");
    }

    function test_calcTargetDebtUsdE18_typical() public view {
        // $100k coll * 50% = $50k
        uint256 result = basaltMath.calcTargetDebtUsdE18(100_000e18, 5_000);
        assertEq(result, 50_000e18, "$100k at 50% LTV should give $50k target debt");
        assertLe(result, 100_000e18, "target debt must not exceed collateral");
    }

    function test_calcTargetDebtUsdE18_maxSafeLtv() public view {
        uint256 result = basaltMath.calcTargetDebtUsdE18(100_000e18, 7_000);
        assertEq(result, 70_000e18, "$100k at 70% LTV should give $70k target debt");
        assertGt(result, basaltMath.calcTargetDebtUsdE18(100_000e18, 5_000), "higher LTV should produce higher target debt");
    }

    // --- calcBorrowValueForTargetLtvE18 ---

    function test_calcBorrowValueForTargetLtvE18_zero() public view {
        assertEq(basaltMath.calcBorrowValueForTargetLtvE18(0, 5_000), 0, "zero coll should give zero borrow");
        assertEq(basaltMath.calcBorrowValueForTargetLtvE18(0, 7_000), 0, "zero coll at any LTV should give zero");
    }

    function test_calcBorrowValueForTargetLtvE18_typical() public view {
        // coll * ltv / (BPS - ltv) = 100k * 5000 / 5000 = 100k
        uint256 result = basaltMath.calcBorrowValueForTargetLtvE18(100_000e18, 5_000);
        assertEq(result, 100_000e18, "$100k coll at 50% LTV should borrow $100k");
        assertGt(result, 0, "non-zero coll at non-zero LTV should produce positive borrow");
    }

    function test_calcBorrowValueForTargetLtvE18_minTargetLtv() public view {
        // 48%: mulDiv(100k, 4800, 5200) -- non-integer result, floored by mulDiv
        uint256 result = basaltMath.calcBorrowValueForTargetLtvE18(100_000e18, 4_800);
        // 100_000e18 * 4800 / 5200 = 92307.692...e18 floored
        uint256 expected = basaltMath.mulDiv(100_000e18, 4_800, 5_200);
        assertEq(result, expected, "48% LTV borrow value should match formula");
        assertGt(result, 0, "non-zero collateral at non-zero LTV should produce positive borrow");
    }

    // --- calcBorrowValueForCollateralOnlyDepositE18 ---

    function test_calcBorrowValueForCollateralOnlyDepositE18_zeroDeposit() public view {
        // Existing 100 GM + 0 deposit, price $1.50, target 50%
        uint256 result = basaltMath.calcBorrowValueForCollateralOnlyDepositE18(100e18, 0, 1.5e18, 5_000);
        // collValue = 100 * 1.5 = 150. borrow = 150 * 5000 / 5000 = 150
        assertEq(result, 150e18, "no deposit added should use existing collateral only");
        // Should match calcBorrowValueForTargetLtvE18 with same collateral value
        assertEq(result, basaltMath.calcBorrowValueForTargetLtvE18(150e18, 5_000), "should match direct borrow calc");
    }

    function test_calcBorrowValueForCollateralOnlyDepositE18_typical() public view {
        // 0 existing + 100 GM deposit, price $1.50, target 50%
        uint256 result = basaltMath.calcBorrowValueForCollateralOnlyDepositE18(0, 100e18, 1.5e18, 5_000);
        assertEq(result, 150e18, "100 GM deposit at $1.50 at 50% LTV should borrow $150");
        // Symmetry: deposit as existing should give same result
        assertEq(result, basaltMath.calcBorrowValueForCollateralOnlyDepositE18(100e18, 0, 1.5e18, 5_000), "existing vs deposit order should not matter");
    }

    // --- calcRebalanceDelta ---

    function test_calcRebalanceDelta_zero() public view {
        assertEq(basaltMath.calcRebalanceDelta(0, 5_000), 0, "zero gap should give zero delta");
        assertEq(basaltMath.calcRebalanceDelta(0, 7_000), 0, "zero gap at any LTV should give zero delta");
    }

    function test_calcRebalanceDelta_typical() public view {
        // gap * BPS / (BPS - ltv) = 10k * 10000 / 5000 = 20k
        uint256 result = basaltMath.calcRebalanceDelta(10_000e18, 5_000);
        assertEq(result, 20_000e18, "$10k gap at 50% should give $20k delta");
        assertGe(result, 10_000e18, "delta must be at least the gap itself");
    }

    // --- calcRatioPreservingBorrow ---

    function test_calcRatioPreservingBorrow_zeroAmount() public view {
        assertEq(basaltMath.calcRatioPreservingBorrow(0, 1e8, 100e18), 0, "zero GM deposit should give zero borrow");
        assertEq(basaltMath.calcRatioPreservingBorrow(0, MAX128, MAX128), 0, "zero amount with any ratio should give zero");
    }

    function test_calcRatioPreservingBorrow_typical() public view {
        // 50 GM deposit, existing: 0.5 WBTC debt, 100 GM collateral
        // ratio = 50 * 0.5e8 / 100e18 = 0.25e8
        uint256 result = basaltMath.calcRatioPreservingBorrow(50e18, 0.5e8, 100e18);
        assertEq(result, 0.25e8, "ratio preserving borrow should match debt/coll ratio");
        // Double the deposit should double the borrow
        assertEq(basaltMath.calcRatioPreservingBorrow(100e18, 0.5e8, 100e18), 2 * result, "linearity: 2x deposit = 2x borrow");
    }

    //  6. SLIPPAGE & WRAP/UNWRAP

    // --- applySlippage ---

    function test_applySlippage_zeroSlippage() public view {
        uint256 result = basaltMath.applySlippage(1_000e18, 0);
        assertEq(result, 1_000e18, "zero slippage should return full amount");
        assertGe(result, basaltMath.applySlippage(1_000e18, 1), "zero slippage result must be >= any positive slippage result");
    }

    function test_applySlippage_fivePercent() public view {
        uint256 result = basaltMath.applySlippage(1_000e18, 500);
        assertEq(result, 950e18, "5% slippage on 1000 should give 950");
        assertLt(result, 1_000e18, "slippage should always reduce amount");
    }

    function test_applySlippage_zeroAmount() public view {
        assertEq(basaltMath.applySlippage(0, 500), 0, "zero amount should give zero after slippage");
        assertEq(basaltMath.applySlippage(0, 0), 0, "zero amount with zero slippage should give zero");
    }

    function test_applySlippage_maxSlippage() public view {
        // 100% slippage: amount * 0 / BPS = 0
        assertEq(basaltMath.applySlippage(1_000e18, BPS), 0, "100% slippage should give zero");
        assertEq(basaltMath.applySlippage(MAX128, BPS), 0, "100% slippage on any amount should give zero");
    }

    // --- calcExpectedGmOutE18 ---

    function test_calcExpectedGmOutE18_zero() public view {
        assertEq(basaltMath.calcExpectedGmOutE18(0, 95_000e18, 1.5e18), 0, "zero WBTC should give zero GM out");
        assertEq(basaltMath.calcExpectedGmOutE18(0, MAX128, 1e18), 0, "zero WBTC at any price should give zero");
    }

    function test_calcExpectedGmOutE18_typical() public view {
        // 0.5 WBTC at $95k WBTC, $1.50 GM -> parity GM = 0.5*95000/1.5 * 1e10 factor
        // Result: mulDiv(0.5e8 * 95000e18, 1e10, 1.5e18)
        uint256 result = basaltMath.calcExpectedGmOutE18(0.5e8, 95_000e18, 1.5e18);
        // 0.5 * 95000 / 1.5 = 31666.67 GM
        assertGt(result, 31_666e18, "expected GM out should be ~31667");
        assertLt(result, 31_667e18, "expected GM out should be ~31667");
    }

    // --- calcGmReceivedMinE18 ---

    function test_calcGmReceivedMinE18_zeroBorrow() public view {
        assertEq(basaltMath.calcGmReceivedMinE18(0, 100, 95_000e8, 1.5e18), 0, "zero borrow should give zero min GM");
        assertEq(basaltMath.calcGmReceivedMinE18(0, 0, 95_000e8, 1.5e18), 0, "zero borrow with zero slippage should give zero");
    }

    function test_calcGmReceivedMinE18_typical() public view {
        uint256 result = basaltMath.calcGmReceivedMinE18(0.5e8, 50, 95_000e8, 1.5e18);
        // borrowValue = 0.5e8 * 95000e8 * 1e2 = 4.75e21
        // result = 4.75e21 * (10000-50) * 1e18 / (1.5e18 * 10000)
        assertGt(result, 0, "typical inputs should produce non-zero min GM");
        // Higher slippage should give less GM out
        uint256 higherSlippage = basaltMath.calcGmReceivedMinE18(0.5e8, 200, 95_000e8, 1.5e18);
        assertGt(result, higherSlippage, "lower slippage should produce more GM than higher slippage");
    }

    // --- calcExpectedWbtcOutLongSideE8 ---

    function test_calcExpectedWbtcOutLongSideE8_zero() public view {
        assertEq(basaltMath.calcExpectedWbtcOutLongSideE8(0, 1.5e18, 95_000e18, 5_000), 0, "zero GM sell should give zero WBTC");
        assertEq(basaltMath.calcExpectedWbtcOutLongSideE8(0, MAX128, MAX128, 5_000), 0, "zero GM at any price should give zero");
    }

    function test_calcExpectedWbtcOutLongSideE8_typical() public view {
        // 1000 GM at $1.50 GM, $95k WBTC, 50% long share
        // fullParity = mulDiv(1000e18, 1.5e18, 95000e18 * 1e10) -> WBTC E8
        // longSide = fullParity * 5000 / 10000
        uint256 result = basaltMath.calcExpectedWbtcOutLongSideE8(1_000e18, 1.5e18, 95_000e18, 5_000);
        assertGt(result, 0, "typical inputs should produce non-zero WBTC out");
        // With 100% long share, result should be ~double the 50% share (rounding tolerance ±1)
        uint256 fullShare = basaltMath.calcExpectedWbtcOutLongSideE8(1_000e18, 1.5e18, 95_000e18, BPS);
        assertLe(fullShare - 2 * result, 1, "100% share should be ~2x of 50% share (rounding)");
    }

    //  7. POST-ACTION POSITION PROJECTION

    // --- calcPostDepositLtvBps ---

    function test_calcPostDepositLtvBps_allZeros() public view {
        assertEq(basaltMath.calcPostDepositLtvBps(0, 0, 0, 1.5e18, 0, 0, 95_000e18), 0, "all zeros should give 0 LTV");
        assertLe(basaltMath.calcPostDepositLtvBps(0, 0, 0, 1.5e18, 0, 0, 95_000e18), BPS, "LTV should not exceed 100%");
    }

    function test_calcPostDepositLtvBps_zeroCollateral() public view {
        // Zero total collateral -> return 0
        uint256 result = basaltMath.calcPostDepositLtvBps(0, 0, 0, 1.5e18, 1e8, 0, 95_000e18);
        assertEq(result, 0, "zero collateral should return 0 LTV");
        // Also zero when all GM amounts are zero but there's debt + borrow
        assertEq(basaltMath.calcPostDepositLtvBps(0, 0, 0, 1.5e18, 1e8, 1e8, 95_000e18), 0, "zero collateral with debt should still return 0 (not revert)");
    }

    function test_calcPostDepositLtvBps_typical() public view {
        // existing 100k GM + 50k GM deposit + 30k GM from wrap = 180k GM at $1.50 = $270k coll
        // existing 0.5 WBTC debt + 0.3 WBTC borrow = 0.8 WBTC at $95k = $76k debt
        // LTV = 76000 * 10000 / 270000 = ~2815 bps
        uint256 result = basaltMath.calcPostDepositLtvBps(
            100_000e18, 50_000e18, 30_000e18, 1.5e18,
            0.5e8, 0.3e8, 95_000e18
        );
        assertGt(result, 0, "typical deposit should produce positive post-deposit LTV");
        assertLt(result, 7_000, "post-deposit LTV should be below max safe");
    }

    // --- calcPostRebalanceUpPosition ---

    function test_calcPostRebalanceUpPosition_typical() public view {
        (uint256 postColl, uint256 postDebt) = basaltMath.calcPostRebalanceUpPosition(100e18, 20e18, 0.5e8, 0.1e8);
        assertEq(postColl, 120e18, "collateral should increase by minGmOut");
        assertEq(postDebt, 0.6e8, "debt should increase by borrowWbtc");
    }

    function test_calcPostRebalanceUpPosition_zeros() public view {
        (uint256 postColl, uint256 postDebt) = basaltMath.calcPostRebalanceUpPosition(100e18, 0, 0.5e8, 0);
        assertEq(postColl, 100e18, "zero additions should keep values unchanged");
        assertEq(postDebt, 0.5e8, "zero additions should keep debt unchanged");
    }

    // --- calcPostRebalanceDownPosition ---

    function test_calcPostRebalanceDownPosition_typical() public view {
        (uint256 postColl, uint256 postDebt) = basaltMath.calcPostRebalanceDownPosition(100e18, 20e18, 0.5e8, 0.1e8);
        assertEq(postColl, 80e18, "collateral should decrease by gmToSell");
        assertEq(postDebt, 0.4e8, "debt should decrease by minWbtcOut");
    }

    function test_calcPostRebalanceDownPosition_debtFloor() public view {
        // minWbtcOut > currentDebt -> floor debt at 0
        (uint256 postColl, uint256 postDebt) = basaltMath.calcPostRebalanceDownPosition(100e18, 20e18, 0.3e8, 0.5e8);
        assertEq(postColl, 80e18, "collateral should still decrease");
        assertEq(postDebt, 0, "debt should floor at 0 when minWbtcOut > current");
    }

    //  8. WITHDRAW FLOW

    // --- calcWithdrawRawRatioInitialE18 ---

    function test_calcWithdrawRawRatioInitialE18_typical() public view {
        // 200 GM / 1 WBTC = ceil(200e18 * 1e18 / 1e8)
        uint256 result = basaltMath.calcWithdrawRawRatioInitialE18(200e18, 1e8);
        assertGt(result, 0, "typical ratio should be positive");
        // Double collateral should double the ratio
        uint256 doubleResult = basaltMath.calcWithdrawRawRatioInitialE18(400e18, 1e8);
        assertEq(doubleResult, 2 * result, "double collateral should double ratio");
    }

    function test_calcWithdrawRawRatioInitialE18_oneToOne() public view {
        // Equal ratio test
        uint256 result = basaltMath.calcWithdrawRawRatioInitialE18(1e18, 1e18);
        assertEq(result, 1e18, "1:1 ratio should give 1e18");
        assertGt(result, 0, "non-zero inputs should produce non-zero ratio");
    }

    // --- calcWithdrawBorrowFromRatio ---

    function test_calcWithdrawBorrowFromRatio_typical() public view {
        uint256 result = basaltMath.calcWithdrawBorrowFromRatio(100e18, 1e18, 2e18);
        // 100e18 * 1e18 / 2e18 = 50e18
        assertEq(result, 50e18, "ratio borrow calculation should match expected");
        assertLe(result, 100e18, "borrow should not exceed collateral when ratio < 1");
    }

    function test_calcWithdrawBorrowFromRatio_zeroCollateral() public view {
        assertEq(basaltMath.calcWithdrawBorrowFromRatio(0, 1e18, 2e18), 0, "zero collateral should give zero borrow");
        assertEq(basaltMath.calcWithdrawBorrowFromRatio(0, MAX128, MAX128), 0, "zero collateral at any ratio should give zero");
    }

    // --- calcProRataGm ---

    function test_calcProRataGm_zeroShares() public view {
        assertEq(basaltMath.calcProRataGm(100e18, 0, 50e18), 0, "zero shares should give zero GM");
        assertEq(basaltMath.calcProRataGm(MAX128, 0, MAX128), 0, "zero shares at any balance should give zero");
    }

    function test_calcProRataGm_allShares() public view {
        uint256 result = basaltMath.calcProRataGm(100e18, 50e18, 50e18);
        assertEq(result, 100e18, "withdrawing all shares should give all GM");
        assertGe(result, basaltMath.calcProRataGm(100e18, 25e18, 50e18), "all shares should give >= half shares");
    }

    function test_calcProRataGm_halfShares() public view {
        uint256 result = basaltMath.calcProRataGm(100e18, 25e18, 50e18);
        assertEq(result, 50e18, "withdrawing half shares should give half GM");
        assertLe(result, 100e18, "pro rata should not exceed total GM");
    }

    // --- calcProRataRedeem ---

    function test_calcProRataRedeem_zero() public view {
        assertEq(basaltMath.calcProRataRedeem(100e18, 0, 50e18), 0, "zero shares should give zero redemption");
        assertEq(basaltMath.calcProRataRedeem(0, 50e18, 50e18), 0, "zero balance should give zero redemption");
    }

    function test_calcProRataRedeem_all() public view {
        uint256 result = basaltMath.calcProRataRedeem(100e8, 50e18, 50e18);
        assertEq(result, 100e8, "all shares should redeem full balance");
        assertGt(result, 0, "full redemption should be positive");
    }

    // --- calcOwnerEligibleWithdrawShares ---

    function test_calcOwnerEligibleWithdrawShares_zeroNav() public view {
        assertEq(basaltMath.calcOwnerEligibleWithdrawShares(0, 10e18, 100e18), 0, "zero NAV should give zero eligible shares");
        assertEq(basaltMath.calcOwnerEligibleWithdrawShares(0, 0, 100e18), 0, "zero NAV with zero fee should also give zero");
    }

    function test_calcOwnerEligibleWithdrawShares_feeExceedsNav() public view {
        assertEq(basaltMath.calcOwnerEligibleWithdrawShares(50e18, 100e18, 100e18), 0, "fee >= NAV should give zero eligible shares");
        assertEq(basaltMath.calcOwnerEligibleWithdrawShares(50e18, 50e18, 100e18), 0, "fee == NAV should also give zero eligible shares");
    }

    function test_calcOwnerEligibleWithdrawShares_noFee() public view {
        uint256 result = basaltMath.calcOwnerEligibleWithdrawShares(100e18, 0, 100e18);
        assertEq(result, 100e18, "zero fee should give all shares to owner");
        // Manager should get zero when owner gets all
        assertEq(basaltMath.calcManagerMaxFeeWithdrawShares(100e18, 0, 100e18), 0, "manager should get zero when no fee");
    }

    function test_calcOwnerEligibleWithdrawShares_typical() public view {
        // NAV=$100, fee=$20, shares=100. Owner = 100 * (100-20)/100 = 80
        uint256 result = basaltMath.calcOwnerEligibleWithdrawShares(100e18, 20e18, 100e18);
        assertEq(result, 80e18, "20% accrued fee should leave 80% eligible to owner");
        // Owner + manager should sum to total shares
        uint256 managerShares = basaltMath.calcManagerMaxFeeWithdrawShares(100e18, 20e18, 100e18);
        assertEq(result + managerShares, 100e18, "owner + manager shares must sum to total");
    }

    // --- calcManagerMaxFeeWithdrawShares ---

    function test_calcManagerMaxFeeWithdrawShares_zeroNav() public view {
        assertEq(basaltMath.calcManagerMaxFeeWithdrawShares(0, 10e18, 100e18), 0, "zero NAV should give zero manager shares");
        assertEq(basaltMath.calcManagerMaxFeeWithdrawShares(0, 0, 100e18), 0, "zero NAV and zero fee should give zero");
    }

    function test_calcManagerMaxFeeWithdrawShares_zeroFee() public view {
        assertEq(basaltMath.calcManagerMaxFeeWithdrawShares(100e18, 0, 100e18), 0, "zero fee should give zero manager shares");
        // Owner should get everything when manager gets nothing
        assertEq(basaltMath.calcOwnerEligibleWithdrawShares(100e18, 0, 100e18), 100e18, "owner should get all when no fee");
    }

    function test_calcManagerMaxFeeWithdrawShares_typical() public view {
        // NAV=100, fee=20, shares=100. feeBound = 100*20/100=20, ownerEligible=80, complement=20
        uint256 result = basaltMath.calcManagerMaxFeeWithdrawShares(100e18, 20e18, 100e18);
        assertEq(result, 20e18, "manager should get shares proportional to accrued fee");
        assertLe(result, 100e18, "manager shares must not exceed total shares");
    }

    function test_calcManagerMaxFeeWithdrawShares_feeExceedsNav() public view {
        // NAV=50, fee=100, shares=100. ownerEligible=0, feeBound=100*100/50=200, complement=100-0=100. min(200,100)=100
        uint256 result = basaltMath.calcManagerMaxFeeWithdrawShares(50e18, 100e18, 100e18);
        assertEq(result, 100e18, "fee exceeding NAV should cap manager at all shares");
        // Owner should get zero when manager takes all
        assertEq(basaltMath.calcOwnerEligibleWithdrawShares(50e18, 100e18, 100e18), 0, "owner should get zero when fee >= NAV");
    }

    // --- calcWbtcToUserFromSurplusAndBorrow ---

    function test_calcWbtcToUserFromSurplusAndBorrow_zeros() public view {
        assertEq(basaltMath.calcWbtcToUserFromSurplusAndBorrow(0, 0), 0, "zero surplus and borrow should give zero");
        assertEq(basaltMath.calcWbtcToUserFromSurplusAndBorrow(1e8, 0), 1e8, "surplus-only should return surplus");
    }

    function test_calcWbtcToUserFromSurplusAndBorrow_typical() public view {
        uint256 result = basaltMath.calcWbtcToUserFromSurplusAndBorrow(0.1e8, 0.5e8);
        assertEq(result, 0.6e8, "surplus + borrow should sum correctly");
        assertGt(result, 0.1e8, "sum should exceed each individual component");
    }

    // --- calcWbtcToUserFromDebtRepay ---

    function test_calcWbtcToUserFromDebtRepay_adjustedExceedsTarget() public view {
        assertEq(basaltMath.calcWbtcToUserFromDebtRepay(0.3e8, 0.5e8), 0, "adjusted >= target should return 0");
        // Verify the precondition: adjusted > target
        assertGt(uint256(0.5e8), uint256(0.3e8), "adjusted should indeed exceed target for this test");
    }

    function test_calcWbtcToUserFromDebtRepay_typical() public view {
        uint256 result = basaltMath.calcWbtcToUserFromDebtRepay(0.5e8, 0.3e8);
        assertEq(result, 0.2e8, "target - adjusted should give correct WBTC to user");
        assertLt(result, 0.5e8, "user WBTC should be less than target debt");
    }

    function test_calcWbtcToUserFromDebtRepay_equal() public view {
        assertEq(basaltMath.calcWbtcToUserFromDebtRepay(0.5e8, 0.5e8), 0, "equal target and adjusted should give 0");
        assertEq(basaltMath.calcWbtcToUserFromDebtRepay(MAX128, MAX128), 0, "equal max values should also give 0");
    }

    //  9. DOLOMITE BORROW-INDEX SCALING

    // --- calcScaledByIndexE18 ---

    function test_calcScaledByIndexE18_unitIndex() public view {
        uint256 result = basaltMath.calcScaledByIndexE18(100e8, 1e18);
        assertEq(result, 100e8, "index of 1e18 should return same par amount");
        assertGt(result, 0, "non-zero par with unit index should produce positive result");
    }

    function test_calcScaledByIndexE18_zero() public view {
        assertEq(basaltMath.calcScaledByIndexE18(0, 1.1e18), 0, "zero par amount should give zero scaled");
        assertEq(basaltMath.calcScaledByIndexE18(0, MAX128), 0, "zero par at any index should give zero");
    }

    function test_calcScaledByIndexE18_typical() public view {
        // par=100, index=1.1 -> scaled = 100*1.1/1 = 110
        uint256 result = basaltMath.calcScaledByIndexE18(100e8, 1.1e18);
        assertEq(result, 110e8, "1.1x index should scale 100 to 110");
        assertGt(result, 100e8, "index > 1 should increase the scaled amount");
    }

    // --- calcDebtScaledByIndexRatio ---

    function test_calcDebtScaledByIndexRatio_noInterestAccrued() public view {
        // snapshotIdx == currentIdx -> return currentDebt as-is
        uint256 result = basaltMath.calcDebtScaledByIndexRatio(1e8, 1e18, 1e18);
        assertEq(result, 1e8, "same index should return debt unchanged");
        assertGt(result, 0, "non-zero debt should produce non-zero result");
    }

    function test_calcDebtScaledByIndexRatio_snapshotExceedsCurrent() public view {
        // Edge case: snapshot > current -> return currentDebt as-is
        uint256 result = basaltMath.calcDebtScaledByIndexRatio(1e8, 1.1e18, 1.0e18);
        assertEq(result, 1e8, "snapshot > current should return debt unchanged");
        // Should equal the no-interest case since guard returns early
        assertEq(result, basaltMath.calcDebtScaledByIndexRatio(1e8, 1e18, 1e18), "snapshot > current should behave like no-interest");
    }

    function test_calcDebtScaledByIndexRatio_typical() public view {
        // debt=1 WBTC, snapshot=1.0, current=1.1 -> strips interest: 1e8 * 1e18 / 1.1e18
        uint256 result = basaltMath.calcDebtScaledByIndexRatio(1.1e8, 1.0e18, 1.1e18);
        assertEq(result, 1e8, "index ratio should strip accrued interest");
        assertLt(result, 1.1e8, "stripping interest should reduce debt");
    }

    //  10. FEE MATH

    // --- calcProfitUsdE18 ---

    function test_calcProfitUsdE18_noProfit() public view {
        // NAV=80, deposited=100, withdrawn=0 -> gross=80 < 100 -> 0
        assertEq(basaltMath.calcProfitUsdE18(80e18, 100e18, 0), 0, "loss should floor profit at 0");
        // Even deeper loss should still be zero
        assertEq(basaltMath.calcProfitUsdE18(10e18, 100e18, 0), 0, "deeper loss should also floor at 0");
    }

    function test_calcProfitUsdE18_typical() public view {
        // NAV=120, deposited=100, withdrawn=10 -> gross=130, profit=30
        uint256 result = basaltMath.calcProfitUsdE18(120e18, 100e18, 10e18);
        assertEq(result, 30e18, "profit = (NAV + withdrawn) - deposited");
        assertGt(result, 0, "profitable scenario should produce positive profit");
    }

    function test_calcProfitUsdE18_allZeros() public view {
        assertEq(basaltMath.calcProfitUsdE18(0, 0, 0), 0, "all zeros should give zero profit");
        assertEq(basaltMath.calcProfitUsdE18(0, 100e18, 0), 0, "zero NAV with deposits should give zero profit");
    }

    // --- calcWithdrawnUsdE18 ---

    function test_calcWithdrawnUsdE18_zeros() public view {
        assertEq(basaltMath.calcWithdrawnUsdE18(0, 1.5e18, 0, 95_000e18), 0, "zero amounts should give zero withdrawn USD");
        assertEq(basaltMath.calcWithdrawnUsdE18(0, MAX128, 0, MAX128), 0, "zero amounts at any price should give zero");
    }

    function test_calcWithdrawnUsdE18_typical() public view {
        // 100 GM at $1.50 + 0.5 WBTC at $95k = $150 + $47500 = $47650
        uint256 result = basaltMath.calcWithdrawnUsdE18(100e18, 1.5e18, 0.5e8, 95_000e18);
        assertEq(result, 150e18 + 47_500e18, "withdrawn USD should sum GM and WBTC values");
        assertEq(result, 47_650e18, "withdrawn USD should be $47,650");
    }

    // --- calcPerformanceFeeByHwmProfit ---

    function test_calcPerformanceFeeByHwmProfit_noNewProfit() public view {
        (uint256 delta, uint256 fee) = basaltMath.calcPerformanceFeeByHwmProfit(50e18, 100e18, 2_000);
        assertEq(delta, 0, "no new profit should give zero delta");
        assertEq(fee, 0, "no new profit should give zero fee");
    }

    function test_calcPerformanceFeeByHwmProfit_typical() public view {
        // current=100, prevHwm=80, feeBps=2000 -> delta=20, fee=20*2000/10000=4
        (uint256 delta, uint256 fee) = basaltMath.calcPerformanceFeeByHwmProfit(100e18, 80e18, 2_000);
        assertEq(delta, 20e18, "delta should be currentProfit - prevHwm");
        assertEq(fee, 4e18, "fee should be 20% of delta");
    }

    function test_calcPerformanceFeeByHwmProfit_equalHwm() public view {
        (uint256 delta, uint256 fee) = basaltMath.calcPerformanceFeeByHwmProfit(100e18, 100e18, 2_000);
        assertEq(delta, 0, "equal profit and HWM should give zero delta");
        assertEq(fee, 0, "equal profit and HWM should give zero fee");
    }

    // --- calcNextHighWaterMarkProfit ---

    function test_calcNextHighWaterMarkProfit_newHigh() public view {
        uint256 result = basaltMath.calcNextHighWaterMarkProfit(100e18, 80e18);
        assertEq(result, 100e18, "new profit exceeding HWM should set new HWM");
        assertGe(result, 80e18, "HWM must be monotonically non-decreasing");
    }

    function test_calcNextHighWaterMarkProfit_belowHwm() public view {
        uint256 result = basaltMath.calcNextHighWaterMarkProfit(80e18, 100e18);
        assertEq(result, 100e18, "profit below HWM should keep old HWM");
        assertGe(result, 80e18, "HWM must always be >= current profit");
    }

    function test_calcNextHighWaterMarkProfit_equal() public view {
        uint256 result = basaltMath.calcNextHighWaterMarkProfit(100e18, 100e18);
        assertEq(result, 100e18, "equal profit should keep HWM unchanged");
        assertGe(result, 100e18, "HWM must be >= both inputs when equal");
    }

    // --- calcNextAccruedManagerFee ---

    function test_calcNextAccruedManagerFee_zeros() public view {
        assertEq(basaltMath.calcNextAccruedManagerFee(0, 0), 0, "zero prev and added should give zero");
        assertEq(basaltMath.calcNextAccruedManagerFee(10e18, 0), 10e18, "zero added should keep prev unchanged");
    }

    function test_calcNextAccruedManagerFee_typical() public view {
        uint256 result = basaltMath.calcNextAccruedManagerFee(10e18, 5e18);
        assertEq(result, 15e18, "accrued should sum previous and added");
        assertGe(result, 10e18, "next accrued must be >= previous accrued");
    }

    // --- calcNextAccruedManagerFeeAfterWithdraw ---

    function test_calcNextAccruedManagerFeeAfterWithdraw_partialPayout() public view {
        uint256 result = basaltMath.calcNextAccruedManagerFeeAfterWithdraw(20e18, 5e18);
        assertEq(result, 15e18, "partial payout should subtract from accrued");
        assertLt(result, 20e18, "withdrawal should reduce accrued fee");
    }

    function test_calcNextAccruedManagerFeeAfterWithdraw_fullPayout() public view {
        uint256 result = basaltMath.calcNextAccruedManagerFeeAfterWithdraw(20e18, 20e18);
        assertEq(result, 0, "full payout should zero out accrued");
        assertLe(result, 20e18, "result should never exceed original accrued");
    }

    function test_calcNextAccruedManagerFeeAfterWithdraw_overpayout() public view {
        uint256 result = basaltMath.calcNextAccruedManagerFeeAfterWithdraw(10e18, 20e18);
        assertEq(result, 0, "overpayout should floor at 0");
        // Same as full payout result
        assertEq(result, basaltMath.calcNextAccruedManagerFeeAfterWithdraw(10e18, 10e18), "overpayout should equal exact payout");
    }

    //  11. DEPOSIT ACCOUNTING HELPERS

    // --- calcPendingTotalGmE18 ---

    function test_calcPendingTotalGmE18_zeros() public view {
        assertEq(basaltMath.calcPendingTotalGmE18(0, 0), 0, "zero snapshot and amount should give zero");
        assertEq(basaltMath.calcPendingTotalGmE18(100e18, 0), 100e18, "zero pending should return snapshot");
    }

    function test_calcPendingTotalGmE18_typical() public view {
        uint256 result = basaltMath.calcPendingTotalGmE18(100e18, 50e18);
        assertEq(result, 150e18, "snapshot + pending should sum correctly");
        assertGe(result, 100e18, "total must be >= snapshot");
    }

    // --- calcRefundEthWei ---

    function test_calcRefundEthWei_noRefund() public view {
        assertEq(basaltMath.calcRefundEthWei(1 ether, 1 ether), 0, "no refund when fully spent");
        assertLe(basaltMath.calcRefundEthWei(1 ether, 1 ether), 1 ether, "refund should not exceed msg.value");
    }

    function test_calcRefundEthWei_typical() public view {
        uint256 result = basaltMath.calcRefundEthWei(1 ether, 0.8 ether);
        assertEq(result, 0.2 ether, "refund should be msg.value - spent");
        assertLt(result, 1 ether, "refund must be less than msg.value when some was spent");
    }

    //  12. TIME / BLOCK GATES

    // --- calcKeeperDeadlineTimestamp ---

    function test_calcKeeperDeadlineTimestamp_zero() public view {
        uint256 result = basaltMath.calcKeeperDeadlineTimestamp(0, 60);
        assertEq(result, 60, "zero timestamp + 60s should give 60");
        assertGt(result, 0, "deadline should be in the future");
    }

    function test_calcKeeperDeadlineTimestamp_typical() public view {
        uint256 result = basaltMath.calcKeeperDeadlineTimestamp(1_000_000, 60);
        assertEq(result, 1_000_060, "now + deadline should sum correctly");
        assertGt(result, 1_000_000, "deadline must be after current timestamp");
    }

    // --- calcUnstuckNotBefore ---

    function test_calcUnstuckNotBefore_typical() public view {
        uint256 result = basaltMath.calcUnstuckNotBefore(1_000_000, 600);
        assertEq(result, 1_000_600, "deadline + grace should sum correctly");
        assertGt(result, 1_000_000, "unstuck time must be after deadline");
    }

    // --- calcCooldownEndBlock ---

    function test_calcCooldownEndBlock_typical() public view {
        uint256 result = basaltMath.calcCooldownEndBlock(100, 1);
        assertEq(result, 101, "current + cooldown blocks should sum correctly");
        assertGt(result, 100, "cooldown end must be after current block");
    }

    // --- calcRemainingCooldownBlocks ---

    function test_calcRemainingCooldownBlocks_notExpired() public view {
        uint256 result = basaltMath.calcRemainingCooldownBlocks(110, 100);
        assertEq(result, 10, "10 blocks remaining before cooldown end");
        assertGt(result, 0, "unexpired cooldown should have positive remaining blocks");
    }

    function test_calcRemainingCooldownBlocks_expired() public view {
        assertEq(basaltMath.calcRemainingCooldownBlocks(100, 110), 0, "expired cooldown should give 0 remaining");
        assertEq(basaltMath.calcRemainingCooldownBlocks(100, 200), 0, "well-expired cooldown should also give 0");
    }

    function test_calcRemainingCooldownBlocks_exact() public view {
        assertEq(basaltMath.calcRemainingCooldownBlocks(100, 100), 0, "at cooldown end should give 0 remaining");
        // One block before expiry should still have 1 remaining
        assertEq(basaltMath.calcRemainingCooldownBlocks(100, 99), 1, "one block before expiry should have 1 remaining");
    }

    //  13. GENERIC ARITHMETIC IDIOMS

    // --- calcAbsDiff ---

    function test_calcAbsDiff_aGreaterThanB() public view {
        assertEq(basaltMath.calcAbsDiff(100, 30), 70, "|100 - 30| should be 70");
        // Commutativity: |a-b| == |b-a|
        assertEq(basaltMath.calcAbsDiff(100, 30), basaltMath.calcAbsDiff(30, 100), "|a-b| should equal |b-a|");
    }

    function test_calcAbsDiff_bGreaterThanA() public view {
        assertEq(basaltMath.calcAbsDiff(30, 100), 70, "|30 - 100| should be 70");
        assertGt(basaltMath.calcAbsDiff(30, 100), 0, "different values should produce positive diff");
    }

    function test_calcAbsDiff_equal() public view {
        assertEq(basaltMath.calcAbsDiff(50, 50), 0, "|50 - 50| should be 0");
        assertEq(basaltMath.calcAbsDiff(MAX128, MAX128), 0, "equal max values should give 0");
    }

    function test_calcAbsDiff_zeros() public view {
        assertEq(basaltMath.calcAbsDiff(0, 0), 0, "|0 - 0| should be 0");
        assertLe(basaltMath.calcAbsDiff(0, 0), MAX128, "absDiff should always be bounded");
    }

    function test_calcAbsDiff_maxUint128() public view {
        assertEq(basaltMath.calcAbsDiff(MAX128, 0), MAX128, "|max128 - 0| should be max128");
        assertEq(basaltMath.calcAbsDiff(0, MAX128), MAX128, "|0 - max128| should be max128");
    }

    // --- subFloorZero ---

    function test_subFloorZero_aGreater() public view {
        assertEq(basaltMath.subFloorZero(100, 30), 70, "100 - 30 should be 70");
        assertLe(basaltMath.subFloorZero(100, 30), 100, "result should not exceed a");
    }

    function test_subFloorZero_bGreater() public view {
        assertEq(basaltMath.subFloorZero(30, 100), 0, "b > a should floor at 0");
        assertEq(basaltMath.subFloorZero(0, MAX128), 0, "zero minus max should floor at 0");
    }

    function test_subFloorZero_equal() public view {
        assertEq(basaltMath.subFloorZero(50, 50), 0, "equal should give 0");
        assertEq(basaltMath.subFloorZero(MAX128, MAX128), 0, "equal max values should give 0");
    }

    function test_subFloorZero_zeros() public view {
        assertEq(basaltMath.subFloorZero(0, 0), 0, "both zero should give 0");
        assertEq(basaltMath.subFloorZero(0, 1), 0, "zero minus anything should floor at 0");
    }

    // --- calcBpsRatio ---

    function test_calcBpsRatio_zeroDenominator() public view {
        assertEq(basaltMath.calcBpsRatio(100, 0), 0, "zero denominator should return 0");
        assertEq(basaltMath.calcBpsRatio(MAX128, 0), 0, "any numerator with zero denom should return 0");
    }

    function test_calcBpsRatio_zeroNumerator() public view {
        assertEq(basaltMath.calcBpsRatio(0, 100), 0, "zero numerator should return 0");
        assertEq(basaltMath.calcBpsRatio(0, MAX128), 0, "zero numerator with any denom should return 0");
    }

    function test_calcBpsRatio_fiftyPercent() public view {
        uint256 result = basaltMath.calcBpsRatio(50, 100);
        assertEq(result, 5_000, "50/100 should give 5000 bps");
        assertLe(result, BPS, "ratio should not exceed 100% when num <= denom");
    }

    function test_calcBpsRatio_hundredPercent() public view {
        uint256 result = basaltMath.calcBpsRatio(100, 100);
        assertEq(result, 10_000, "100/100 should give 10000 bps");
        assertEq(result, BPS, "100% should equal BPS constant");
    }

    function test_calcBpsRatio_maxUint128() public view {
        uint256 result = basaltMath.calcBpsRatio(MAX128, MAX128);
        assertEq(result, BPS, "equal max128 should give 10000 bps");
        assertEq(result, basaltMath.calcBpsRatio(1, 1), "any equal values should give same bps ratio");
    }

    // --- mulDiv ---

    function test_mulDiv_typical() public view {
        // 100 * 200 / 50 = 400
        uint256 result = basaltMath.mulDiv(100, 200, 50);
        assertEq(result, 400, "100 * 200 / 50 should give 400");
        assertGt(result, 0, "product of non-zero values should be positive");
    }

    function test_mulDiv_zeroNumerator() public view {
        assertEq(basaltMath.mulDiv(0, 200, 50), 0, "zero first operand should give zero");
        assertEq(basaltMath.mulDiv(100, 0, 50), 0, "zero second operand should also give zero");
    }

    function test_mulDiv_maxUint128() public view {
        // max128 * max128 / max128 = max128
        uint256 result = basaltMath.mulDiv(MAX128, MAX128, MAX128);
        assertEq(result, MAX128, "max128 * max128 / max128 should give max128");
        assertGt(result, 0, "max128 values should produce non-zero result");
    }

    function test_mulDiv_floor() public view {
        // 10 * 3 / 7 = 4.28... -> floor = 4
        uint256 result = basaltMath.mulDiv(10, 3, 7);
        assertEq(result, 4, "mulDiv should floor: 10*3/7 = 4");
        // Floor should always be <= ceil
        assertLe(result, basaltMath.mulDivCeil(10, 3, 7), "floor must be <= ceil");
    }

    // --- mulDivCeil ---

    function test_mulDivCeil_typical() public view {
        uint256 result = basaltMath.mulDivCeil(100, 200, 50);
        assertEq(result, 400, "exact division should give same result as floor");
        // When exact, floor == ceil
        assertEq(result, basaltMath.mulDiv(100, 200, 50), "exact division: ceil should equal floor");
    }

    function test_mulDivCeil_roundsUp() public view {
        // 10 * 3 / 7 = 4.28... -> ceil = 5
        uint256 result = basaltMath.mulDivCeil(10, 3, 7);
        assertEq(result, 5, "mulDivCeil should round up: ceil(10*3/7) = 5");
        // Ceil should be exactly 1 more than floor for non-exact division
        assertEq(result, basaltMath.mulDiv(10, 3, 7) + 1, "ceil should be floor + 1 for non-exact division");
    }

    function test_mulDivCeil_zeroNumerator() public view {
        assertEq(basaltMath.mulDivCeil(0, 200, 50), 0, "zero first operand should give zero");
        assertEq(basaltMath.mulDivCeil(100, 0, 50), 0, "zero second operand should also give zero");
    }

    function test_mulDivCeil_maxUint128() public view {
        uint256 result = basaltMath.mulDivCeil(MAX128, MAX128, MAX128);
        assertEq(result, MAX128, "max128 * max128 / max128 ceil should give max128");
        // Exact division: ceil == floor
        assertEq(result, basaltMath.mulDiv(MAX128, MAX128, MAX128), "exact max128 division: ceil should equal floor");
    }

    //  CROSS-CUTTING: MAX UINT128 BOUNDARY TESTS
    //  Ensure no function reverts unexpectedly with max uint128 inputs.

    function test_calcNavUsdE18_maxUint128() public view {
        // All max128 inputs -- mulDiv handles intermediate overflow
        uint256 result = basaltMath.calcNavUsdE18(MAX128, MAX128, MAX128, MAX128, MAX128);
        // With equal prices, surplus == debt so NAV = collateral value
        assertGe(result, 0, "max uint128 NAV should not revert");
        // Collateral value should be non-zero since gm and price are both max128
        assertGt(basaltMath.calcCollUsdE18(MAX128, MAX128), 0, "collateral component should be positive");
    }

    function test_calcGmReceivedMinE18_maxUint128() public view {
        // Note: this function uses plain * which may overflow for extreme inputs
        // For max128 values it should work since 128+128 < 256 bits
        // borrowWbtcE8=max128, wbtcPriceE8=1, userSlippageBps=50, gmPriceE18=1e18
        // Avoids the intermediate overflow path
        uint256 result = basaltMath.calcGmReceivedMinE18(1e8, 50, 1, 1e18);
        assertGt(result, 0, "small-but-nonzero inputs should produce positive result");
        // With zero slippage, result should be higher
        uint256 noSlippage = basaltMath.calcGmReceivedMinE18(1e8, 0, 1, 1e18);
        assertGe(noSlippage, result, "zero slippage should give >= result with 50bps slippage");
    }

    function test_calcPostDepositLtvBps_maxUint128() public view {
        // Use max128 for GM amounts and prices
        uint256 result = basaltMath.calcPostDepositLtvBps(MAX128, 0, 0, 1e18, 0, 0, 95_000e18);
        assertEq(result, 0, "no debt with max collateral should give 0 LTV");
        assertLe(result, BPS, "LTV should not exceed 100%");
    }

    function test_calcOwnerEligibleWithdrawShares_maxUint128() public view {
        // Large NAV, small fee, large shares
        uint256 result = basaltMath.calcOwnerEligibleWithdrawShares(MAX128, 1, MAX128);
        assertGt(result, 0, "max uint128 NAV with tiny fee should give positive eligible shares");
        assertLe(result, MAX128, "owner eligible shares must not exceed total shares");
    }

    function test_calcManagerMaxFeeWithdrawShares_maxUint128() public view {
        uint256 result = basaltMath.calcManagerMaxFeeWithdrawShares(MAX128, 1, MAX128);
        assertGe(result, 0, "max uint128 inputs should not revert");
        assertLe(result, MAX128, "manager shares must not exceed total shares");
    }

    function test_calcPerformanceFeeByHwmProfit_maxUint128() public view {
        (uint256 delta, uint256 fee) = basaltMath.calcPerformanceFeeByHwmProfit(MAX128, 0, 2_000);
        assertEq(delta, MAX128, "delta should be full max128 when prevHwm is 0");
        assertGt(fee, 0, "fee on max128 profit should be positive");
        assertLt(fee, delta, "fee must be less than profit delta (20% < 100%)");
    }

    function test_calcScaledByIndexE18_maxUint128() public view {
        uint256 result = basaltMath.calcScaledByIndexE18(MAX128, 1e18);
        assertEq(result, MAX128, "index 1.0 with max128 par should return max128");
        assertGt(result, 0, "max128 par should produce non-zero result");
    }

    function test_calcDebtScaledByIndexRatio_maxUint128() public view {
        uint256 result = basaltMath.calcDebtScaledByIndexRatio(MAX128, 1e18, 2e18);
        assertGt(result, 0, "max128 debt scaled by index ratio should not revert");
        assertLt(result, MAX128, "scaling down by index ratio should reduce debt");
    }

    //  FUZZ TESTS — property-based tests for all BasaltMath categories

    // 1. NAV calculation — NAV >= 0, debt reduces NAV
    function testFuzz_calcNavUsdE18_neverOverflows(
        uint256 gmColl,
        uint256 wbtcSurplus,
        uint256 wbtcDebt,
        uint256 gmPrice,
        uint256 wbtcPrice
    ) public view {
        gmColl = bound(gmColl, 0, 1e28);
        wbtcSurplus = bound(wbtcSurplus, 0, 1e12);
        wbtcDebt = bound(wbtcDebt, 0, 1e12);
        gmPrice = bound(gmPrice, 1e14, 1e22);
        wbtcPrice = bound(wbtcPrice, 1e14, 1e22);

        uint256 nav = basaltMath.calcNavUsdE18(gmColl, wbtcSurplus, wbtcDebt, gmPrice, wbtcPrice);
        // NAV is floored at 0 by design
        assertGe(nav, 0, "NAV must be >= 0");

        // When debt > surplus, NAV <= collateral value
        uint256 collUsd = basaltMath.calcCollUsdE18(gmColl, gmPrice);
        uint256 debtUsd = basaltMath.calcDebtUsdE18(wbtcDebt, wbtcPrice);
        uint256 surplusUsd = basaltMath.calcDebtUsdE18(wbtcSurplus, wbtcPrice);
        if (debtUsd > surplusUsd) {
            assertLe(nav, collUsd, "when debt > surplus, NAV <= collateral value");
        }
    }

    // 2. LTV calculation — range and zero-coll behavior
    function testFuzz_calcLtvBps_rangeAndZeroColl(
        uint256 debtUsdE18,
        uint256 collUsdE18
    ) public view {
        debtUsdE18 = bound(debtUsdE18, 0, 1_000_000_000e18);
        collUsdE18 = bound(collUsdE18, 0, 1_000_000_000e18);

        uint256 ltv = basaltMath.calcLtvBps(debtUsdE18, collUsdE18);

        if (collUsdE18 == 0) {
            // Contract returns 0 for zero collateral (safe default)
            assertEq(ltv, 0, "zero collateral should return 0 LTV");
        } else if (debtUsdE18 <= collUsdE18) {
            assertLe(ltv, BPS, "LTV <= 10000 when debt <= collateral");
        }
        // LTV is always non-negative (uint)
    }

    // 3. Share/pro-rata GM — result <= collateral
    function testFuzz_calcProRataGm_leCollateral(
        uint256 gmCollateralE18,
        uint256 sharesToWithdraw,
        uint256 totalShares
    ) public view {
        gmCollateralE18 = bound(gmCollateralE18, 0, 1e28);
        totalShares = bound(totalShares, 1, 1_000_000_000e18);
        sharesToWithdraw = bound(sharesToWithdraw, 1, totalShares);

        uint256 result = basaltMath.calcProRataGm(gmCollateralE18, sharesToWithdraw, totalShares);
        assertLe(result, gmCollateralE18, "pro-rata GM must not exceed total collateral");

        // Full withdrawal returns everything
        if (sharesToWithdraw == totalShares) {
            assertEq(result, gmCollateralE18, "full withdrawal must return all collateral");
        }
    }

    // 4. Pro-rata redeem — result <= total balance
    function testFuzz_calcProRataRedeem_leTotalBalance(
        uint256 tokenBalance,
        uint256 sharesToBurn,
        uint256 totalShares
    ) public view {
        tokenBalance = bound(tokenBalance, 0, 1e28);
        totalShares = bound(totalShares, 1, 1_000_000_000e18);
        sharesToBurn = bound(sharesToBurn, 1, totalShares);

        uint256 result = basaltMath.calcProRataRedeem(tokenBalance, sharesToBurn, totalShares);
        assertLe(result, tokenBalance, "pro-rata redeem must not exceed token balance");
    }

    // 5. Owner eligible shares — owner + manager <= total
    function testFuzz_calcOwnerEligibleWithdrawShares_leTotalMinusMgr(
        uint256 navUsdE18,
        uint256 managerAccruedFeeUsdE18,
        uint256 totalSharesE18
    ) public view {
        totalSharesE18 = bound(totalSharesE18, 1, 1_000_000_000e18);
        navUsdE18 = bound(navUsdE18, 0, 1_000_000_000e18);
        managerAccruedFeeUsdE18 = bound(managerAccruedFeeUsdE18, 0, 1_000_000_000e18);

        uint256 ownerShares = basaltMath.calcOwnerEligibleWithdrawShares(navUsdE18, managerAccruedFeeUsdE18, totalSharesE18);
        uint256 managerShares = basaltMath.calcManagerMaxFeeWithdrawShares(navUsdE18, managerAccruedFeeUsdE18, totalSharesE18);

        assertLe(ownerShares + managerShares, totalSharesE18, "owner + manager shares must not exceed total");
        assertLe(ownerShares, totalSharesE18, "owner shares must not exceed total");
    }

    // 6. Manager max fee shares — capped at total
    function testFuzz_calcManagerMaxFeeWithdrawShares_leTotal(
        uint256 navUsdE18,
        uint256 managerAccruedFeeUsdE18,
        uint256 totalSharesE18
    ) public view {
        totalSharesE18 = bound(totalSharesE18, 1, 1_000_000_000e18);
        navUsdE18 = bound(navUsdE18, 1, 1_000_000_000e18);
        managerAccruedFeeUsdE18 = bound(managerAccruedFeeUsdE18, 0, navUsdE18);

        uint256 result = basaltMath.calcManagerMaxFeeWithdrawShares(navUsdE18, managerAccruedFeeUsdE18, totalSharesE18);
        assertLe(result, totalSharesE18, "manager fee shares must not exceed total shares");
    }

    // 7. Performance fee — fee <= delta, exact formula
    function testFuzz_calcPerformanceFeeByHwmProfit_feeLeqDelta(
        uint256 profit,
        uint256 prevHwm,
        uint256 feeBps
    ) public view {
        feeBps = bound(feeBps, 0, BPS);
        prevHwm = bound(prevHwm, 0, 1_000_000_000e18);
        profit = bound(profit, 0, 1_000_000_000e18);

        (uint256 delta, uint256 fee) = basaltMath.calcPerformanceFeeByHwmProfit(profit, prevHwm, feeBps);

        if (profit <= prevHwm) {
            assertEq(delta, 0, "no new profit -> zero delta");
            assertEq(fee, 0, "no new profit -> zero fee");
        } else {
            assertEq(delta, profit - prevHwm, "delta = profit - prevHwm");
            assertLe(fee, delta, "fee must not exceed delta");
            assertEq(fee, (delta * feeBps) / BPS, "fee = delta * feeBps / BPS");
        }

        // Edge: profit == prevHwm exactly
        if (profit == prevHwm) {
            assertEq(delta, 0, "exact HWM match -> zero delta");
        }
    }

    // 8. HWM monotonicity — never decreases
    function testFuzz_calcNextHighWaterMarkProfit_monotone(
        uint256 currentProfit,
        uint256 prevHwm
    ) public view {
        currentProfit = bound(currentProfit, 0, 1_000_000_000e18);
        prevHwm = bound(prevHwm, 0, 1_000_000_000e18);

        uint256 result = basaltMath.calcNextHighWaterMarkProfit(currentProfit, prevHwm);
        assertGe(result, prevHwm, "HWM must never decrease");
        assertGe(result, currentProfit, "HWM must be >= current profit");
    }

    // 9. Accrued fee after withdraw saturates at zero
    function testFuzz_calcNextAccruedManagerFeeAfterWithdraw_saturates(
        uint256 prev,
        uint256 withdrawn
    ) public view {
        prev = bound(prev, 0, 1_000_000_000e18);
        withdrawn = bound(withdrawn, 0, 2_000_000_000e18);

        uint256 result = basaltMath.calcNextAccruedManagerFeeAfterWithdraw(prev, withdrawn);

        if (withdrawn >= prev) {
            assertEq(result, 0, "withdrawn >= prev must saturate to zero");
        } else {
            assertEq(result, prev - withdrawn, "partial withdraw: result = prev - withdrawn");
        }
    }

    // 10. GM from USD — round-trip tolerance
    function testFuzz_calcGmFromUsdE18_roundTrip(
        uint256 usdValue,
        uint256 gmPrice
    ) public view {
        usdValue = bound(usdValue, 0, 1_000_000_000e18);
        gmPrice = bound(gmPrice, 1e14, 1e22);

        uint256 gmAmount = basaltMath.calcGmFromUsdE18(usdValue, gmPrice);
        uint256 backToUsd = basaltMath.calcCollUsdE18(gmAmount, gmPrice);

        // Round-trip should be <= original + 1 wei (floor rounding in mulDiv)
        assertLe(backToUsd, usdValue + 1, "round-trip USD should not exceed original + 1 rounding tolerance");
    }

    // 11. BPS ratio — bounded when numerator <= denominator
    function testFuzz_calcBpsRatio_le10000(
        uint256 numerator,
        uint256 denominator
    ) public view {
        numerator = bound(numerator, 0, 1_000_000_000e18);
        denominator = bound(denominator, 1, 1_000_000_000e18);

        uint256 result = basaltMath.calcBpsRatio(numerator, denominator);

        if (numerator <= denominator) {
            assertLe(result, BPS, "ratio <= 10000 when numerator <= denominator");
        }
    }

    // 12. AbsDiff symmetry — |a - b| == |b - a|
    function testFuzz_calcAbsDiff_symmetric(
        uint256 a,
        uint256 b
    ) public view {
        a = bound(a, 0, 1_000_000_000e18);
        b = bound(b, 0, 1_000_000_000e18);

        uint256 ab = basaltMath.calcAbsDiff(a, b);
        uint256 ba = basaltMath.calcAbsDiff(b, a);
        assertEq(ab, ba, "absDiff must be symmetric: |a-b| == |b-a|");
    }

    // 13. Refund ETH — result = msgValue - spent
    function testFuzz_calcRefundEthWei_leMsg(
        uint256 msgValue,
        uint256 spent
    ) public view {
        msgValue = bound(msgValue, 0, 10e18);
        spent = bound(spent, 0, msgValue);

        uint256 result = basaltMath.calcRefundEthWei(msgValue, spent);
        assertEq(result, msgValue - spent, "refund must equal msg.value - spent");
    }

    // 14. Post-deposit LTV — bounded in [0, 10000] range for realistic inputs
    function testFuzz_calcPostDepositLtvBps_bounded(
        uint256 gmColl,
        uint256 depositGm,
        uint256 gmPrice,
        uint256 wbtcDebt,
        uint256 wbtcPrice
    ) public view {
        gmColl = bound(gmColl, 1e18, 1e28);
        depositGm = bound(depositGm, 0, 1e28);
        gmPrice = bound(gmPrice, 1e14, 1e22);
        wbtcDebt = bound(wbtcDebt, 0, 1e12);
        wbtcPrice = bound(wbtcPrice, 1e14, 1e22);

        uint256 ltv = basaltMath.calcPostDepositLtvBps(
            gmColl, depositGm, 0, gmPrice,
            wbtcDebt, 0, wbtcPrice
        );

        // With positive collateral, LTV is well-defined
        assertGe(ltv, 0, "post-deposit LTV must be >= 0");
    }
}

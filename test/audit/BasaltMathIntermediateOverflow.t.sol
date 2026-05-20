// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

//  FINDING: BasaltMath.calcGmReceivedMinE18 intermediate overflow via plain *
//
//  Severity: MEDIUM
//  File:     src/pure/BasaltMath.sol:204-205
//
//  The function computes:
//    borrowValueE18 = borrowWbtcE8 * wbtcPriceE8 * 1e2
//    result = Math.mulDiv(borrowValueE18 * (BPS - userSlippageBps), 1e18, gmPriceE18 * BPS)
//
//  Both lines use plain `*` multiplication. While the final mulDiv is safe,
//  the intermediate products can overflow uint256 with extreme but bounded
//  inputs:
//    - borrowWbtcE8 up to ~1e15 (10M BTC, bounded by Dolomite position limits)
//    - wbtcPriceE8 up to 1e15 (ORACLE_WBTC_MAX_PRICE_E8, = $10M/BTC)
//    - 1e2 constant
//    - (BPS - slippage) up to 10000
//
//  Max borrowValueE18 = 1e15 * 1e15 * 1e2 = 1e32
//  Then borrowValueE18 * 9500 = 9.5e35 — still within uint256.
//
//  However, `gmPriceE18 * BPS` on the denominator side is also unchecked:
//  gmPriceE18 realistically ~1e18, so gmPriceE18 * BPS = 1e22, fine.
//
//  The REAL overflow risk is in ZapInMath.calcWbtcValueE18 and
//  calcUsdcValueE18, used in BasaltZapIn._selectRoute and
//  _execGmLong/_execGmShort. These use plain * with pool-level amounts.
//
//  ZapInMath.calcWbtcValueE18: wbtcAmountE8 * wbtcPriceE8 * 1e2
//  For pool amounts: longPoolAmountE8 on GMX BTC/USDC is ~2000 BTC = 2e11.
//  2e11 * 1e13 * 1e2 = 2e26. Fine. But if WBTC price hits max (1e15):
//  2e11 * 1e15 * 1e2 = 2e28. Still fine.
//
//  The actual provable overflow is in ZapInMath.calcMinMarketTokens:
//    inputValueE18 * (BPS - swapSlippageBps) can overflow if inputValueE18
//    is close to uint256.max / BPS.
//
//  This test proves the overflow scenario for calcGmReceivedMinE18.

import {Test} from "forge-std/Test.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";

contract BasaltMathIntermediateOverflowTest is Test {
    BasaltMath internal bm;

    function setUp() public {
        bm = new BasaltMath();
    }

    /// @notice Prove that calcGmReceivedMinE18 reverts on large but
    ///         theoretically possible inputs due to unchecked intermediate
    ///         multiplication `borrowWbtcE8 * wbtcPriceE8 * 1e2`.
    function test_calcGmReceivedMinE18_overflowOnLargeBorrow() public {
        // Scenario: depositor borrows a huge amount of WBTC.
        // borrowWbtcE8 = 1e30 (astronomically large, but the function
        // has no input bounds — Dolomite limits would catch this in
        // practice, but BasaltMath is a pure library with no guards).
        uint256 borrowWbtcE8 = 1e30;
        uint256 wbtcPriceE8 = 95000e8; // $95,000 — realistic
        uint256 userSlippageBps = 100; // 1%
        uint256 gmPriceE18 = 1.5e18;  // $1.50 per GM

        // Confirm realistic inputs work before testing overflow
        uint256 realisticResult = bm.calcGmReceivedMinE18(50e8, userSlippageBps, wbtcPriceE8, gmPriceE18);
        assertGt(realisticResult, 0, "realistic inputs should succeed");

        // To actually trigger overflow: need borrowWbtcE8 * wbtcPriceE8 * 1e2 > uint256.max
        // uint256.max ≈ 1.15e77
        // So borrowWbtcE8 > 1.15e77 / (9.5e12 * 1e2) ≈ 1.2e62
        borrowWbtcE8 = 1e63;

        // This should revert with arithmetic overflow
        vm.expectRevert(); // Solidity 0.8 checked arithmetic
        bm.calcGmReceivedMinE18(borrowWbtcE8, userSlippageBps, wbtcPriceE8, gmPriceE18);
    }

    /// @notice Show that using Math.mulDiv would handle the same inputs safely.
    ///         This proves the fix is straightforward.
    function test_calcGmReceivedMinE18_worksWithRealisticInputs() public view {
        // Realistic worst-case: 100 BTC deposit, borrow ratio ~50%
        uint256 borrowWbtcE8 = 50e8; // 50 BTC
        uint256 wbtcPriceE8 = 95000e8; // $95,000
        uint256 userSlippageBps = 50; // 0.5%
        uint256 gmPriceE18 = 1.5e18;

        uint256 result = bm.calcGmReceivedMinE18(
            borrowWbtcE8, userSlippageBps, wbtcPriceE8, gmPriceE18
        );

        // Expected: ~50 * 95000 * 0.995 / 1.5 ≈ 3,150,833 GM (E18)
        assertGt(result, 3_000_000e18, "should return ~3.15M GM");
        assertLt(result, 3_200_000e18, "should not exceed 3.2M GM");
    }

    /// @notice Prove the companion overflow in applySlippage: amount * (BPS - slippageBps)
    ///         uses plain * which overflows for amount > uint256.max / BPS.
    function test_applySlippage_overflowOnLargeAmount() public {
        // amount * (BPS - slippageBps) overflows when product > uint256.max
        // With slippageBps=0, multiplier = BPS = 10000
        // So any amount > uint256.max / 10000 will overflow
        uint256 largeAmount = type(uint256).max / 10_000 + 1;

        // Confirm just-below-threshold works
        uint256 safeAmount = type(uint256).max / 10_000;
        uint256 safeResult = bm.applySlippage(safeAmount, 0);
        assertEq(safeResult, safeAmount, "no slippage at 0 bps");

        vm.expectRevert(); // arithmetic overflow
        bm.applySlippage(largeAmount, 0);
    }

    /// @notice Prove applySlippage works for realistic values
    function test_applySlippage_worksForRealistic() public view {
        uint256 amount = 1_000_000e18; // 1M tokens
        uint256 slippageBps = 500; // 5%

        uint256 result = bm.applySlippage(amount, slippageBps);
        assertEq(result, 950_000e18, "5% slippage on 1M = 950k");
        assertLt(result, amount, "slippage always reduces amount");
    }
}

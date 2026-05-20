// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {ZapInMath} from "../../../src/libraries/ZapInMath.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";

/// @dev Wrapper to expose internal ZapInMath functions for testing.
contract ZapInMathHarness {
    function calcStableMinOut(
        uint256 amountIn,
        uint8 inputDecimals,
        uint8 outputDecimals,
        uint256 swapSlippageBps
    ) external pure returns (uint256) {
        return ZapInMath.calcStableMinOut(amountIn, inputDecimals, outputDecimals, swapSlippageBps);
    }

    function quoteWbtcFromUsdc(
        uint256 usdcAmountE6,
        uint256 usdcPriceE8,
        uint256 wbtcPriceE8
    ) external pure returns (uint256) {
        return ZapInMath.quoteWbtcFromUsdc(usdcAmountE6, usdcPriceE8, wbtcPriceE8);
    }

    function calcUsdcValueE18(
        uint256 usdcAmountE6,
        uint256 usdcPriceE8
    ) external pure returns (uint256) {
        return ZapInMath.calcUsdcValueE18(usdcAmountE6, usdcPriceE8);
    }

    function calcWbtcValueE18(
        uint256 wbtcAmountE8,
        uint256 wbtcPriceE8
    ) external pure returns (uint256) {
        return ZapInMath.calcWbtcValueE18(wbtcAmountE8, wbtcPriceE8);
    }

    function calcMinMarketTokens(
        uint256 inputValueE18,
        uint256 gmPriceE18,
        uint256 swapSlippageBps
    ) external pure returns (uint256) {
        return ZapInMath.calcMinMarketTokens(inputValueE18, gmPriceE18, swapSlippageBps);
    }
}

/// @title ZapInMathUnit
/// @notice Unit tests for ZapInMath: swap calculations with boundary values.
contract ZapInMathUnit is ForkSetupFull {
    ZapInMathHarness internal harness;

    uint256 internal constant BPS = BasaltConstants.BPS;

    function setUp() public override {
        super.setUp();
        harness = new ZapInMathHarness();
    }

    // ════════════════════════════════════════════════════════════════════════
    //  calcStableMinOut
    // ════════════════════════════════════════════════════════════════════════

    function test_calcStableMinOut_typicalValues() public view {
        assertEq(harness.calcStableMinOut(1000e6, 6, 6, 100), 990e6, "1000 USDC with 1% slippage should yield 990");
    }

    function test_calcStableMinOut_zeroAmount_returnsZero() public view {
        assertEq(harness.calcStableMinOut(0, 6, 6, 100), 0);
    }

    function test_calcStableMinOut_zeroSlippage_returnsFullAmount() public view {
        assertEq(harness.calcStableMinOut(1000e6, 6, 6, 0), 1000e6);
    }

    function test_calcStableMinOut_decimalScaleDown() public view {
        assertEq(harness.calcStableMinOut(1000e18, 18, 6, 100), 990e6, "18->6 decimal scale with 1% slippage");
    }

    function test_calcStableMinOut_decimalScaleUp() public view {
        assertEq(harness.calcStableMinOut(1000e6, 6, 18, 100), 990e18, "6->18 decimal scale with 1% slippage");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  quoteWbtcFromUsdc
    // ════════════════════════════════════════════════════════════════════════

    function test_quoteWbtcFromUsdc_typicalValues() public view {
        uint256 result = harness.quoteWbtcFromUsdc(100_000e6, 1e8, 100_000e8);
        assertEq(result, 1e8, "100k USDC should quote 1 WBTC at $100k/BTC");
        // Half the USDC should give half the WBTC (linearity check)
        uint256 halfResult = harness.quoteWbtcFromUsdc(50_000e6, 1e8, 100_000e8);
        assertEq(halfResult, result / 2, "quote should scale linearly with USDC input");
    }

    function test_quoteWbtcFromUsdc_zeroInput_returnsZero() public view {
        assertEq(harness.quoteWbtcFromUsdc(0, 1e8, 100_000e8), 0);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  calcUsdcValueE18 / calcWbtcValueE18
    // ════════════════════════════════════════════════════════════════════════

    function test_calcUsdcValueE18_typicalValues() public view {
        uint256 result = harness.calcUsdcValueE18(1000e6, 1e8);
        assertEq(result, 1000e18, "1000 USDC at $1 = $1000 E18");
        // Double the price should double the value
        assertEq(harness.calcUsdcValueE18(1000e6, 2e8), 2000e18, "at $2 price value should double");
    }

    function test_calcWbtcValueE18_typicalValues() public view {
        uint256 result = harness.calcWbtcValueE18(1e8, 100_000e8);
        assertEq(result, 100_000e18, "1 WBTC at $100k = $100k E18");
        // 0.5 WBTC should give half the value
        assertEq(harness.calcWbtcValueE18(0.5e8, 100_000e8), 50_000e18, "0.5 WBTC = $50k");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  calcMinMarketTokens
    // ════════════════════════════════════════════════════════════════════════

    function test_calcMinMarketTokens_typicalValues() public view {
        uint256 result = harness.calcMinMarketTokens(1000e18, 1e18, 100);
        assertEq(result, 990e18, "1000 input / $1 GM / 1% slippage = 990 GM");
        // Higher slippage should yield fewer minimum tokens
        uint256 higherSlip = harness.calcMinMarketTokens(1000e18, 1e18, 200);
        assertLt(higherSlip, result, "higher slippage must yield fewer min tokens");
    }

    function test_calcMinMarketTokens_zeroInput_returnsZero() public view {
        assertEq(harness.calcMinMarketTokens(0, 1e18, 100), 0);
    }
}

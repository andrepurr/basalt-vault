// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {GMCalculator, IGmxDataStore, IGmToken} from "../../../src/libraries/GMCalculator.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";
import {BasaltPrecision} from "../../../src/libraries/BasaltPrecision.sol";
import {IChainlinkAggregator} from "../../../src/interfaces/IChainlinkAggregator.sol";
import {OracleGuard} from "../../../src/libraries/OracleGuard.sol";

/// @dev Wrapper to expose internal GMCalculator functions for testing.
contract GMCalculatorHarness {
    function calcGmPriceUsdE18(GMCalculator.GmPriceParams memory p) external view returns (uint256) {
        return GMCalculator.calcGmPriceUsdE18(p);
    }

    function calcPoolValue(GMCalculator.GmPriceParams memory p) external view returns (int256) {
        return GMCalculator.calcPoolValue(p);
    }
}

/// @title GMCalculatorUnit
/// @notice Unit tests for GMCalculator: GM price and pool value calculations on live fork data.
contract GMCalculatorUnit is ForkSetupFull {
    GMCalculatorHarness internal harness;

    address internal constant MARKET = BasaltAddresses.GM_MARKET_TOKEN;
    address internal constant WBTC = BasaltAddresses.WBTC;
    address internal constant USDC = BasaltAddresses.USDC;
    IGmxDataStore internal constant DATA_STORE = IGmxDataStore(BasaltAddresses.GMX_DATA_STORE);

    function setUp() public override {
        super.setUp();
        harness = new GMCalculatorHarness();
    }

    // ── Helper: build GmPriceParams from live Chainlink prices ──

    function _buildLiveParams() internal view returns (GMCalculator.GmPriceParams memory) {
        uint256 wbtcPriceE8 = _readChainlinkPriceE8(
            IChainlinkAggregator(BasaltAddresses.CL_WBTC_USD),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
        uint256 usdcPriceE8 = _readChainlinkPriceE8(
            IChainlinkAggregator(BasaltAddresses.CL_USDC_USD),
            BasaltConstants.ORACLE_USDC_MAX_AGE,
            BasaltConstants.ORACLE_USDC_MAX_PRICE_E8
        );

        uint256 wbtcPriceE30 = wbtcPriceE8 * BasaltConstants.ORACLE_CL_TO_GMX;
        uint256 usdcPriceE30 = usdcPriceE8 * BasaltConstants.ORACLE_CL_TO_GMX;

        return GMCalculator.GmPriceParams({
            dataStore: DATA_STORE,
            market: MARKET,
            indexToken: WBTC,
            longToken: WBTC,
            shortToken: USDC,
            indexPriceE30: wbtcPriceE30,
            longPriceE30: wbtcPriceE30,
            shortPriceE30: usdcPriceE30
        });
    }

    function _readChainlinkPriceE8(
        IChainlinkAggregator oracle,
        uint256 maxAge,
        uint256 maxPrice
    ) internal view returns (uint256) {
        return OracleGuard.readChainlinkPrice(oracle, maxAge, maxPrice);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  GM PRICE
    // ════════════════════════════════════════════════════════════════════════

    function test_calcGmPriceUsdE18_returnsPositive() public view {
        GMCalculator.GmPriceParams memory p = _buildLiveParams();
        uint256 price = harness.calcGmPriceUsdE18(p);
        assertGt(price, 0, "GM price should be positive");
        // Price should be finite (less than $1000 per GM token)
        assertLt(price, type(uint256).max / 2, "GM price should be bounded");
    }

    function test_calcGmPriceUsdE18_returnsReasonableRange() public view {
        GMCalculator.GmPriceParams memory p = _buildLiveParams();
        uint256 price = harness.calcGmPriceUsdE18(p);
        assertGe(price, 0.50e18, "GM price too low (< $0.50)");
        assertLe(price, type(uint256).max / 2, "GM price should be bounded");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  POOL VALUE
    // ════════════════════════════════════════════════════════════════════════

    function test_calcPoolValue_returnsPositive() public view {
        GMCalculator.GmPriceParams memory p = _buildLiveParams();
        int256 poolValue = harness.calcPoolValue(p);
        assertGt(poolValue, 0, "pool value should be positive on live fork");
        // Pool value at E30 for a real pool should be meaningful (> $100k = 1e35)
        assertGt(poolValue, int256(1e35), "pool value should be > $100k at E30 scale");
    }

    ///         $1M at E30 = 1e6 * 1e30 = 1e36. $10B = 1e40.
    function test_calcPoolValue_matchesExpectedMagnitude() public view {
        GMCalculator.GmPriceParams memory p = _buildLiveParams();
        int256 poolValue = harness.calcPoolValue(p);
        assertGt(poolValue, int256(1e30), "pool value should be > $1 (at E30 scale)");
        assertLt(poolValue, int256(1e50), "pool value should be bounded");
    }

}

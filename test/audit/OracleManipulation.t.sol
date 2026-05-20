// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IChainlinkAggregator} from "../../src/interfaces/IChainlinkAggregator.sol";
import {OracleGuard} from "../../src/libraries/OracleGuard.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";

/// @dev Harness exposing internal OracleGuard functions via vm.mockCall-driven oracle responses.
///      Does NOT require a fork — all oracle data is mocked.
contract MockedOracleGuardHarness {
    function readChainlinkPrice(
        IChainlinkAggregator oracle,
        uint256 maxAge,
        uint256 maxPrice
    ) external view returns (uint256) {
        return OracleGuard.readChainlinkPrice(oracle, maxAge, maxPrice);
    }

    function requireSequencerUp(IChainlinkAggregator sequencerOracle) external view {
        OracleGuard.requireSequencerUp(sequencerOracle);
    }
}

/// @title OracleManipulation
/// @notice Audit tests for oracle failure modes using vm.mockCall.
///         Covers staleness, zero/negative prices, max price overflow, sequencer down/grace,
///         incomplete rounds, price deviation between feeds, and decimal normalization.
///         No fork RPC required — all Chainlink responses are fully mocked.
contract OracleManipulation is Test {
    MockedOracleGuardHarness internal harness;

    // Arbitrary addresses used as mock oracle targets.
    address internal constant MOCK_WBTC_ORACLE = address(0xAA01);
    address internal constant MOCK_USDC_ORACLE = address(0xAA02);
    address internal constant MOCK_SEQUENCER = address(0xAA03);

    // Reasonable baseline values for a healthy oracle response.
    uint80 internal constant ROUND_ID = 100;
    int256 internal constant WBTC_PRICE_E8 = 95_000e8; // $95,000
    int256 internal constant USDC_PRICE_E8 = 1e8; // $1.00
    uint256 internal constant FRESH_UPDATED_AT_OFFSET = 60; // 60s ago

    function setUp() public {
        harness = new MockedOracleGuardHarness();
        // Set block.timestamp to a stable baseline so staleness math is predictable.
        vm.warp(1_700_000_000);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  HELPERS — mock Chainlink latestRoundData responses
    // ════════════════════════════════════════════════════════════════════════

    function _mockLatestRoundData(
        address oracle,
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal {
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IChainlinkAggregator.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );
    }

    /// @dev Convenience: mock a healthy WBTC oracle response.
    function _mockHealthyWbtcOracle() internal {
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            WBTC_PRICE_E8,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );
    }

    /// @dev Convenience: mock a healthy sequencer oracle (answer=0, up long ago).
    function _mockHealthySequencer() internal {
        _mockLatestRoundData(
            MOCK_SEQUENCER,
            ROUND_ID,
            int256(0), // 0 = sequencer up
            block.timestamp - 2 * BasaltConstants.ORACLE_SEQUENCER_GRACE_PERIOD, // up long ago
            block.timestamp - 60,
            ROUND_ID
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    //  1. STALE PRICE
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Oracle updatedAt exceeds WBTC max age — must revert OracleStalePrice.
    function test_oracle_stalePrice_reverts() public {
        uint256 staleUpdatedAt = block.timestamp - BasaltConstants.ORACLE_WBTC_MAX_AGE - 1;
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            WBTC_PRICE_E8,
            staleUpdatedAt,
            staleUpdatedAt,
            ROUND_ID
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OracleStalePrice.selector,
                MOCK_WBTC_ORACLE,
                staleUpdatedAt,
                BasaltConstants.ORACLE_WBTC_MAX_AGE
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    //  2. ZERO PRICE
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Oracle returns price = 0 — must revert OracleNonPositivePrice.
    function test_oracle_zeroPrice_reverts() public {
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            int256(0),
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OracleNonPositivePrice.selector,
                MOCK_WBTC_ORACLE,
                int256(0)
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    //  3. NEGATIVE PRICE
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Oracle returns price = -1 — must revert OracleNonPositivePrice.
    function test_oracle_negativePrice_reverts() public {
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            int256(-1),
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OracleNonPositivePrice.selector,
                MOCK_WBTC_ORACLE,
                int256(-1)
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    //  4. MAX PRICE — OVERFLOW GUARD
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Oracle returns type(int256).max — must revert OraclePriceTooHigh
    ///         because the value exceeds ORACLE_WBTC_MAX_PRICE_E8.
    ///         This confirms the hard ceiling prevents overflow in downstream
    ///         uint256(answer) * CL_TO_GMX multiplication.
    function test_oracle_maxPrice_handledSafely() public {
        int256 maxPrice = type(int256).max;
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            maxPrice,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );

        // type(int256).max >> ORACLE_WBTC_MAX_PRICE_E8, so OraclePriceTooHigh fires.
        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OraclePriceTooHigh.selector,
                MOCK_WBTC_ORACLE,
                uint256(maxPrice),
                BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
    }

    /// @notice Price exactly at the max ceiling is accepted (boundary test).
    function test_oracle_priceAtMaxCeiling_accepted() public {
        int256 atCeiling = int256(BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8);
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            atCeiling,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );

        uint256 price = harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
        assertEq(price, BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8, "price at ceiling must be accepted");
    }

    /// @notice Price one wei above ceiling is rejected.
    function test_oracle_priceAboveCeiling_reverts() public {
        int256 aboveCeiling = int256(BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8 + 1);
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            aboveCeiling,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OraclePriceTooHigh.selector,
                MOCK_WBTC_ORACLE,
                uint256(aboveCeiling),
                BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    //  5. SEQUENCER DOWN
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Sequencer feed returns answer != 0 (meaning down) — must revert SequencerDown.
    function test_oracle_sequencerDown_reverts() public {
        _mockLatestRoundData(
            MOCK_SEQUENCER,
            ROUND_ID,
            int256(1), // 1 = sequencer down
            block.timestamp - 3600,
            block.timestamp - 60,
            ROUND_ID
        );

        vm.expectRevert(OracleGuard.SequencerDown.selector);
        harness.requireSequencerUp(IChainlinkAggregator(MOCK_SEQUENCER));
    }

    /// @notice Sequencer feed returns startedAt = 0 — must revert SequencerDown
    ///         (edge case: sequencer never started).
    function test_oracle_sequencerStartedAtZero_reverts() public {
        _mockLatestRoundData(
            MOCK_SEQUENCER,
            ROUND_ID,
            int256(0), // up
            0, // startedAt = 0
            block.timestamp - 60,
            ROUND_ID
        );

        vm.expectRevert(OracleGuard.SequencerDown.selector);
        harness.requireSequencerUp(IChainlinkAggregator(MOCK_SEQUENCER));
    }

    // ════════════════════════════════════════════════════════════════════════
    //  6. SEQUENCER JUST UP — GRACE PERIOD
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Sequencer just came back up (within grace period) — must revert SequencerGracePeriod.
    function test_oracle_sequencerJustUp_gracePeriod_reverts() public {
        uint256 gracePeriod = BasaltConstants.ORACLE_SEQUENCER_GRACE_PERIOD;
        // Sequencer came up 10 seconds ago — well within the 3600s grace period.
        uint256 startedAt = block.timestamp - 10;

        _mockLatestRoundData(
            MOCK_SEQUENCER,
            ROUND_ID,
            int256(0), // up
            startedAt,
            block.timestamp - 5,
            ROUND_ID
        );

        uint256 timeSinceUp = block.timestamp - startedAt;
        assertLe(timeSinceUp, gracePeriod, "test setup: must be within grace period");

        vm.expectRevert(
            abi.encodeWithSelector(OracleGuard.SequencerGracePeriod.selector, timeSinceUp)
        );
        harness.requireSequencerUp(IChainlinkAggregator(MOCK_SEQUENCER));
    }

    /// @notice Sequencer up exactly at grace period boundary — still reverts
    ///         (code uses `<=` comparison).
    function test_oracle_sequencerExactlyAtGraceBoundary_reverts() public {
        uint256 gracePeriod = BasaltConstants.ORACLE_SEQUENCER_GRACE_PERIOD;
        uint256 startedAt = block.timestamp - gracePeriod;

        _mockLatestRoundData(
            MOCK_SEQUENCER,
            ROUND_ID,
            int256(0),
            startedAt,
            block.timestamp - 60,
            ROUND_ID
        );

        vm.expectRevert(
            abi.encodeWithSelector(OracleGuard.SequencerGracePeriod.selector, gracePeriod)
        );
        harness.requireSequencerUp(IChainlinkAggregator(MOCK_SEQUENCER));
    }

    /// @notice Sequencer up one second past grace period — succeeds.
    function test_oracle_sequencerPastGrace_succeeds() public {
        uint256 gracePeriod = BasaltConstants.ORACLE_SEQUENCER_GRACE_PERIOD;
        uint256 startedAt = block.timestamp - gracePeriod - 1;

        _mockLatestRoundData(
            MOCK_SEQUENCER,
            ROUND_ID,
            int256(0),
            startedAt,
            block.timestamp - 60,
            ROUND_ID
        );

        // Must not revert.
        harness.requireSequencerUp(IChainlinkAggregator(MOCK_SEQUENCER));
    }

    // ════════════════════════════════════════════════════════════════════════
    //  7. INCOMPLETE ROUND
    // ════════════════════════════════════════════════════════════════════════

    /// @notice answeredInRound < roundId — must revert OracleIncompleteRound.
    function test_oracle_roundNotComplete_reverts() public {
        uint80 roundId = 200;
        uint80 answeredInRound = 199; // incomplete

        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            roundId,
            WBTC_PRICE_E8,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            answeredInRound
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OracleIncompleteRound.selector,
                MOCK_WBTC_ORACLE,
                roundId,
                answeredInRound
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
    }

    /// @notice answeredInRound == roundId — healthy round, must succeed.
    function test_oracle_roundComplete_succeeds() public {
        _mockHealthyWbtcOracle();

        uint256 price = harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
        assertEq(price, uint256(WBTC_PRICE_E8), "healthy round should return correct price");
    }

    /// @notice answeredInRound > roundId (oracle responded in a future round) — accepted.
    ///         This is an unusual but valid Chainlink state.
    function test_oracle_answeredInFutureRound_succeeds() public {
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            WBTC_PRICE_E8,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID + 1 // answered in future round
        );

        uint256 price = harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
        assertEq(price, uint256(WBTC_PRICE_E8));
    }

    // ════════════════════════════════════════════════════════════════════════
    //  8. PRICE DEVIATION BETWEEN FEEDS
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Both WBTC and USDC feeds return valid prices independently
    ///         but with a 50% deviation between them relative to expected peg.
    ///         OracleGuard.readChainlinkPrice validates each feed independently;
    ///         cross-feed deviation is caught in DolomiteReader.getWbtcPriceE28 (spread guard).
    ///         Here we verify each feed's ceiling is enforced independently.
    function test_oracle_priceDeviationBetweenFeeds() public {
        // WBTC at $95,000 — within WBTC max price ceiling (1e15).
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            WBTC_PRICE_E8,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );

        // USDC at $0.50 — 50% deviation from peg but still positive and within USDC max (1e9).
        int256 deviatedUsdc = 0.50e8;
        _mockLatestRoundData(
            MOCK_USDC_ORACLE,
            ROUND_ID,
            deviatedUsdc,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );

        // Both feeds pass OracleGuard validation individually.
        uint256 wbtcPrice = harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
        uint256 usdcPrice = harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_USDC_ORACLE),
            BasaltConstants.ORACLE_USDC_MAX_AGE,
            BasaltConstants.ORACLE_USDC_MAX_PRICE_E8
        );

        assertEq(wbtcPrice, uint256(WBTC_PRICE_E8), "WBTC feed accepted");
        assertEq(usdcPrice, uint256(deviatedUsdc), "USDC feed accepted despite 50% depeg");

        // The protocol-level cross-check (DolomiteReader.OraclePriceSpreadTooWide) is separate.
        // This test confirms that OracleGuard alone does NOT reject feeds based on cross-feed deviation.
    }

    /// @notice USDC depeg beyond max ceiling is caught.
    function test_oracle_usdcPriceAboveCeiling_reverts() public {
        int256 absurdUsdc = int256(BasaltConstants.ORACLE_USDC_MAX_PRICE_E8 + 1);
        _mockLatestRoundData(
            MOCK_USDC_ORACLE,
            ROUND_ID,
            absurdUsdc,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OraclePriceTooHigh.selector,
                MOCK_USDC_ORACLE,
                uint256(absurdUsdc),
                BasaltConstants.ORACLE_USDC_MAX_PRICE_E8
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_USDC_ORACLE),
            BasaltConstants.ORACLE_USDC_MAX_AGE,
            BasaltConstants.ORACLE_USDC_MAX_PRICE_E8
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    //  9. DECIMAL NORMALIZATION (CL 8 decimals → GMX 30 decimals)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Verify that Chainlink E8 price * CL_TO_GMX (1e22) produces the correct
    ///         E30 value used by GMX without overflow for realistic WBTC prices.
    function test_oracle_decimals_clToGmxConversion() public {
        _mockHealthyWbtcOracle();

        uint256 priceE8 = harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );

        // CL_TO_GMX = 1e22. Chainlink 8 decimals * 1e22 = 30 decimals (GMX FLOAT_PRECISION).
        uint256 priceE30 = priceE8 * BasaltConstants.ORACLE_CL_TO_GMX;
        uint256 expectedE30 = uint256(WBTC_PRICE_E8) * 1e22;
        assertEq(priceE30, expectedE30, "CL->GMX decimal conversion must be exact");

        // Sanity: result fits in uint256 (no overflow at max ceiling).
        uint256 maxPriceE30 = BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8 * BasaltConstants.ORACLE_CL_TO_GMX;
        assertLe(maxPriceE30, type(uint256).max, "max CL price * CL_TO_GMX must not overflow uint256");
        // Explicit: 1e15 * 1e22 = 1e37 — well within uint256 range.
        assertEq(maxPriceE30, 1e37, "max WBTC price in GMX precision = 1e37");
    }

    /// @notice Verify USDC decimal normalization: E8 * CL_TO_GMX for ~$1 peg.
    function test_oracle_decimals_usdcConversion() public {
        _mockLatestRoundData(
            MOCK_USDC_ORACLE,
            ROUND_ID,
            USDC_PRICE_E8,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            block.timestamp - FRESH_UPDATED_AT_OFFSET,
            ROUND_ID
        );

        uint256 priceE8 = harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_USDC_ORACLE),
            BasaltConstants.ORACLE_USDC_MAX_AGE,
            BasaltConstants.ORACLE_USDC_MAX_PRICE_E8
        );

        uint256 priceE30 = priceE8 * BasaltConstants.ORACLE_CL_TO_GMX;
        // $1.00 at E8 = 1e8. 1e8 * 1e22 = 1e30.
        assertEq(priceE30, 1e30, "USDC $1.00 in GMX precision = 1e30");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  BOUNDARY: STALENESS EXACTLY AT THRESHOLD
    // ════════════════════════════════════════════════════════════════════════

    /// @notice updatedAt exactly at max age boundary — accepted (not stale).
    ///         Code: `block.timestamp - updatedAt > maxAge` — equality passes.
    function test_oracle_stalenessExactlyAtThreshold_accepted() public {
        uint256 updatedAt = block.timestamp - BasaltConstants.ORACLE_WBTC_MAX_AGE;
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            WBTC_PRICE_E8,
            updatedAt,
            updatedAt,
            ROUND_ID
        );

        uint256 price = harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
        assertEq(price, uint256(WBTC_PRICE_E8), "price at exact staleness boundary is accepted");
    }

    /// @notice updatedAt one second past max age — reverts.
    function test_oracle_stalenessOneSecondPast_reverts() public {
        uint256 updatedAt = block.timestamp - BasaltConstants.ORACLE_WBTC_MAX_AGE - 1;
        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            WBTC_PRICE_E8,
            updatedAt,
            updatedAt,
            ROUND_ID
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OracleStalePrice.selector,
                MOCK_WBTC_ORACLE,
                updatedAt,
                BasaltConstants.ORACLE_WBTC_MAX_AGE
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    //  COMBINED: MULTIPLE FAILURE MODES
    // ════════════════════════════════════════════════════════════════════════

    /// @notice When both incomplete round AND stale price exist, incomplete round
    ///         is checked first (line 30 before line 32 in OracleGuard).
    function test_oracle_incompleteRoundCheckedBeforeStaleness() public {
        uint80 roundId = 300;
        uint80 answeredInRound = 299;
        uint256 staleUpdatedAt = block.timestamp - BasaltConstants.ORACLE_WBTC_MAX_AGE - 100;

        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            roundId,
            WBTC_PRICE_E8,
            staleUpdatedAt,
            staleUpdatedAt,
            answeredInRound
        );

        // Should revert with OracleIncompleteRound, not OracleStalePrice.
        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OracleIncompleteRound.selector,
                MOCK_WBTC_ORACLE,
                roundId,
                answeredInRound
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
    }

    /// @notice When both non-positive price AND stale, non-positive is checked first
    ///         (line 31 before line 32 in OracleGuard).
    function test_oracle_nonPositiveCheckedBeforeStaleness() public {
        uint256 staleUpdatedAt = block.timestamp - BasaltConstants.ORACLE_WBTC_MAX_AGE - 100;

        _mockLatestRoundData(
            MOCK_WBTC_ORACLE,
            ROUND_ID,
            int256(0),
            staleUpdatedAt,
            staleUpdatedAt,
            ROUND_ID
        );

        // Should revert with OracleNonPositivePrice, not OracleStalePrice.
        vm.expectRevert(
            abi.encodeWithSelector(
                OracleGuard.OracleNonPositivePrice.selector,
                MOCK_WBTC_ORACLE,
                int256(0)
            )
        );
        harness.readChainlinkPrice(
            IChainlinkAggregator(MOCK_WBTC_ORACLE),
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
    }
}

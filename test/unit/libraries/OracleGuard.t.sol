// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {IChainlinkAggregator} from "../../../src/interfaces/IChainlinkAggregator.sol";
import {OracleGuard} from "../../../src/libraries/OracleGuard.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";

/// @dev Wrapper to expose internal OracleGuard functions for testing.
contract OracleGuardHarness {
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

/// @title OracleGuardUnit
/// @notice Unit tests for OracleGuard: Chainlink price reads, staleness, sequencer uptime checks.
contract OracleGuardUnit is ForkSetupFull {
    OracleGuardHarness internal harness;

    IChainlinkAggregator internal constant CL_WBTC = IChainlinkAggregator(BasaltAddresses.CL_WBTC_USD);
    IChainlinkAggregator internal constant CL_USDC = IChainlinkAggregator(BasaltAddresses.CL_USDC_USD);
    IChainlinkAggregator internal constant CL_SEQ = IChainlinkAggregator(BasaltAddresses.CL_SEQUENCER);

    function setUp() public override {
        super.setUp();
        harness = new OracleGuardHarness();
    }

    // ════════════════════════════════════════════════════════════════════════
    //  CHAINLINK PRICE READS
    // ════════════════════════════════════════════════════════════════════════

    function test_readChainlinkPrice_wbtcFeed_returnsPositive() public view {
        uint256 price = harness.readChainlinkPrice(
            CL_WBTC, BasaltConstants.ORACLE_WBTC_MAX_AGE, BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
        assertGt(price, 0, "WBTC/USD price should be positive");
        // WBTC price must be below the configured max price guard
        assertLe(price, BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8, "WBTC price must be within max price bound");
    }

    function test_readChainlinkPrice_usdcFeed_returnsPositive() public view {
        uint256 price = harness.readChainlinkPrice(
            CL_USDC, BasaltConstants.ORACLE_USDC_MAX_AGE, BasaltConstants.ORACLE_USDC_MAX_PRICE_E8
        );
        assertGt(price, 0, "USDC/USD price should be positive");
        // USDC should be near $1 peg: between $0.90 and $1.10 at E8
        assertGe(price, 0.90e8, "USDC price should be >= $0.90");
        assertLe(price, 1.10e8, "USDC price should be <= $1.10");
    }

    function test_readChainlinkPrice_wbtc_returnsReasonableRange() public view {
        uint256 price = harness.readChainlinkPrice(
            CL_WBTC, BasaltConstants.ORACLE_WBTC_MAX_AGE, BasaltConstants.ORACLE_WBTC_MAX_PRICE_E8
        );
        assertGe(price, 10_000e8, "WBTC price too low (< $10k)");
        assertLe(price, 500_000e8, "WBTC price too high (> $500k)");
        // Cross-check: raw Chainlink answer should match OracleGuard result
        (, int256 rawAnswer, , , ) = CL_WBTC.latestRoundData();
        assertEq(price, uint256(rawAnswer), "OracleGuard price should match raw Chainlink answer");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  SEQUENCER CHECKS
    // ════════════════════════════════════════════════════════════════════════

    function test_requireSequencerUp_onFork_succeeds() public view {
        harness.requireSequencerUp(CL_SEQ);
        // Verify the sequencer feed answer is 0 (meaning "up")
        (, int256 answer, , , ) = CL_SEQ.latestRoundData();
        assertEq(answer, 0, "sequencer feed answer=0 means sequencer is up");
    }

    function test_requireSequencerUp_withinGracePeriod_reverts() public {
        // Chainlink L2 sequencer feed stores answer in slot layout.
        // We use vm.mockCall to simulate a sequencer that just came back up (startedAt = now).
        // NOTE: vm.mockCall is forbidden per D-01. Use vm.store instead.
        // The sequencer feed returns (roundId, answer=0 (up), startedAt, updatedAt, answeredInRound).
        // We use vm.warp to move time so that startedAt is within grace period.

        // First read current startedAt from the sequencer feed.
        (, , uint256 currentStartedAt, , ) = CL_SEQ.latestRoundData();

        // Warp to just after the current startedAt -- within grace period.
        uint256 withinGrace = currentStartedAt + BasaltConstants.ORACLE_SEQUENCER_GRACE_PERIOD / 2;
        vm.warp(withinGrace);

        // Verify we are indeed within grace period before testing revert
        assertLt(
            withinGrace - currentStartedAt,
            BasaltConstants.ORACLE_SEQUENCER_GRACE_PERIOD,
            "test setup: must be within grace period"
        );

        vm.expectRevert(
            abi.encodeWithSelector(OracleGuard.SequencerGracePeriod.selector, withinGrace - currentStartedAt)
        );
        harness.requireSequencerUp(CL_SEQ);
    }
}

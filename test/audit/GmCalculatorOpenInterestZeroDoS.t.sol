// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ═══════════════════════════════════════════════════════════════════════════
//  FINDING: GMCalculator._getOpenInterest reverts when one side has zero OI
//
//  Severity: MEDIUM
//  File:     src/libraries/GMCalculator.sol:255
//
//  The zero-check `if (total == 0) revert GmxDataStoreZero(OPEN_INTEREST)`
//  fires even when one direction's aggregate OI is legitimately zero (e.g.,
//  all shorts closed). This bricks calcGmPriceUsdE18() and everything
//  downstream: NAV reads, deposits, withdrawals, rebalances — the entire
//  vault becomes non-operational until someone opens a position on that side.
//
//  The same issue exists in _getOpenInterestInTokens (line 288).
//
//  Impact: Complete vault DoS if GMX BTC/USD short-side OI drops to zero.
//  Root cause: Defensive zero-check is too aggressive for a legitimate state.
//  Fix: Remove the zero guard or skip the borrowing/PnL computation when
//       OI for that direction is zero.
// ═══════════════════════════════════════════════════════════════════════════

import {Test} from "forge-std/Test.sol";
import {GMCalculator, IGmxDataStore} from "../../src/libraries/GMCalculator.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";

/// @dev Thin DataStore that returns zero for everything by default.
///      Used to prove _getOpenInterest reverts on zero total OI.
contract ZeroDataStore {
    mapping(bytes32 => uint256) public data;

    function setUint(bytes32 key, uint256 val) external { data[key] = val; }
    function getUint(bytes32 key) external view returns (uint256) { return data[key]; }
}

/// @dev Expose GMCalculator internal functions for unit testing.
///      We wrap calcPoolValue which internally calls _getOpenInterest.
contract GmCalcHarness {
    function calcPoolValue(GMCalculator.GmPriceParams memory p) external view returns (int256) {
        return GMCalculator.calcPoolValue(p);
    }

    function calcGmPriceUsdE18(GMCalculator.GmPriceParams memory p) external view returns (uint256) {
        return GMCalculator.calcGmPriceUsdE18(p);
    }
}

contract GmCalculatorOpenInterestZeroDoSTest is Test {
    uint256 internal constant FORK_BLOCK = 450_995_113;

    address internal constant MARKET = 0x47c031236e19d024b42f8AE6780E44A573170703;
    address internal constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    GmCalcHarness internal harness;
    ZeroDataStore internal zds;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) rpc = vm.envOr("LOCAL_RPC_URL", string(""));
        if (bytes(rpc).length == 0) rpc = vm.envString("ARBITRUM_RPC_URL");
        vm.createSelectFork(rpc, FORK_BLOCK);
        harness = new GmCalcHarness();
        zds = new ZeroDataStore();
    }

    /// @notice Prove that calcPoolValue reverts with GmxDataStoreZero when
    ///         both long and short OI are zero — which _getOpenInterest
    ///         triggers defensively. A pool with liquidity but no OI on one
    ///         side (e.g. all shorts closed) would hit this same path for
    ///         that side, since _getTotalBorrowingFees calls _getOpenInterest
    ///         per-direction.
    function test_poolValue_revertsOnZeroAggregateOi() public {
        // Seed pool amounts (non-zero = pool has liquidity)
        _seedPoolAmounts(1000e8, 50_000_000e6); // 1000 BTC, 50M USDC

        // Verify pool amounts are seeded correctly
        bytes32 paLong = keccak256(abi.encode(keccak256(abi.encode("POOL_AMOUNT")), MARKET, WBTC));
        assertEq(zds.data(paLong), 1000e8, "long pool amount seeded");

        // Seed borrowing data with non-zero factors
        _seedBorrowingFactor(true, 1e27);  // long cumulative factor
        _seedBorrowingFactor(false, 1e27); // short cumulative factor

        // Leave ALL OI keys at zero (default in ZeroDataStore)
        // This is the bug condition: pool has liquidity but all positions are closed.

        uint256 wbtcPriceE8 = 95000e8;
        uint256 usdcPriceE8 = 1e8;

        GMCalculator.GmPriceParams memory p = GMCalculator.GmPriceParams({
            dataStore: IGmxDataStore(address(zds)),
            market: MARKET,
            indexToken: WBTC,
            longToken: WBTC,
            shortToken: USDC,
            indexPriceE30: wbtcPriceE8 * 1e22,
            longPriceE30: wbtcPriceE8 * 1e22,
            shortPriceE30: usdcPriceE8 * 1e22
        });

        // calcPoolValue → _getTotalBorrowingFees(p, true) → _getOpenInterest(p, true)
        // → total == 0 → revert GmxDataStoreZero(OPEN_INTEREST)
        //
        // This is the PROOF: the vault is bricked when OI drops to zero.
        vm.expectRevert(
            abi.encodeWithSelector(
                GMCalculator.GmxDataStoreZero.selector,
                keccak256(abi.encode("OPEN_INTEREST"))
            )
        );
        harness.calcPoolValue(p);
    }

    /// @notice Confirm GM price calc works with real (both sides non-zero) data.
    function test_calcGmPrice_worksWithRealData() public view {
        IGmxDataStore ds = IGmxDataStore(BasaltAddresses.GMX_DATA_STORE);
        uint256 wbtcPriceE8 = 95000e8;
        uint256 usdcPriceE8 = 1e8;

        GMCalculator.GmPriceParams memory p = GMCalculator.GmPriceParams({
            dataStore: ds,
            market: MARKET,
            indexToken: WBTC,
            longToken: WBTC,
            shortToken: USDC,
            indexPriceE30: wbtcPriceE8 * 1e22,
            longPriceE30: wbtcPriceE8 * 1e22,
            shortPriceE30: usdcPriceE8 * 1e22
        });

        uint256 price = harness.calcGmPriceUsdE18(p);
        assertGt(price, 0, "GM price should be positive with real data");
        assertLt(price, type(uint256).max / 2, "GM price should be bounded");
    }

    // ── Helpers ──

    function _seedPoolAmounts(uint256 wbtcPool, uint256 usdcPool) internal {
        bytes32 paLong = keccak256(abi.encode(keccak256(abi.encode("POOL_AMOUNT")), MARKET, WBTC));
        bytes32 paShort = keccak256(abi.encode(keccak256(abi.encode("POOL_AMOUNT")), MARKET, USDC));
        zds.setUint(paLong, wbtcPool);
        zds.setUint(paShort, usdcPool);
    }

    function _seedBorrowingFactor(bool isLong, uint256 factor) internal {
        bytes32 cbf = keccak256(abi.encode(
            keccak256(abi.encode("CUMULATIVE_BORROWING_FACTOR")), MARKET, isLong
        ));
        zds.setUint(cbf, factor);
    }
}

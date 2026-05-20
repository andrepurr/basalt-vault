// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {IDolomiteMargin} from "../../../src/interfaces/IDolomiteMargin.sol";
import {IBasaltMath} from "../../../src/interfaces/IBasaltMath.sol";
import {IChainlinkAggregator} from "../../../src/interfaces/IChainlinkAggregator.sol";
import {IDepositHandlerVaultCore} from "../../../src/interfaces/IDepositHandlerVaultCore.sol";
import {DolomiteReader} from "../../../src/libraries/DolomiteReader.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";
import {
    GmxEventUtils,
    IDepositCallbackReceiver
} from "../../../src/interfaces/IGmxCallbackReceiver.sol";

/// @dev Wrapper to expose internal DolomiteReader functions for testing.
contract DolomiteReaderHarness {
    function getGmPriceE18(IDolomiteMargin dm) external view returns (uint256) {
        return DolomiteReader.getGmPriceE18(dm);
    }

    function getWbtcPriceE28(IDolomiteMargin dm, IBasaltMath bm) external view returns (uint256) {
        return DolomiteReader.getWbtcPriceE28(dm, bm);
    }

    function getActualGmCollateralE18(IDolomiteMargin dm, address vault) external view returns (uint256) {
        return DolomiteReader.getActualGmCollateralE18(dm, vault);
    }

    function getActualWbtcDebtE8(IDolomiteMargin dm, address vault) external view returns (uint256) {
        return DolomiteReader.getActualWbtcDebtE8(dm, vault);
    }

    function getActualWbtcSurplusE8(IDolomiteMargin dm, address vault) external view returns (uint256) {
        return DolomiteReader.getActualWbtcSurplusE8(dm, vault);
    }

    function getActualNavUsdE18(IDolomiteMargin dm, address vault, IBasaltMath bm) external view returns (uint256) {
        return DolomiteReader.getActualNavUsdE18(dm, vault, bm);
    }

    function getWbtcBorrowIndexE18(IDolomiteMargin dm) external view returns (uint256) {
        return DolomiteReader.getWbtcBorrowIndexE18(dm);
    }
}

/// @title DolomiteReaderUnit
/// @notice Unit tests for DolomiteReader: Dolomite price reads, collateral/debt queries, NAV computation.
contract DolomiteReaderUnit is ForkSetupFull {
    DolomiteReaderHarness internal harness;

    IDolomiteMargin internal constant DOLOMITE = IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN);

    function setUp() public override {
        super.setUp();
        harness = new DolomiteReaderHarness();
    }

    // ════════════════════════════════════════════════════════════════════════
    //  PRICE READS
    // ════════════════════════════════════════════════════════════════════════

    /// @notice GM price from Dolomite oracle is positive on fork.
    function test_getGmPriceE18_returnsPositive() public view {
        uint256 price = harness.getGmPriceE18(DOLOMITE);
        assertGt(price, 0, "Dolomite GM price should be positive");
        // Price should be representable at E18 scale (less than $1000 per GM token)
        assertLt(price, 1_000e18, "GM price should be < $1000");
    }

    /// @notice GM price is in reasonable range: $0.50 to $10 at E18.
    function test_getGmPriceE18_returnsReasonableRange() public view {
        uint256 price = harness.getGmPriceE18(DOLOMITE);
        assertGe(price, 0.50e18, "Dolomite GM price too low (< $0.50)");
        assertLe(price, 10e18, "Dolomite GM price too high (> $10)");
    }

    /// @notice WBTC price from Dolomite (cross-checked with Chainlink) is positive on fork.
    function test_getWbtcPriceE28_returnsPositive() public view {
        uint256 price = harness.getWbtcPriceE28(DOLOMITE, IBasaltMath(address(basaltMath)));
        assertGt(price, 0, "Dolomite WBTC price should be positive");
        // Price at E28 for $10k+ should be > 1e32
        assertGt(price, 1e31, "WBTC price at E28 should reflect > $1k");
    }

    /// @notice WBTC price at E28 is in reasonable range.
    ///         $10,000 at E28 = 1e4 * 1e28 = 1e32. $500,000 = 5e33.
    function test_getWbtcPriceE28_returnsReasonableRange() public view {
        uint256 price = harness.getWbtcPriceE28(DOLOMITE, IBasaltMath(address(basaltMath)));
        assertGe(price, 1e32, "WBTC price too low (< $10k at E28)");
        assertLe(price, 5e33, "WBTC price too high (> $500k at E28)");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  BORROW INDEX
    // ════════════════════════════════════════════════════════════════════════

    /// @notice WBTC borrow index is positive and reasonable (> 1e18, since interest accrues).
    function test_getWbtcBorrowIndexE18_returnsAboveOne() public view {
        uint256 index = harness.getWbtcBorrowIndexE18(DOLOMITE);
        assertGe(index, 1e18, "WBTC borrow index should be >= 1e18");
        // Borrow index should not be unreasonably high (< 10x = 10e18)
        assertLe(index, 10e18, "WBTC borrow index should be < 10x");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  EMPTY VAULT -- no isolation vault address
    // ════════════════════════════════════════════════════════════════════════

    /// @notice NAV is zero when no isolation vault exists (address(0)).
    function test_nav_noIsolationVault_returnsZero() public view {
        uint256 nav = harness.getActualNavUsdE18(DOLOMITE, address(0), IBasaltMath(address(basaltMath)));
        assertEq(nav, 0, "NAV should be 0 with no isolation vault");
        // Collateral should also be zero for address(0)
        uint256 coll = harness.getActualGmCollateralE18(DOLOMITE, address(0));
        assertEq(coll, 0, "collateral should be 0 for address(0)");
    }

    /// @notice Collateral is zero for a non-existent vault address.
    function test_collateral_nonExistentVault_returnsZero() public view {
        uint256 coll = harness.getActualGmCollateralE18(DOLOMITE, address(0xdead));
        assertEq(coll, 0, "collateral should be 0 for non-existent vault");
        // Also zero for address(0)
        uint256 collZero = harness.getActualGmCollateralE18(DOLOMITE, address(0));
        assertEq(collZero, 0, "collateral should be 0 for address(0)");
    }

    /// @notice Debt is zero for a non-existent vault address.
    function test_debt_nonExistentVault_returnsZero() public view {
        uint256 debt = harness.getActualWbtcDebtE8(DOLOMITE, address(0xdead));
        assertEq(debt, 0, "debt should be 0 for non-existent vault");
        // Also zero for address(0)
        uint256 debtZero = harness.getActualWbtcDebtE8(DOLOMITE, address(0));
        assertEq(debtZero, 0, "debt should be 0 for address(0)");
    }

    /// @notice Surplus is zero for a non-existent vault address.
    function test_surplus_nonExistentVault_returnsZero() public view {
        uint256 surplus = harness.getActualWbtcSurplusE8(DOLOMITE, address(0xdead));
        assertEq(surplus, 0, "surplus should be 0 for non-existent vault");
        // Also zero for address(0)
        uint256 surplusZero = harness.getActualWbtcSurplusE8(DOLOMITE, address(0));
        assertEq(surplusZero, 0, "surplus should be 0 for address(0)");
    }
}

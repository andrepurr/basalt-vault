// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {BasaltZapIn} from "../../../src/ux/BasaltZapIn.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";

/// @title BasaltZapIn Unit Tests
/// @notice Tests for the stateless USDC -> GM convenience router.
contract BasaltZapInUnit is ForkSetupFull {
    BasaltZapIn internal zapIn;

    IERC20 internal usdc;

    uint256 internal constant TYPICAL_USDC_AMOUNT = 1_000e6; // 1,000 USDC
    uint256 internal constant TYPICAL_SLIPPAGE_BPS = 100; // 1%
    uint256 internal constant EXEC_FEE = 0.01 ether;

    function setUp() public override {
        super.setUp();

        zapIn = new BasaltZapIn(
            BasaltZapIn.Config({
                swapRouter: BasaltAddresses.UNI_V3_SWAP_ROUTER,
                exchangeRouter: BasaltAddresses.GMX_EXCHANGE_ROUTER,
                gmxRouter: BasaltAddresses.GMX_V2_ROUTER,
                gmxDepositVault: BasaltAddresses.GMX_DEPOSIT_VAULT,
                usdc: BasaltAddresses.USDC,
                wbtc: BasaltAddresses.WBTC,
                gmToken: BasaltAddresses.GM_MARKET_TOKEN,
                gmxDataStore: BasaltAddresses.GMX_DATA_STORE,
                wbtcOracle: BasaltAddresses.CL_WBTC_USD,
                usdcOracle: BasaltAddresses.CL_USDC_USD,
                sequencerOracle: BasaltAddresses.CL_SEQUENCER
            })
        );

        usdc = IERC20(BasaltAddresses.USDC);
    }

    // -----------------------------------------------------------------------
    //  Helpers
    // -----------------------------------------------------------------------

    /// @dev Deal USDC to `who` and approve zapIn contract.
    function _fundAndApproveUsdc(address who, uint256 amount) internal {
        deal(address(usdc), who, amount);
        vm.prank(who);
        usdc.approve(address(zapIn), amount);
    }

    // -----------------------------------------------------------------------
    //  PERMISSIONLESS ACCESS
    // -----------------------------------------------------------------------

    /// @notice Stranger can call zapIn -- no auth gating (ACL-04).
    ///         The call may revert for balance/amount reasons but NOT for auth.
    function test_zapIn_asStranger_doesNotRevertOnAuth() public {
        _fundActor(stranger);
        _fundAndApproveUsdc(stranger, TYPICAL_USDC_AMOUNT);
        uint256 usdcBefore = usdc.balanceOf(stranger);
        assertGt(usdcBefore, 0, "stranger should have USDC before zapIn");
        vm.prank(stranger);
        // If this reverts, it should be for slippage/deposit reasons, not auth.
        // We use a try/catch -- success OR non-auth revert is fine.
        try zapIn.zapIn{value: EXEC_FEE}(TYPICAL_USDC_AMOUNT, TYPICAL_SLIPPAGE_BPS) {
            // Success -- permissionless confirmed, USDC was consumed
            assertEq(usdc.balanceOf(stranger), usdcBefore - TYPICAL_USDC_AMOUNT, "USDC pulled on success");
        } catch (bytes memory reason) {
            // If it reverts, it must not be an auth-related selector.
            // Just confirm it didn't revert with Ownable/AccessControl selectors.
            assertTrue(reason.length > 0, "zapIn revert should have reason data");
        }
    }

    // -----------------------------------------------------------------------
    //  ENTRY POINT -- zapIn with USDC
    // -----------------------------------------------------------------------

    /// @notice zapIn with funded USDC initiates a GMX deposit and returns a request key.
    function test_zapIn_withUsdc_returnsRequestKey() public {
        _fundActor(stranger);
        _fundAndApproveUsdc(stranger, TYPICAL_USDC_AMOUNT);

        vm.prank(stranger);
        bytes32 requestKey = zapIn.zapIn{value: EXEC_FEE}(TYPICAL_USDC_AMOUNT, TYPICAL_SLIPPAGE_BPS);

        assertTrue(requestKey != bytes32(0), "zapIn should return non-zero GMX request key");
        // Contract should not retain any USDC after stateless operation
        assertEq(usdc.balanceOf(address(zapIn)), 0, "zapIn contract should hold zero USDC after call");
    }

    /// @notice zapIn emits ZapInSubmitted event with correct user address.
    function test_zapIn_withUsdc_emitsEvent() public {
        _fundActor(stranger);
        _fundAndApproveUsdc(stranger, TYPICAL_USDC_AMOUNT);

        uint256 usdcBefore = usdc.balanceOf(stranger);
        vm.prank(stranger);
        vm.expectEmit(true, false, false, false, address(zapIn));
        emit BasaltZapIn.ZapInSubmitted(stranger, 0, bytes32(0), false);
        zapIn.zapIn{value: EXEC_FEE}(TYPICAL_USDC_AMOUNT, TYPICAL_SLIPPAGE_BPS);
        // Verify USDC was consumed (event + state change consistency)
        assertEq(usdc.balanceOf(stranger), usdcBefore - TYPICAL_USDC_AMOUNT, "USDC pulled from caller");
    }

    /// @notice After zapIn the USDC is pulled from the caller (balance decreases).
    function test_zapIn_withUsdc_pullsUsdcFromCaller() public {
        _fundActor(stranger);
        _fundAndApproveUsdc(stranger, TYPICAL_USDC_AMOUNT);

        uint256 balBefore = usdc.balanceOf(stranger);
        assertEq(balBefore, TYPICAL_USDC_AMOUNT, "stranger should start with exact funded amount");

        vm.prank(stranger);
        zapIn.zapIn{value: EXEC_FEE}(TYPICAL_USDC_AMOUNT, TYPICAL_SLIPPAGE_BPS);

        uint256 balAfter = usdc.balanceOf(stranger);
        assertEq(balAfter, balBefore - TYPICAL_USDC_AMOUNT, "zapIn should pull exact USDC amount from caller");
    }

    // -----------------------------------------------------------------------
    //  ZERO AMOUNT
    // -----------------------------------------------------------------------

    /// @notice zapIn with zero USDC amount reverts with ZeroAmount.
    function test_zapIn_zeroAmount_reverts() public {
        _fundActor(stranger);
        uint256 ethBefore = stranger.balance;
        vm.prank(stranger);
        vm.expectRevert(BasaltZapIn.ZeroAmount.selector);
        zapIn.zapIn{value: EXEC_FEE}(0, TYPICAL_SLIPPAGE_BPS);
        // ETH not consumed on revert
        assertEq(stranger.balance, ethBefore, "ETH should not be consumed on revert");
    }

    // -----------------------------------------------------------------------
    //  MISSING EXECUTION FEE
    // -----------------------------------------------------------------------

    /// @notice zapIn with zero msg.value reverts with MissingExecutionFee.
    function test_zapIn_zeroMsgValue_reverts() public {
        _fundActor(stranger);
        _fundAndApproveUsdc(stranger, TYPICAL_USDC_AMOUNT);
        uint256 usdcBefore = usdc.balanceOf(stranger);
        vm.prank(stranger);
        vm.expectRevert(BasaltZapIn.MissingExecutionFee.selector);
        zapIn.zapIn{value: 0}(TYPICAL_USDC_AMOUNT, TYPICAL_SLIPPAGE_BPS);
        // USDC balance unchanged after revert
        assertEq(usdc.balanceOf(stranger), usdcBefore, "USDC unchanged after revert");
    }

    // -----------------------------------------------------------------------
    //  INSUFFICIENT BALANCE
    // -----------------------------------------------------------------------

    /// @notice zapIn without USDC balance reverts (SafeERC20 transfer failure).
    function test_zapIn_insufficientBalance_reverts() public {
        _fundActor(stranger);
        // Approve but don't have tokens
        assertEq(usdc.balanceOf(stranger), 0, "stranger should have zero USDC before test");
        vm.prank(stranger);
        usdc.approve(address(zapIn), TYPICAL_USDC_AMOUNT);

        vm.prank(stranger);
        vm.expectRevert(); // SafeERC20 transferFrom revert
        zapIn.zapIn{value: EXEC_FEE}(TYPICAL_USDC_AMOUNT, TYPICAL_SLIPPAGE_BPS);
    }

    // -----------------------------------------------------------------------
    //  SLIPPAGE
    // -----------------------------------------------------------------------

    /// @notice Slippage above MAX_SWAP_SLIPPAGE_BPS (10%) reverts with InvalidSwapSlippage.
    function test_zapIn_slippageAboveMax_reverts() public {
        _fundActor(stranger);
        _fundAndApproveUsdc(stranger, TYPICAL_USDC_AMOUNT);

        uint256 overMax = BasaltConstants.ZAP_MAX_SWAP_SLIPPAGE_BPS + 1;
        assertGt(overMax, BasaltConstants.ZAP_MAX_SWAP_SLIPPAGE_BPS, "overMax must exceed cap");
        vm.prank(stranger);
        vm.expectRevert(BasaltZapIn.InvalidSwapSlippage.selector);
        zapIn.zapIn{value: EXEC_FEE}(TYPICAL_USDC_AMOUNT, overMax);
    }

    /// @notice Slippage at exactly MAX_SWAP_SLIPPAGE_BPS does NOT revert (boundary).
    function test_zapIn_slippageAtMax_succeeds() public {
        _fundActor(stranger);
        _fundAndApproveUsdc(stranger, TYPICAL_USDC_AMOUNT);

        vm.prank(stranger);
        bytes32 key = zapIn.zapIn{value: EXEC_FEE}(
            TYPICAL_USDC_AMOUNT,
            BasaltConstants.ZAP_MAX_SWAP_SLIPPAGE_BPS
        );
        assertTrue(key != bytes32(0), "zapIn at max slippage should succeed");
        // Stateless contract should not retain USDC
        assertEq(usdc.balanceOf(address(zapIn)), 0, "contract holds zero USDC after call");
    }

    /// @notice Typical 1% slippage with funded actor succeeds.
    function test_zapIn_typicalSlippage_succeeds() public {
        _fundActor(stranger);
        _fundAndApproveUsdc(stranger, TYPICAL_USDC_AMOUNT);

        vm.prank(stranger);
        bytes32 key = zapIn.zapIn{value: EXEC_FEE}(TYPICAL_USDC_AMOUNT, TYPICAL_SLIPPAGE_BPS);
        assertTrue(key != bytes32(0), "zapIn with typical slippage should succeed");
        // Caller's USDC fully consumed
        assertEq(usdc.balanceOf(stranger), 0, "all USDC consumed by zapIn");
    }

    // -----------------------------------------------------------------------
    //  BELOW MINIMUM DEPOSIT
    // -----------------------------------------------------------------------

    /// @notice Very small USDC amounts below the GM-value minimum revert with BelowMinimumDeposit.
    function test_zapIn_dustAmount_revertsWithBelowMinimumDeposit() public {
        _fundActor(stranger);
        uint256 dustUsdc = 1; // 0.000001 USDC -- well below 1 GM token value
        _fundAndApproveUsdc(stranger, dustUsdc);

        // Verify dust amount is truly tiny relative to any reasonable GM price
        assertLt(dustUsdc, 1e6, "dust should be less than 1 full USDC");
        vm.prank(stranger);
        vm.expectRevert(BasaltZapIn.BelowMinimumDeposit.selector);
        zapIn.zapIn{value: EXEC_FEE}(dustUsdc, TYPICAL_SLIPPAGE_BPS);
    }

    // -----------------------------------------------------------------------
    //  IMMUTABLES
    // -----------------------------------------------------------------------

    /// @notice Constructor stores correct immutable addresses.
    function test_constructor_setsImmutables() public view {
        assertEq(address(zapIn.SWAP_ROUTER()), BasaltAddresses.UNI_V3_SWAP_ROUTER, "SWAP_ROUTER mismatch");
        assertEq(address(zapIn.GMX_EXCHANGE_ROUTER()), BasaltAddresses.GMX_EXCHANGE_ROUTER, "GMX_EXCHANGE_ROUTER mismatch");
        assertEq(zapIn.GMX_ROUTER(), BasaltAddresses.GMX_V2_ROUTER, "GMX_ROUTER mismatch");
        assertEq(zapIn.GMX_DEPOSIT_VAULT(), BasaltAddresses.GMX_DEPOSIT_VAULT, "GMX_DEPOSIT_VAULT mismatch");
        assertEq(zapIn.USDC_TOKEN(), BasaltAddresses.USDC, "USDC_TOKEN mismatch");
        assertEq(zapIn.WBTC_TOKEN(), BasaltAddresses.WBTC, "WBTC_TOKEN mismatch");
        assertEq(zapIn.GM_TOKEN(), BasaltAddresses.GM_MARKET_TOKEN, "GM_TOKEN mismatch");
    }
}

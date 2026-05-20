// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {BasaltGmUnwrapper} from "../../../src/ux/BasaltGmUnwrapper.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";

/// @title BasaltGmUnwrapper Unit Tests
/// @notice Tests for the stateless GM -> (WBTC + USDC) convenience router.
contract BasaltGmUnwrapperUnit is ForkSetupFull {
    BasaltGmUnwrapper internal gmUnwrapper;

    IERC20 internal gmToken;

    uint256 internal constant TYPICAL_GM_AMOUNT = 1e18; // 1 GM token
    uint256 internal constant TYPICAL_SLIPPAGE_BPS = 100; // 1%
    uint256 internal constant EXEC_FEE = 0.01 ether;

    function setUp() public override {
        super.setUp();

        gmUnwrapper = new BasaltGmUnwrapper(
            BasaltGmUnwrapper.Config({
                exchangeRouter: BasaltAddresses.GMX_EXCHANGE_ROUTER,
                gmxRouter: BasaltAddresses.GMX_V2_ROUTER,
                gmxWithdrawalVault: BasaltAddresses.GMX_WITHDRAWAL_VAULT,
                gmToken: BasaltAddresses.GM_MARKET_TOKEN,
                wbtc: BasaltAddresses.WBTC,
                usdc: BasaltAddresses.USDC,
                gmxDataStore: BasaltAddresses.GMX_DATA_STORE,
                wbtcOracle: BasaltAddresses.CL_WBTC_USD,
                usdcOracle: BasaltAddresses.CL_USDC_USD,
                sequencerOracle: BasaltAddresses.CL_SEQUENCER
            })
        );

        gmToken = IERC20(BasaltAddresses.GM_MARKET_TOKEN);
    }

    // -----------------------------------------------------------------------
    //  Helpers
    // -----------------------------------------------------------------------

    /// @dev Deal GM tokens to `who` and approve gmUnwrapper contract.
    function _fundAndApproveGm(address who, uint256 amount) internal {
        deal(address(gmToken), who, amount);
        vm.prank(who);
        gmToken.approve(address(gmUnwrapper), amount);
    }

    // -----------------------------------------------------------------------
    //  PERMISSIONLESS ACCESS
    // -----------------------------------------------------------------------

    function test_unwrap_asStranger_doesNotRevertOnAuth() public {
        _fundActor(stranger);
        _fundAndApproveGm(stranger, TYPICAL_GM_AMOUNT);

        vm.prank(stranger);
        bytes32 key = gmUnwrapper.unwrap{value: EXEC_FEE}(TYPICAL_GM_AMOUNT, TYPICAL_SLIPPAGE_BPS);
        assertTrue(key != bytes32(0), "unwrap should return non-zero GMX request key");
        // GM tokens should be pulled from caller
        assertEq(gmToken.balanceOf(stranger), 0, "all GM pulled from stranger");
    }

    // -----------------------------------------------------------------------
    //  ENTRY POINT -- unwrap with GM tokens
    // -----------------------------------------------------------------------

    function test_unwrap_withGmTokens_initiatesWithdrawal() public {
        _fundActor(stranger);
        _fundAndApproveGm(stranger, TYPICAL_GM_AMOUNT);

        uint256 gmBefore = gmToken.balanceOf(stranger);

        vm.prank(stranger);
        bytes32 key = gmUnwrapper.unwrap{value: EXEC_FEE}(TYPICAL_GM_AMOUNT, TYPICAL_SLIPPAGE_BPS);

        uint256 gmAfter = gmToken.balanceOf(stranger);
        assertTrue(key != bytes32(0), "unwrap should return non-zero GMX request key");
        assertEq(gmAfter, gmBefore - TYPICAL_GM_AMOUNT, "unwrap should pull exact GM amount from caller");
    }

    function test_unwrap_emitsEvent() public {
        _fundActor(stranger);
        _fundAndApproveGm(stranger, TYPICAL_GM_AMOUNT);

        uint256 gmBefore = gmToken.balanceOf(stranger);
        vm.prank(stranger);
        vm.expectEmit(true, false, false, false, address(gmUnwrapper));
        emit BasaltGmUnwrapper.GmUnwrapSubmitted(stranger, 0, 0, 0, bytes32(0));
        gmUnwrapper.unwrap{value: EXEC_FEE}(TYPICAL_GM_AMOUNT, TYPICAL_SLIPPAGE_BPS);
        // GM pulled from caller alongside event emission
        assertEq(gmToken.balanceOf(stranger), gmBefore - TYPICAL_GM_AMOUNT, "GM pulled from caller");
    }

    // -----------------------------------------------------------------------
    //  ZERO AMOUNT
    // -----------------------------------------------------------------------

    function test_unwrap_zeroAmount_reverts() public {
        _fundActor(stranger);
        uint256 ethBefore = stranger.balance;
        vm.prank(stranger);
        vm.expectRevert(BasaltGmUnwrapper.ZeroAmount.selector);
        gmUnwrapper.unwrap{value: EXEC_FEE}(0, TYPICAL_SLIPPAGE_BPS);
        // ETH not consumed on revert
        assertEq(stranger.balance, ethBefore, "ETH not consumed on revert");
    }

    // -----------------------------------------------------------------------
    //  MISSING EXECUTION FEE
    // -----------------------------------------------------------------------

    function test_unwrap_zeroMsgValue_reverts() public {
        _fundActor(stranger);
        _fundAndApproveGm(stranger, TYPICAL_GM_AMOUNT);

        uint256 gmBefore = gmToken.balanceOf(stranger);
        vm.prank(stranger);
        vm.expectRevert(BasaltGmUnwrapper.MissingExecutionFee.selector);
        gmUnwrapper.unwrap{value: 0}(TYPICAL_GM_AMOUNT, TYPICAL_SLIPPAGE_BPS);
        // GM balance unchanged after revert
        assertEq(gmToken.balanceOf(stranger), gmBefore, "GM unchanged after revert");
    }

    // -----------------------------------------------------------------------
    //  INSUFFICIENT BALANCE
    // -----------------------------------------------------------------------

    function test_unwrap_insufficientBalance_reverts() public {
        _fundActor(stranger);
        assertEq(gmToken.balanceOf(stranger), 0, "stranger should have zero GM before test");
        vm.prank(stranger);
        gmToken.approve(address(gmUnwrapper), TYPICAL_GM_AMOUNT);

        vm.prank(stranger);
        vm.expectRevert(); // SafeERC20 transferFrom revert
        gmUnwrapper.unwrap{value: EXEC_FEE}(TYPICAL_GM_AMOUNT, TYPICAL_SLIPPAGE_BPS);
    }

    // -----------------------------------------------------------------------
    //  SLIPPAGE
    // -----------------------------------------------------------------------

    function test_unwrap_zeroSlippage_reverts() public {
        _fundActor(stranger);
        _fundAndApproveGm(stranger, TYPICAL_GM_AMOUNT);

        uint256 gmBefore = gmToken.balanceOf(stranger);
        vm.prank(stranger);
        vm.expectRevert(BasaltGmUnwrapper.InvalidSlippage.selector);
        gmUnwrapper.unwrap{value: EXEC_FEE}(TYPICAL_GM_AMOUNT, 0);
        // GM unchanged after revert
        assertEq(gmToken.balanceOf(stranger), gmBefore, "GM unchanged after slippage revert");
    }

    function test_unwrap_slippageAboveMax_reverts() public {
        _fundActor(stranger);
        _fundAndApproveGm(stranger, TYPICAL_GM_AMOUNT);

        uint256 aboveMax = BasaltConstants.GM_UNWRAPPER_MAX_SLIPPAGE_BPS + 1;
        assertGt(aboveMax, BasaltConstants.GM_UNWRAPPER_MAX_SLIPPAGE_BPS, "aboveMax must exceed cap");
        vm.prank(stranger);
        vm.expectRevert(BasaltGmUnwrapper.InvalidSlippage.selector);
        gmUnwrapper.unwrap{value: EXEC_FEE}(TYPICAL_GM_AMOUNT, aboveMax);
    }

    function test_unwrap_slippageAtMax_succeeds() public {
        _fundActor(stranger);
        _fundAndApproveGm(stranger, TYPICAL_GM_AMOUNT);

        vm.prank(stranger);
        bytes32 key = gmUnwrapper.unwrap{value: EXEC_FEE}(
            TYPICAL_GM_AMOUNT,
            BasaltConstants.GM_UNWRAPPER_MAX_SLIPPAGE_BPS
        );
        assertTrue(key != bytes32(0), "unwrap at max slippage should succeed");
        // GM pulled from caller
        assertEq(gmToken.balanceOf(stranger), 0, "all GM pulled at max slippage");
    }

    // -----------------------------------------------------------------------
    //  LEG CALCULATION
    // -----------------------------------------------------------------------

    ///         (non-zero and proportional to pool composition).
    function test_unwrap_calculatesCorrectLegs() public {
        _fundActor(stranger);
        uint256 largerGm = 10e18; // 10 GM tokens for more visible legs
        _fundAndApproveGm(stranger, largerGm);

        // unwrap submits the GMX withdrawal -- the min legs are computed internally.
        // We verify the call succeeds (i.e., the legs don't overflow or underflow)
        // and that the event is emitted with non-zero min amounts.
        vm.prank(stranger);
        vm.recordLogs();
        gmUnwrapper.unwrap{value: EXEC_FEE}(largerGm, TYPICAL_SLIPPAGE_BPS);

        // Event: GmUnwrapSubmitted(address indexed user, uint256 gmAmount,
        //        uint256 minLongWbtcE8, uint256 minShortUsdcE6, bytes32 indexed gmxRequestKey)
        // Indexed: user (topic[1]), gmxRequestKey (topic[2])
        // Data: gmAmount, minLongWbtcE8, minShortUsdcE6
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool found = false;
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == BasaltGmUnwrapper.GmUnwrapSubmitted.selector) {
                (uint256 gmAmount, uint256 minLong, uint256 minShort) =
                    abi.decode(entries[i].data, (uint256, uint256, uint256));
                assertEq(gmAmount, largerGm, "event gmAmount should match input");
                assertGt(minLong, 0, "minLongWbtcE8 should be non-zero for meaningful GM amount");
                assertGt(minShort, 0, "minShortUsdcE6 should be non-zero for meaningful GM amount");
                found = true;
                break;
            }
        }
        assertTrue(found, "GmUnwrapSubmitted event should be emitted");
    }

    // -----------------------------------------------------------------------
    //  IMMUTABLES
    // -----------------------------------------------------------------------

    function test_constructor_setsImmutables() public view {
        assertEq(address(gmUnwrapper.GMX_EXCHANGE_ROUTER()), BasaltAddresses.GMX_EXCHANGE_ROUTER, "GMX_EXCHANGE_ROUTER mismatch");
        assertEq(gmUnwrapper.GMX_ROUTER(), BasaltAddresses.GMX_V2_ROUTER, "GMX_ROUTER mismatch");
        assertEq(gmUnwrapper.GMX_WITHDRAWAL_VAULT(), BasaltAddresses.GMX_WITHDRAWAL_VAULT, "GMX_WITHDRAWAL_VAULT mismatch");
        assertEq(gmUnwrapper.GM_TOKEN(), BasaltAddresses.GM_MARKET_TOKEN, "GM_TOKEN mismatch");
        assertEq(gmUnwrapper.WBTC_TOKEN(), BasaltAddresses.WBTC, "WBTC_TOKEN mismatch");
        assertEq(gmUnwrapper.USDC_TOKEN(), BasaltAddresses.USDC, "USDC_TOKEN mismatch");
    }
}

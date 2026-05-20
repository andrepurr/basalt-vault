// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {VaultState} from "../../../src/core/VaultState.sol";
import {FeeAccountingHandler} from "../../../src/handlers/FeeAccountingHandler.sol";
import {IBasaltMath} from "../../../src/interfaces/IBasaltMath.sol";
import {IFeeAccountingHandlerVaultCore} from "../../../src/interfaces/IFeeAccountingHandlerVaultCore.sol";
import {IDepositHandlerVaultCore} from "../../../src/interfaces/IDepositHandlerVaultCore.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";
import {
    GmxEventUtils,
    IDepositCallbackReceiver
} from "../../../src/interfaces/IGmxCallbackReceiver.sol";

/// @title FeeAccountingHandlerUnit
/// @notice Unit tests for FeeAccountingHandler: access control, fee calculation correctness, and edge cases.
contract FeeAccountingHandlerUnit is ForkSetupFull {
    // ── Constants ────────────────────────────────────────────────────────────
    address internal constant DOLOMITE_AUTH_HANDLER = 0x1fF6B8E1192eB0369006Bbad76dA9068B68961B2;
    bytes32 internal constant SIG_ASYNC_DEPOSIT_CREATED =
        0x07483e098a6cfa5c67659e928fc3e7b08b3e60e09d57a7825c4becf2da6da2a7;

    uint256 internal constant PERF_FEE_BPS = 2_000; // 20%
    uint256 internal constant DEPOSIT_GM = 10e18;
    uint256 internal constant KEEPER_WRAP_GM = 2e18;

    function setUp() public override {
        super.setUp();
        _fundActor(vaultOwner);
        // managementFeeBps is auto-initialized to MANAGER_FEE_BPS (2_000) in VaultState.initialize()
        require(vaultState.managementFeeBps() == PERF_FEE_BPS, "management fee init drift");

        vm.prank(vaultOwner);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(address(depositHandler), type(uint256).max);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  ACCESS CONTROL (Priority 1)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Stranger cannot trigger fee accrual -- not authorized as initiator.
    function test_accrueManagerFee_asStranger_reverts() public {
        uint256 feeBefore = vaultState.managerAccruedFeeUsdE18();

        vm.prank(stranger);
        vm.expectRevert(FeeAccountingHandler.InvalidInitiator.selector);
        feeAccountingHandler.accrueManagerFee(
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath)),
            stranger
        );

        // Fee must not change after reverted call
        assertEq(vaultState.managerAccruedFeeUsdE18(), feeBefore, "fee must not change on revert");
    }

    /// @notice Stranger calling through themselves (not a handler slot) also reverts.
    function test_accrueManagerFee_strangerDirectCall_reverts() public {
        uint256 hwmBefore = vaultState.highWaterMarkProfitUsdE18();

        // Even if initiator is vaultOwner, caller must be in a handler slot or be initiator
        vm.prank(stranger);
        vm.expectRevert(FeeAccountingHandler.NotAuthorizedCaller.selector);
        feeAccountingHandler.accrueManagerFee(
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath)),
            vaultOwner
        );

        // HWM must not change after reverted call
        assertEq(vaultState.highWaterMarkProfitUsdE18(), hwmBefore, "HWM must not change on revert");
    }

    /// @notice Operational can accrue fee through managerContract (protocolManager path).
    function test_accrueManagerFee_asOperational_succeeds() public {
        // Setup: do a full deposit cycle so vault has a position
        _doFirstDepositCycle();

        uint256 hwmBefore = vaultState.highWaterMarkProfitUsdE18();

        // Accrue fee through managerContract (operational -> managerContract -> feeAccountingHandler)
        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );
        // Should not revert -- that's the success test
        // HWM should be >= before (unchanged or increased depending on profit)
        assertGe(vaultState.highWaterMarkProfitUsdE18(), hwmBefore, "HWM should not decrease after accrual");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  FEE CALCULATION CORRECTNESS (Priority 2)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice After profit accrual, highWaterMark increases.
    function test_accrueManagerFee_withProfit_updatesHwm() public {
        _doFirstDepositCycle();
        uint256 hwmBefore = vaultState.highWaterMarkProfitUsdE18();

        // Simulate profit: reduce totalDepositedUsdE18 so profit = NAV - deposited + withdrawn > 0
        // totalDepositedUsdE18 is at slot 17 of VaultState
        _simulateProfit();

        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        uint256 hwmAfter = vaultState.highWaterMarkProfitUsdE18();
        assertGt(hwmAfter, hwmBefore, "HWM should increase after profit accrual");
    }

    /// @notice When NAV <= HWM (no new profit), no fee accrues.
    function test_accrueManagerFee_withNoProfit_hwmUnchanged() public {
        _doFirstDepositCycle();

        // Accrue once to set baseline HWM with profit
        _simulateProfit();

        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        uint256 hwmAfterFirst = vaultState.highWaterMarkProfitUsdE18();
        uint256 feeAfterFirst = vaultState.managerAccruedFeeUsdE18();

        // Accrue again without any additional profit -- NAV unchanged
        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        uint256 hwmAfterSecond = vaultState.highWaterMarkProfitUsdE18();
        uint256 feeAfterSecond = vaultState.managerAccruedFeeUsdE18();

        assertEq(hwmAfterSecond, hwmAfterFirst, "HWM should not change without new profit");
        assertEq(feeAfterSecond, feeAfterFirst, "Accrued fee should not change without new profit");
    }

    /// @notice Accrued fee is bounded: fee <= profitDelta * PERF_FEE_BPS / BPS.
    function test_accrueManagerFee_accruedFeeWithinBounds() public {
        _doFirstDepositCycle();
        _simulateProfit();

        uint256 feeBefore = vaultState.managerAccruedFeeUsdE18();

        // Calculate expected fee via view function before accrual
        (,, uint256 profitDelta, uint256 performanceFee,,) = feeAccountingHandler.calculateManagerFee(
            IFeeAccountingHandlerVaultCore(address(vaultCore)), IBasaltMath(address(basaltMath))
        );

        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        uint256 feeAfter = vaultState.managerAccruedFeeUsdE18();
        uint256 feeAccrued = feeAfter - feeBefore;

        // Fee should be exactly performanceFee from view
        assertEq(feeAccrued, performanceFee, "accrued fee should match calculateManagerFee result");

        // performanceFee <= profitDelta * PERF_FEE_BPS / BPS
        uint256 maxFee = (profitDelta * PERF_FEE_BPS) / BasaltConstants.BPS;
        assertLe(performanceFee, maxFee, "performance fee should be <= profitDelta * feeBps / BPS");
    }

    /// @notice calculateManagerFee view returns same values as what accrueManagerFee sets.
    function test_calculateManagerFee_matchesAccrued() public {
        _doFirstDepositCycle();
        _simulateProfit();

        // Read view result
        (,,, uint256 viewFee, uint256 viewHwm, uint256 viewAccruedFee) = feeAccountingHandler.calculateManagerFee(
            IFeeAccountingHandlerVaultCore(address(vaultCore)), IBasaltMath(address(basaltMath))
        );

        // Accrue
        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        if (viewFee > 0) {
            assertEq(vaultState.highWaterMarkProfitUsdE18(), viewHwm, "HWM should match view prediction");
            assertEq(vaultState.managerAccruedFeeUsdE18(), viewAccruedFee, "accrued fee should match view prediction");
        }
    }

    /// @notice Calling accrueManagerFee twice without new profit doesn't double-accrue.
    function test_accrueManagerFee_calledTwice_idempotent() public {
        _doFirstDepositCycle();
        _simulateProfit();

        // Accrue first time
        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        uint256 feeAfterFirst = vaultState.managerAccruedFeeUsdE18();
        uint256 hwmAfterFirst = vaultState.highWaterMarkProfitUsdE18();

        // Accrue second time (no new profit)
        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        uint256 feeAfterSecond = vaultState.managerAccruedFeeUsdE18();
        uint256 hwmAfterSecond = vaultState.highWaterMarkProfitUsdE18();

        assertEq(feeAfterSecond, feeAfterFirst, "double accrual should not increase fee");
        assertEq(hwmAfterSecond, hwmAfterFirst, "double accrual should not increase HWM");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  EDGE CASES
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Empty vault (no isolation vault): calculateManagerFee returns zero fee.
    function test_calculateManagerFee_emptyVault_returnsZero() public view {
        (, uint256 profit,, uint256 performanceFee,,) = feeAccountingHandler.calculateManagerFee(
            IFeeAccountingHandlerVaultCore(address(vaultCore)), IBasaltMath(address(basaltMath))
        );
        assertEq(profit, 0, "empty vault should have zero profit");
        assertEq(performanceFee, 0, "empty vault should have zero performance fee");
    }

    /// @notice Accruing on empty vault should not revert and should not change state.
    function test_accrueManagerFee_emptyVault_noRevert() public {
        uint256 hwmBefore = vaultState.highWaterMarkProfitUsdE18();
        uint256 feeBefore = vaultState.managerAccruedFeeUsdE18();

        // Accrue on empty vault through managerContract
        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        assertEq(vaultState.highWaterMarkProfitUsdE18(), hwmBefore, "HWM unchanged on empty vault");
        assertEq(vaultState.managerAccruedFeeUsdE18(), feeBefore, "fee unchanged on empty vault");
    }

    /// @notice NftOwner can also accrue fee directly (initiator = self, caller = self).
    function test_accrueManagerFee_asNftOwnerDirect_succeeds() public {
        _doFirstDepositCycle();

        uint256 feeBefore = vaultState.managerAccruedFeeUsdE18();

        vm.prank(vaultOwner);
        feeAccountingHandler.accrueManagerFee(
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath)),
            vaultOwner
        );
        // Should not revert; fee should be >= before
        assertGe(vaultState.managerAccruedFeeUsdE18(), feeBefore, "fee must not decrease after direct accrual");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  REGRESSION — BAS-1 (performance fee was always zero)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice REGRESSION BAS-1: performance fee actually accrues non-zero after profit.
    /// @dev    Pre-fix: `targetVaultCore.performanceFeeBps()` returned 0 (uninitialized
    ///         storage in VaultCore) → `performanceFeeUsdE18 = profitDelta * 0 / BPS = 0`.
    ///         Post-fix: reads `vaultState.managementFeeBps()` (auto-initialized to
    ///         `MANAGER_FEE_BPS = 2_000` in `VaultState.initialize`) → fee = 20% of profitDelta.
    function test_accrueManagerFee_BAS1_feeAccruesNonZero_regression() public {
        _doFirstDepositCycle();
        _simulateProfit();

        // 1. View predicts non-zero fee.
        (, , uint256 profitDelta, uint256 expectedFee, , ) = feeAccountingHandler.calculateManagerFee(
            IFeeAccountingHandlerVaultCore(address(vaultCore)), IBasaltMath(address(basaltMath))
        );
        assertGt(profitDelta, 0, "profitDelta must be > 0 after _simulateProfit");
        assertGt(expectedFee, 0, "BAS-1 regression: expected fee must be > 0 (was always 0 pre-fix)");
        assertEq(
            expectedFee, (profitDelta * PERF_FEE_BPS) / BasaltConstants.BPS,
            "fee formula: profitDelta * managementFeeBps / BPS"
        );

        // 2. Source of truth for bps is VaultState, not VaultCore.
        assertEq(vaultState.managementFeeBps(), PERF_FEE_BPS, "VaultState owns managementFeeBps = 2_000");

        // 3. Operational prank: accrual writes the exact predicted fee into VaultState.
        uint256 feeBefore = vaultState.managerAccruedFeeUsdE18();
        uint256 hwmBefore = vaultState.highWaterMarkProfitUsdE18();

        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        uint256 feeAfter = vaultState.managerAccruedFeeUsdE18();
        uint256 hwmAfter = vaultState.highWaterMarkProfitUsdE18();

        assertEq(feeAfter - feeBefore, expectedFee, "BAS-1: accrued delta must match view prediction");
        assertGt(feeAfter, feeBefore, "BAS-1: managerAccruedFeeUsdE18 must increase (was unchanged pre-fix)");
        assertGt(hwmAfter, hwmBefore, "HWM ratchets up after profit");
    }

    /// @notice REGRESSION BAS-1: zero `managementFeeBps` reproduces the pre-fix bug
    ///         (no fee accrues), confirming the formula path actually depends on the
    ///         storage we wired through. Uses a fresh VaultState clone via storage write
    ///         on slot of `managementFeeBps` to bypass the only-decrease setter constraint.
    function test_accrueManagerFee_BAS1_zeroBpsProducesZeroFee_negativeControl() public {
        _doFirstDepositCycle();
        _simulateProfit();

        // managementFeeBps is at slot 21 of VaultState (verified via inspection: see contract layout above).
        // Force-zero it via vm.store to prove the math reads from VaultState (negative control).
        bytes32 slot = _findManagementFeeBpsSlot();
        vm.store(address(vaultState), slot, bytes32(uint256(0)));
        assertEq(vaultState.managementFeeBps(), 0, "vm.store: managementFeeBps must be 0");

        (, , uint256 profitDelta, uint256 expectedFee, , ) = feeAccountingHandler.calculateManagerFee(
            IFeeAccountingHandlerVaultCore(address(vaultCore)), IBasaltMath(address(basaltMath))
        );
        assertGt(profitDelta, 0, "profit still present");
        assertEq(expectedFee, 0, "fee must be 0 when managementFeeBps = 0 (pre-fix behavior reproduced)");

        uint256 feeBefore = vaultState.managerAccruedFeeUsdE18();

        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );

        assertEq(
            vaultState.managerAccruedFeeUsdE18(), feeBefore,
            "no fee accrual when bps = 0 (proves storage source is VaultState)"
        );
    }

    /// @dev Locate `managementFeeBps` slot dynamically — robust against future storage reordering.
    function _findManagementFeeBpsSlot() internal view returns (bytes32) {
        for (uint256 i = 0; i < 64; i++) {
            if (uint256(vm.load(address(vaultState), bytes32(i))) == PERF_FEE_BPS) {
                return bytes32(i);
            }
        }
        revert("managementFeeBps slot not found");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  HELPERS
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Simulate profit by reducing totalDepositedUsdE18 to 1 wei so that
    ///      profit = NAV - deposited + withdrawn > 0. Uses vm.store on VaultState
    ///      slot 19 (totalDepositedUsdE18). This is the most reliable way to create
    ///      profit on a pinned fork where Dolomite prices are fixed.
    function _simulateProfit() internal {
        // slot 19 = totalDepositedUsdE18 in VaultState storage layout (verified via forge inspect)
        vm.store(address(vaultState), bytes32(uint256(19)), bytes32(uint256(1)));
        assertEq(vaultState.totalDepositedUsdE18(), 1, "totalDepositedUsdE18 should be 1 after store");
    }

    /// @dev Execute a full first deposit cycle: deposit -> GMX callback -> cooldown -> finalize.
    function _doFirstDepositCycle() internal {
        deal(BasaltAddresses.GM_MARKET_TOKEN, vaultOwner, 100e18);

        _rollCooldown();
        vm.recordLogs();
        vm.prank(vaultOwner);
        depositHandler.deposit{value: _firstDepositMsgValue()}(
            IDepositHandlerVaultCore(address(vaultCore)), DEPOSIT_GM, 500
        );
        bytes32 key = _captureLatestAsyncDepositKey();

        _simulateGmxDepositExecutionWithGm(key, KEEPER_WRAP_GM);

        _rollCooldown();
        vm.prank(operational);
        managerContract.finalizeDeposit(depositHandler, IDepositHandlerVaultCore(address(vaultCore)));
    }

    function _rollCooldown() internal {
        uint256 endBlock = vaultState.globalActionCooldownEndBlock();
        if (block.number <= endBlock) {
            vm.roll(endBlock + 1);
        }
    }

    function _captureLatestAsyncDepositKey() internal returns (bytes32 key) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length >= 2 && logs[i].topics[0] == SIG_ASYNC_DEPOSIT_CREATED) {
                key = logs[i].topics[1];
            }
        }
        require(key != bytes32(0), "_captureLatestAsyncDepositKey: not found");
    }

    function _simulateGmxDepositExecutionWithGm(bytes32 key, uint256 gmReceivedE18) internal {
        deal(BasaltAddresses.GM_MARKET_TOKEN, _dolomiteGmWrapper(), gmReceivedE18);

        GmxEventUtils.EventLogData memory depositData;
        depositData.uintItems.items = new GmxEventUtils.UintKeyValue[](1);
        depositData.uintItems.items[0] =
            GmxEventUtils.UintKeyValue({key: "minMarketTokens", value: 1});

        GmxEventUtils.EventLogData memory eventData;
        eventData.uintItems.items = new GmxEventUtils.UintKeyValue[](1);
        eventData.uintItems.items[0] =
            GmxEventUtils.UintKeyValue({key: "receivedMarketTokens", value: gmReceivedE18});

        vm.prank(DOLOMITE_AUTH_HANDLER);
        IDepositCallbackReceiver(_dolomiteGmWrapper()).afterDepositExecution(key, depositData, eventData);
    }
}

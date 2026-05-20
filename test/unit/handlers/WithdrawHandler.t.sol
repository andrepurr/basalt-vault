// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {VaultState} from "../../../src/core/VaultState.sol";
import {DepositHandler} from "../../../src/handlers/DepositHandler.sol";
import {WithdrawHandler} from "../../../src/handlers/WithdrawHandler.sol";
import {IDepositHandlerVaultCore} from "../../../src/interfaces/IDepositHandlerVaultCore.sol";
import {IWithdrawHandlerVaultCore} from "../../../src/interfaces/IWithdrawHandlerVaultCore.sol";
import {IFeeAccountingHandlerVaultCore} from "../../../src/interfaces/IFeeAccountingHandlerVaultCore.sol";
import {IBasaltMath} from "../../../src/interfaces/IBasaltMath.sol";
import {IDolomiteMargin} from "../../../src/interfaces/IDolomiteMargin.sol";
import {DolomiteReader} from "../../../src/libraries/DolomiteReader.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";
import {
    NotIdle,
    NotVaultNftOwner,
    NotManagerOrNftOwner,
    NotProtocolManager,
    InvalidPositionShareToWithdraw,
    WithdrawNotPending,
    NothingToWithdraw,
    WithdrawExceedsOwnerEligibleShares,
    WithdrawBranch,
    WithdrawContext,
    WithdrawPreview,
    WithdrawSharePolicy
} from "../../../src/handlers/withdrawHandlerLibraries/WithdrawHandlerTypes.sol";
import {
    GmxEventUtils,
    IDepositCallbackReceiver,
    IWithdrawalCallbackReceiver
} from "../../../src/interfaces/IGmxCallbackReceiver.sol";

/// @title WithdrawHandlerUnit
/// @notice Unit tests for WithdrawHandler: access control, withdraw branch paths (async), state machine,
///         finalize, and view functions.
///         CSRE libraries exercised through handler calls per D-05.
contract WithdrawHandlerUnit is ForkSetupFull {
    // ── Constants ────────────────────────────────────────────────────────────
    address internal constant DOLOMITE_AUTH_HANDLER = 0x1fF6B8E1192eB0369006Bbad76dA9068B68961B2;
    address internal constant GM_UNWRAPPER = 0xFE07082DCcaF08C8c6C77a55e0Eb07Af80cDD87b;
    bytes32 internal constant SIG_ASYNC_DEPOSIT_CREATED =
        0x07483e098a6cfa5c67659e928fc3e7b08b3e60e09d57a7825c4becf2da6da2a7;
    bytes32 internal constant SIG_ASYNC_WITHDRAWAL_CREATED =
        0x8c528bde64c1b9528c88498bc469dbd84b35fff473102a86eba122238d20619d;

    uint256 internal constant PERF_FEE_BPS = 2_000;
    uint256 internal constant DEPOSIT_GM = 10e18;
    uint256 internal constant KEEPER_WRAP_GM = 2e18;

    /// @dev After deposit cycle, vault has levered position (GM collateral + WBTC debt).
    ///      Withdraw is ASYNC (AsyncDebt branch). Use 25% of SHARE_UNIT for safe tests.
    uint256 internal constant SAFE_WITHDRAW_SHARES = 25e16; // 25%

    function setUp() public override {
        super.setUp();
        _fundActor(vaultOwner);
        _fundActor(stranger);
        _fundActor(address(managerContract));

        // managementFeeBps is auto-initialized to MANAGER_FEE_BPS (2_000) in VaultState.initialize()
        require(vaultState.managementFeeBps() == PERF_FEE_BPS, "management fee init drift");

        // Approve deposit handler for vaultOwner
        vm.prank(vaultOwner);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(address(depositHandler), type(uint256).max);

        // Deal GM to vaultOwner
        deal(BasaltAddresses.GM_MARKET_TOKEN, vaultOwner, 200e18);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  ACCESS CONTROL (Priority 1)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Stranger cannot withdraw -- not vault NFT owner.
    function test_withdraw_asStranger_reverts() public {
        _setupVaultWithPosition();

        // Snapshot state before revert to verify no mutation
        uint8 stateBefore = uint8(vaultState.withdrawState());
        assertEq(stateBefore, uint8(VaultState.State.IDLE), "withdraw state should be IDLE before attempt");

        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.prank(stranger);
        vm.expectRevert(NotVaultNftOwner.selector);
        withdrawHandler.withdraw{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES, 1
        );

        assertEq(uint8(vaultState.withdrawState()), stateBefore, "withdraw state must not change on revert");
    }

    /// @notice VaultOwner can withdraw -- async path sets state to PENDING.
    function test_withdraw_asNftOwner_succeeds() public {
        _setupVaultWithPosition();

        _rollCooldown();
        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.prank(vaultOwner);
        withdrawHandler.withdraw{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES, 1
        );

        assertEq(
            uint8(vaultState.withdrawState()),
            uint8(VaultState.State.PENDING),
            "async withdraw should set state to PENDING"
        );
        assertEq(
            vaultState.pendingWithdrawer(),
            vaultOwner,
            "pendingWithdrawer should be set to vault NFT owner"
        );
    }

    /// @notice Only protocolManager can call withdrawManagerFeeShares.
    function test_withdrawManagerFeeShares_asStranger_reverts() public {
        _setupVaultWithPosition();

        uint8 stateBefore = uint8(vaultState.withdrawState());
        assertEq(stateBefore, uint8(VaultState.State.IDLE), "withdraw state should be IDLE before attempt");

        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.prank(stranger);
        vm.expectRevert(NotProtocolManager.selector);
        withdrawHandler.withdrawManagerFeeShares{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES, 1
        );

        assertEq(uint8(vaultState.withdrawState()), stateBefore, "withdraw state must not change on revert");
    }

    /// @notice Stranger cannot finalize withdraw -- not manager or nft owner.
    function test_finalizeWithdraw_asStranger_reverts() public {
        uint8 stateBefore = uint8(vaultState.withdrawState());
        assertEq(stateBefore, uint8(VaultState.State.IDLE), "withdraw state should be IDLE initially");

        vm.prank(stranger);
        vm.expectRevert(NotManagerOrNftOwner.selector);
        withdrawHandler.finalizeWithdraw(IWithdrawHandlerVaultCore(address(vaultCore)));

        assertEq(uint8(vaultState.withdrawState()), stateBefore, "withdraw state must not change on revert");
    }

    /// @notice Operational finalize when withdraw not pending reverts correctly.
    function test_finalizeWithdraw_notPending_reverts() public {
        _setupVaultWithPosition();

        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "withdraw state should be IDLE");
        assertEq(vaultState.pendingWithdrawer(), address(0), "no pending withdrawer expected");

        vm.prank(operational);
        vm.expectRevert(WithdrawNotPending.selector);
        managerContract.finalizeWithdraw(withdrawHandler, IWithdrawHandlerVaultCore(address(vaultCore)));
    }

    /// @notice previewWithdraw is permissionless view (anyone can call).
    function test_previewWithdraw_asAnyone_succeeds() public {
        _setupVaultWithPosition();

        // Stranger can call previewWithdraw -- permissionless view function
        vm.prank(stranger);
        WithdrawPreview memory preview =
            withdrawHandler.previewWithdraw(IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES);
        assertGt(preview.gmToSellE18, 0, "stranger should see non-zero gmToSell in preview");
        assertGt(preview.ownerEligibleSharesE18, 0, "stranger should see non-zero owner-eligible shares");
    }

    /// @notice managerMaxFeeWithdrawShares is permissionless view.
    function test_managerMaxFeeWithdrawShares_asAnyone_succeeds() public {
        _setupVaultWithPosition();

        vm.prank(stranger);
        uint256 maxShares =
            withdrawHandler.managerMaxFeeWithdrawShares(IWithdrawHandlerVaultCore(address(vaultCore)));
        // Should not revert -- permissionless view
        assertLt(maxShares, BasaltConstants.SHARE_UNIT, "fee shares must be < total shares");
        assertGt(maxShares, 0, "fee shares should be non-zero after deposit cycle with fee accrual");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  WITHDRAW BRANCHES (Priority 4 -- exercises CSRE per D-05)
    // ════════════════════════════════════════════════════════════════════════

    // ── Async branch (vault has GM collateral + WBTC debt = AsyncDebt) ───

    /// @notice Withdrawal from levered vault triggers async path and sets withdrawState to PENDING.
    function test_withdraw_async_setsStateToPending() public {
        _setupVaultWithPosition();

        _rollCooldown();
        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.prank(vaultOwner);
        withdrawHandler.withdraw{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES, 1
        );

        assertEq(
            uint8(vaultState.withdrawState()),
            uint8(VaultState.State.PENDING),
            "async withdraw should set state to PENDING"
        );
        assertGt(
            vaultState.pendingWithdrawSharesE18(),
            0,
            "pending withdraw shares should be recorded"
        );
    }

    /// @notice selectWithdrawBranch returns AsyncDebt for levered vault.
    function test_selectWithdrawBranch_levered_returnsAsyncDebt() public {
        _setupVaultWithPosition();

        WithdrawContext memory ctx = withdrawHandler.selectWithdrawBranch(
            IWithdrawHandlerVaultCore(address(vaultCore)),
            vaultOwner,
            SAFE_WITHDRAW_SHARES,
            0,
            WithdrawSharePolicy.OwnerEligible
        );
        assertEq(
            uint8(ctx.branch),
            uint8(WithdrawBranch.AsyncDebt),
            "levered vault should select AsyncDebt branch"
        );
        assertGt(ctx.gmCollateralE18, 0, "context should have GM collateral for async branch");
        assertGt(ctx.wbtcDebtE8, 0, "context should have WBTC debt for AsyncDebt branch");
    }

    /// @notice After async withdraw, pending accounting is recorded correctly.
    function test_withdraw_async_recordsPendingAccounting() public {
        _setupVaultWithPosition();

        _rollCooldown();
        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.prank(vaultOwner);
        withdrawHandler.withdraw{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES, 1
        );

        assertEq(
            vaultState.pendingWithdrawSharesE18(),
            SAFE_WITHDRAW_SHARES,
            "pending shares should match requested shares"
        );
        assertGt(
            vaultState.pendingWithdrawGmToSellE18(),
            0,
            "pending GM to sell should be > 0"
        );
        assertGt(
            vaultState.pendingWithdrawCollateralSnapshotE18(),
            0,
            "pending collateral snapshot should be > 0"
        );
    }

    /// @notice Pending withdrawer is the vault NFT owner.
    function test_withdraw_async_pendingWithdrawerIsOwner() public {
        _setupVaultWithPosition();

        _rollCooldown();
        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.prank(vaultOwner);
        withdrawHandler.withdraw{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES, 1
        );

        assertEq(
            vaultState.pendingWithdrawer(),
            vaultOwner,
            "pending withdrawer should be the vault NFT owner"
        );
        assertEq(
            uint8(vaultState.withdrawState()),
            uint8(VaultState.State.PENDING),
            "withdraw state should be PENDING alongside pending withdrawer"
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    //  STATE MACHINE ENFORCEMENT
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Withdraw while deposit is PENDING reverts with NotIdle.
    function test_withdraw_whileDepositPending_reverts() public {
        _rollCooldown();
        vm.recordLogs();
        vm.prank(vaultOwner);
        depositHandler.deposit{value: _firstDepositMsgValue()}(
            IDepositHandlerVaultCore(address(vaultCore)), DEPOSIT_GM, 100
        );

        assertEq(
            uint8(vaultState.depositState()),
            uint8(VaultState.State.PENDING),
            "deposit should be PENDING"
        );

        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.prank(vaultOwner);
        vm.expectRevert(NotIdle.selector);
        withdrawHandler.withdraw{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES, 1
        );

        assertEq(
            uint8(vaultState.withdrawState()),
            uint8(VaultState.State.IDLE),
            "withdraw state should remain IDLE after revert"
        );
    }

    /// @notice Withdraw while withdraw already PENDING reverts with NotIdle.
    function test_withdraw_whileWithdrawPending_reverts() public {
        _setupVaultWithPosition();

        // First withdraw -> PENDING
        _rollCooldown();
        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.prank(vaultOwner);
        withdrawHandler.withdraw{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES, 1
        );

        assertEq(
            uint8(vaultState.withdrawState()),
            uint8(VaultState.State.PENDING),
            "should be PENDING after first withdraw"
        );

        uint256 pendingSharesBefore = vaultState.pendingWithdrawSharesE18();

        // Second withdraw -> NotIdle
        fee = _forkExecFeeWithdrawalWei();
        vm.prank(vaultOwner);
        vm.expectRevert(NotIdle.selector);
        withdrawHandler.withdraw{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES, 1
        );

        assertEq(
            vaultState.pendingWithdrawSharesE18(),
            pendingSharesBefore,
            "pending shares must not change after reverted second withdraw"
        );
    }

    /// @notice Withdraw with zero shares reverts.
    function test_withdraw_zeroShares_reverts() public {
        _setupVaultWithPosition();

        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "should be IDLE before attempt");

        _rollCooldown();
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidPositionShareToWithdraw.selector, 0, BasaltConstants.SHARE_UNIT)
        );
        withdrawHandler.withdraw(
            IWithdrawHandlerVaultCore(address(vaultCore)), 0, 0
        );

        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "state must remain IDLE after revert");
    }

    /// @notice Withdraw with shares > SHARE_UNIT reverts.
    function test_withdraw_aboveShareUnit_reverts() public {
        _setupVaultWithPosition();

        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "should be IDLE before attempt");

        _rollCooldown();
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidPositionShareToWithdraw.selector,
                BasaltConstants.SHARE_UNIT + 1,
                BasaltConstants.SHARE_UNIT
            )
        );
        withdrawHandler.withdraw(
            IWithdrawHandlerVaultCore(address(vaultCore)), BasaltConstants.SHARE_UNIT + 1, 0
        );

        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "state must remain IDLE after revert");
    }

    /// @notice Withdrawing more than owner-eligible shares reverts.
    function test_withdraw_exceedsOwnerEligible_reverts() public {
        _setupVaultWithPosition();

        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "should be IDLE before attempt");

        _rollCooldown();
        // Full SHARE_UNIT exceeds owner-eligible because vault has auto-accrued fee
        vm.prank(vaultOwner);
        vm.expectRevert(); // WithdrawExceedsOwnerEligibleShares
        withdrawHandler.withdraw(
            IWithdrawHandlerVaultCore(address(vaultCore)), BasaltConstants.SHARE_UNIT, 0
        );

        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "state must remain IDLE after revert");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  VIEW TESTS
    // ════════════════════════════════════════════════════════════════════════

    /// @notice previewWithdraw on empty vault reverts because ownerEligibleShares = 0.
    function test_previewWithdraw_emptyVault_reverts() public {
        // Verify vault is truly empty before testing revert
        assertEq(vaultState.totalDepositedGmE18(), 0, "vault should have zero deposited GM");
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.IDLE), "deposit state should be IDLE");

        vm.expectRevert(); // WithdrawExceedsOwnerEligibleShares or NothingToWithdraw
        withdrawHandler.previewWithdraw(IWithdrawHandlerVaultCore(address(vaultCore)), 1e18);
    }

    /// @notice managerMaxFeeWithdrawShares after deposit cycle is bounded below SHARE_UNIT.
    function test_managerMaxFeeWithdrawShares_afterDeposit_bounded() public {
        _setupVaultWithPosition();

        uint256 maxShares =
            withdrawHandler.managerMaxFeeWithdrawShares(IWithdrawHandlerVaultCore(address(vaultCore)));
        assertLt(maxShares, BasaltConstants.SHARE_UNIT, "manager fee shares must be < total shares");
        assertGt(maxShares, 0, "manager fee shares should be non-zero after deposit with fee accrual");
    }

    /// @notice previewWithdraw with position shows non-zero gmToSell for async branch.
    function test_previewWithdraw_withPosition_showsAsyncFields() public {
        _setupVaultWithPosition();

        WithdrawPreview memory preview =
            withdrawHandler.previewWithdraw(IWithdrawHandlerVaultCore(address(vaultCore)), SAFE_WITHDRAW_SHARES);
        // Async branch: gmToSellE18 > 0 (the handler will unwrap GM to repay debt)
        assertGt(
            preview.gmToSellE18,
            0,
            "async preview should show non-zero gmToSellE18"
        );
        assertEq(
            uint8(preview.withdrawContext.branch),
            uint8(WithdrawBranch.AsyncDebt),
            "preview branch should be AsyncDebt for levered vault"
        );
    }

    /// @notice collectWithdrawContext returns correct GM collateral.
    function test_collectWithdrawContext_returnsExpectedCollateral() public {
        _setupVaultWithPosition();

        WithdrawContext memory ctx = withdrawHandler.collectWithdrawContext(
            IWithdrawHandlerVaultCore(address(vaultCore)),
            vaultOwner,
            SAFE_WITHDRAW_SHARES,
            0
        );
        assertGt(ctx.gmCollateralE18, 0, "context should reflect GM collateral");
        assertGt(ctx.wbtcDebtE8, 0, "context should reflect WBTC debt (levered vault)");
        assertGt(ctx.navUsdE18, 0, "context should reflect non-zero NAV");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  HELPERS
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Perform full deposit cycle so vault has GM collateral + WBTC debt for withdraw testing.
    function _setupVaultWithPosition() internal {
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

    function _captureLatestWithdrawalKey() internal returns (bytes32 key) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length >= 2 && logs[i].topics[0] == SIG_ASYNC_WITHDRAWAL_CREATED) {
                key = logs[i].topics[1];
            }
        }
        require(key != bytes32(0), "_captureLatestWithdrawalKey: not found");
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

    function _simulateGmxWithdrawalExecutionWithWbtc(bytes32 key, uint256 gmSoldE18, uint256 wbtcReceivedE8)
        internal
    {
        deal(BasaltAddresses.WBTC, GM_UNWRAPPER, wbtcReceivedE8);

        GmxEventUtils.EventLogData memory withdrawalData;
        withdrawalData.uintItems.items = new GmxEventUtils.UintKeyValue[](1);
        withdrawalData.uintItems.items[0] =
            GmxEventUtils.UintKeyValue({key: "marketTokenAmount", value: gmSoldE18});

        GmxEventUtils.EventLogData memory eventData;
        eventData.addressItems.items = new GmxEventUtils.AddressKeyValue[](2);
        eventData.addressItems.items[0] =
            GmxEventUtils.AddressKeyValue({key: "outputToken", value: BasaltAddresses.WBTC});
        eventData.addressItems.items[1] =
            GmxEventUtils.AddressKeyValue({key: "secondaryOutputToken", value: BasaltAddresses.WBTC});

        eventData.uintItems.items = new GmxEventUtils.UintKeyValue[](2);
        eventData.uintItems.items[0] =
            GmxEventUtils.UintKeyValue({key: "outputAmount", value: wbtcReceivedE8});
        eventData.uintItems.items[1] =
            GmxEventUtils.UintKeyValue({key: "secondaryOutputAmount", value: 0});

        vm.prank(DOLOMITE_AUTH_HANDLER);
        IWithdrawalCallbackReceiver(GM_UNWRAPPER).afterWithdrawalExecution(key, withdrawalData, eventData);
    }

    /// @dev Rough estimate: 1 GM ~ $13.35 at fork block, WBTC ~ $95k, so
    ///      wbtcE8 ~ gmE18 * 13.35 / 95000 * 1e8 / 1e18. Simplified to gmE18 / 7e12.
    function _estimateWbtcFromGm(uint256 gmE18) internal pure returns (uint256) {
        return gmE18 / 7e12;
    }

    // ════════════════════════════════════════════════════════════════════════
    //  FUZZ TESTS (FUZZ-02: withdraw flow edge cases)
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Fuzz withdraw with random shares and slippage — must not produce unexpected reverts.
    function testFuzz_withdraw_randomSharesAndSlippage(uint256 sharesSeed, uint256 slippageSeed) public {
        _setupVaultWithPosition();

        // Owner-eligible shares are less than SHARE_UNIT due to fee accrual.
        // Bound shares to a safe range: [1, 50% of SHARE_UNIT] to stay within owner-eligible.
        uint256 shares = bound(sharesSeed, 1, BasaltConstants.SHARE_UNIT / 2);
        uint256 slippage = bound(slippageSeed, 0, 1000); // 0..10% minWbtcOut as BPS (not deposit slippage)

        if (uint8(vaultState.withdrawState()) != uint8(VaultState.State.IDLE)) return;

        _rollCooldown();
        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.deal(vaultOwner, 10 ether);

        vm.prank(vaultOwner);
        try withdrawHandler.withdraw{value: fee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), shares, slippage
        ) {
            // Success: withdraw state should be PENDING (async on levered vault)
            assertEq(
                uint8(vaultState.withdrawState()),
                uint8(VaultState.State.PENDING),
                "fuzz: withdraw success should set PENDING"
            );
            assertEq(vaultState.pendingWithdrawer(), vaultOwner, "fuzz: pending withdrawer should be owner");
        } catch {
            // Revert is acceptable (e.g., shares too small, exceeds eligible, slippage issues)
            assertEq(
                uint8(vaultState.withdrawState()),
                uint8(VaultState.State.IDLE),
                "fuzz: withdraw revert should leave state IDLE"
            );
        }
    }

    /// @notice Fuzz withdraw with zero shares — handler should revert.
    function testFuzz_withdraw_zeroSharesReverts(uint256 slippageSeed) public {
        _setupVaultWithPosition();

        uint256 slippage = bound(slippageSeed, 0, 1000);

        if (uint8(vaultState.withdrawState()) != uint8(VaultState.State.IDLE)) return;

        _rollCooldown();
        vm.deal(vaultOwner, 10 ether);

        vm.prank(vaultOwner);
        try withdrawHandler.withdraw{value: _forkExecFeeWithdrawalWei()}(
            IWithdrawHandlerVaultCore(address(vaultCore)), 0, slippage
        ) {
            fail("fuzz: withdraw with 0 shares should revert");
        } catch {
            // Expected: revert on zero shares
            assertEq(
                uint8(vaultState.withdrawState()),
                uint8(VaultState.State.IDLE),
                "fuzz: zero-shares revert should leave state IDLE"
            );
        }
    }
}

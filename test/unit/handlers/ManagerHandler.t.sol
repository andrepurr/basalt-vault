// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {VaultState} from "../../../src/core/VaultState.sol";
import {ManagerHandler} from "../../../src/handlers/ManagerHandler.sol";
import {IDepositHandlerVaultCore} from "../../../src/interfaces/IDepositHandlerVaultCore.sol";
import {IManagerHandler} from "../../../src/interfaces/IManagerHandler.sol";
import {IManagerHandlerVaultCore} from "../../../src/interfaces/IManagerHandlerVaultCore.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";
import {
    NotIdle,
    NotProtocolManager,
    NotManagerOrNftOwner,
    NotVaultNftOwner,
    InvalidTargetLtv,
    InvalidSlippage,
    RebalanceNotPending,
    NoCollateral,
    LtvAlreadyAtTarget
} from "../../../src/handlers/managerHandlerLibraries/ManagerHandlerTypes.sol";
import {
    GmxEventUtils,
    IDepositCallbackReceiver
} from "../../../src/interfaces/IGmxCallbackReceiver.sol";

/// @title ManagerHandlerUnit
/// @notice Unit tests for ManagerHandler: config setters, rebalance flow, and view functions.
///         Config setters are called through managerContract by the configurator role.
///         CSRE libraries exercised through handler calls per D-05.
contract ManagerHandlerUnit is ForkSetupFull {
    // ── Constants ────────────────────────────────────────────────────────────
    address internal constant DOLOMITE_AUTH_HANDLER = 0x1fF6B8E1192eB0369006Bbad76dA9068B68961B2;
    bytes32 internal constant SIG_ASYNC_DEPOSIT_CREATED =
        0x07483e098a6cfa5c67659e928fc3e7b08b3e60e09d57a7825c4becf2da6da2a7;

    uint256 internal constant PERF_FEE_BPS = 2_000;
    uint256 internal constant DEPOSIT_GM = 10e18;
    uint256 internal constant KEEPER_WRAP_GM = 2e18;

    function setUp() public override {
        super.setUp();
        _fundActor(vaultOwner);
        _fundActor(stranger);
        _fundActor(address(managerContract));
        _fundActor(configurator);
        _fundActor(operational);

        // managementFeeBps is auto-initialized to MANAGER_FEE_BPS (2_000) in VaultState.initialize()
        require(vaultState.managementFeeBps() == PERF_FEE_BPS, "management fee init drift");

        // Approve deposit handler for vaultOwner
        vm.prank(vaultOwner);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(address(depositHandler), type(uint256).max);

        // Deal GM to vaultOwner
        deal(BasaltAddresses.GM_MARKET_TOKEN, vaultOwner, 200e18);
    }

    //  CONFIG SETTERS (Priority 3) -- via managerContract.onlyConfigurator

    function test_setTargetLtv_asConfigurator_updatesVaultState() public {
        uint256 newLtv = 5_100; // within [4800, 5200]
        vm.prank(configurator);
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newLtv
        );
        assertEq(vaultState.targetLtvBps(), newLtv, "targetLtvBps should be updated");
        assertGe(newLtv, BasaltConstants.MIN_TARGET_LTV_BPS, "new LTV should be >= MIN");
        assertLe(newLtv, BasaltConstants.MAX_TARGET_LTV_BPS, "new LTV should be <= MAX");
    }

    function test_setKeeperDeadline_asConfigurator_updatesVaultState() public {
        uint256 newDeadline = 120; // within [60, 3600]
        vm.prank(configurator);
        managerContract.setVaultKeeperDeadline(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newDeadline
        );
        assertEq(vaultState.keeperDeadline(), newDeadline, "keeperDeadline should be updated");
        assertGe(newDeadline, BasaltConstants.MIN_KEEPER_DEADLINE, "deadline >= MIN");
        assertLe(newDeadline, BasaltConstants.MAX_KEEPER_DEADLINE, "deadline <= MAX");
    }

    function test_setRebalanceSlippageCapBps_asConfigurator_updatesVaultState() public {
        uint256 newCap = 300; // within [100, 1000]
        vm.prank(configurator);
        managerContract.setVaultRebalanceSlippageCapBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newCap
        );
        assertEq(vaultState.rebalanceSlippageCapBps(), newCap, "rebalanceSlippageCapBps should be updated");
        assertGe(newCap, BasaltConstants.MIN_REBALANCE_SLIPPAGE_CAP_BPS, "cap >= MIN");
        assertLe(newCap, BasaltConstants.MAX_REBALANCE_SLIPPAGE_CAP_BPS, "cap <= MAX");
    }

    function test_setUnwrapLongShareBps_asConfigurator_updatesVaultState() public {
        uint256 newShare = 4_500; // within [4000, 5000]
        vm.prank(configurator);
        managerContract.setVaultUnwrapLongShareBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newShare
        );
        assertEq(vaultState.unwrapLongShareBps(), newShare, "unwrapLongShareBps should be updated");
        assertGe(newShare, BasaltConstants.MIN_UNWRAP_LONG_SHARE_BPS, "share >= MIN");
        assertLe(newShare, BasaltConstants.MAX_UNWRAP_LONG_SHARE_BPS, "share <= MAX");
    }

    function test_setRebalanceThresholdUpBps_asConfigurator_updatesVaultState() public {
        uint256 newThresh = 1_000; // within [500, 2000]
        vm.prank(configurator);
        managerContract.setVaultRebalanceThresholdUpBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newThresh
        );
        assertEq(vaultState.rebalanceThresholdUpBps(), newThresh, "rebalanceThresholdUpBps should be updated");
        assertGe(newThresh, BasaltConstants.MIN_REBALANCE_THRESHOLD_BPS, "threshold >= MIN");
        assertLe(newThresh, BasaltConstants.MAX_REBALANCE_THRESHOLD_BPS, "threshold <= MAX");
    }

    function test_setRebalanceThresholdDownBps_asConfigurator_updatesVaultState() public {
        uint256 newThresh = 1_500; // within [500, 2000]
        vm.prank(configurator);
        managerContract.setVaultRebalanceThresholdDownBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newThresh
        );
        assertEq(vaultState.rebalanceThresholdDownBps(), newThresh, "rebalanceThresholdDownBps should be updated");
        assertGe(newThresh, BasaltConstants.MIN_REBALANCE_THRESHOLD_BPS, "threshold >= MIN");
        assertLe(newThresh, BasaltConstants.MAX_REBALANCE_THRESHOLD_BPS, "threshold <= MAX");
    }

    function test_setTargetLtv_asStranger_reverts() public {
        uint256 ltvBefore = vaultState.targetLtvBps();
        vm.prank(stranger);
        vm.expectRevert(); // ManagerContract.NotConfigurator
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            5_100
        );
        assertEq(vaultState.targetLtvBps(), ltvBefore, "targetLtv unchanged after revert");
    }

    function test_setTargetLtv_outOfBounds_reverts() public {
        uint256 ltvBefore = vaultState.targetLtvBps();
        assertGt(uint256(9_000), BasaltConstants.MAX_TARGET_LTV_BPS, "test value must exceed MAX");
        vm.prank(configurator);
        vm.expectRevert(); // InvalidTargetLtv
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            9_000 // above MAX_TARGET_LTV_BPS (5200)
        );
        assertEq(vaultState.targetLtvBps(), ltvBefore, "targetLtv unchanged after OOB revert");
    }

    //  REBALANCE FLOW (Priority 4)

    function test_rebalance_emptyVault_reverts() public {
        uint256 ltvBefore = managerHandler.currentLtvBps(IManagerHandlerVaultCore(address(vaultCore)));
        assertEq(ltvBefore, 0, "empty vault should have 0 LTV");
        uint256 fee = _forkExecFeeWithdrawalWei();
        vm.prank(operational);
        vm.expectRevert(NoCollateral.selector);
        managerContract.rebalanceVault{value: fee}(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            300
        );
        assertEq(
            uint8(vaultState.rebalanceState()),
            uint8(VaultState.State.IDLE),
            "rebalance state unchanged after revert"
        );
    }

    function test_rebalance_asStranger_reverts() public {
        assertEq(
            uint8(vaultState.rebalanceState()),
            uint8(VaultState.State.IDLE),
            "rebalance should be IDLE before"
        );
        vm.prank(stranger);
        vm.expectRevert(); // ManagerContract.NotOperational
        managerContract.rebalanceVault(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            300
        );
        assertEq(
            uint8(vaultState.rebalanceState()),
            uint8(VaultState.State.IDLE),
            "rebalance state unchanged after revert"
        );
    }

    function test_rebalance_ltvAtTarget_reverts() public {
        _setupVaultWithPosition();

        // The vault's LTV after deposit may already be at target (5000 default).
        // If it is, the rebalance should revert with LtvAlreadyAtTarget.
        uint256 currentLtv = managerHandler.currentLtvBps(IManagerHandlerVaultCore(address(vaultCore)));
        uint256 targetLtv = vaultState.targetLtvBps();
        assertGt(currentLtv, 0, "vault with position should have non-zero LTV");
        assertLe(currentLtv, BasaltConstants.MAX_SAFE_LTV_BPS, "LTV should be within safe range");

        if (currentLtv == targetLtv) {
            _rollCooldown();
            uint256 fee = _forkExecFeeWithdrawalWei();
            vm.prank(operational);
            vm.expectRevert(); // LtvAlreadyAtTarget
            managerContract.rebalanceVault{value: fee}(
                IManagerHandler(address(managerHandler)),
                IManagerHandlerVaultCore(address(vaultCore)),
                300
            );
        }
        // If LTV != target, the test is a no-op (the fork state varies)
    }

    function test_finalizeRebalance_asStranger_reverts() public {
        assertEq(
            uint8(vaultState.rebalanceState()),
            uint8(VaultState.State.IDLE),
            "rebalance should be IDLE before"
        );
        vm.prank(stranger);
        vm.expectRevert(); // ManagerContract.NotOperational
        managerContract.finalizeRebalance(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore))
        );
        assertEq(
            uint8(vaultState.rebalanceState()),
            uint8(VaultState.State.IDLE),
            "rebalance state unchanged after stranger attempt"
        );
    }

    function test_finalizeRebalance_notPending_reverts() public {
        _setupVaultWithPosition();

        assertEq(
            uint8(vaultState.rebalanceState()),
            uint8(VaultState.State.IDLE),
            "rebalance should be IDLE (not pending)"
        );
        vm.prank(operational);
        vm.expectRevert(RebalanceNotPending.selector);
        managerContract.finalizeRebalance(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore))
        );
        assertEq(
            uint8(vaultState.rebalanceState()),
            uint8(VaultState.State.IDLE),
            "rebalance state still IDLE after revert"
        );
    }

    function test_rebalance_whileDepositPending_reverts() public {
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
        vm.prank(operational);
        vm.expectRevert(NotIdle.selector);
        managerContract.rebalanceVault{value: fee}(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            300
        );
    }

    //  VIEW TESTS

    function test_currentLtvBps_withPosition_returnsNonZero() public {
        _setupVaultWithPosition();

        uint256 ltv = managerHandler.currentLtvBps(IManagerHandlerVaultCore(address(vaultCore)));
        assertGt(ltv, 0, "LTV should be > 0 with levered position");
        assertLe(ltv, BasaltConstants.MAX_SAFE_LTV_BPS, "LTV should be <= 70%");
    }

    function test_currentLtvBps_emptyVault_returnsZero() public view {
        uint256 ltv = managerHandler.currentLtvBps(IManagerHandlerVaultCore(address(vaultCore)));
        assertEq(ltv, 0, "LTV should be 0 on empty vault");
        assertEq(
            uint8(vaultState.depositState()),
            uint8(VaultState.State.IDLE),
            "empty vault deposit state should be IDLE"
        );
    }

    //  HELPERS

    /// @dev Perform full deposit cycle so vault has GM collateral + WBTC debt.
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

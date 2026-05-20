// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {VaultState} from "../../../src/core/VaultState.sol";
import {NotVaultCore, VaultNotIdle, AlreadyInitialized as VsAlreadyInitialized} from "../../../src/core/vaultStateLibraries/VaultStateTypes.sol";
import {ManagerContract} from "../../../src/core/ManagerContract.sol";
import {IManagerHandler} from "../../../src/interfaces/IManagerHandler.sol";
import {IManagerHandlerVaultCore} from "../../../src/interfaces/IManagerHandlerVaultCore.sol";
import {IDepositHandler} from "../../../src/interfaces/IDepositHandler.sol";
import {IDepositHandlerVaultCore} from "../../../src/interfaces/IDepositHandlerVaultCore.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";

/// @title VaultState onlyVaultCore enforcement, state machine, config routing, and default values unit tests
contract VaultStateUnit is ForkSetupFull {
    // ══════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL: onlyVaultCore -- direct calls must revert
    // ══════════════════════════════════════════════════════════════════════

    function test_setDepositState_directCall_reverts() public {
        // Pre-condition: stranger is not vaultCore
        assertTrue(stranger != address(vaultCore), "stranger must differ from vaultCore");
        VaultState.State stateBefore = vaultState.depositState();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setDepositState(VaultState.State.PENDING);
        // State unchanged after revert
        assertEq(uint8(vaultState.depositState()), uint8(stateBefore), "depositState must not change after revert");
    }

    function test_setWithdrawState_directCall_reverts() public {
        assertTrue(stranger != address(vaultCore), "stranger must differ from vaultCore");
        VaultState.State stateBefore = vaultState.withdrawState();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setWithdrawState(VaultState.State.PENDING);
        assertEq(uint8(vaultState.withdrawState()), uint8(stateBefore), "withdrawState must not change after revert");
    }

    function test_setRebalanceState_directCall_reverts() public {
        assertTrue(stranger != address(vaultCore), "stranger must differ from vaultCore");
        VaultState.State stateBefore = vaultState.rebalanceState();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setRebalanceState(VaultState.State.PENDING);
        assertEq(uint8(vaultState.rebalanceState()), uint8(stateBefore), "rebalanceState must not change after revert");
    }

    function test_setTargetLtvBps_directCall_reverts() public {
        uint256 ltvBefore = vaultState.targetLtvBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setTargetLtvBps(5000);
        assertEq(vaultState.targetLtvBps(), ltvBefore, "targetLtvBps must not change after revert");
        assertEq(uint8(vaultState.depositState()), 0, "depositState unaffected by failed setTargetLtvBps");
    }

    function test_setKeeperDeadline_directCall_reverts() public {
        uint256 deadlineBefore = vaultState.keeperDeadline();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setKeeperDeadline(120);
        assertEq(vaultState.keeperDeadline(), deadlineBefore, "keeperDeadline must not change after revert");
        assertEq(deadlineBefore, BasaltConstants.DEFAULT_KEEPER_DEADLINE, "keeperDeadline should still be the default");
    }

    function test_setPendingDepositAccounting_directCall_reverts() public {
        uint256 amountBefore = vaultState.pendingDepositAmountGmE18();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setPendingDepositAccounting(1e18, 1e18, 1e18, block.timestamp + 60);
        assertEq(vaultState.pendingDepositAmountGmE18(), amountBefore, "pendingDepositAmountGmE18 must not change");
        assertEq(vaultState.pendingDepositDeadline(), 0, "pendingDepositDeadline must remain zero");
    }

    function test_setFeeAccounting_directCall_reverts() public {
        uint256 hwmBefore = vaultState.highWaterMarkProfitUsdE18();
        uint256 feeBefore = vaultState.managerAccruedFeeUsdE18();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setFeeAccounting(1e18, 1e18);
        assertEq(vaultState.highWaterMarkProfitUsdE18(), hwmBefore, "highWaterMarkProfitUsdE18 must not change");
        assertEq(vaultState.managerAccruedFeeUsdE18(), feeBefore, "managerAccruedFeeUsdE18 must not change");
    }

    function test_addDepositedUsdE18_directCall_reverts() public {
        uint256 totalBefore = vaultState.totalDepositedUsdE18();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.addDepositedUsdE18(1e18);
        assertEq(vaultState.totalDepositedUsdE18(), totalBefore, "totalDepositedUsdE18 must not change");
        assertEq(totalBefore, 0, "totalDepositedUsdE18 should be zero in fresh state");
    }

    function test_clearPendingDepositAccounting_directCall_reverts() public {
        VaultState.State stateBefore = vaultState.depositState();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.clearPendingDepositAccounting();
        assertEq(uint8(vaultState.depositState()), uint8(stateBefore), "depositState must not change after revert");
        assertEq(vaultState.pendingDepositDeadline(), 0, "pendingDepositDeadline must remain zero after failed clear");
    }

    function test_setPendingWithdrawAccounting_directCall_reverts() public {
        address withdrawerBefore = vaultState.pendingWithdrawer();
        VaultState.State stateBefore = vaultState.withdrawState();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setPendingWithdrawAccounting(
            stranger, 1e18, 1e18, 1e18, 1e8, 1e18, 0, 1e18, block.timestamp + 60, false
        );
        assertEq(vaultState.pendingWithdrawer(), withdrawerBefore, "pendingWithdrawer must not change");
        assertEq(uint8(vaultState.withdrawState()), uint8(stateBefore), "withdrawState must not change after revert");
        assertEq(vaultState.pendingWithdrawDeadline(), 0, "pendingWithdrawDeadline must remain zero after failed clear");
    }

    function test_clearPendingWithdrawAccounting_directCall_reverts() public {
        VaultState.State stateBefore = vaultState.withdrawState();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.clearPendingWithdrawAccounting();
        assertEq(uint8(vaultState.withdrawState()), uint8(stateBefore), "withdrawState must not change after revert");
        assertEq(vaultState.pendingWithdrawer(), address(0), "pendingWithdrawer must remain zero after failed clear");
    }

    function test_finalizeDepositAccounting_directCall_reverts() public {
        uint256 totalGmBefore = vaultState.totalDepositedGmE18();
        uint256 totalUsdBefore = vaultState.totalDepositedUsdE18();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.finalizeDepositAccounting(1e18, 1e18, 1e18, 1e8);
        assertEq(vaultState.totalDepositedGmE18(), totalGmBefore, "totalDepositedGmE18 must not change");
        assertEq(vaultState.totalDepositedUsdE18(), totalUsdBefore, "totalDepositedUsdE18 must not change");
    }

    function test_setDolomiteIsolationVault_directCall_reverts() public {
        address isoVaultBefore = vaultState.dolomiteIsolationVault();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setDolomiteIsolationVault(address(uint160(0xBBB1)));
        assertEq(vaultState.dolomiteIsolationVault(), isoVaultBefore, "dolomiteIsolationVault must not change");
        assertEq(isoVaultBefore, address(0), "dolomiteIsolationVault should be zero in fresh state");
    }

    function test_addWithdrawnUsdE18_directCall_reverts() public {
        uint256 totalBefore = vaultState.totalWithdrawnUsdE18();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.addWithdrawnUsdE18(1e18);
        assertEq(vaultState.totalWithdrawnUsdE18(), totalBefore, "totalWithdrawnUsdE18 must not change");
        assertEq(totalBefore, 0, "totalWithdrawnUsdE18 should be zero in fresh state");
    }

    function test_subAccruedManagerFeeUsdE18_directCall_reverts() public {
        uint256 feeBefore = vaultState.managerAccruedFeeUsdE18();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.subAccruedManagerFeeUsdE18(1e18);
        assertEq(vaultState.managerAccruedFeeUsdE18(), feeBefore, "managerAccruedFeeUsdE18 must not change");
        assertEq(feeBefore, 0, "managerAccruedFeeUsdE18 should be zero in fresh state");
    }

    function test_setManagementFeeBps_directCall_reverts() public {
        uint256 feeBpsBefore = vaultState.managementFeeBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setManagementFeeBps(1000);
        assertEq(vaultState.managementFeeBps(), feeBpsBefore, "managementFeeBps must not change");
        assertEq(feeBpsBefore, BasaltConstants.MANAGER_FEE_BPS, "managementFeeBps should still be the default");
    }

    function test_startGlobalActionCooldown_directCall_reverts() public {
        uint256 cooldownBefore = vaultState.globalActionCooldownEndBlock();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.startGlobalActionCooldown(block.number + 10);
        assertEq(vaultState.globalActionCooldownEndBlock(), cooldownBefore, "cooldownEndBlock must not change");
        assertEq(cooldownBefore, 0, "cooldownEndBlock should be zero in fresh state");
    }

    function test_setPendingRebalance_directCall_reverts() public {
        VaultState.State stateBefore = vaultState.rebalanceState();
        address initiatorBefore = vaultState.pendingRebalanceInitiator();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setPendingRebalance(0, 0, stranger, 5000, block.timestamp + 60);
        assertEq(uint8(vaultState.rebalanceState()), uint8(stateBefore), "rebalanceState must not change");
        assertEq(vaultState.pendingRebalanceInitiator(), initiatorBefore, "initiator must not change");
    }

    function test_clearPendingRebalance_directCall_reverts() public {
        VaultState.State stateBefore = vaultState.rebalanceState();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.clearPendingRebalance();
        assertEq(uint8(vaultState.rebalanceState()), uint8(stateBefore), "rebalanceState must not change");
        assertEq(vaultState.pendingRebalanceDeadline(), 0, "pendingRebalanceDeadline must remain zero");
    }

    function test_setRebalanceSlippageCapBps_directCall_reverts() public {
        uint256 capBefore = vaultState.rebalanceSlippageCapBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setRebalanceSlippageCapBps(300);
        assertEq(vaultState.rebalanceSlippageCapBps(), capBefore, "rebalanceSlippageCapBps must not change");
        assertEq(capBefore, BasaltConstants.DEFAULT_REBALANCE_SLIPPAGE_CAP_BPS, "slippage cap should still be default");
    }

    function test_setUnwrapLongShareBps_directCall_reverts() public {
        uint256 bpsBefore = vaultState.unwrapLongShareBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setUnwrapLongShareBps(4500);
        assertEq(vaultState.unwrapLongShareBps(), bpsBefore, "unwrapLongShareBps must not change");
        assertEq(bpsBefore, BasaltConstants.DEFAULT_UNWRAP_LONG_SHARE_BPS, "unwrapLongShareBps should still be default");
    }

    function test_setRebalanceThresholdUpBps_directCall_reverts() public {
        uint256 threshBefore = vaultState.rebalanceThresholdUpBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setRebalanceThresholdUpBps(1000);
        assertEq(vaultState.rebalanceThresholdUpBps(), threshBefore, "rebalanceThresholdUpBps must not change");
        assertEq(threshBefore, BasaltConstants.DEFAULT_REBALANCE_THRESHOLD_UP_BPS, "thresholdUp should still be default");
    }

    function test_setRebalanceThresholdDownBps_directCall_reverts() public {
        uint256 threshBefore = vaultState.rebalanceThresholdDownBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setRebalanceThresholdDownBps(1000);
        assertEq(vaultState.rebalanceThresholdDownBps(), threshBefore, "rebalanceThresholdDownBps must not change");
        assertEq(threshBefore, BasaltConstants.DEFAULT_REBALANCE_THRESHOLD_DOWN_BPS, "thresholdDown should still be default");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STATE MACHINE: requireAllIdle
    // ══════════════════════════════════════════════════════════════════════

    function test_requireAllIdle_whenAllIdle_succeeds() public view {
        // Default state after setUp -- all IDLE, should not revert
        vaultState.requireAllIdle();
        // If we reach here, the function did not revert
        assertEq(uint8(vaultState.depositState()), 0, "depositState should be IDLE (0)");
        assertEq(uint8(vaultState.withdrawState()), 0, "withdrawState should be IDLE (0)");
        assertEq(uint8(vaultState.rebalanceState()), 0, "rebalanceState should be IDLE (0)");
    }

    function test_requireAllIdle_whenDepositPending_reverts() public {
        // Set deposit state to PENDING via vaultCore
        vm.prank(address(vaultCore));
        vaultState.setDepositState(VaultState.State.PENDING);
        assertEq(uint8(vaultState.depositState()), 1, "depositState should be PENDING (1) after set");

        vm.expectRevert(abi.encodeWithSelector(VaultNotIdle.selector));
        vaultState.requireAllIdle();
    }

    function test_requireAllIdle_whenWithdrawPending_reverts() public {
        vm.prank(address(vaultCore));
        vaultState.setWithdrawState(VaultState.State.PENDING);
        assertEq(uint8(vaultState.withdrawState()), 1, "withdrawState should be PENDING (1) after set");

        vm.expectRevert(abi.encodeWithSelector(VaultNotIdle.selector));
        vaultState.requireAllIdle();
    }

    function test_requireAllIdle_whenRebalancePending_reverts() public {
        vm.prank(address(vaultCore));
        vaultState.setRebalanceState(VaultState.State.PENDING);
        assertEq(uint8(vaultState.rebalanceState()), 1, "rebalanceState should be PENDING (1) after set");

        vm.expectRevert(abi.encodeWithSelector(VaultNotIdle.selector));
        vaultState.requireAllIdle();
    }

    // ══════════════════════════════════════════════════════════════════════
    // CONFIG THROUGH MANAGER: verify setters route correctly
    // ══════════════════════════════════════════════════════════════════════

    function test_setTargetLtvBps_throughManager_updatesState() public {
        uint256 newLtv = 4900;
        assertEq(vaultState.targetLtvBps(), BasaltConstants.DEFAULT_TARGET_LTV_BPS, "pre: targetLtvBps should be default");
        vm.prank(configurator);
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newLtv
        );
        assertEq(vaultState.targetLtvBps(), newLtv, "targetLtvBps should be updated to 4900 via manager routing");
    }

    function test_setKeeperDeadline_throughManager_updatesState() public {
        uint256 newDeadline = 120;
        assertEq(vaultState.keeperDeadline(), BasaltConstants.DEFAULT_KEEPER_DEADLINE, "pre: keeperDeadline should be default");
        vm.prank(configurator);
        managerContract.setVaultKeeperDeadline(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newDeadline
        );
        assertEq(vaultState.keeperDeadline(), newDeadline, "keeperDeadline should be updated to 120 via manager routing");
    }

    function test_setRebalanceSlippageCapBps_throughManager_updatesState() public {
        uint256 newCap = 300;
        assertEq(vaultState.rebalanceSlippageCapBps(), BasaltConstants.DEFAULT_REBALANCE_SLIPPAGE_CAP_BPS, "pre: slippage cap should be default");
        vm.prank(configurator);
        managerContract.setVaultRebalanceSlippageCapBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newCap
        );
        assertEq(
            vaultState.rebalanceSlippageCapBps(),
            newCap,
            "rebalanceSlippageCapBps should be updated to 300 via manager routing"
        );
    }

    function test_setUnwrapLongShareBps_throughManager_updatesState() public {
        uint256 newBps = 4500;
        assertEq(vaultState.unwrapLongShareBps(), BasaltConstants.DEFAULT_UNWRAP_LONG_SHARE_BPS, "pre: unwrapLongShareBps should be default");
        vm.prank(configurator);
        managerContract.setVaultUnwrapLongShareBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newBps
        );
        assertEq(
            vaultState.unwrapLongShareBps(),
            newBps,
            "unwrapLongShareBps should be updated to 4500 via manager routing"
        );
    }

    function test_setRebalanceThresholdUpBps_throughManager_updatesState() public {
        uint256 newBps = 1000;
        assertEq(vaultState.rebalanceThresholdUpBps(), BasaltConstants.DEFAULT_REBALANCE_THRESHOLD_UP_BPS, "pre: thresholdUp should be default");
        vm.prank(configurator);
        managerContract.setVaultRebalanceThresholdUpBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newBps
        );
        assertEq(
            vaultState.rebalanceThresholdUpBps(),
            newBps,
            "rebalanceThresholdUpBps should be updated to 1000 via manager routing"
        );
    }

    function test_setRebalanceThresholdDownBps_throughManager_updatesState() public {
        uint256 newBps = 1500;
        assertEq(vaultState.rebalanceThresholdDownBps(), BasaltConstants.DEFAULT_REBALANCE_THRESHOLD_DOWN_BPS, "pre: thresholdDown should be default");
        vm.prank(configurator);
        managerContract.setVaultRebalanceThresholdDownBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newBps
        );
        assertEq(
            vaultState.rebalanceThresholdDownBps(),
            newBps,
            "rebalanceThresholdDownBps should be updated to 1500 via manager routing"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // STATE VIEWS: default values after setUp
    // ══════════════════════════════════════════════════════════════════════

    function test_depositState_afterSetUp_isIdle() public view {
        assertEq(uint8(vaultState.depositState()), 0, "depositState should be IDLE after setUp");
        assertEq(vaultState.pendingDepositAmountGmE18(), 0, "no pending deposit amount when IDLE");
    }

    function test_withdrawState_afterSetUp_isIdle() public view {
        assertEq(uint8(vaultState.withdrawState()), 0, "withdrawState should be IDLE after setUp");
        assertEq(vaultState.pendingWithdrawer(), address(0), "no pending withdrawer when IDLE");
    }

    function test_rebalanceState_afterSetUp_isIdle() public view {
        assertEq(uint8(vaultState.rebalanceState()), 0, "rebalanceState should be IDLE after setUp");
        assertEq(vaultState.pendingRebalanceInitiator(), address(0), "no pending rebalance initiator when IDLE");
    }

    function test_targetLtvBps_afterSetUp_hasDefault() public view {
        assertEq(
            vaultState.targetLtvBps(),
            BasaltConstants.DEFAULT_TARGET_LTV_BPS,
            "targetLtvBps should match DEFAULT_TARGET_LTV_BPS (5000) after setUp"
        );
        assertGe(vaultState.targetLtvBps(), BasaltConstants.MIN_TARGET_LTV_BPS, "default LTV must be >= MIN");
        assertLe(vaultState.targetLtvBps(), BasaltConstants.MAX_TARGET_LTV_BPS, "default LTV must be <= MAX");
    }

    function test_keeperDeadline_afterSetUp_hasDefault() public view {
        assertEq(
            vaultState.keeperDeadline(),
            BasaltConstants.DEFAULT_KEEPER_DEADLINE,
            "keeperDeadline should match DEFAULT_KEEPER_DEADLINE (60) after setUp"
        );
        assertGe(vaultState.keeperDeadline(), BasaltConstants.MIN_KEEPER_DEADLINE, "default deadline must be >= MIN");
        assertLe(vaultState.keeperDeadline(), BasaltConstants.MAX_KEEPER_DEADLINE, "default deadline must be <= MAX");
    }

    function test_managementFeeBps_afterSetUp_hasDefault() public view {
        assertEq(
            vaultState.managementFeeBps(),
            BasaltConstants.MANAGER_FEE_BPS,
            "managementFeeBps should match MANAGER_FEE_BPS (2000) after setUp"
        );
        assertLe(vaultState.managementFeeBps(), BasaltConstants.BPS, "fee must not exceed 100%");
    }

    function test_rebalanceSlippageCapBps_afterSetUp_hasDefault() public view {
        assertEq(
            vaultState.rebalanceSlippageCapBps(),
            BasaltConstants.DEFAULT_REBALANCE_SLIPPAGE_CAP_BPS,
            "rebalanceSlippageCapBps should match default (500) after setUp"
        );
        assertGe(vaultState.rebalanceSlippageCapBps(), BasaltConstants.MIN_REBALANCE_SLIPPAGE_CAP_BPS, "default slippage cap must be >= MIN");
    }

    function test_unwrapLongShareBps_afterSetUp_hasDefault() public view {
        assertEq(
            vaultState.unwrapLongShareBps(),
            BasaltConstants.DEFAULT_UNWRAP_LONG_SHARE_BPS,
            "unwrapLongShareBps should match default (5000) after setUp"
        );
        assertLe(vaultState.unwrapLongShareBps(), BasaltConstants.MAX_UNWRAP_LONG_SHARE_BPS, "default unwrap share must be <= MAX");
    }

    function test_rebalanceThresholdUpBps_afterSetUp_hasDefault() public view {
        assertEq(
            vaultState.rebalanceThresholdUpBps(),
            BasaltConstants.DEFAULT_REBALANCE_THRESHOLD_UP_BPS,
            "rebalanceThresholdUpBps should match default (2000) after setUp"
        );
        assertGe(vaultState.rebalanceThresholdUpBps(), BasaltConstants.MIN_REBALANCE_THRESHOLD_BPS, "default thresholdUp must be >= MIN");
    }

    function test_rebalanceThresholdDownBps_afterSetUp_hasDefault() public view {
        assertEq(
            vaultState.rebalanceThresholdDownBps(),
            BasaltConstants.DEFAULT_REBALANCE_THRESHOLD_DOWN_BPS,
            "rebalanceThresholdDownBps should match default (2000) after setUp"
        );
        assertGe(vaultState.rebalanceThresholdDownBps(), BasaltConstants.MIN_REBALANCE_THRESHOLD_BPS, "default thresholdDown must be >= MIN");
    }

    function test_dolomiteIsolationVault_afterSetUp_isZero() public view {
        assertEq(
            vaultState.dolomiteIsolationVault(),
            address(0),
            "dolomiteIsolationVault should be zero before first deposit"
        );
        // vaultCoreClone must be set (initialized) even when dolomiteIsolationVault is not
        assertTrue(vaultState.vaultCoreClone() != address(0), "vaultCoreClone should be set after init");
    }

    function test_totalDepositedUsdE18_afterSetUp_isZero() public view {
        assertEq(vaultState.totalDepositedUsdE18(), 0, "totalDepositedUsdE18 should be 0 after setUp");
        assertEq(vaultState.totalWithdrawnUsdE18(), 0, "totalWithdrawnUsdE18 should also be 0 after setUp");
    }

    function test_totalDepositedGmE18_afterSetUp_isZero() public view {
        assertEq(vaultState.totalDepositedGmE18(), 0, "totalDepositedGmE18 should be 0 after setUp");
        assertEq(vaultState.pendingDepositAmountGmE18(), 0, "pendingDepositAmountGmE18 should also be 0");
    }

    function test_highWaterMarkProfitUsdE18_afterSetUp_isZero() public view {
        assertEq(vaultState.highWaterMarkProfitUsdE18(), 0, "highWaterMarkProfitUsdE18 should be 0 after setUp");
        assertEq(vaultState.managerAccruedFeeUsdE18(), 0, "no accrued fee when no profit exists");
    }

    function test_managerAccruedFeeUsdE18_afterSetUp_isZero() public view {
        assertEq(vaultState.managerAccruedFeeUsdE18(), 0, "managerAccruedFeeUsdE18 should be 0 after setUp");
        assertEq(vaultState.highWaterMarkProfitUsdE18(), 0, "HWM should be 0 when no fee has accrued");
    }

    function test_vaultCoreClone_afterSetUp_isVaultCore() public view {
        assertEq(
            vaultState.vaultCoreClone(),
            address(vaultCore),
            "vaultCoreClone should point to the deployed vaultCore"
        );
        assertTrue(vaultState.vaultCoreClone() != address(0), "vaultCoreClone must be non-zero after init");
    }

    // ══════════════════════════════════════════════════════════════════════
    // INITIALIZE: double init protection
    // ══════════════════════════════════════════════════════════════════════

    function test_initialize_doubleInit_reverts() public {
        address vaultCoreBefore = vaultState.vaultCoreClone();
        assertTrue(vaultCoreBefore != address(0), "pre: vaultCoreClone must be set from first init");
        vm.expectRevert(abi.encodeWithSelector(VsAlreadyInitialized.selector));
        vaultState.initialize(address(uint160(0xBBB2)), address(0));
        assertEq(vaultState.vaultCoreClone(), vaultCoreBefore, "vaultCoreClone must not change after failed re-init");
    }
}

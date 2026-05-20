// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {VaultState} from "../../../src/core/VaultState.sol";
import {NotVaultCore, VaultNotIdle, AlreadyInitialized as VsAlreadyInitialized} from "../../../src/core/vaultStateLibraries/VaultStateTypes.sol";
import {IManagerHandler} from "../../../src/interfaces/IManagerHandler.sol";
import {IManagerHandlerVaultCore} from "../../../src/interfaces/IManagerHandlerVaultCore.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";

/// @title VaultState unit tests
contract VaultStateUnit is ForkSetupFull {
    // ACCESS CONTROL: onlyVaultCore -- direct calls must revert

    function test_setDepositState_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setDepositState(VaultState.State.PENDING);
    }

    function test_setWithdrawState_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setWithdrawState(VaultState.State.PENDING);
    }

    function test_setRebalanceState_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setRebalanceState(VaultState.State.PENDING);
    }

    function test_setTargetLtvBps_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setTargetLtvBps(5000);
    }

    function test_setKeeperDeadline_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setKeeperDeadline(120);
    }

    function test_setPendingDepositAccounting_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setPendingDepositAccounting(1e18, 1e18, 1e18, block.timestamp + 60);
    }

    function test_setFeeAccounting_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setFeeAccounting(1e18, 1e18);
    }

    function test_addDepositedUsdE18_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.addDepositedUsdE18(1e18);
    }

    function test_clearPendingDepositAccounting_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.clearPendingDepositAccounting();
    }

    function test_setPendingWithdrawAccounting_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setPendingWithdrawAccounting(
            stranger, 1e18, 1e18, 1e18, 1e8, 1e18, 0, 1e18, block.timestamp + 60, false
        );
    }

    function test_clearPendingWithdrawAccounting_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.clearPendingWithdrawAccounting();
    }

    function test_finalizeDepositAccounting_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.finalizeDepositAccounting(1e18, 1e18, 1e18, 1e8);
    }

    function test_setDolomiteIsolationVault_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setDolomiteIsolationVault(address(uint160(0xBBB1)));
    }

    function test_addWithdrawnUsdE18_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.addWithdrawnUsdE18(1e18);
    }

    function test_subAccruedManagerFeeUsdE18_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.subAccruedManagerFeeUsdE18(1e18);
    }

    function test_setManagementFeeBps_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setManagementFeeBps(1000);
    }

    function test_startGlobalActionCooldown_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.startGlobalActionCooldown(block.number + 10);
    }

    function test_setPendingRebalance_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setPendingRebalance(0, 0, stranger, 5000, block.timestamp + 60);
    }

    function test_clearPendingRebalance_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.clearPendingRebalance();
    }

    function test_setRebalanceSlippageCapBps_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setRebalanceSlippageCapBps(300);
    }

    function test_setUnwrapLongShareBps_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setUnwrapLongShareBps(4500);
    }

    function test_setRebalanceThresholdUpBps_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setRebalanceThresholdUpBps(1000);
    }

    function test_setRebalanceThresholdDownBps_directCall_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotVaultCore.selector));
        vaultState.setRebalanceThresholdDownBps(1000);
    }

    // STATE MACHINE: requireAllIdle

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

    // CONFIG THROUGH MANAGER: verify setters route correctly

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

    // STATE VIEWS: default values after setUp

    function test_defaultValues_afterSetUp() public view {
        assertEq(uint8(vaultState.depositState()), 0);
        assertEq(uint8(vaultState.withdrawState()), 0);
        assertEq(uint8(vaultState.rebalanceState()), 0);
        assertEq(vaultState.targetLtvBps(), BasaltConstants.DEFAULT_TARGET_LTV_BPS);
        assertEq(vaultState.keeperDeadline(), BasaltConstants.DEFAULT_KEEPER_DEADLINE);
        assertEq(vaultState.managementFeeBps(), BasaltConstants.MANAGER_FEE_BPS);
        assertEq(vaultState.rebalanceSlippageCapBps(), BasaltConstants.DEFAULT_REBALANCE_SLIPPAGE_CAP_BPS);
        assertEq(vaultState.unwrapLongShareBps(), BasaltConstants.DEFAULT_UNWRAP_LONG_SHARE_BPS);
        assertEq(vaultState.rebalanceThresholdUpBps(), BasaltConstants.DEFAULT_REBALANCE_THRESHOLD_UP_BPS);
        assertEq(vaultState.rebalanceThresholdDownBps(), BasaltConstants.DEFAULT_REBALANCE_THRESHOLD_DOWN_BPS);
        assertEq(vaultState.dolomiteIsolationVault(), address(0));
        assertEq(vaultState.totalDepositedUsdE18(), 0);
        assertEq(vaultState.totalDepositedGmE18(), 0);
        assertEq(vaultState.highWaterMarkProfitUsdE18(), 0);
        assertEq(vaultState.managerAccruedFeeUsdE18(), 0);
        assertEq(vaultState.vaultCoreClone(), address(vaultCore));
    }

    // INITIALIZE: double init protection

    function test_initialize_doubleInit_reverts() public {
        address vaultCoreBefore = vaultState.vaultCoreClone();
        assertTrue(vaultCoreBefore != address(0), "pre: vaultCoreClone must be set from first init");
        vm.expectRevert(abi.encodeWithSelector(VsAlreadyInitialized.selector));
        vaultState.initialize(address(uint160(0xBBB2)), address(0));
        assertEq(vaultState.vaultCoreClone(), vaultCoreBefore, "vaultCoreClone must not change after failed re-init");
    }
}

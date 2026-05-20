// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {ManagerContract} from "../../../src/core/ManagerContract.sol";
import {
    NotPendingRole, NotFeeCollector, NotOperational, NotConfigurator,
    NotHandlerProposer, NotAddressProposer, ZeroFactory, ZeroProtocolManager,
    ZeroRole, NoVotingWeight, ActiveProposalExists, AlreadySigned,
    InsufficientFeeParticipantSupport, InsufficientCancelSupport
} from "../../../src/core/managerContractLibraries/ManagerContractTypes.sol";
import {VaultCore} from "../../../src/core/VaultCore.sol";
import {VaultCoreNftFactory} from "../../../src/core/VaultCoreNftFactory.sol";
import {VaultState} from "../../../src/core/VaultState.sol";
import {FeeSplitter} from "../../../src/core/FeeSplitter.sol";
import {IManagerHandler} from "../../../src/interfaces/IManagerHandler.sol";
import {IManagerHandlerVaultCore} from "../../../src/interfaces/IManagerHandlerVaultCore.sol";
import {IDepositHandler} from "../../../src/interfaces/IDepositHandler.sol";
import {IDepositHandlerVaultCore} from "../../../src/interfaces/IDepositHandlerVaultCore.sol";
import {IWithdrawHandler} from "../../../src/interfaces/IWithdrawHandler.sol";
import {IWithdrawHandlerVaultCore} from "../../../src/interfaces/IWithdrawHandlerVaultCore.sol";
import {IFeeAccountingHandler} from "../../../src/interfaces/IFeeAccountingHandler.sol";
import {IFeeAccountingHandlerVaultCore} from "../../../src/interfaces/IFeeAccountingHandlerVaultCore.sol";
import {IVaultCoreGovernance} from "../../../src/interfaces/IVaultCoreGovernance.sol";
import {IBasaltMath} from "../../../src/interfaces/IBasaltMath.sol";
import {IInitialCoreAddressBook} from "../../../src/interfaces/IInitialCoreAddressBook.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";

/// @title ManagerContract role isolation, config boundaries, and governance flow unit tests
contract ManagerContractUnit is ForkSetupFull {
    // ── Additional Actors ───────────────────────────────────────────────
    address internal handlerProposer;
    address internal addressProposer;

    function setUp() public override {
        super.setUp();
        handlerProposer = address(uint160(0x1008));
        addressProposer = address(uint160(0x1009));

        vm.startPrank(managerContract.owner());
        managerContract.setHandlerProposer(handlerProposer);
        managerContract.setAddressProposer(addressProposer);
        vm.stopPrank();
    }

    // ROLE ISOLATION: onlyOwner -- setConfigurator

    function test_setConfigurator_asStranger_reverts() public {
        address confBefore = managerContract.configurator();
        vm.prank(stranger);
        vm.expectRevert();
        managerContract.setConfigurator(address(uint160(0xAAA1)));
        assertEq(managerContract.configurator(), confBefore, "configurator must not change on revert");
        assertTrue(confBefore != address(0), "configurator should already be set in setUp");
    }

    function test_setConfigurator_asOwner_succeeds() public {
        address oldConf = managerContract.configurator();
        address newConf = address(uint160(0xAAA1));
        assertTrue(newConf != oldConf, "new configurator must differ from old");
        vm.prank(managerContract.owner());
        managerContract.setConfigurator(newConf);
        assertEq(managerContract.configurator(), newConf, "configurator should be updated");
    }

    function test_setConfigurator_zeroAddress_reverts() public {
        address confBefore = managerContract.configurator();
        vm.prank(managerContract.owner());
        vm.expectRevert(abi.encodeWithSelector(ZeroRole.selector));
        managerContract.setConfigurator(address(0));
        assertEq(managerContract.configurator(), confBefore, "configurator must not change on zero-address revert");
        assertTrue(confBefore != address(0), "pre-existing configurator should be non-zero");
    }

    // ROLE ISOLATION: onlyOwner -- setOperational

    function test_setOperational_asStranger_reverts() public {
        address opBefore = managerContract.operational();
        vm.prank(stranger);
        vm.expectRevert();
        managerContract.setOperational(address(uint160(0xAAA2)));
        assertEq(managerContract.operational(), opBefore, "operational must not change on revert");
        assertTrue(opBefore != address(0), "operational should already be set in setUp");
    }

    function test_setOperational_asOwner_succeeds() public {
        address oldOp = managerContract.operational();
        address newOp = address(uint160(0xAAA2));
        assertTrue(newOp != oldOp, "new operational must differ from old");
        vm.prank(managerContract.owner());
        managerContract.setOperational(newOp);
        assertEq(managerContract.operational(), newOp, "operational should be updated");
    }

    function test_setOperational_zeroAddress_reverts() public {
        address opBefore = managerContract.operational();
        vm.prank(managerContract.owner());
        vm.expectRevert(abi.encodeWithSelector(ZeroRole.selector));
        managerContract.setOperational(address(0));
        assertEq(managerContract.operational(), opBefore, "operational must not change on zero-address revert");
        assertTrue(opBefore != address(0), "pre-existing operational should be non-zero");
    }

    // ROLE ISOLATION: onlyOwner -- setHandlerProposer

    function test_setHandlerProposer_asStranger_reverts() public {
        address hpBefore = managerContract.handlerProposer();
        vm.prank(stranger);
        vm.expectRevert();
        managerContract.setHandlerProposer(address(uint160(0xAAA3)));
        assertEq(managerContract.handlerProposer(), hpBefore, "handlerProposer must not change on revert");
        assertEq(hpBefore, handlerProposer, "handlerProposer should match setUp value");
    }

    function test_setHandlerProposer_asOwner_succeeds() public {
        address oldHp = managerContract.handlerProposer();
        address newHp = address(uint160(0xAAA3));
        assertTrue(newHp != oldHp, "new handlerProposer must differ from old");
        vm.prank(managerContract.owner());
        managerContract.setHandlerProposer(newHp);
        assertEq(managerContract.handlerProposer(), newHp, "handlerProposer should be updated");
    }

    // ROLE ISOLATION: onlyOwner -- setAddressProposer

    function test_setAddressProposer_asStranger_reverts() public {
        address apBefore = managerContract.addressProposer();
        vm.prank(stranger);
        vm.expectRevert();
        managerContract.setAddressProposer(address(uint160(0xAAA4)));
        assertEq(managerContract.addressProposer(), apBefore, "addressProposer must not change on revert");
        assertEq(apBefore, addressProposer, "addressProposer should match setUp value");
    }

    function test_setAddressProposer_asOwner_succeeds() public {
        address oldAp = managerContract.addressProposer();
        address newAp = address(uint160(0xAAA4));
        assertTrue(newAp != oldAp, "new addressProposer must differ from old");
        vm.prank(managerContract.owner());
        managerContract.setAddressProposer(newAp);
        assertEq(managerContract.addressProposer(), newAp, "addressProposer should be updated");
    }

    // ROLE ISOLATION: onlyOwner -- setInitialCoreAddressBook

    function test_setInitialCoreAddressBook_asStranger_reverts() public {
        address ownerBefore = managerContract.owner();
        vm.prank(stranger);
        vm.expectRevert();
        managerContract.setInitialCoreAddressBook(
            vaultCoreNftFactory, IInitialCoreAddressBook(address(uint160(0xAAA5)))
        );
        assertEq(managerContract.owner(), ownerBefore, "owner must not change on revert");
        assertTrue(stranger != ownerBefore, "stranger must not be owner for this test to be valid");
    }

    // ROLE ISOLATION: onlyOwner -- addFeeSplitterTrackedToken

    function test_addFeeSplitterTrackedToken_asStranger_reverts() public {
        bool trackedBefore = feeSplitter.isTrackedToken(IERC20(USDT));
        vm.prank(stranger);
        vm.expectRevert();
        managerContract.addFeeSplitterTrackedToken(IERC20(USDT));
        assertEq(feeSplitter.isTrackedToken(IERC20(USDT)), trackedBefore, "tracked status must not change on revert");
        assertTrue(stranger != managerContract.owner(), "stranger must not be owner");
    }

    function test_addFeeSplitterTrackedToken_asOwner_succeeds() public {
        assertFalse(feeSplitter.isTrackedToken(IERC20(USDT)), "USDT should not be tracked before add");
        vm.prank(managerContract.owner());
        managerContract.addFeeSplitterTrackedToken(IERC20(USDT));
        // Verify token was added by checking FeeSplitter
        assertTrue(feeSplitter.isTrackedToken(IERC20(USDT)), "USDT should be tracked after add");
    }

    // ROLE ISOLATION: onlyConfigurator -- setVaultTargetLtv

    function test_setVaultTargetLtv_asStranger_reverts() public {
        uint256 ltvBefore = vaultState.targetLtvBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotConfigurator.selector));
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            5000
        );
        assertEq(vaultState.targetLtvBps(), ltvBefore, "targetLtvBps must not change on revert");
        assertTrue(stranger != configurator, "stranger must not be configurator");
    }

    function test_setVaultTargetLtv_asConfigurator_succeeds() public {
        uint256 ltvBefore = vaultState.targetLtvBps();
        assertTrue(ltvBefore != 4900, "targetLtvBps must differ from target for test validity");
        vm.prank(configurator);
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            4900
        );
        assertEq(vaultState.targetLtvBps(), 4900, "targetLtvBps should be 4900 after configurator set");
    }

    // ROLE ISOLATION: onlyConfigurator -- setVaultKeeperDeadline

    function test_setVaultKeeperDeadline_asStranger_reverts() public {
        uint256 deadlineBefore = vaultState.keeperDeadline();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotConfigurator.selector));
        managerContract.setVaultKeeperDeadline(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            120
        );
        assertEq(vaultState.keeperDeadline(), deadlineBefore, "keeperDeadline must not change on revert");
        assertTrue(stranger != configurator, "stranger must not be configurator");
    }

    function test_setVaultKeeperDeadline_asConfigurator_succeeds() public {
        uint256 deadlineBefore = vaultState.keeperDeadline();
        assertTrue(deadlineBefore != 120, "keeperDeadline must differ from 120 for test validity");
        vm.prank(configurator);
        managerContract.setVaultKeeperDeadline(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            120
        );
        assertEq(vaultState.keeperDeadline(), 120, "keeperDeadline should be 120 after configurator set");
    }

    // ROLE ISOLATION: onlyConfigurator -- setVaultRebalanceSlippageCapBps

    function test_setVaultRebalanceSlippageCapBps_asStranger_reverts() public {
        uint256 slippageBefore = vaultState.rebalanceSlippageCapBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotConfigurator.selector));
        managerContract.setVaultRebalanceSlippageCapBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            300
        );
        assertEq(vaultState.rebalanceSlippageCapBps(), slippageBefore, "rebalanceSlippageCapBps must not change on revert");
        assertTrue(stranger != configurator, "stranger must not be configurator");
    }

    function test_setVaultRebalanceSlippageCapBps_asConfigurator_succeeds() public {
        uint256 slippageBefore = vaultState.rebalanceSlippageCapBps();
        assertTrue(slippageBefore != 300, "rebalanceSlippageCapBps must differ from 300 for test validity");
        vm.prank(configurator);
        managerContract.setVaultRebalanceSlippageCapBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            300
        );
        assertEq(vaultState.rebalanceSlippageCapBps(), 300, "rebalanceSlippageCapBps should be 300");
    }

    // ROLE ISOLATION: onlyConfigurator -- setVaultUnwrapLongShareBps

    function test_setVaultUnwrapLongShareBps_asStranger_reverts() public {
        uint256 shareBefore = vaultState.unwrapLongShareBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotConfigurator.selector));
        managerContract.setVaultUnwrapLongShareBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            4500
        );
        assertEq(vaultState.unwrapLongShareBps(), shareBefore, "unwrapLongShareBps must not change on revert");
        assertTrue(stranger != configurator, "stranger must not be configurator");
    }

    function test_setVaultUnwrapLongShareBps_asConfigurator_succeeds() public {
        uint256 shareBefore = vaultState.unwrapLongShareBps();
        assertTrue(shareBefore != 4500, "unwrapLongShareBps must differ from 4500 for test validity");
        vm.prank(configurator);
        managerContract.setVaultUnwrapLongShareBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            4500
        );
        assertEq(vaultState.unwrapLongShareBps(), 4500, "unwrapLongShareBps should be 4500");
    }

    // ROLE ISOLATION: onlyConfigurator -- setVaultRebalanceThresholdUpBps

    function test_setVaultRebalanceThresholdUpBps_asStranger_reverts() public {
        uint256 threshBefore = vaultState.rebalanceThresholdUpBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotConfigurator.selector));
        managerContract.setVaultRebalanceThresholdUpBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            1000
        );
        assertEq(vaultState.rebalanceThresholdUpBps(), threshBefore, "rebalanceThresholdUpBps must not change on revert");
        assertTrue(stranger != configurator, "stranger must not be configurator");
    }

    function test_setVaultRebalanceThresholdUpBps_asConfigurator_succeeds() public {
        uint256 threshBefore = vaultState.rebalanceThresholdUpBps();
        assertTrue(threshBefore != 1000, "rebalanceThresholdUpBps must differ from 1000 for test validity");
        vm.prank(configurator);
        managerContract.setVaultRebalanceThresholdUpBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            1000
        );
        assertEq(vaultState.rebalanceThresholdUpBps(), 1000, "rebalanceThresholdUpBps should be 1000");
    }

    // ROLE ISOLATION: onlyConfigurator -- setVaultRebalanceThresholdDownBps

    function test_setVaultRebalanceThresholdDownBps_asStranger_reverts() public {
        uint256 threshBefore = vaultState.rebalanceThresholdDownBps();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotConfigurator.selector));
        managerContract.setVaultRebalanceThresholdDownBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            1500
        );
        assertEq(vaultState.rebalanceThresholdDownBps(), threshBefore, "rebalanceThresholdDownBps must not change on revert");
        assertTrue(stranger != configurator, "stranger must not be configurator");
    }

    function test_setVaultRebalanceThresholdDownBps_asConfigurator_succeeds() public {
        uint256 threshBefore = vaultState.rebalanceThresholdDownBps();
        assertTrue(threshBefore != 1500, "rebalanceThresholdDownBps must differ from 1500 for test validity");
        vm.prank(configurator);
        managerContract.setVaultRebalanceThresholdDownBps(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            1500
        );
        assertEq(vaultState.rebalanceThresholdDownBps(), 1500, "rebalanceThresholdDownBps should be 1500");
    }

    // CONFIG BOUNDARY VALUES: targetLtvBps

    function test_setVaultTargetLtv_belowMin_reverts() public {
        uint256 ltvBefore = vaultState.targetLtvBps();
        vm.prank(configurator);
        vm.expectRevert();
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            4799 // below MIN_TARGET_LTV_BPS (4800)
        );
        assertEq(vaultState.targetLtvBps(), ltvBefore, "targetLtvBps must not change on boundary revert");
        assertGe(ltvBefore, 4800, "initial targetLtvBps should be within valid range");
    }

    function test_setVaultTargetLtv_aboveMax_reverts() public {
        uint256 ltvBefore = vaultState.targetLtvBps();
        vm.prank(configurator);
        vm.expectRevert();
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            5201 // above MAX_TARGET_LTV_BPS (5200)
        );
        assertEq(vaultState.targetLtvBps(), ltvBefore, "targetLtvBps must not change on boundary revert");
        assertLe(ltvBefore, 5200, "initial targetLtvBps should be within valid range");
    }

    function test_setVaultTargetLtv_atMin_succeeds() public {
        vm.prank(configurator);
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            4800 // exactly MIN_TARGET_LTV_BPS
        );
        assertEq(vaultState.targetLtvBps(), 4800, "targetLtvBps should be 4800 at min boundary");
        assertGe(vaultState.targetLtvBps(), 4800, "targetLtvBps should be >= MIN_TARGET_LTV_BPS");
    }

    function test_setVaultTargetLtv_atMax_succeeds() public {
        vm.prank(configurator);
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            5200 // exactly MAX_TARGET_LTV_BPS
        );
        assertEq(vaultState.targetLtvBps(), 5200, "targetLtvBps should be 5200 at max boundary");
        assertLe(vaultState.targetLtvBps(), 5200, "targetLtvBps should be <= MAX_TARGET_LTV_BPS");
    }

    // CONFIG BOUNDARY VALUES: keeperDeadline

    function test_setVaultKeeperDeadline_belowMin_reverts() public {
        uint256 deadlineBefore = vaultState.keeperDeadline();
        vm.prank(configurator);
        vm.expectRevert();
        managerContract.setVaultKeeperDeadline(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            59 // below MIN_KEEPER_DEADLINE (60)
        );
        assertEq(vaultState.keeperDeadline(), deadlineBefore, "keeperDeadline must not change on boundary revert");
        assertGe(deadlineBefore, 60, "initial keeperDeadline should be within valid range");
    }

    function test_setVaultKeeperDeadline_aboveMax_reverts() public {
        uint256 deadlineBefore = vaultState.keeperDeadline();
        vm.prank(configurator);
        vm.expectRevert();
        managerContract.setVaultKeeperDeadline(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            3601 // above MAX_KEEPER_DEADLINE (3600)
        );
        assertEq(vaultState.keeperDeadline(), deadlineBefore, "keeperDeadline must not change on boundary revert");
        assertLe(deadlineBefore, 3600, "initial keeperDeadline should be within valid range");
    }

    function test_setVaultKeeperDeadline_atMin_succeeds() public {
        vm.prank(configurator);
        managerContract.setVaultKeeperDeadline(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            60 // exactly MIN_KEEPER_DEADLINE
        );
        assertEq(vaultState.keeperDeadline(), 60, "keeperDeadline should be 60 at min boundary");
        assertGe(vaultState.keeperDeadline(), 60, "keeperDeadline should be >= MIN_KEEPER_DEADLINE");
    }

    function test_setVaultKeeperDeadline_atMax_succeeds() public {
        vm.prank(configurator);
        managerContract.setVaultKeeperDeadline(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            3600 // exactly MAX_KEEPER_DEADLINE
        );
        assertEq(vaultState.keeperDeadline(), 3600, "keeperDeadline should be 3600 at max boundary");
        assertLe(vaultState.keeperDeadline(), 3600, "keeperDeadline should be <= MAX_KEEPER_DEADLINE");
    }

    // ROLE ISOLATION: onlyOperational

    function test_rebalanceVault_asStranger_reverts() public {
        assertTrue(stranger != managerContract.operational(), "stranger must not be operational");
        assertEq(managerContract.operational(), operational, "operational should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.rebalanceVault(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            100
        );
    }

    function test_finalizeDeposit_asStranger_reverts() public {
        assertTrue(stranger != managerContract.operational(), "stranger must not be operational");
        assertEq(managerContract.operational(), operational, "operational should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.finalizeDeposit(
            IDepositHandler(address(depositHandler)),
            IDepositHandlerVaultCore(address(vaultCore))
        );
    }

    function test_finalizeWithdraw_asStranger_reverts() public {
        assertTrue(stranger != managerContract.operational(), "stranger must not be operational");
        assertEq(managerContract.operational(), operational, "operational should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.finalizeWithdraw(
            IWithdrawHandler(address(withdrawHandler)),
            IWithdrawHandlerVaultCore(address(vaultCore))
        );
    }

    function test_finalizeRebalance_asStranger_reverts() public {
        assertTrue(stranger != managerContract.operational(), "stranger must not be operational");
        assertEq(managerContract.operational(), operational, "operational should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.finalizeRebalance(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore))
        );
    }

    function test_notifyFeeSplitterReward_asStranger_reverts() public {
        assertTrue(stranger != managerContract.operational(), "stranger must not be operational");
        assertEq(managerContract.operational(), operational, "operational should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.notifyFeeSplitterReward(IERC20(BasaltAddresses.USDC));
    }

    function test_accrueManagerFee_asStranger_reverts() public {
        assertTrue(stranger != managerContract.operational(), "stranger must not be operational");
        assertEq(managerContract.operational(), operational, "operational should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.accrueManagerFee(
            IFeeAccountingHandler(address(feeAccountingHandler)),
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );
    }

    function test_withdrawManagerFee_asStranger_reverts() public {
        assertTrue(stranger != managerContract.operational(), "stranger must not be operational");
        assertEq(managerContract.operational(), operational, "operational should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.withdrawManagerFee(
            IWithdrawHandler(address(withdrawHandler)),
            IWithdrawHandlerVaultCore(address(vaultCore)),
            1e18,
            0
        );
    }

    function test_collectManagerFeesFromVaultAndSweep_asStranger_reverts() public {
        assertTrue(stranger != managerContract.operational(), "stranger must not be operational");
        assertEq(managerContract.operational(), operational, "operational should match setUp");
        IERC20[] memory tokens = new IERC20[](0);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.collectManagerFeesFromVaultAndSweep(
            IWithdrawHandler(address(withdrawHandler)),
            IWithdrawHandlerVaultCore(address(vaultCore)),
            1e18,
            0,
            tokens
        );
    }

    function test_finalizeManagerFeeWithdrawAndSweep_asStranger_reverts() public {
        assertTrue(stranger != managerContract.operational(), "stranger must not be operational");
        assertEq(managerContract.operational(), operational, "operational should match setUp");
        IERC20[] memory tokens = new IERC20[](0);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.finalizeManagerFeeWithdrawAndSweep(
            IWithdrawHandler(address(withdrawHandler)),
            IWithdrawHandlerVaultCore(address(vaultCore)),
            tokens
        );
    }

    // ROLE ISOLATION: onlyHandlerProposer

    function test_proposeHandler_asStranger_reverts() public {
        assertTrue(stranger != managerContract.handlerProposer(), "stranger must not be handlerProposer");
        assertEq(managerContract.handlerProposer(), handlerProposer, "handlerProposer should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotHandlerProposer.selector));
        managerContract.proposeHandler(
            IVaultCoreGovernance(address(vaultCore)),
            address(depositHandler),
            address(uint160(0xBEEF01))
        );
    }

    /// @dev To test proposeHandler succeeding, we need factory.owner() == address(managerContract).
    ///      In the default ForkSetupFull, factory.owner() == factoryOwner (0x1001), so ManagerContract
    ///      can't call VaultCore.proposeHandler (NotManager). We create a separate factory where
    ///      owner = managerContract to test the full routing.
    function test_proposeHandler_asHandlerProposer_succeeds() public {
        // Deploy a new factory where owner = address(managerContract)
        VaultCoreNftFactory mcOwnedFactory = new VaultCoreNftFactory(
            initialCoreAddressBook,
            address(managerContract),
            address(managerContract)
        );
        // Create a vault through the new factory
        (, address mcVc) = mcOwnedFactory.createVaultCore(vaultOwner);

        address newHandler = address(uint160(0xBEEF01));
        vm.prank(handlerProposer);
        managerContract.proposeHandler(
            IVaultCoreGovernance(mcVc),
            address(depositHandler),
            newHandler
        );
        // Proposal should be active on vaultCore
        (address pendingOld, address pendingNew, bool exists) = VaultCore(payable(mcVc)).handlerProposal();
        assertTrue(exists, "handler proposal should exist");
        assertEq(pendingOld, address(depositHandler), "pending old handler should be depositHandler");
        assertEq(pendingNew, newHandler, "pending new handler should be newHandler");
    }

    function test_cancelHandlerProposal_asStranger_reverts() public {
        assertTrue(stranger != managerContract.handlerProposer(), "stranger must not be handlerProposer");
        assertEq(managerContract.handlerProposer(), handlerProposer, "handlerProposer should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotHandlerProposer.selector));
        managerContract.cancelHandlerProposal(IVaultCoreGovernance(address(vaultCore)));
    }

    // ROLE ISOLATION: onlyAddressProposer

    function test_proposeBasaltAddresses_asStranger_reverts() public {
        assertTrue(stranger != managerContract.addressProposer(), "stranger must not be addressProposer");
        assertEq(managerContract.addressProposer(), addressProposer, "addressProposer should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotAddressProposer.selector));
        managerContract.proposeBasaltAddresses(
            IVaultCoreGovernance(address(vaultCore)),
            address(uint160(0xBEEF02)),
            address(uint160(0xBEEF03))
        );
    }

    function test_proposeBasaltAddresses_asAddressProposer_succeeds() public {
        // Deploy a factory where owner = address(managerContract) so VaultCore.onlyManager passes
        VaultCoreNftFactory mcOwnedFactory = new VaultCoreNftFactory(
            initialCoreAddressBook,
            address(managerContract),
            address(managerContract)
        );
        (, address mcVc) = mcOwnedFactory.createVaultCore(vaultOwner);

        address newMath = address(uint160(0xBEEF02));
        address newState = address(uint160(0xBEEF03));
        vm.prank(addressProposer);
        managerContract.proposeBasaltAddresses(
            IVaultCoreGovernance(mcVc),
            newMath,
            newState
        );
        // Verify proposal is stored on vaultCore
        (address pendingMath, address pendingState, bool exists) = VaultCore(payable(mcVc)).basaltAddressesProposal();
        assertTrue(exists, "basalt addresses proposal should exist");
        assertEq(pendingMath, newMath, "pending math should be newMath");
        assertEq(pendingState, newState, "pending state should be newState");
    }

    function test_cancelBasaltAddressesProposal_asStranger_reverts() public {
        assertTrue(stranger != managerContract.addressProposer(), "stranger must not be addressProposer");
        assertEq(managerContract.addressProposer(), addressProposer, "addressProposer should match setUp");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotAddressProposer.selector));
        managerContract.cancelBasaltAddressesProposal(IVaultCoreGovernance(address(vaultCore)));
    }

    // FEE COLLECTOR GOVERNANCE

    function test_proposeFeeCollector_asStranger_reverts() public {
        address pendingBefore = managerContract.pendingFeeCollector();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotFeeCollector.selector));
        managerContract.proposeFeeCollector(address(uint160(0xCCC1)));
        assertEq(managerContract.pendingFeeCollector(), pendingBefore, "pendingFeeCollector must not change on revert");
        assertTrue(stranger != managerContract.feeCollector(), "stranger must not be feeCollector");
    }

    function test_proposeFeeCollector_asFeeCollector_succeeds() public {
        address newCollector = address(uint160(0xCCC1));
        assertEq(managerContract.pendingFeeCollector(), address(0), "pendingFeeCollector should be zero before propose");
        vm.prank(feeCollector);
        managerContract.proposeFeeCollector(newCollector);
        assertEq(managerContract.pendingFeeCollector(), newCollector, "pending fee collector should be set");
        assertEq(managerContract.feeCollector(), feeCollector, "active feeCollector must not change on propose");
    }

    function test_proposeFeeCollector_zeroAddress_reverts() public {
        address pendingBefore = managerContract.pendingFeeCollector();
        vm.prank(feeCollector);
        vm.expectRevert(abi.encodeWithSelector(ZeroRole.selector));
        managerContract.proposeFeeCollector(address(0));
        assertEq(managerContract.pendingFeeCollector(), pendingBefore, "pendingFeeCollector must not change on revert");
        assertEq(managerContract.feeCollector(), feeCollector, "feeCollector must not change on revert");
    }

    function test_acceptFeeCollector_asStranger_reverts() public {
        // Propose first
        address newCollector = address(uint160(0xCCC1));
        vm.prank(feeCollector);
        managerContract.proposeFeeCollector(newCollector);

        address collectorBefore = managerContract.feeCollector();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(NotPendingRole.selector, stranger, newCollector)
        );
        managerContract.acceptFeeCollector();
        assertEq(managerContract.feeCollector(), collectorBefore, "feeCollector must not change on revert");
        assertEq(managerContract.pendingFeeCollector(), newCollector, "pendingFeeCollector must remain set after failed accept");
    }

    function test_acceptFeeCollector_asPendingCollector_succeeds() public {
        address newCollector = address(uint160(0xCCC1));
        vm.prank(feeCollector);
        managerContract.proposeFeeCollector(newCollector);

        vm.prank(newCollector);
        managerContract.acceptFeeCollector();
        assertEq(managerContract.feeCollector(), newCollector, "feeCollector should be updated after accept");
        assertEq(managerContract.pendingFeeCollector(), address(0), "pendingFeeCollector should be cleared");
    }

    // PROTOCOL MANAGER GOVERNANCE

    /// @dev Helper: factoryOwner holds all fee shares. Give voting weight and advance 1 block for snapshot.
    function _setupGovernanceVoter() internal returns (address voter) {
        voter = factoryOwner;
        // factoryOwner is the initial share owner in FeeSplitter and already self-delegated
        // Advance 1 block so getPastVotes works (snapshot = block.number - 1)
        vm.roll(block.number + 1);
    }

    function test_proposeProtocolManagerChange_succeeds() public {
        address voter = _setupGovernanceVoter();
        address nextManager = address(uint160(0xDDD1));

        vm.prank(voter);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, nextManager);
        assertGt(proposalId, 0, "proposalId should be non-zero");
        assertEq(
            managerContract.activeProtocolManagerProposalId(),
            proposalId,
            "activeProtocolManagerProposalId should match"
        );
    }

    function test_proposeProtocolManagerChange_zeroFactory_reverts() public {
        _setupGovernanceVoter();
        uint256 proposalIdBefore = managerContract.nextProtocolManagerProposalId();
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(ZeroFactory.selector));
        managerContract.proposeProtocolManagerChange(VaultCoreNftFactory(address(0)), address(uint160(0xDDD1)));
        assertEq(managerContract.nextProtocolManagerProposalId(), proposalIdBefore, "nextProposalId must not change on revert");
        assertEq(managerContract.activeProtocolManagerProposalId(), 0, "activeProposalId must remain 0 on revert");
    }

    function test_proposeProtocolManagerChange_zeroNextManager_reverts() public {
        _setupGovernanceVoter();
        uint256 proposalIdBefore = managerContract.nextProtocolManagerProposalId();
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(ZeroProtocolManager.selector));
        managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, address(0));
        assertEq(managerContract.nextProtocolManagerProposalId(), proposalIdBefore, "nextProposalId must not change on revert");
        assertEq(managerContract.activeProtocolManagerProposalId(), 0, "activeProposalId must remain 0 on revert");
    }

    function test_proposeProtocolManagerChange_noVotingWeight_reverts() public {
        vm.roll(block.number + 1);
        uint256 proposalIdBefore = managerContract.nextProtocolManagerProposalId();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NoVotingWeight.selector));
        managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, address(uint160(0xDDD1)));
        assertEq(managerContract.nextProtocolManagerProposalId(), proposalIdBefore, "nextProposalId must not change on revert");
        assertEq(managerContract.activeProtocolManagerProposalId(), 0, "activeProposalId must remain 0 on revert");
    }

    function test_proposeProtocolManagerChange_duplicateActive_reverts() public {
        address voter = _setupGovernanceVoter();
        address nextManager = address(uint160(0xDDD1));

        vm.prank(voter);
        uint256 firstId = managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, nextManager);

        uint256 nextIdAfterFirst = managerContract.nextProtocolManagerProposalId();
        vm.roll(block.number + 1);
        vm.prank(voter);
        vm.expectRevert(abi.encodeWithSelector(ActiveProposalExists.selector, firstId));
        managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, address(uint160(0xDDD2)));
        assertEq(managerContract.activeProtocolManagerProposalId(), firstId, "activeProposalId must still be firstId");
        assertEq(managerContract.nextProtocolManagerProposalId(), nextIdAfterFirst, "nextProposalId must not increment on revert");
    }

    function test_signProtocolManagerChange_succeeds() public {
        address voter = _setupGovernanceVoter();
        address nextManager = address(uint160(0xDDD1));

        vm.prank(voter);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, nextManager);

        vm.prank(voter);
        managerContract.signProtocolManagerChange(proposalId);

        (,,,uint256 yesWeight,,,,) = managerContract.protocolManagerProposals(proposalId);
        assertGt(yesWeight, 0, "yesWeight should be non-zero after signing");
    }

    function test_signProtocolManagerChange_noWeight_reverts() public {
        address voter = _setupGovernanceVoter();

        vm.prank(voter);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, address(uint160(0xDDD1)));

        (,,,uint256 yesWeightBefore,,,,) = managerContract.protocolManagerProposals(proposalId);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NoVotingWeight.selector));
        managerContract.signProtocolManagerChange(proposalId);
        (,,,uint256 yesWeightAfter,,,,) = managerContract.protocolManagerProposals(proposalId);
        assertEq(yesWeightAfter, yesWeightBefore, "yesWeight must not change on revert");
    }

    function test_signProtocolManagerChange_doubleSigning_reverts() public {
        address voter = _setupGovernanceVoter();

        vm.prank(voter);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, address(uint160(0xDDD1)));

        vm.prank(voter);
        managerContract.signProtocolManagerChange(proposalId);

        (,,,uint256 yesWeightAfterFirst,,,,) = managerContract.protocolManagerProposals(proposalId);
        vm.prank(voter);
        vm.expectRevert(abi.encodeWithSelector(AlreadySigned.selector));
        managerContract.signProtocolManagerChange(proposalId);
        (,,,uint256 yesWeightAfterSecond,,,,) = managerContract.protocolManagerProposals(proposalId);
        assertEq(yesWeightAfterSecond, yesWeightAfterFirst, "yesWeight must not change on double-sign revert");
    }

    function test_executeProtocolManagerChange_beforeThreshold_reverts() public {
        address voter = _setupGovernanceVoter();
        address nextManager = address(uint160(0xDDD1));

        vm.prank(voter);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, nextManager);

        address pmBefore = vaultCoreNftFactory.protocolManager();
        // Do NOT sign -- try to execute without sufficient votes
        vm.prank(voter);
        vm.expectRevert(abi.encodeWithSelector(InsufficientFeeParticipantSupport.selector));
        managerContract.executeProtocolManagerChange(proposalId);
        assertEq(vaultCoreNftFactory.protocolManager(), pmBefore, "protocolManager must not change on revert");
        (,,,,,, bool executed,) = managerContract.protocolManagerProposals(proposalId);
        assertFalse(executed, "proposal must not be marked executed on revert");
    }

    function test_executeProtocolManagerChange_afterThreshold_succeeds() public {
        address voter = _setupGovernanceVoter();
        address nextManager = address(uint160(0xDDD1));

        vm.prank(voter);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, nextManager);

        // voter holds 100% of supply, threshold is 80% -- signing once is enough
        vm.prank(voter);
        managerContract.signProtocolManagerChange(proposalId);

        vm.prank(voter);
        managerContract.executeProtocolManagerChange(proposalId);

        // Verify factory's protocolManager changed
        assertEq(
            vaultCoreNftFactory.protocolManager(),
            nextManager,
            "factory protocolManager should be updated after execution"
        );

        // Verify proposal state
        (,,,,,, bool executed,) = managerContract.protocolManagerProposals(proposalId);
        assertTrue(executed, "proposal should be marked executed");

        // Active proposal cleared
        assertEq(managerContract.activeProtocolManagerProposalId(), 0, "activeProtocolManagerProposalId should be 0");
    }

    function test_cancelProtocolManagerChange_succeeds() public {
        address voter = _setupGovernanceVoter();
        address nextManager = address(uint160(0xDDD1));

        vm.prank(voter);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, nextManager);

        // Sign cancel with 100% weight (above 80% threshold)
        vm.prank(voter);
        managerContract.signProtocolManagerChangeCancel(proposalId);

        vm.prank(voter);
        managerContract.cancelProtocolManagerChange(proposalId);

        // Verify proposal cancelled
        (,,,,,,, bool cancelled) = managerContract.protocolManagerProposals(proposalId);
        assertTrue(cancelled, "proposal should be marked cancelled");

        // Active proposal cleared
        assertEq(managerContract.activeProtocolManagerProposalId(), 0, "activeProtocolManagerProposalId should be 0");
    }

    function test_cancelProtocolManagerChange_insufficientCancelWeight_reverts() public {
        address voter = _setupGovernanceVoter();

        vm.prank(voter);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(vaultCoreNftFactory, address(uint160(0xDDD1)));

        // Do NOT sign cancel -- try to cancel without sufficient votes
        vm.prank(voter);
        vm.expectRevert(abi.encodeWithSelector(InsufficientCancelSupport.selector));
        managerContract.cancelProtocolManagerChange(proposalId);
        (,,,,,,, bool cancelled) = managerContract.protocolManagerProposals(proposalId);
        assertFalse(cancelled, "proposal must not be marked cancelled on revert");
        assertEq(managerContract.activeProtocolManagerProposalId(), proposalId, "activeProposalId must remain set");
    }

    // FEE OPERATIONS: collectFees (holder OR operational)

    function test_collectFees_sweepsToFeeSplitter() public {
        uint256 amount = 1000e6;
        deal(BasaltAddresses.USDC, address(managerContract), amount);
        uint256 splitterBalBefore = IERC20(BasaltAddresses.USDC).balanceOf(address(feeSplitter));

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(BasaltAddresses.USDC);

        vm.prank(operational);
        managerContract.collectFees(tokens);

        uint256 splitterBalAfter = IERC20(BasaltAddresses.USDC).balanceOf(address(feeSplitter));
        assertEq(
            splitterBalAfter - splitterBalBefore,
            amount,
            "feeSplitter should have received all USDC from managerContract"
        );
        assertEq(
            IERC20(BasaltAddresses.USDC).balanceOf(address(managerContract)),
            0,
            "managerContract USDC balance should be 0 after sweep"
        );
    }

    function test_collectFees_zeroBalance_noOp() public {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(BasaltAddresses.USDC);

        uint256 splitterBalBefore = IERC20(BasaltAddresses.USDC).balanceOf(address(feeSplitter));
        assertEq(IERC20(BasaltAddresses.USDC).balanceOf(address(managerContract)), 0, "managerContract USDC should be zero before test");
        vm.prank(operational);
        managerContract.collectFees(tokens);
        uint256 splitterBalAfter = IERC20(BasaltAddresses.USDC).balanceOf(address(feeSplitter));
        assertEq(splitterBalAfter, splitterBalBefore, "no tokens should move when balance is zero");
    }

    function test_collectFees_multipleTokens_sweepsAll() public {
        // Deal USDC and WETH to managerContract
        uint256 usdcAmount = 500e6;
        uint256 wethAmount = 1e18;
        deal(BasaltAddresses.USDC, address(managerContract), usdcAmount);
        deal(BasaltAddresses.WETH, address(managerContract), wethAmount);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(BasaltAddresses.USDC);
        tokens[1] = IERC20(BasaltAddresses.WETH);

        uint256 usdcBefore = IERC20(BasaltAddresses.USDC).balanceOf(address(feeSplitter));
        uint256 wethBefore = IERC20(BasaltAddresses.WETH).balanceOf(address(feeSplitter));

        vm.prank(operational);
        managerContract.collectFees(tokens);

        assertEq(
            IERC20(BasaltAddresses.USDC).balanceOf(address(feeSplitter)) - usdcBefore,
            usdcAmount,
            "feeSplitter should receive all USDC"
        );
        assertEq(
            IERC20(BasaltAddresses.WETH).balanceOf(address(feeSplitter)) - wethBefore,
            wethAmount,
            "feeSplitter should receive all WETH"
        );
        assertEq(
            IERC20(BasaltAddresses.USDC).balanceOf(address(managerContract)),
            0,
            "managerContract USDC balance should be 0 after sweep"
        );
        assertEq(
            IERC20(BasaltAddresses.WETH).balanceOf(address(managerContract)),
            0,
            "managerContract WETH balance should be 0 after sweep"
        );
    }
}

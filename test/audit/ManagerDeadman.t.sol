// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../helpers/ForkSetupFull.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {NotNftOwner, DeadmanAlreadyTriggered, NotManager as VcNotManager} from "../../src/core/vaultCoreLibraries/VaultCoreTypes.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";
import {NotOperational} from "../../src/core/managerContractLibraries/ManagerContractTypes.sol";
import {IManagerHandler} from "../../src/interfaces/IManagerHandler.sol";
import {IManagerHandlerVaultCore} from "../../src/interfaces/IManagerHandlerVaultCore.sol";
import {NotNftOwner, DeadmanAlreadyTriggered, NotManager as VcNotManager} from "../../src/core/vaultCoreLibraries/VaultCoreTypes.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";

contract ManagerDeadmanTest is ForkSetupFull {
    address internal newHandler;

    function setUp() public override {
        super.setUp();
        newHandler = address(uint160(0xDEAD01));
    }

    function _rollPastDeadman() internal {
        vm.roll(block.number + BasaltConstants.MANAGER_DEADMAN_BLOCKS + 1);
    }

    function _rollCooldown() internal {
        uint256 endBlock = vaultState.globalActionCooldownEndBlock();
        if (block.number <= endBlock) {
            vm.roll(endBlock + 1);
        }
    }

    function test_lastManagerActionBlock_initializedToCreationBlock() public view {
        assertGt(vaultState.lastManagerActionBlock(), 0, "should be set on initialize");
        assertEq(vaultState.managerDeadmanTriggered(), false, "deadman should be off initially");
    }

    function test_pingHeartbeat_asOperational_bumpsLastAction() public {
        uint256 before = vaultState.lastManagerActionBlock();
        vm.roll(block.number + 100);

        vm.prank(operational);
        managerContract.pingVaultHeartbeat(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore))
        );

        assertEq(vaultState.lastManagerActionBlock(), block.number, "ping should set to current block");
        assertGt(vaultState.lastManagerActionBlock(), before, "ping should bump forward");
    }

    function test_pingVaultHeartbeat_asStranger_reverts() public {
        uint256 lastBefore = vaultState.lastManagerActionBlock();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotOperational.selector));
        managerContract.pingVaultHeartbeat(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore))
        );
        assertEq(vaultState.lastManagerActionBlock(), lastBefore, "lastManagerActionBlock unchanged after revert");
    }

    function test_pingHeartbeat_directCall_asStranger_reverts() public {
        uint256 lastBefore = vaultState.lastManagerActionBlock();
        vm.prank(stranger);
        vm.expectRevert();
        managerHandler.pingHeartbeat(IManagerHandlerVaultCore(address(vaultCore)));
        assertEq(vaultState.lastManagerActionBlock(), lastBefore, "lastManagerActionBlock unchanged after direct revert");
    }

    function test_setTargetLtv_bumpsLastManagerAction() public {
        _rollCooldown();
        vm.roll(block.number + 50);

        vm.prank(configurator);
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            5_100
        );

        assertEq(vaultState.lastManagerActionBlock(), block.number, "setTargetLtv should bump");
        assertEq(vaultState.targetLtvBps(), 5_100, "targetLtv value should be applied");
    }

    function test_triggerDeadman_beforePeriod_reverts() public {
        assertEq(vaultState.managerDeadmanTriggered(), false, "deadman should be off before attempt");
        vm.prank(vaultOwner);
        vm.expectRevert();
        vaultCore.triggerManagerDeadman();
        assertEq(vaultState.managerDeadmanTriggered(), false, "deadman unchanged after early revert");
    }

    function test_triggerDeadman_asNonNftOwner_reverts() public {
        _rollPastDeadman();

        assertEq(vaultState.managerDeadmanTriggered(), false, "deadman should be off before attempt");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotNftOwner.selector));
        vaultCore.triggerManagerDeadman();
        assertEq(vaultState.managerDeadmanTriggered(), false, "deadman unchanged after non-owner revert");
    }

    function test_triggerDeadman_afterPeriod_succeeds_emitsEvent() public {
        _rollPastDeadman();
        uint256 lastAction = vaultState.lastManagerActionBlock();

        vm.expectEmit(true, false, false, true, address(vaultCore));
        emit VaultCore.ManagerDeadmanTriggered(vaultOwner, block.number, lastAction);
        vm.prank(vaultOwner);
        vaultCore.triggerManagerDeadman();

        assertEq(vaultState.managerDeadmanTriggered(), true, "flag should latch");
        assertGt(block.number, lastAction + BasaltConstants.MANAGER_DEADMAN_BLOCKS, "trigger block past deadman period");
    }

    function test_triggerDeadman_alreadyTriggered_reverts() public {
        _rollPastDeadman();
        vm.prank(vaultOwner);
        vaultCore.triggerManagerDeadman();
        assertEq(vaultState.managerDeadmanTriggered(), true, "deadman should be on after first trigger");

        vm.prank(vaultOwner);
        vm.expectRevert(DeadmanAlreadyTriggered.selector);
        vaultCore.triggerManagerDeadman();
        assertEq(vaultState.managerDeadmanTriggered(), true, "deadman still on after duplicate revert");
    }

    function test_afterDeadman_nftOwner_canProposeHandler() public {
        _rollPastDeadman();
        vm.prank(vaultOwner);
        vaultCore.triggerManagerDeadman();

        vm.prank(vaultOwner);
        vaultCore.proposeHandler(address(depositHandler), newHandler);

        (address oldH, address newH, bool exists) = vaultCore.handlerProposal();
        assertEq(oldH, address(depositHandler), "old handler set");
        assertEq(newH, newHandler, "new handler set");
        assertEq(exists, true, "proposal exists");
    }

    function test_afterDeadman_nftOwner_canProposeBasaltAddresses() public {
        _rollPastDeadman();
        vm.prank(vaultOwner);
        vaultCore.triggerManagerDeadman();

        vm.prank(vaultOwner);
        vaultCore.proposeBasaltAddresses(address(0xAAAA), address(0xBBBB));

        (address pMath, address pState, bool exists) = vaultCore.basaltAddressesProposal();
        assertEq(pMath, address(0xAAAA), "math proposed");
        assertEq(pState, address(0xBBBB), "state proposed");
        assertEq(exists, true, "proposal exists");
    }

    function test_afterDeadman_strangerStill_cannotProposeHandler() public {
        _rollPastDeadman();
        vm.prank(vaultOwner);
        vaultCore.triggerManagerDeadman();
        assertEq(vaultState.managerDeadmanTriggered(), true, "deadman triggered");

        vm.prank(stranger);
        vm.expectRevert(VcNotManager.selector);
        vaultCore.proposeHandler(address(depositHandler), newHandler);
        (,, bool exists) = vaultCore.handlerProposal();
        assertEq(exists, false, "no proposal should exist after stranger revert");
    }

    function test_oneWay_managerBumpAfterTrigger_nftOwnerStillHasRights() public {
        _rollPastDeadman();
        vm.prank(vaultOwner);
        vaultCore.triggerManagerDeadman();

        vm.prank(operational);
        managerContract.pingVaultHeartbeat(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore))
        );
        assertEq(vaultState.managerDeadmanTriggered(), true, "flag stays latched after manager activity");

        vm.prank(vaultOwner);
        vaultCore.proposeHandler(address(depositHandler), newHandler);
        (,, bool exists) = vaultCore.handlerProposal();
        assertEq(exists, true, "nftOwner still has rights after manager bump");
    }

    function test_beforeDeadman_nftOwner_cannotProposeHandler() public {
        assertEq(vaultState.managerDeadmanTriggered(), false, "deadman should be off");
        vm.prank(vaultOwner);
        vm.expectRevert(VcNotManager.selector);
        vaultCore.proposeHandler(address(depositHandler), newHandler);
        (,, bool exists) = vaultCore.handlerProposal();
        assertEq(exists, false, "no proposal after revert");
    }
}

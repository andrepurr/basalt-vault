// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {VaultCore} from "../../../src/core/VaultCore.sol";
import {
    NotManager, NotHandler, NotNftOwner, NotManagerOrNftOwner,
    NoHandlerProposal, NoBasaltAddressesProposal, UnknownHandler,
    ZeroHandler, DuplicateHandler
} from "../../../src/core/vaultCoreLibraries/VaultCoreTypes.sol";
import {VaultCoreNftFactory} from "../../../src/core/VaultCoreNftFactory.sol";

/// @title VaultCore access control and governance proposal flow unit tests
contract VaultCoreUnit is ForkSetupFull {
    // ── Helpers ──────────────────────────────────────────────────────────

    address internal newHandler;

    function setUp() public override {
        super.setUp();
        // A dummy address that is NOT already a handler slot, used as newHandler in proposals
        newHandler = address(uint160(0xBEEF01));
    }

    // ══════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL: proposeHandler
    // ══════════════════════════════════════════════════════════════════════

    function test_proposeHandler_asStranger_reverts() public {
        (, , bool existsBefore) = vaultCore.handlerProposal();
        assertFalse(existsBefore, "pre: no proposal should exist");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotManager.selector));
        vaultCore.proposeHandler(address(depositHandler), newHandler);

        (, , bool existsAfter) = vaultCore.handlerProposal();
        assertFalse(existsAfter, "post: proposal must remain absent after revert");
    }

    function test_proposeHandler_asManager_succeeds() public {
        // onlyManager checks factory.protocolManager() == address(managerContract)
        vm.prank(address(managerContract));
        vaultCore.proposeHandler(address(depositHandler), newHandler);

        (address oldH, address newH, bool exists) = vaultCore.handlerProposal();
        assertEq(oldH, address(depositHandler), "proposeHandler: old handler mismatch");
        assertEq(newH, newHandler, "proposeHandler: new handler mismatch");
        assertTrue(exists, "proposeHandler: proposal should exist");
    }

    // ══════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL: acceptHandler
    // ══════════════════════════════════════════════════════════════════════

    function test_acceptHandler_asStranger_reverts() public {
        address handlerBefore = vaultCore.depositHandler();

        // First create a proposal so there is something to accept
        vm.prank(address(managerContract));
        vaultCore.proposeHandler(address(depositHandler), newHandler);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotNftOwner.selector));
        vaultCore.acceptHandler();

        assertEq(vaultCore.depositHandler(), handlerBefore, "post: handler must remain unchanged after revert");
        (, , bool exists) = vaultCore.handlerProposal();
        assertTrue(exists, "post: proposal must still exist after failed accept");
    }

    function test_acceptHandler_asNftOwner_succeeds() public {
        vm.prank(address(managerContract));
        vaultCore.proposeHandler(address(depositHandler), newHandler);

        vm.prank(vaultOwner);
        vaultCore.acceptHandler();

        assertEq(vaultCore.depositHandler(), newHandler, "acceptHandler: handler not replaced");
        (, , bool exists) = vaultCore.handlerProposal();
        assertFalse(exists, "acceptHandler: proposal should be cleared after accept");
    }

    // ══════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL: cancelHandlerProposal
    // ══════════════════════════════════════════════════════════════════════

    function test_cancelHandlerProposal_asStranger_reverts() public {
        vm.prank(address(managerContract));
        vaultCore.proposeHandler(address(depositHandler), newHandler);

        (, , bool existsBefore) = vaultCore.handlerProposal();
        assertTrue(existsBefore, "pre: proposal must exist before cancel attempt");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotManagerOrNftOwner.selector));
        vaultCore.cancelHandlerProposal();

        (, , bool existsAfter) = vaultCore.handlerProposal();
        assertTrue(existsAfter, "post: proposal must survive failed cancel");
    }

    function test_cancelHandlerProposal_asManager_succeeds() public {
        address handlerBefore = vaultCore.depositHandler();

        vm.prank(address(managerContract));
        vaultCore.proposeHandler(address(depositHandler), newHandler);

        vm.prank(address(managerContract));
        vaultCore.cancelHandlerProposal();

        (, , bool exists) = vaultCore.handlerProposal();
        assertFalse(exists, "cancelHandlerProposal by manager: proposal should be deleted");
        assertEq(vaultCore.depositHandler(), handlerBefore, "cancel: handler must remain unchanged");
    }

    function test_cancelHandlerProposal_asNftOwner_succeeds() public {
        address handlerBefore = vaultCore.depositHandler();

        vm.prank(address(managerContract));
        vaultCore.proposeHandler(address(depositHandler), newHandler);

        vm.prank(vaultOwner);
        vaultCore.cancelHandlerProposal();

        (, , bool exists) = vaultCore.handlerProposal();
        assertFalse(exists, "cancelHandlerProposal by nftOwner: proposal should be deleted");
        assertEq(vaultCore.depositHandler(), handlerBefore, "cancel by owner: handler must remain unchanged");
    }

    // ══════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL: proposeBasaltAddresses
    // ══════════════════════════════════════════════════════════════════════

    function test_proposeBasaltAddresses_asStranger_reverts() public {
        (, , bool existsBefore) = vaultCore.basaltAddressesProposal();
        assertFalse(existsBefore, "pre: no basalt proposal should exist");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotManager.selector));
        vaultCore.proposeBasaltAddresses(address(0xAAAA), address(0xBBBB));

        (, , bool existsAfter) = vaultCore.basaltAddressesProposal();
        assertFalse(existsAfter, "post: basalt proposal must remain absent after revert");
    }

    function test_proposeBasaltAddresses_asManager_succeeds() public {
        address newMath = address(uint160(0xAAAA));
        address newState = address(uint160(0xBBBB));

        vm.prank(address(managerContract));
        vaultCore.proposeBasaltAddresses(newMath, newState);

        (address pMath, address pState, bool exists) = vaultCore.basaltAddressesProposal();
        assertEq(pMath, newMath, "proposeBasaltAddresses: math mismatch");
        assertEq(pState, newState, "proposeBasaltAddresses: state mismatch");
        assertTrue(exists, "proposeBasaltAddresses: proposal should exist");
    }

    // ══════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL: acceptBasaltAddresses
    // ══════════════════════════════════════════════════════════════════════

    function test_acceptBasaltAddresses_asStranger_reverts() public {
        address mathBefore = vaultCore.basaltMath();
        address stateBefore = vaultCore.basaltState();

        vm.prank(address(managerContract));
        vaultCore.proposeBasaltAddresses(address(0xAAAA), address(0xBBBB));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotNftOwner.selector));
        vaultCore.acceptBasaltAddresses();

        assertEq(vaultCore.basaltMath(), mathBefore, "post: basaltMath must remain unchanged");
        assertEq(vaultCore.basaltState(), stateBefore, "post: basaltState must remain unchanged");
    }

    function test_acceptBasaltAddresses_asNftOwner_succeeds() public {
        address newMath = address(uint160(0xAAAA));
        address newState = address(uint160(0xBBBB));

        vm.prank(address(managerContract));
        vaultCore.proposeBasaltAddresses(newMath, newState);

        vm.prank(vaultOwner);
        vaultCore.acceptBasaltAddresses();

        assertEq(vaultCore.basaltMath(), newMath, "acceptBasaltAddresses: math not updated");
        assertEq(vaultCore.basaltState(), newState, "acceptBasaltAddresses: state not updated");
        (, , bool exists) = vaultCore.basaltAddressesProposal();
        assertFalse(exists, "acceptBasaltAddresses: proposal should be cleared after accept");
    }

    // ══════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL: cancelBasaltAddressesProposal
    // ══════════════════════════════════════════════════════════════════════

    function test_cancelBasaltAddressesProposal_asStranger_reverts() public {
        vm.prank(address(managerContract));
        vaultCore.proposeBasaltAddresses(address(0xAAAA), address(0xBBBB));

        (, , bool existsBefore) = vaultCore.basaltAddressesProposal();
        assertTrue(existsBefore, "pre: basalt proposal must exist");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotManagerOrNftOwner.selector));
        vaultCore.cancelBasaltAddressesProposal();

        (, , bool existsAfter) = vaultCore.basaltAddressesProposal();
        assertTrue(existsAfter, "post: basalt proposal must survive failed cancel");
    }

    function test_cancelBasaltAddressesProposal_asManager_succeeds() public {
        address mathBefore = vaultCore.basaltMath();

        vm.prank(address(managerContract));
        vaultCore.proposeBasaltAddresses(address(0xAAAA), address(0xBBBB));

        vm.prank(address(managerContract));
        vaultCore.cancelBasaltAddressesProposal();

        (, , bool exists) = vaultCore.basaltAddressesProposal();
        assertFalse(exists, "cancelBasaltAddresses by manager: proposal should be deleted");
        assertEq(vaultCore.basaltMath(), mathBefore, "cancel basalt: math must remain unchanged");
    }

    function test_cancelBasaltAddressesProposal_asNftOwner_succeeds() public {
        address stateBefore = vaultCore.basaltState();

        vm.prank(address(managerContract));
        vaultCore.proposeBasaltAddresses(address(0xAAAA), address(0xBBBB));

        vm.prank(vaultOwner);
        vaultCore.cancelBasaltAddressesProposal();

        (, , bool exists) = vaultCore.basaltAddressesProposal();
        assertFalse(exists, "cancelBasaltAddresses by nftOwner: proposal should be deleted");
        assertEq(vaultCore.basaltState(), stateBefore, "cancel basalt by owner: state must remain unchanged");
    }

    // ══════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL: universalCall
    // ══════════════════════════════════════════════════════════════════════

    function test_universalCall_asStranger_reverts() public {
        assertEq(vaultCore.depositHandler(), address(depositHandler), "pre: deposit handler set");
        assertEq(vaultCore.withdrawHandler(), address(withdrawHandler), "pre: withdraw handler set");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotHandler.selector));
        vaultCore.universalCall(vaultOwner, address(0), "", 0, false);
    }

    // ══════════════════════════════════════════════════════════════════════
    // HANDLER PROPOSAL FLOW
    // ══════════════════════════════════════════════════════════════════════

    function test_proposeHandler_thenAccept_replacesHandler() public {
        address oldDepositHandler = vaultCore.depositHandler();

        vm.prank(address(managerContract));
        vaultCore.proposeHandler(oldDepositHandler, newHandler);

        vm.prank(vaultOwner);
        vaultCore.acceptHandler();

        assertEq(vaultCore.depositHandler(), newHandler, "propose+accept: deposit handler should be replaced");
        assertTrue(vaultCore.depositHandler() != oldDepositHandler, "propose+accept: old handler should differ");
    }

    function test_proposeHandler_thenCancel_noChange() public {
        address oldDepositHandler = vaultCore.depositHandler();

        vm.prank(address(managerContract));
        vaultCore.proposeHandler(oldDepositHandler, newHandler);

        vm.prank(address(managerContract));
        vaultCore.cancelHandlerProposal();

        assertEq(vaultCore.depositHandler(), oldDepositHandler, "propose+cancel: handler should be unchanged");
        (, , bool exists) = vaultCore.handlerProposal();
        assertFalse(exists, "propose+cancel: proposal must be cleared");
    }

    function test_proposeBasaltAddresses_thenAccept_updatesAddresses() public {
        address newMath = address(uint160(0xAAAA));
        address newState = address(uint160(0xBBBB));

        vm.prank(address(managerContract));
        vaultCore.proposeBasaltAddresses(newMath, newState);

        vm.prank(vaultOwner);
        vaultCore.acceptBasaltAddresses();

        assertEq(vaultCore.basaltMath(), newMath, "propose+accept basalt: math not updated");
        assertEq(vaultCore.basaltState(), newState, "propose+accept basalt: state not updated");
        (, , bool exists) = vaultCore.basaltAddressesProposal();
        assertFalse(exists, "propose+accept basalt: proposal should be cleared");
    }

    function test_acceptHandler_withoutProposal_reverts() public {
        (, , bool existsBefore) = vaultCore.handlerProposal();
        assertFalse(existsBefore, "pre: no handler proposal should exist");

        address handlerBefore = vaultCore.depositHandler();

        vm.prank(vaultOwner);
        vm.expectRevert(abi.encodeWithSelector(NoHandlerProposal.selector));
        vaultCore.acceptHandler();

        assertEq(vaultCore.depositHandler(), handlerBefore, "post: handler must remain unchanged");
    }

    function test_acceptBasaltAddresses_withoutProposal_reverts() public {
        (, , bool existsBefore) = vaultCore.basaltAddressesProposal();
        assertFalse(existsBefore, "pre: no basalt proposal should exist");

        address mathBefore = vaultCore.basaltMath();

        vm.prank(vaultOwner);
        vm.expectRevert(abi.encodeWithSelector(NoBasaltAddressesProposal.selector));
        vaultCore.acceptBasaltAddresses();

        assertEq(vaultCore.basaltMath(), mathBefore, "post: basaltMath must remain unchanged");
    }

    function test_cancelHandlerProposal_withoutProposal_reverts() public {
        (, , bool existsBefore) = vaultCore.handlerProposal();
        assertFalse(existsBefore, "pre: no handler proposal should exist");

        vm.prank(address(managerContract));
        vm.expectRevert(abi.encodeWithSelector(NoHandlerProposal.selector));
        vaultCore.cancelHandlerProposal();

        assertEq(vaultCore.depositHandler(), address(depositHandler), "post: handler must remain unchanged");
    }

    function test_cancelBasaltAddressesProposal_withoutProposal_reverts() public {
        (, , bool existsBefore) = vaultCore.basaltAddressesProposal();
        assertFalse(existsBefore, "pre: no basalt proposal should exist");

        address stateBefore = vaultCore.basaltState();

        vm.prank(address(managerContract));
        vm.expectRevert(abi.encodeWithSelector(NoBasaltAddressesProposal.selector));
        vaultCore.cancelBasaltAddressesProposal();

        assertEq(vaultCore.basaltState(), stateBefore, "post: basaltState must remain unchanged");
    }

    // ══════════════════════════════════════════════════════════════════════
    // HANDLER PROPOSAL EDGE CASES
    // ══════════════════════════════════════════════════════════════════════

    function test_proposeHandler_unknownOldHandler_reverts() public {
        (, , bool existsBefore) = vaultCore.handlerProposal();
        assertFalse(existsBefore, "pre: no proposal should exist");

        vm.prank(address(managerContract));
        vm.expectRevert(abi.encodeWithSelector(UnknownHandler.selector));
        vaultCore.proposeHandler(address(0xDEAD), newHandler);

        (, , bool existsAfter) = vaultCore.handlerProposal();
        assertFalse(existsAfter, "post: proposal must not be created on revert");
    }

    function test_proposeHandler_zeroNewHandler_reverts() public {
        (, , bool existsBefore) = vaultCore.handlerProposal();
        assertFalse(existsBefore, "pre: no proposal should exist");

        vm.prank(address(managerContract));
        vm.expectRevert(abi.encodeWithSelector(ZeroHandler.selector));
        vaultCore.proposeHandler(address(depositHandler), address(0));

        (, , bool existsAfter) = vaultCore.handlerProposal();
        assertFalse(existsAfter, "post: proposal must not be created on revert");
    }

    function test_proposeHandler_duplicateHandler_reverts() public {
        address handlerBefore = vaultCore.depositHandler();

        // newHandler = an existing handler slot (withdrawHandler) => duplicate
        vm.prank(address(managerContract));
        vm.expectRevert(abi.encodeWithSelector(DuplicateHandler.selector));
        vaultCore.proposeHandler(address(depositHandler), address(withdrawHandler));

        assertEq(vaultCore.depositHandler(), handlerBefore, "post: handler must remain unchanged after duplicate revert");
        (, , bool exists) = vaultCore.handlerProposal();
        assertFalse(exists, "post: proposal must not be created on duplicate revert");
    }
}

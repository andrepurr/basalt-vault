// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {InitialCoreAddressBook} from "../../../src/core/InitialCoreAddressBook.sol";

/// @title InitialCoreAddressBook view getter unit tests
contract InitialCoreAddressBookUnit is ForkSetupFull {
    function test_initialCoreAddresses_returnsDeployedAddresses() public view {
        InitialCoreAddressBook.InitialCoreAddresses memory addrs = initialCoreAddressBook.initialCoreAddresses();

        assertEq(addrs.depositHandler, address(depositHandler), "addressBook: depositHandler mismatch");
        assertEq(addrs.withdrawHandler, address(withdrawHandler), "addressBook: withdrawHandler mismatch");
        assertEq(addrs.managerHandler, address(managerHandler), "addressBook: managerHandler mismatch");
        assertEq(
            addrs.asyncRecoveryHandler, address(asyncRecoveryHandler), "addressBook: asyncRecoveryHandler mismatch"
        );
        assertEq(
            addrs.feeAccountingHandler, address(feeAccountingHandler), "addressBook: feeAccountingHandler mismatch"
        );
        assertEq(addrs.basaltMath, address(basaltMath), "addressBook: basaltMath mismatch");
    }

    function test_initialCoreAddresses_nonZeroAddresses() public view {
        InitialCoreAddressBook.InitialCoreAddresses memory addrs = initialCoreAddressBook.initialCoreAddresses();

        assertTrue(addrs.vaultCore != address(0), "addressBook: vaultCore is zero");
        assertTrue(addrs.depositHandler != address(0), "addressBook: depositHandler is zero");
        assertTrue(addrs.withdrawHandler != address(0), "addressBook: withdrawHandler is zero");
        assertTrue(addrs.managerHandler != address(0), "addressBook: managerHandler is zero");
        assertTrue(addrs.asyncRecoveryHandler != address(0), "addressBook: asyncRecoveryHandler is zero");
        assertTrue(addrs.feeAccountingHandler != address(0), "addressBook: feeAccountingHandler is zero");
        assertTrue(addrs.extensionHandler1 != address(0), "addressBook: extensionHandler1 is zero");
        assertTrue(addrs.extensionHandler2 != address(0), "addressBook: extensionHandler2 is zero");
        assertTrue(addrs.extensionHandler3 != address(0), "addressBook: extensionHandler3 is zero");
        assertTrue(addrs.basaltState != address(0), "addressBook: basaltState is zero");
        assertTrue(addrs.basaltMath != address(0), "addressBook: basaltMath is zero");
        assertTrue(addrs.dolomiteVault != address(0), "addressBook: dolomiteVault is zero");
    }
}

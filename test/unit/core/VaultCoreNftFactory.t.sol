// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {VaultCore} from "../../../src/core/VaultCore.sol";
import {VaultCoreNftFactory} from "../../../src/core/VaultCoreNftFactory.sol";
import {NotCurrentProtocolManager} from "../../../src/core/managerContractLibraries/ManagerContractTypes.sol";
import {IInitialCoreAddressBook} from "../../../src/interfaces/IInitialCoreAddressBook.sol";

/// @title VaultCoreNftFactory access control and creation unit tests
contract VaultCoreNftFactoryUnit is ForkSetupFull {
    // createVaultCore -- permissionless

    function test_createVaultCore_asAnyone_succeeds() public {
        vm.prank(stranger);
        (uint256 tokenId, address vc) = vaultCoreNftFactory.createVaultCore(stranger);
        assertTrue(tokenId > 0, "createVaultCore: tokenId should be > 0");
        assertTrue(vc != address(0), "createVaultCore: vault address should be non-zero");
        // Deployed vault should have code (it's a clone)
        assertGt(vc.code.length, 0, "vault clone should have deployed code");
    }

    function test_createVaultCore_mintsNft() public {
        vm.prank(stranger);
        (uint256 tokenId, address vc) = vaultCoreNftFactory.createVaultCore(stranger);
        address nftOwner = vaultCoreNftFactory.ownerOfVault(vc);
        assertEq(nftOwner, stranger, "createVaultCore: NFT owner should be the caller-supplied owner");
        // Token ID should be positive
        assertGt(tokenId, 0, "minted tokenId should be > 0");
    }

    // setProtocolManager -- restricted to current protocolManager

    function test_setProtocolManager_asStranger_reverts() public {
        address pmBefore = vaultCoreNftFactory.protocolManager();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(NotCurrentProtocolManager.selector)
        );
        vaultCoreNftFactory.setProtocolManager(stranger);

        // protocolManager must remain unchanged after revert
        assertEq(vaultCoreNftFactory.protocolManager(), pmBefore, "protocolManager must not change on revert");
    }

    function test_setProtocolManager_asProtocolManager_succeeds() public {
        address oldPM = vaultCoreNftFactory.protocolManager();
        address newPM = address(uint160(0xCAFE));
        // Current protocolManager is managerContract
        assertEq(oldPM, address(managerContract), "initial protocolManager should be managerContract");

        vm.prank(address(managerContract));
        vaultCoreNftFactory.setProtocolManager(newPM);

        assertEq(
            vaultCoreNftFactory.protocolManager(),
            newPM,
            "setProtocolManager: protocolManager should be updated"
        );
    }

    // setInitialCoreAddressBook -- onlyOwner (factoryOwner)

    function test_setInitialCoreAddressBook_asStranger_reverts() public {
        address bookBefore = address(vaultCoreNftFactory.initialCoreAddressBook());

        vm.prank(stranger);
        vm.expectRevert(); // Ownable: caller is not the owner
        vaultCoreNftFactory.setInitialCoreAddressBook(IInitialCoreAddressBook(address(0xBEEF)));

        // Address book must remain unchanged after revert
        assertEq(
            address(vaultCoreNftFactory.initialCoreAddressBook()),
            bookBefore,
            "initialCoreAddressBook must not change on revert"
        );
    }

    function test_setInitialCoreAddressBook_asOwner_succeeds() public {
        // Create a new address book to set (reuse existing one for simplicity)
        IInitialCoreAddressBook newBook = IInitialCoreAddressBook(address(initialCoreAddressBook));

        // Verify the factory has an owner set
        assertTrue(factoryOwner != address(0), "factoryOwner should be non-zero");

        vm.prank(factoryOwner);
        vaultCoreNftFactory.setInitialCoreAddressBook(newBook);

        assertEq(
            address(vaultCoreNftFactory.initialCoreAddressBook()),
            address(newBook),
            "setInitialCoreAddressBook: address book should be updated"
        );
    }

    // ownerOfVault -- view correctness

    function test_ownerOfVault_returnsCorrectOwner() public view {
        address owner = vaultCoreNftFactory.ownerOfVault(address(vaultCore));
        assertEq(owner, vaultOwner, "ownerOfVault: should return vaultOwner for the deployed vault");
        // Owner should be non-zero
        assertTrue(owner != address(0), "vault owner should be non-zero address");
        // vaultCore address itself should be non-zero
        assertTrue(address(vaultCore) != address(0), "vaultCore address should be non-zero");
    }
}

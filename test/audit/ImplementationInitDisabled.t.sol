// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {AlreadyInitialized} from "../../src/core/vaultCoreLibraries/VaultCoreTypes.sol";
import {AlreadyInitialized as VsAlreadyInitialized, NotVaultCore} from "../../src/core/vaultStateLibraries/VaultStateTypes.sol";
import {VaultState} from "../../src/core/VaultState.sol";

/// @title ImplementationInitDisabled — REGRESSION
/// @notice Pre-fix: `VaultCore.initialize` and `VaultState.initialize` could be called on the
///         implementation contract itself (one-shot guard read uninitialized storage). An
///         attacker could turn the implementation into an orphan-vault with malicious params,
///         polluting indexers and enabling phishing.
///
///         Post-fix: implementation constructors set the one-shot sentinels at deploy time, so
///         `initialize` reverts with `AlreadyInitialized` on the implementation. Clones via
///         `Clones.clone` are minimal proxies (no constructor run) — their fresh storage still
///         allows `initialize` to succeed exactly once.
contract ImplementationInitDisabledTest is Test {
    function test_regression_vaultCoreImplCannotBeInitialized() public {
        VaultCore impl = new VaultCore();
        // Fresh implementation: constructor sets `initialized = true`. Any `initialize(...)` reverts.
        assertEq(impl.initialized(), true, "VaultCore impl pre-marked initialized");
        // Deployed code should be non-empty (valid contract)
        assertGt(address(impl).code.length, 0, "VaultCore impl should have deployed code");

        vm.expectRevert(AlreadyInitialized.selector);
        impl.initialize(
            address(0x1), address(0x2), address(0x3), address(0x4), address(0x5),
            address(0x6), address(0x7), address(0x8), address(0x9), address(0xA), address(0xB)
        );
    }

    function test_regression_vaultStateImplCannotBeInitialized() public {
        VaultState impl = new VaultState();
        // Fresh implementation: constructor sets `vaultCoreClone` to a non-zero sentinel.
        assertTrue(impl.vaultCoreClone() != address(0), "VaultState impl pre-marked initialized");
        // Deployed code should be non-empty (valid contract)
        assertGt(address(impl).code.length, 0, "VaultState impl should have deployed code");

        vm.expectRevert(AlreadyInitialized.selector);
        impl.initialize(address(0x1), address(0x2));
    }

    function test_regression_vaultStateImplWritesBlocked() public {
        // Even if attacker bypasses `initialize`, every other write is gated by `onlyVaultCore`
        // which requires `msg.sender == vaultCoreClone`. The sentinel is unreachable.
        VaultState impl = new VaultState();

        // Verify deposit state is IDLE before attempting the blocked write
        assertEq(uint8(impl.depositState()), uint8(VaultState.State.IDLE), "initial depositState should be IDLE");

        vm.expectRevert(NotVaultCore.selector);
        impl.setDepositState(VaultState.State.PENDING);

        // Confirm state unchanged after revert
        assertEq(uint8(impl.depositState()), uint8(VaultState.State.IDLE), "depositState must remain IDLE after revert");
    }
}

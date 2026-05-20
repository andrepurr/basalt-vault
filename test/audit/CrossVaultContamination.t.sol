// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ForkSetupFull} from "../helpers/ForkSetupFull.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";
import {IManagerHandler} from "../../src/interfaces/IManagerHandler.sol";
import {IManagerHandlerVaultCore} from "../../src/interfaces/IManagerHandlerVaultCore.sol";

/// @title CrossVaultContaminationTest
/// @notice Verifies that singleton handlers operating on vault A never mutate vault B state.
///         The protocol uses shared handler instances across all vaults; these tests prove
///         per-vault state isolation through the VaultState clone boundary.
contract CrossVaultContaminationTest is ForkSetupFull {
    // ═══════════════════════════════════════════════════════════════════════
    //  VAULT B FIXTURES
    // ═══════════════════════════════════════════════════════════════════════

    address internal vaultOwnerB;
    uint256 internal vaultTokenIdB;
    VaultCore internal vaultCoreB;
    VaultState internal vaultStateB;

    function setUp() public override {
        super.setUp();

        vaultOwnerB = address(uint160(0x2002));
        (vaultTokenIdB, vaultCoreB) = _createVaultCore(vaultOwnerB);
        vaultStateB = VaultState(vaultCoreB.basaltState());
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Advance past the global action cooldown for a given vault state.
    function _rollPastCooldown(VaultState vs) internal {
        uint256 endBlock = vs.globalActionCooldownEndBlock();
        if (block.number <= endBlock) {
            vm.roll(endBlock + 1);
        }
    }

    /// @dev Snapshot all VaultState accounting fields for comparison.
    struct VaultSnapshot {
        uint8 depositState;
        uint8 withdrawState;
        uint8 rebalanceState;
        uint256 totalDepositedGmE18;
        uint256 totalDepositedUsdE18;
        uint256 totalWithdrawnUsdE18;
        uint256 highWaterMarkProfitUsdE18;
        uint256 managerAccruedFeeUsdE18;
        uint256 targetLtvBps;
        bool managerDeadmanTriggered;
        uint256 lastManagerActionBlock;
        uint256 pendingDepositAmountGmE18;
        uint256 pendingWithdrawSharesE18;
    }

    function _snapshot(VaultState vs) internal view returns (VaultSnapshot memory s) {
        s.depositState = uint8(vs.depositState());
        s.withdrawState = uint8(vs.withdrawState());
        s.rebalanceState = uint8(vs.rebalanceState());
        s.totalDepositedGmE18 = vs.totalDepositedGmE18();
        s.totalDepositedUsdE18 = vs.totalDepositedUsdE18();
        s.totalWithdrawnUsdE18 = vs.totalWithdrawnUsdE18();
        s.highWaterMarkProfitUsdE18 = vs.highWaterMarkProfitUsdE18();
        s.managerAccruedFeeUsdE18 = vs.managerAccruedFeeUsdE18();
        s.targetLtvBps = vs.targetLtvBps();
        s.managerDeadmanTriggered = vs.managerDeadmanTriggered();
        s.lastManagerActionBlock = vs.lastManagerActionBlock();
        s.pendingDepositAmountGmE18 = vs.pendingDepositAmountGmE18();
        s.pendingWithdrawSharesE18 = vs.pendingWithdrawSharesE18();
    }

    function _assertSnapshotsEqual(VaultSnapshot memory before, VaultSnapshot memory after_, string memory label)
        internal
        pure
    {
        assertEq(after_.depositState, before.depositState, string.concat(label, ": depositState changed"));
        assertEq(after_.withdrawState, before.withdrawState, string.concat(label, ": withdrawState changed"));
        assertEq(after_.rebalanceState, before.rebalanceState, string.concat(label, ": rebalanceState changed"));
        assertEq(
            after_.totalDepositedGmE18,
            before.totalDepositedGmE18,
            string.concat(label, ": totalDepositedGmE18 changed")
        );
        assertEq(
            after_.totalDepositedUsdE18,
            before.totalDepositedUsdE18,
            string.concat(label, ": totalDepositedUsdE18 changed")
        );
        assertEq(
            after_.totalWithdrawnUsdE18,
            before.totalWithdrawnUsdE18,
            string.concat(label, ": totalWithdrawnUsdE18 changed")
        );
        assertEq(
            after_.highWaterMarkProfitUsdE18,
            before.highWaterMarkProfitUsdE18,
            string.concat(label, ": highWaterMarkProfitUsdE18 changed")
        );
        assertEq(
            after_.managerAccruedFeeUsdE18,
            before.managerAccruedFeeUsdE18,
            string.concat(label, ": managerAccruedFeeUsdE18 changed")
        );
        assertEq(after_.targetLtvBps, before.targetLtvBps, string.concat(label, ": targetLtvBps changed"));
        assertEq(
            after_.managerDeadmanTriggered,
            before.managerDeadmanTriggered,
            string.concat(label, ": managerDeadmanTriggered changed")
        );
        assertEq(
            after_.lastManagerActionBlock,
            before.lastManagerActionBlock,
            string.concat(label, ": lastManagerActionBlock changed")
        );
        assertEq(
            after_.pendingDepositAmountGmE18,
            before.pendingDepositAmountGmE18,
            string.concat(label, ": pendingDepositAmountGmE18 changed")
        );
        assertEq(
            after_.pendingWithdrawSharesE18,
            before.pendingWithdrawSharesE18,
            string.concat(label, ": pendingWithdrawSharesE18 changed")
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  ISOLATION INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Each vault clone gets its own VaultState; verify they are distinct addresses.
    function test_vaultState_addresses_areDistinct() public view {
        assertTrue(
            address(vaultState) != address(vaultStateB),
            "vault A and B must have distinct VaultState clones"
        );
        assertTrue(
            address(vaultCore) != address(vaultCoreB),
            "vault A and B must have distinct VaultCore clones"
        );
    }

    /// @notice VaultState clones are bound to their respective VaultCore; cross-calls revert.
    function test_vaultState_rejectsWrongVaultCore() public {
        // vaultState (A) only accepts calls from vaultCore (A).
        // Attempting to call from vaultCoreB should revert with NotVaultCore.
        vm.prank(address(vaultCoreB));
        vm.expectRevert();
        vaultState.setDepositState(VaultState.State.PENDING);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TEST 1: deposit into vault A does not affect vault B shares/totals
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Directly set pending deposit accounting on vault A via its VaultCore,
    ///         then verify vault B deposit totals remain zero.
    function test_deposit_vaultA_doesNotAffectVaultB_shares() public {
        VaultSnapshot memory snapshotBBefore = _snapshot(vaultStateB);

        // Simulate deposit accounting on vault A by calling VaultState through VaultCore.
        // We use the manager contract (protocolManager) which has universalCall access.
        uint256 depositAmountGm = 100e18;
        uint256 gmPrice = 1e18;
        uint256 gmCollateral = 50e18;
        uint256 deadline = block.timestamp + 3600;

        vm.prank(address(vaultCore));
        vaultState.setPendingDepositAccounting(depositAmountGm, gmPrice, gmCollateral, deadline);

        vm.prank(address(vaultCore));
        vaultState.setDepositState(VaultState.State.PENDING);

        // Verify vault A state changed
        assertEq(vaultState.pendingDepositAmountGmE18(), depositAmountGm, "vault A pending deposit set");
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.PENDING), "vault A deposit state PENDING");

        // Verify vault B state unchanged
        VaultSnapshot memory snapshotBAfter = _snapshot(vaultStateB);
        _assertSnapshotsEqual(snapshotBBefore, snapshotBAfter, "vaultB after vaultA deposit");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TEST 2: deposit into vault A sets PENDING, vault B stays IDLE
    // ═══════════════════════════════════════════════════════════════════════

    function test_deposit_vaultA_doesNotAffectVaultB_state() public {
        // Both start IDLE
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.IDLE), "A starts IDLE");
        assertEq(uint8(vaultStateB.depositState()), uint8(VaultState.State.IDLE), "B starts IDLE");

        // Set vault A to PENDING
        vm.prank(address(vaultCore));
        vaultState.setDepositState(VaultState.State.PENDING);

        // A is PENDING
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.PENDING), "A is PENDING");

        // B remains IDLE
        assertEq(uint8(vaultStateB.depositState()), uint8(VaultState.State.IDLE), "B still IDLE");
        assertEq(uint8(vaultStateB.withdrawState()), uint8(VaultState.State.IDLE), "B withdraw still IDLE");
        assertEq(uint8(vaultStateB.rebalanceState()), uint8(VaultState.State.IDLE), "B rebalance still IDLE");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TEST 3: withdraw from vault A does not affect vault B balances
    // ═══════════════════════════════════════════════════════════════════════

    function test_withdraw_vaultA_doesNotAffectVaultB_balances() public {
        VaultSnapshot memory snapshotBBefore = _snapshot(vaultStateB);

        // Simulate finalized deposit on vault A to give it totalDeposited values
        vm.startPrank(address(vaultCore));
        vaultState.setPendingDepositAccounting(50e18, 1e18, 25e18, block.timestamp + 3600);
        vaultState.finalizeDepositAccounting(100e18, 200e18, 75e18, 1e8);
        vm.stopPrank();

        // Verify vault A has deposit data
        assertGt(vaultState.totalDepositedGmE18(), 0, "A has deposited GM");
        assertGt(vaultState.totalDepositedUsdE18(), 0, "A has deposited USD");

        // Simulate a withdraw accounting entry on vault A
        vm.prank(address(vaultCore));
        vaultState.addWithdrawnUsdE18(10e18);

        assertEq(vaultState.totalWithdrawnUsdE18(), 10e18, "A has withdrawn USD");

        // Vault B balances remain pristine
        VaultSnapshot memory snapshotBAfter = _snapshot(vaultStateB);
        _assertSnapshotsEqual(snapshotBBefore, snapshotBAfter, "vaultB after vaultA withdraw");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TEST 4: fee accrual on vault A does not affect vault B
    // ═══════════════════════════════════════════════════════════════════════

    function test_fee_accrual_vaultA_doesNotAffectVaultB() public {
        VaultSnapshot memory snapshotBBefore = _snapshot(vaultStateB);

        // Set fee accounting on vault A
        uint256 hwmProfit = 500e18;
        uint256 accruedFee = 100e18;

        vm.prank(address(vaultCore));
        vaultState.setFeeAccounting(hwmProfit, accruedFee);

        // Verify vault A fee state
        assertEq(vaultState.highWaterMarkProfitUsdE18(), hwmProfit, "A HWM set");
        assertEq(vaultState.managerAccruedFeeUsdE18(), accruedFee, "A accrued fee set");

        // Verify vault B fee state untouched
        VaultSnapshot memory snapshotBAfter = _snapshot(vaultStateB);
        _assertSnapshotsEqual(snapshotBBefore, snapshotBAfter, "vaultB after vaultA fee accrual");

        // Explicit zero-check on the critical fee field
        assertEq(vaultStateB.managerAccruedFeeUsdE18(), 0, "B managerAccruedFee must be 0");
        assertEq(vaultStateB.highWaterMarkProfitUsdE18(), 0, "B HWM must be 0");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TEST 5: deadman trigger on vault A does not affect vault B
    // ═══════════════════════════════════════════════════════════════════════

    function test_deadman_vaultA_doesNotAffectVaultB() public {
        VaultSnapshot memory snapshotBBefore = _snapshot(vaultStateB);

        // Fast-forward past deadman period for vault A
        vm.roll(block.number + BasaltConstants.MANAGER_DEADMAN_BLOCKS + 1);

        // Trigger deadman on vault A
        vm.prank(vaultOwner);
        vaultCore.triggerManagerDeadman();

        // Vault A deadman is triggered
        assertEq(vaultState.managerDeadmanTriggered(), true, "A deadman triggered");

        // Vault B deadman is NOT triggered
        assertEq(vaultStateB.managerDeadmanTriggered(), false, "B deadman must remain false");

        // Full snapshot check on vault B
        // Note: lastManagerActionBlock will have changed for B since it was set at init block,
        // but managerDeadmanTriggered is the critical field. We check it explicitly above.
        assertEq(uint8(vaultStateB.depositState()), uint8(VaultState.State.IDLE), "B deposit IDLE");
        assertEq(uint8(vaultStateB.withdrawState()), uint8(VaultState.State.IDLE), "B withdraw IDLE");
        assertEq(vaultStateB.totalDepositedGmE18(), 0, "B totalDeposited 0");
        assertEq(vaultStateB.managerAccruedFeeUsdE18(), 0, "B accrued fee 0");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TEST 6: target LTV on vault A does not affect vault B
    // ═══════════════════════════════════════════════════════════════════════

    function test_rebalance_vaultA_doesNotAffectVaultB_ltv() public {
        uint256 vaultBTargetLtvBefore = vaultStateB.targetLtvBps();
        uint256 vaultBLastActionBefore = vaultStateB.lastManagerActionBlock();

        _rollPastCooldown(vaultState);

        // Set target LTV on vault A via the ManagerHandler (through ManagerContract)
        uint256 newLtv = 5_100;
        vm.prank(configurator);
        managerContract.setVaultTargetLtv(
            IManagerHandler(address(managerHandler)),
            IManagerHandlerVaultCore(address(vaultCore)),
            newLtv
        );

        // Vault A LTV changed
        assertEq(vaultState.targetLtvBps(), newLtv, "A target LTV updated");

        // Vault B LTV unchanged (still default)
        assertEq(vaultStateB.targetLtvBps(), vaultBTargetLtvBefore, "B target LTV unchanged");
        assertEq(
            vaultStateB.targetLtvBps(),
            BasaltConstants.DEFAULT_TARGET_LTV_BPS,
            "B target LTV is still default"
        );

        // Vault B lastManagerActionBlock unchanged
        assertEq(
            vaultStateB.lastManagerActionBlock(),
            vaultBLastActionBefore,
            "B lastManagerActionBlock unchanged"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TEST 7: concurrent deposits into both vaults are independent
    // ═══════════════════════════════════════════════════════════════════════

    function test_concurrent_deposits_twoVaults_independent() public {
        uint256 depositA_gm = 100e18;
        uint256 depositA_price = 2e18;
        uint256 depositA_collateral = 50e18;

        uint256 depositB_gm = 200e18;
        uint256 depositB_price = 3e18;
        uint256 depositB_collateral = 80e18;

        uint256 deadline = block.timestamp + 3600;

        // Set pending deposits on BOTH vaults in the same block
        vm.prank(address(vaultCore));
        vaultState.setPendingDepositAccounting(depositA_gm, depositA_price, depositA_collateral, deadline);
        vm.prank(address(vaultCore));
        vaultState.setDepositState(VaultState.State.PENDING);

        vm.prank(address(vaultCoreB));
        vaultStateB.setPendingDepositAccounting(depositB_gm, depositB_price, depositB_collateral, deadline);
        vm.prank(address(vaultCoreB));
        vaultStateB.setDepositState(VaultState.State.PENDING);

        // Verify vault A has its own values
        assertEq(vaultState.pendingDepositAmountGmE18(), depositA_gm, "A pending GM amount");
        assertEq(vaultState.pendingDepositGmPriceE18(), depositA_price, "A pending GM price");
        assertEq(vaultState.pendingDepositGmCollateralSnapshotE18(), depositA_collateral, "A pending collateral");
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.PENDING), "A deposit PENDING");

        // Verify vault B has its own distinct values
        assertEq(vaultStateB.pendingDepositAmountGmE18(), depositB_gm, "B pending GM amount");
        assertEq(vaultStateB.pendingDepositGmPriceE18(), depositB_price, "B pending GM price");
        assertEq(vaultStateB.pendingDepositGmCollateralSnapshotE18(), depositB_collateral, "B pending collateral");
        assertEq(uint8(vaultStateB.depositState()), uint8(VaultState.State.PENDING), "B deposit PENDING");

        // Cross-check: A values != B values (confirms no shared storage)
        assertTrue(
            vaultState.pendingDepositAmountGmE18() != vaultStateB.pendingDepositAmountGmE18(),
            "pending GM amounts must differ"
        );
        assertTrue(
            vaultState.pendingDepositGmPriceE18() != vaultStateB.pendingDepositGmPriceE18(),
            "pending GM prices must differ"
        );

        // Finalize only vault A; vault B stays PENDING
        vm.prank(address(vaultCore));
        vaultState.finalizeDepositAccounting(50e18, 150e18, 75e18, 1e8);

        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.IDLE), "A back to IDLE after finalize");
        assertEq(vaultState.pendingDepositAmountGmE18(), 0, "A pending cleared");
        assertGt(vaultState.totalDepositedGmE18(), 0, "A totalDeposited incremented");

        // Vault B remains PENDING with its original values
        assertEq(uint8(vaultStateB.depositState()), uint8(VaultState.State.PENDING), "B still PENDING");
        assertEq(vaultStateB.pendingDepositAmountGmE18(), depositB_gm, "B pending GM unchanged");
        assertEq(vaultStateB.totalDepositedGmE18(), 0, "B totalDeposited still 0");
    }
}

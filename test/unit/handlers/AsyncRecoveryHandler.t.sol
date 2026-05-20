// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {VaultState} from "../../../src/core/VaultState.sol";
import {AsyncRecoveryHandler} from "../../../src/handlers/AsyncRecoveryHandler.sol";
import {IDepositHandlerVaultCore} from "../../../src/interfaces/IDepositHandlerVaultCore.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../../src/libraries/BasaltConstants.sol";
import {
    IAsyncRecoveryHandlerVaultCore,
    AsyncRecoveryOperation,
    AsyncRecoveryPendingOperation,
    NothingPending,
    TooEarly,
    NotVaultNftOwner,
    NotManagerOrNftOwner
} from "../../../src/handlers/asyncRecoveryHandlerLibraries/AsyncRecoveryHandlerTypes.sol";
import {
    GmxEventUtils,
    IDepositCallbackReceiver
} from "../../../src/interfaces/IGmxCallbackReceiver.sol";

/// @title AsyncRecoveryHandlerUnit
/// @notice Unit tests for AsyncRecoveryHandler: unstuck flow, deadline enforcement, views.
///         Tests the safety net for stuck async operations.
contract AsyncRecoveryHandlerUnit is ForkSetupFull {
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

        // managementFeeBps is auto-initialized to MANAGER_FEE_BPS (2_000) in VaultState.initialize()
        require(vaultState.managementFeeBps() == PERF_FEE_BPS, "management fee init drift");

        vm.prank(vaultOwner);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(address(depositHandler), type(uint256).max);
        deal(BasaltAddresses.GM_MARKET_TOKEN, vaultOwner, 200e18);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  ACCESS CONTROL
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Stranger cannot call nextUnstuckAt -- restricted to protocolManager or vaultNftOwner.
    function test_nextUnstuckAt_asStranger_reverts() public {
        // Pre-condition: stranger is neither vaultOwner nor protocolManager
        assertTrue(stranger != vaultOwner, "stranger must differ from vaultOwner");
        assertTrue(stranger != address(managerContract), "stranger must differ from protocolManager");

        vm.prank(stranger);
        vm.expectRevert(NotManagerOrNftOwner.selector);
        asyncRecoveryHandler.nextUnstuckAt(IAsyncRecoveryHandlerVaultCore(address(vaultCore)));
    }

    /// @notice VaultOwner can call nextUnstuckAt.
    function test_nextUnstuckAt_asNftOwner_succeeds() public {
        vm.prank(vaultOwner);
        (uint256 unstuckNotBefore, uint256 deprecated) =
            asyncRecoveryHandler.nextUnstuckAt(IAsyncRecoveryHandlerVaultCore(address(vaultCore)));
        // On idle vault, returns 0
        assertEq(unstuckNotBefore, 0, "no pending = unstuckNotBefore should be 0");
        assertEq(deprecated, 0, "deprecated field should be 0");
    }

    /// @notice Stranger cannot call canUnstuckWith.
    function test_canUnstuckWith_asStranger_reverts() public {
        // Pre-condition: vault is idle, no pending operation
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.IDLE), "vault should be idle before test");

        vm.prank(stranger);
        vm.expectRevert(NotManagerOrNftOwner.selector);
        asyncRecoveryHandler.canUnstuckWith(
            IAsyncRecoveryHandlerVaultCore(address(vaultCore)), bytes32(0)
        );
    }

    /// @notice Stranger cannot call unstuckPending.
    function test_unstuckPending_asStranger_reverts() public {
        // Pre-condition: deposit state unchanged after revert
        uint8 stateBefore = uint8(vaultState.depositState());

        vm.prank(stranger);
        vm.expectRevert(NotManagerOrNftOwner.selector);
        asyncRecoveryHandler.unstuckPending(
            IAsyncRecoveryHandlerVaultCore(address(vaultCore)), bytes32(0)
        );

        // State must remain unchanged after failed call
        assertEq(uint8(vaultState.depositState()), stateBefore, "deposit state must not change on revert");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  VIEWS -- IDLE VAULT
    // ════════════════════════════════════════════════════════════════════════

    /// @notice nextUnstuckAt on idle vault returns zero.
    function test_nextUnstuckAt_whenIdle_returnsZero() public {
        vm.prank(vaultOwner);
        (uint256 unstuckNotBefore, uint256 deprecated) =
            asyncRecoveryHandler.nextUnstuckAt(IAsyncRecoveryHandlerVaultCore(address(vaultCore)));
        assertEq(unstuckNotBefore, 0, "idle vault should have unstuckNotBefore = 0");
        assertEq(deprecated, 0, "deprecated return should always be 0");
    }

    /// @notice canUnstuckWith on idle vault returns (false, "nothing pending").
    function test_canUnstuckWith_whenIdle_returnsNotAllowed() public {
        vm.prank(vaultOwner);
        (bool allowed, string memory reason) = asyncRecoveryHandler.canUnstuckWith(
            IAsyncRecoveryHandlerVaultCore(address(vaultCore)), bytes32(0)
        );
        assertFalse(allowed, "idle vault should not allow unstuck");
        assertGt(bytes(reason).length, 0, "reason should be non-empty when blocked");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  UNSTUCK FLOW -- PENDING STATE
    // ════════════════════════════════════════════════════════════════════════

    /// @notice unstuckPending on idle vault reverts with NothingPending.
    function test_unstuckPending_whenIdle_reverts() public {
        // Pre-condition: vault must be idle
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.IDLE), "vault should be idle");
        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "withdraw should be idle");

        vm.prank(vaultOwner);
        vm.expectRevert(NothingPending.selector);
        asyncRecoveryHandler.unstuckPending(
            IAsyncRecoveryHandlerVaultCore(address(vaultCore)), bytes32(0)
        );
    }

    /// @notice nextUnstuckAt when deposit is pending returns deadline + grace > 0.
    function test_nextUnstuckAt_whenDepositPending_returnsNonZero() public {
        _setupStuckDeposit();

        vm.prank(vaultOwner);
        (uint256 unstuckNotBefore,) =
            asyncRecoveryHandler.nextUnstuckAt(IAsyncRecoveryHandlerVaultCore(address(vaultCore)));
        assertGt(unstuckNotBefore, 0, "pending deposit should have unstuckNotBefore > 0");
        // unstuckNotBefore should be in the future (deadline + grace > current block.timestamp)
        assertGt(unstuckNotBefore, block.timestamp, "unstuckNotBefore should be after current block.timestamp");
        // Vault must be in PENDING deposit state
        assertEq(
            uint8(vaultState.depositState()),
            uint8(VaultState.State.PENDING),
            "deposit state should be PENDING when checking unstuck"
        );
    }

    /// @notice unstuckPending before deadline + grace reverts with TooEarly.
    function test_unstuckPending_beforeDeadline_reverts() public {
        _setupStuckDeposit();

        // Verify we are indeed before the unstuck window
        vm.prank(vaultOwner);
        (uint256 unstuckNotBefore,) =
            asyncRecoveryHandler.nextUnstuckAt(IAsyncRecoveryHandlerVaultCore(address(vaultCore)));
        assertGt(unstuckNotBefore, block.timestamp, "test requires us to be before unstuck window");

        // Try unstuck immediately (before deadline + grace)
        vm.prank(vaultOwner);
        vm.expectRevert(); // TooEarly
        asyncRecoveryHandler.unstuckPending(
            IAsyncRecoveryHandlerVaultCore(address(vaultCore)), bytes32(0)
        );
    }

    /// @notice UNSTUCK_GRACE_AFTER_DEADLINE constant matches BasaltConstants.
    function test_unstuckGracePeriod_matchesConstant() public view {
        uint256 grace = asyncRecoveryHandler.UNSTUCK_GRACE_AFTER_DEADLINE();
        assertEq(
            grace,
            BasaltConstants.UNSTUCK_GRACE_AFTER_DEADLINE,
            "UNSTUCK_GRACE_AFTER_DEADLINE should match BasaltConstants"
        );
        // Grace period should be reasonable: at least 1 minute, at most 1 day
        assertGe(grace, 60, "grace period should be >= 60 seconds");
        assertLe(grace, 86_400, "grace period should be <= 1 day");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  HELPERS
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Start a deposit but do NOT simulate GMX execution or finalize.
    ///      This leaves the vault in deposit-PENDING state.
    function _setupStuckDeposit() internal {
        _rollCooldown();
        vm.recordLogs();
        vm.prank(vaultOwner);
        depositHandler.deposit{value: _firstDepositMsgValue()}(
            IDepositHandlerVaultCore(address(vaultCore)), DEPOSIT_GM, 100
        );

        assertEq(
            uint8(vaultState.depositState()),
            uint8(VaultState.State.PENDING),
            "deposit should be PENDING after setup"
        );
    }

    function _rollCooldown() internal {
        uint256 endBlock = vaultState.globalActionCooldownEndBlock();
        if (block.number <= endBlock) {
            vm.roll(endBlock + 1);
        }
    }
}

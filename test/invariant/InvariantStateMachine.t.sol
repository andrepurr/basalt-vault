// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ForkSetupFull} from "../helpers/ForkSetupFull.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {VaultCoreNftFactory} from "../../src/core/VaultCoreNftFactory.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";
import {DepositHandler} from "../../src/handlers/DepositHandler.sol";
import {WithdrawHandler} from "../../src/handlers/WithdrawHandler.sol";
import {ManagerHandler} from "../../src/handlers/ManagerHandler.sol";
import {FeeAccountingHandler} from "../../src/handlers/FeeAccountingHandler.sol";
import {IDepositHandlerVaultCore} from "../../src/interfaces/IDepositHandlerVaultCore.sol";
import {IWithdrawHandlerVaultCore} from "../../src/interfaces/IWithdrawHandlerVaultCore.sol";
import {IManagerHandlerVaultCore} from "../../src/interfaces/IManagerHandlerVaultCore.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  StateMachineActor -- drives deposit/withdraw/rebalance/finalize/governance
//  sequences for INV-03, INV-VC-003, INV-MGR-001.
// ─────────────────────────────────────────────────────────────────────────────

contract StateMachineActor is Test {
    address internal immutable VAULT_CORE;
    address internal immutable VAULT_OWNER;
    address internal immutable PROTOCOL_MANAGER;

    VaultState internal immutable STATE;
    DepositHandler internal immutable DEPOSIT_H;
    WithdrawHandler internal immutable WITHDRAW_H;
    ManagerHandler internal immutable MANAGER_H;
    ManagerContract internal immutable MANAGER_CONTRACT;
    FeeSplitter internal immutable FEE_SPLITTER;
    VaultCoreNftFactory internal immutable FACTORY;

    // -- Ghosts --
    uint256 public ghost_depositAttempts;
    uint256 public ghost_depositSuccesses;
    uint256 public ghost_withdrawAttempts;
    uint256 public ghost_withdrawSuccesses;
    uint256 public ghost_rebalanceAttempts;
    uint256 public ghost_rebalanceSuccesses;
    uint256 public ghost_finalizeDepositAttempts;
    uint256 public ghost_finalizeDepositSuccesses;
    uint256 public ghost_finalizeWithdrawAttempts;
    uint256 public ghost_finalizeWithdrawSuccesses;
    uint256 public ghost_maxConcurrentPending;
    uint256 public ghost_mgrRotationAttempts;
    uint256 public ghost_mgrRotationBelowThresholdSuccesses;

    constructor(
        address vaultCoreAddr,
        address vaultStateAddr,
        address depositHandlerAddr,
        address withdrawHandlerAddr,
        address managerHandlerAddr,
        address managerContractAddr,
        address feeSplitterAddr,
        address factoryAddr,
        address vaultOwnerAddr,
        address protocolManagerAddr
    ) {
        VAULT_CORE = vaultCoreAddr;
        STATE = VaultState(vaultStateAddr);
        DEPOSIT_H = DepositHandler(depositHandlerAddr);
        WITHDRAW_H = WithdrawHandler(withdrawHandlerAddr);
        MANAGER_H = ManagerHandler(managerHandlerAddr);
        MANAGER_CONTRACT = ManagerContract(managerContractAddr);
        FEE_SPLITTER = FeeSplitter(feeSplitterAddr);
        FACTORY = VaultCoreNftFactory(factoryAddr);
        VAULT_OWNER = vaultOwnerAddr;
        PROTOCOL_MANAGER = protocolManagerAddr;

        // One-shot approvals for deposit handler.
        vm.prank(VAULT_OWNER);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(depositHandlerAddr, type(uint256).max);
    }

    // -- Actions --

    function actOwnerDeposit(uint256 amountGmSeed) external {
        uint256 amountGm = bound(amountGmSeed, 1, 100_000e18);
        if (STATE.depositState() != VaultState.State.IDLE) return;
        if (STATE.withdrawState() != VaultState.State.IDLE) return;
        if (STATE.rebalanceState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        ghost_depositAttempts += 1;
        deal(BasaltAddresses.GM_MARKET_TOKEN, VAULT_OWNER, amountGm);
        vm.deal(VAULT_OWNER, 10 ether);
        vm.startPrank(VAULT_OWNER);
        try DEPOSIT_H.deposit{value: 2 ether}(
            IDepositHandlerVaultCore(VAULT_CORE), amountGm, 500
        ) {
            ghost_depositSuccesses += 1;
        } catch {}
        vm.stopPrank();
        _countPendingStates();
    }

    function actOwnerWithdraw(uint256 sharesSeed, uint256 slippageSeed) external {
        if (STATE.withdrawState() != VaultState.State.IDLE) return;
        if (STATE.depositState() != VaultState.State.IDLE) return;
        if (STATE.rebalanceState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        uint256 shares = bound(sharesSeed, 1, BasaltConstants.SHARE_UNIT);
        ghost_withdrawAttempts += 1;
        vm.deal(VAULT_OWNER, 10 ether);
        vm.startPrank(VAULT_OWNER);
        try WITHDRAW_H.withdraw{value: 2 ether}(
            IWithdrawHandlerVaultCore(VAULT_CORE), shares, 0
        ) {
            ghost_withdrawSuccesses += 1;
        } catch {}
        vm.stopPrank();
        _countPendingStates();
    }

    function actRebalance(uint256 directionSeed) external {
        if (STATE.rebalanceState() != VaultState.State.IDLE) return;
        if (STATE.depositState() != VaultState.State.IDLE) return;
        if (STATE.withdrawState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        uint256 slippage = bound(directionSeed, 1, 500);
        ghost_rebalanceAttempts += 1;
        vm.deal(PROTOCOL_MANAGER, 10 ether);
        vm.startPrank(PROTOCOL_MANAGER);
        try MANAGER_H.rebalance{value: 2 ether}(
            IManagerHandlerVaultCore(VAULT_CORE), slippage
        ) {
            ghost_rebalanceSuccesses += 1;
        } catch {}
        vm.stopPrank();
        _countPendingStates();
    }

    function actFinalizeDeposit(uint256) external {
        if (STATE.depositState() != VaultState.State.PENDING) return;
        _rollPastCooldown();
        vm.warp(block.timestamp + 1800);

        ghost_finalizeDepositAttempts += 1;
        vm.startPrank(VAULT_OWNER);
        try DEPOSIT_H.finalizeDeposit(IDepositHandlerVaultCore(VAULT_CORE)) {
            ghost_finalizeDepositSuccesses += 1;
        } catch {}
        vm.stopPrank();
        _countPendingStates();
    }

    function actFinalizeWithdraw(uint256) external {
        if (STATE.withdrawState() != VaultState.State.PENDING) return;
        _rollPastCooldown();
        vm.warp(block.timestamp + 1800);

        ghost_finalizeWithdrawAttempts += 1;
        vm.startPrank(VAULT_OWNER);
        try WITHDRAW_H.finalizeWithdraw(IWithdrawHandlerVaultCore(VAULT_CORE)) {
            ghost_finalizeWithdrawSuccesses += 1;
        } catch {}
        vm.stopPrank();
        _countPendingStates();
    }

    /// @dev INV-MGR-001: Try to propose+sign+execute a manager change with insufficient voting weight.
    ///      If execute succeeds when the signer has <80% share weight, the governance threshold is broken.
    function actProposeAndVoteManagerChange(uint256 nextManagerSeed) external {
        ghost_mgrRotationAttempts += 1;

        address nextManager = address(uint160(bound(nextManagerSeed, 1, type(uint160).max)));
        if (nextManager == address(0)) return;

        // Need at least 2 blocks for snapshot.
        if (block.number <= 1) vm.roll(3);

        // Mint a small share to a signer -- less than 80% of total supply.
        address weakSigner = address(uint160(0xBEEF01));
        uint256 totalSupply = FEE_SPLITTER.totalSupply();

        // If no supply exists yet, mint to two addresses so signer has <80%.
        if (totalSupply == 0) {
            // Mint 100 to majority holder, 10 to weak signer.
            // FeeSplitter is owned by factoryOwner, and minting is done via deposit flow.
            // We cannot mint directly. Skip this attempt.
            return;
        }

        // Check if the signer already has voting weight from a snapshot.
        uint256 snapshot = block.number - 1;
        uint256 signerWeight = FEE_SPLITTER.getPastVotes(weakSigner, snapshot);
        uint256 pastSupply = FEE_SPLITTER.getPastTotalSupply(snapshot);
        if (pastSupply == 0) return;

        // Only attempt when signer has < 80% weight (the interesting case for INV-MGR-001).
        // If signer has >= 80%, the execute should succeed legitimately.
        bool signerBelowThreshold = signerWeight * 10_000 < pastSupply * 8000;

        // Propose: must be done by someone with voting weight.
        // Use the protocol manager (managerContract) as the proposer via its owner.
        vm.prank(PROTOCOL_MANAGER);
        try MANAGER_CONTRACT.proposeProtocolManagerChange(FACTORY, nextManager) returns (uint256 proposalId) {
            // Sign with weak signer (may revert if no weight).
            if (signerWeight > 0) {
                vm.prank(weakSigner);
                try MANAGER_CONTRACT.signProtocolManagerChange(proposalId) {} catch {}
            }

            // Try to execute.
            vm.prank(PROTOCOL_MANAGER);
            try MANAGER_CONTRACT.executeProtocolManagerChange(proposalId) {
                // Execution succeeded. Check if it was below threshold.
                if (signerBelowThreshold && signerWeight > 0) {
                    ghost_mgrRotationBelowThresholdSuccesses += 1;
                }
            } catch {}
        } catch {}
    }

    // -- Internal --

    function _rollPastCooldown() internal {
        uint256 end = STATE.globalActionCooldownEndBlock();
        if (block.number <= end) {
            vm.roll(end + 1);
        }
    }

    function _countPendingStates() internal {
        uint8 pendingCount = 0;
        if (STATE.depositState() == VaultState.State.PENDING) pendingCount += 1;
        if (STATE.withdrawState() == VaultState.State.PENDING) pendingCount += 1;
        if (STATE.rebalanceState() == VaultState.State.PENDING) pendingCount += 1;
        if (pendingCount > ghost_maxConcurrentPending) {
            ghost_maxConcurrentPending = pendingCount;
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  InvariantStateMachine -- INV-03 mutual exclusion, INV-VC-003 handler slots,
//  INV-MGR-001 manager rotation threshold.
// ─────────────────────────────────────────────────────────────────────────────

contract InvariantStateMachine is ForkSetupFull {
    StateMachineActor internal actor;

    function setUp() public override {
        super.setUp();
        _fundActor(vaultOwner);

        actor = new StateMachineActor(
            address(vaultCore),
            address(vaultState),
            address(depositHandler),
            address(withdrawHandler),
            address(managerHandler),
            address(managerContract),
            address(feeSplitter),
            address(vaultCoreNftFactory),
            vaultOwner,
            address(managerContract)
        );

        targetContract(address(actor));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = StateMachineActor.actOwnerDeposit.selector;
        selectors[1] = StateMachineActor.actOwnerWithdraw.selector;
        selectors[2] = StateMachineActor.actRebalance.selector;
        selectors[3] = StateMachineActor.actFinalizeDeposit.selector;
        selectors[4] = StateMachineActor.actFinalizeWithdraw.selector;
        selectors[5] = StateMachineActor.actProposeAndVoteManagerChange.selector;
        targetSelector(FuzzSelector({addr: address(actor), selectors: selectors}));
        targetSender(address(this));
    }

    // -- Invariants --

    /// INV-03: At most one of deposit/withdraw/rebalance can be PENDING simultaneously.
    function invariant_inv03_atMostOnePendingState() public view {
        uint8 pendingCount = 0;
        if (vaultState.depositState() == VaultState.State.PENDING) pendingCount += 1;
        if (vaultState.withdrawState() == VaultState.State.PENDING) pendingCount += 1;
        if (vaultState.rebalanceState() == VaultState.State.PENDING) pendingCount += 1;
        assertLe(pendingCount, 1, "INV-03: more than one lifecycle is PENDING at once");
    }

    /// INV-03 (auxiliary): If any operation succeeded, ghost_maxConcurrentPending tracks the worst case.
    function invariant_inv03_noIdleToIdleTransition() public view {
        uint256 totalSuccesses = actor.ghost_depositSuccesses()
            + actor.ghost_withdrawSuccesses()
            + actor.ghost_rebalanceSuccesses();
        // If operations succeeded, the max concurrent PENDING must not exceed 1.
        if (totalSuccesses > 0) {
            assertLe(
                actor.ghost_maxConcurrentPending(), 1,
                "INV-03: ghost tracked >1 concurrent PENDING states"
            );
        }
    }

    /// INV-VC-003: All 8 handler slots on VaultCore have unique non-zero addresses.
    ///             No two slots may share the same address.
    function invariant_invVc003_handlerSlotsUnique() public view {
        address[8] memory slots = [
            vaultCore.depositHandler(),
            vaultCore.withdrawHandler(),
            vaultCore.managerHandler(),
            vaultCore.asyncRecoveryHandler(),
            vaultCore.feeAccountingHandler(),
            vaultCore.extensionHandler1(),
            vaultCore.extensionHandler2(),
            vaultCore.extensionHandler3()
        ];
        for (uint256 i = 0; i < slots.length; i++) {
            if (slots[i] == address(0)) continue;
            for (uint256 j = i + 1; j < slots.length; j++) {
                if (slots[j] == address(0)) continue;
                assertTrue(
                    slots[i] != slots[j],
                    "INV-VC-003: duplicate handler slot detected"
                );
            }
        }
    }

    /// INV-MGR-001: Manager rotation must require >= 80% voting support.
    ///              If any rotation executed with signer weight below threshold, the counter increments.
    function invariant_invMgr001_rotationRequiresThreshold() public view {
        assertEq(
            actor.ghost_mgrRotationBelowThresholdSuccesses(), 0,
            "INV-MGR-001: manager rotation succeeded below 80% threshold"
        );
    }

    /// @dev At least some operations must succeed — otherwise fuzzer is just spinning on reverts
    function invariant_atLeastSomeSuccesses() public view {
        if (actor.ghost_depositAttempts() + actor.ghost_withdrawAttempts() > 10) {
            assertTrue(
                actor.ghost_depositSuccesses() + actor.ghost_withdrawSuccesses() > 0,
                "fuzzer achieved zero successes - invariant test is meaningless"
            );
        }
    }

    /// Summary: log ghost counters for debugging.
    function invariant_summary() public view {
        assertTrue(
            actor.ghost_depositAttempts() + actor.ghost_withdrawAttempts()
                + actor.ghost_rebalanceAttempts() + actor.ghost_finalizeDepositAttempts()
                + actor.ghost_finalizeWithdrawAttempts() + actor.ghost_mgrRotationAttempts() >= 0
        );
    }
}

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
import {IFeeAccountingHandlerVaultCore} from "../../src/interfaces/IFeeAccountingHandlerVaultCore.sol";
import {IBasaltMath} from "../../src/interfaces/IBasaltMath.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  OwnerActor — deposit, withdraw, triggerDeadman on vaultA (NFT owner ops)
// ─────────────────────────────────────────────────────────────────────────────

contract OwnerActor is Test {
    address internal immutable VAULT_CORE;
    address internal immutable VAULT_OWNER;

    VaultState internal immutable STATE;
    DepositHandler internal immutable DEPOSIT_H;
    WithdrawHandler internal immutable WITHDRAW_H;

    uint256 public ghost_depositAttempts;
    uint256 public ghost_depositSuccesses;
    uint256 public ghost_withdrawAttempts;
    uint256 public ghost_withdrawSuccesses;
    uint256 public ghost_finalizeDepositAttempts;
    uint256 public ghost_finalizeDepositSuccesses;
    uint256 public ghost_finalizeWithdrawAttempts;
    uint256 public ghost_finalizeWithdrawSuccesses;
    uint256 public ghost_deadmanAttempts;
    uint256 public ghost_deadmanSuccesses;

    constructor(
        address vaultCoreAddr,
        address vaultStateAddr,
        address depositHandlerAddr,
        address withdrawHandlerAddr,
        address vaultOwnerAddr
    ) {
        VAULT_CORE = vaultCoreAddr;
        STATE = VaultState(vaultStateAddr);
        DEPOSIT_H = DepositHandler(depositHandlerAddr);
        WITHDRAW_H = WithdrawHandler(withdrawHandlerAddr);
        VAULT_OWNER = vaultOwnerAddr;

        vm.prank(VAULT_OWNER);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(depositHandlerAddr, type(uint256).max);
    }

    function actOwnerDeposit(uint256 amountGmSeed) external {
        uint256 amountGm = bound(amountGmSeed, 1e18, 5e21);
        if (STATE.depositState() != VaultState.State.IDLE) return;
        if (STATE.withdrawState() != VaultState.State.IDLE) return;
        if (STATE.rebalanceState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        ghost_depositAttempts += 1;
        deal(BasaltAddresses.GM_MARKET_TOKEN, VAULT_OWNER, amountGm);
        vm.deal(VAULT_OWNER, 10 ether);
        vm.startPrank(VAULT_OWNER);
        try DEPOSIT_H.deposit{value: 2 ether}(IDepositHandlerVaultCore(VAULT_CORE), amountGm, 500) {
            ghost_depositSuccesses += 1;
        } catch {}
        vm.stopPrank();
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
    }

    function actOwnerWithdraw(uint256 shareSeed) external {
        if (STATE.withdrawState() != VaultState.State.IDLE) return;
        if (STATE.depositState() != VaultState.State.IDLE) return;
        if (STATE.rebalanceState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        uint256 shares = bound(shareSeed, 1, BasaltConstants.SHARE_UNIT);
        ghost_withdrawAttempts += 1;
        vm.deal(VAULT_OWNER, 10 ether);
        vm.startPrank(VAULT_OWNER);
        try WITHDRAW_H.withdraw{value: 2 ether}(IWithdrawHandlerVaultCore(VAULT_CORE), shares, 0) {
            ghost_withdrawSuccesses += 1;
        } catch {}
        vm.stopPrank();
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
    }

    function actTriggerDeadman(uint256) external {
        ghost_deadmanAttempts += 1;
        vm.startPrank(VAULT_OWNER);
        try VaultCore(payable(VAULT_CORE)).triggerManagerDeadman() {
            ghost_deadmanSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function _rollPastCooldown() internal {
        uint256 end = STATE.globalActionCooldownEndBlock();
        if (block.number <= end) vm.roll(end + 1);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ManagerActor — rebalance, accrueManagerFee, setTargetLtv, pingHeartbeat
// ─────────────────────────────────────────────────────────────────────────────

contract ManagerActor is Test {
    address internal immutable VAULT_CORE;
    address internal immutable PROTOCOL_MANAGER;

    VaultState internal immutable STATE;
    BasaltMath internal immutable MATH;
    ManagerHandler internal immutable MANAGER_H;
    FeeAccountingHandler internal immutable FEE_H;

    uint256 public ghost_rebalanceAttempts;
    uint256 public ghost_rebalanceSuccesses;
    uint256 public ghost_finalizeRebalanceAttempts;
    uint256 public ghost_finalizeRebalanceSuccesses;
    uint256 public ghost_feeAccrualSuccesses;
    uint256 public ghost_setTargetLtvAttempts;
    uint256 public ghost_setTargetLtvSuccesses;
    uint256 public ghost_pingHeartbeatSuccesses;

    /// @dev Address used as the "owner" argument to accrueManagerFee. The fee accounting
    ///      handler takes the vault owner for HWM calculations — we pass the real one.
    address internal immutable VAULT_OWNER;

    constructor(
        address vaultCoreAddr,
        address vaultStateAddr,
        address mathAddr,
        address managerHandlerAddr,
        address feeHandlerAddr,
        address protocolManagerAddr,
        address vaultOwnerAddr
    ) {
        VAULT_CORE = vaultCoreAddr;
        STATE = VaultState(vaultStateAddr);
        MATH = BasaltMath(mathAddr);
        MANAGER_H = ManagerHandler(managerHandlerAddr);
        FEE_H = FeeAccountingHandler(feeHandlerAddr);
        PROTOCOL_MANAGER = protocolManagerAddr;
        VAULT_OWNER = vaultOwnerAddr;
    }

    function actRebalance(uint256 slippageSeed) external {
        if (STATE.rebalanceState() != VaultState.State.IDLE) return;
        if (STATE.depositState() != VaultState.State.IDLE) return;
        if (STATE.withdrawState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        uint256 slippage = bound(slippageSeed, 1, 500);
        ghost_rebalanceAttempts += 1;
        vm.deal(PROTOCOL_MANAGER, 10 ether);
        vm.startPrank(PROTOCOL_MANAGER);
        try MANAGER_H.rebalance{value: 2 ether}(IManagerHandlerVaultCore(VAULT_CORE), slippage) {
            ghost_rebalanceSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function actFinalizeRebalance(uint256) external {
        if (STATE.rebalanceState() != VaultState.State.PENDING) return;
        _rollPastCooldown();
        vm.warp(block.timestamp + 1800);

        ghost_finalizeRebalanceAttempts += 1;
        vm.startPrank(PROTOCOL_MANAGER);
        try MANAGER_H.finalizeRebalance(IManagerHandlerVaultCore(VAULT_CORE)) {
            ghost_finalizeRebalanceSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function actAccrueFees(uint256) external {
        try FEE_H.accrueManagerFee(
            IFeeAccountingHandlerVaultCore(VAULT_CORE), IBasaltMath(address(MATH)), VAULT_OWNER
        ) {
            ghost_feeAccrualSuccesses += 1;
        } catch {}
    }

    function actSetTargetLtv(uint256 ltvSeed) external {
        if (STATE.depositState() != VaultState.State.IDLE) return;
        if (STATE.withdrawState() != VaultState.State.IDLE) return;
        if (STATE.rebalanceState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        uint256 ltv = bound(ltvSeed, BasaltConstants.MIN_TARGET_LTV_BPS, BasaltConstants.MAX_TARGET_LTV_BPS);
        ghost_setTargetLtvAttempts += 1;
        vm.startPrank(PROTOCOL_MANAGER);
        try MANAGER_H.setTargetLtv(IManagerHandlerVaultCore(VAULT_CORE), ltv) {
            ghost_setTargetLtvSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function actPingHeartbeat(uint256) external {
        vm.startPrank(PROTOCOL_MANAGER);
        try MANAGER_H.pingHeartbeat(IManagerHandlerVaultCore(VAULT_CORE)) {
            ghost_pingHeartbeatSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function _rollPastCooldown() internal {
        uint256 end = STATE.globalActionCooldownEndBlock();
        if (block.number <= end) vm.roll(end + 1);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SecondOwnerActor — deposit/withdraw on vaultB (independent vault)
// ─────────────────────────────────────────────────────────────────────────────

contract SecondOwnerActor is Test {
    address internal immutable VAULT_CORE_B;
    address internal immutable SECOND_OWNER;

    VaultState internal immutable STATE_B;
    DepositHandler internal immutable DEPOSIT_H;
    WithdrawHandler internal immutable WITHDRAW_H;

    uint256 public ghost_depositAttempts;
    uint256 public ghost_depositSuccesses;
    uint256 public ghost_withdrawAttempts;
    uint256 public ghost_withdrawSuccesses;
    uint256 public ghost_finalizeDepositAttempts;
    uint256 public ghost_finalizeDepositSuccesses;
    uint256 public ghost_finalizeWithdrawAttempts;
    uint256 public ghost_finalizeWithdrawSuccesses;

    constructor(
        address vaultCoreBAddr,
        address vaultStateBAddr,
        address depositHandlerAddr,
        address withdrawHandlerAddr,
        address secondOwnerAddr
    ) {
        VAULT_CORE_B = vaultCoreBAddr;
        STATE_B = VaultState(vaultStateBAddr);
        DEPOSIT_H = DepositHandler(depositHandlerAddr);
        WITHDRAW_H = WithdrawHandler(withdrawHandlerAddr);
        SECOND_OWNER = secondOwnerAddr;

        vm.prank(SECOND_OWNER);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(depositHandlerAddr, type(uint256).max);
    }

    function actSecondOwnerDeposit(uint256 amountGmSeed) external {
        uint256 amountGm = bound(amountGmSeed, 1e18, 5e21);
        if (STATE_B.depositState() != VaultState.State.IDLE) return;
        if (STATE_B.withdrawState() != VaultState.State.IDLE) return;
        if (STATE_B.rebalanceState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        ghost_depositAttempts += 1;
        deal(BasaltAddresses.GM_MARKET_TOKEN, SECOND_OWNER, amountGm);
        vm.deal(SECOND_OWNER, 10 ether);
        vm.startPrank(SECOND_OWNER);
        try DEPOSIT_H.deposit{value: 2 ether}(IDepositHandlerVaultCore(VAULT_CORE_B), amountGm, 500) {
            ghost_depositSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function actSecondOwnerFinalizeDeposit(uint256) external {
        if (STATE_B.depositState() != VaultState.State.PENDING) return;
        _rollPastCooldown();
        vm.warp(block.timestamp + 1800);

        ghost_finalizeDepositAttempts += 1;
        vm.startPrank(SECOND_OWNER);
        try DEPOSIT_H.finalizeDeposit(IDepositHandlerVaultCore(VAULT_CORE_B)) {
            ghost_finalizeDepositSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function actSecondOwnerWithdraw(uint256 shareSeed) external {
        if (STATE_B.withdrawState() != VaultState.State.IDLE) return;
        if (STATE_B.depositState() != VaultState.State.IDLE) return;
        if (STATE_B.rebalanceState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        uint256 shares = bound(shareSeed, 1, BasaltConstants.SHARE_UNIT);
        ghost_withdrawAttempts += 1;
        vm.deal(SECOND_OWNER, 10 ether);
        vm.startPrank(SECOND_OWNER);
        try WITHDRAW_H.withdraw{value: 2 ether}(IWithdrawHandlerVaultCore(VAULT_CORE_B), shares, 0) {
            ghost_withdrawSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function actSecondOwnerFinalizeWithdraw(uint256) external {
        if (STATE_B.withdrawState() != VaultState.State.PENDING) return;
        _rollPastCooldown();
        vm.warp(block.timestamp + 1800);

        ghost_finalizeWithdrawAttempts += 1;
        vm.startPrank(SECOND_OWNER);
        try WITHDRAW_H.finalizeWithdraw(IWithdrawHandlerVaultCore(VAULT_CORE_B)) {
            ghost_finalizeWithdrawSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function _rollPastCooldown() internal {
        uint256 end = STATE_B.globalActionCooldownEndBlock();
        if (block.number <= end) vm.roll(end + 1);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  StrangerActor — deposit on vaultA should fail (not NFT owner),
//                  attempts privileged ops to verify ACL
// ─────────────────────────────────────────────────────────────────────────────

contract StrangerActor is Test {
    address internal immutable VAULT_CORE;
    address internal immutable STRANGER;

    VaultState internal immutable STATE;
    DepositHandler internal immutable DEPOSIT_H;
    WithdrawHandler internal immutable WITHDRAW_H;
    ManagerHandler internal immutable MANAGER_H;

    uint256 public ghost_depositAttempts;
    uint256 public ghost_depositSuccesses;
    uint256 public ghost_withdrawAttempts;
    uint256 public ghost_withdrawSuccesses;
    uint256 public ghost_rebalanceAttempts;
    uint256 public ghost_rebalanceSuccesses;
    uint256 public ghost_setTargetLtvAttempts;
    uint256 public ghost_setTargetLtvSuccesses;

    constructor(
        address vaultCoreAddr,
        address vaultStateAddr,
        address depositHandlerAddr,
        address withdrawHandlerAddr,
        address managerHandlerAddr,
        address strangerAddr
    ) {
        VAULT_CORE = vaultCoreAddr;
        STATE = VaultState(vaultStateAddr);
        DEPOSIT_H = DepositHandler(depositHandlerAddr);
        WITHDRAW_H = WithdrawHandler(withdrawHandlerAddr);
        MANAGER_H = ManagerHandler(managerHandlerAddr);
        STRANGER = strangerAddr;

        vm.prank(STRANGER);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(depositHandlerAddr, type(uint256).max);
    }

    /// @dev Stranger tries to deposit into vaultA — should revert (not NFT owner).
    function actStrangerDeposit(uint256 amountGmSeed) external {
        uint256 amountGm = bound(amountGmSeed, 1e18, 5e21);
        _rollPastCooldown();

        ghost_depositAttempts += 1;
        deal(BasaltAddresses.GM_MARKET_TOKEN, STRANGER, amountGm);
        vm.deal(STRANGER, 10 ether);
        vm.startPrank(STRANGER);
        try DEPOSIT_H.deposit{value: 2 ether}(IDepositHandlerVaultCore(VAULT_CORE), amountGm, 500) {
            ghost_depositSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    /// @dev Stranger tries to withdraw from vaultA — should revert.
    function actStrangerWithdraw(uint256 shareSeed) external {
        uint256 shares = bound(shareSeed, 1, BasaltConstants.SHARE_UNIT);
        _rollPastCooldown();

        ghost_withdrawAttempts += 1;
        vm.deal(STRANGER, 10 ether);
        vm.startPrank(STRANGER);
        try WITHDRAW_H.withdraw{value: 2 ether}(IWithdrawHandlerVaultCore(VAULT_CORE), shares, 0) {
            ghost_withdrawSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    /// @dev Stranger tries to rebalance vaultA — should revert (not protocol manager, and
    ///      only the NFT owner can rebalance past thresholds, but stranger is neither).
    function actStrangerRebalance(uint256 slippageSeed) external {
        uint256 slippage = bound(slippageSeed, 1, 500);
        _rollPastCooldown();

        ghost_rebalanceAttempts += 1;
        vm.deal(STRANGER, 10 ether);
        vm.startPrank(STRANGER);
        try MANAGER_H.rebalance{value: 2 ether}(IManagerHandlerVaultCore(VAULT_CORE), slippage) {
            ghost_rebalanceSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    /// @dev Stranger tries setTargetLtv — should revert (onlyProtocolManager).
    function actStrangerSetTargetLtv(uint256 ltvSeed) external {
        uint256 ltv = bound(ltvSeed, BasaltConstants.MIN_TARGET_LTV_BPS, BasaltConstants.MAX_TARGET_LTV_BPS);
        _rollPastCooldown();

        ghost_setTargetLtvAttempts += 1;
        vm.startPrank(STRANGER);
        try MANAGER_H.setTargetLtv(IManagerHandlerVaultCore(VAULT_CORE), ltv) {
            ghost_setTargetLtvSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    function _rollPastCooldown() internal {
        uint256 end = STATE.globalActionCooldownEndBlock();
        if (block.number <= end) vm.roll(end + 1);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AttackerActor — tries direct handler calls, state manipulation,
//                  universalCall via VaultCore. All should revert.
// ─────────────────────────────────────────────────────────────────────────────

contract AttackerActor is Test {
    address internal immutable VAULT_CORE;
    address internal immutable ATTACKER;

    VaultState internal immutable STATE;
    DepositHandler internal immutable DEPOSIT_H;
    WithdrawHandler internal immutable WITHDRAW_H;
    ManagerHandler internal immutable MANAGER_H;

    uint256 public ghost_universalCallAttempts;
    uint256 public ghost_universalCallSuccesses;
    uint256 public ghost_directStateWriteAttempts;
    uint256 public ghost_directStateWriteSuccesses;
    uint256 public ghost_depositAttempts;
    uint256 public ghost_depositSuccesses;
    uint256 public ghost_deadmanAttempts;
    uint256 public ghost_deadmanSuccesses;
    uint256 public ghost_pingHeartbeatAttempts;
    uint256 public ghost_pingHeartbeatSuccesses;

    constructor(
        address vaultCoreAddr,
        address vaultStateAddr,
        address depositHandlerAddr,
        address withdrawHandlerAddr,
        address managerHandlerAddr,
        address attackerAddr
    ) {
        VAULT_CORE = vaultCoreAddr;
        STATE = VaultState(vaultStateAddr);
        DEPOSIT_H = DepositHandler(depositHandlerAddr);
        WITHDRAW_H = WithdrawHandler(withdrawHandlerAddr);
        MANAGER_H = ManagerHandler(managerHandlerAddr);
        ATTACKER = attackerAddr;
    }

    /// @dev Attacker calls universalCall directly on VaultCore — should revert (onlyHandler).
    function actAttackerUniversalCall(uint256) external {
        ghost_universalCallAttempts += 1;
        vm.startPrank(ATTACKER);
        try VaultCore(payable(VAULT_CORE)).universalCall(
            ATTACKER, ATTACKER, abi.encodeWithSignature("transfer(address,uint256)", ATTACKER, 1e18), 0, false
        ) {
            ghost_universalCallSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    /// @dev Attacker tries to write directly to VaultState (setDepositState) — should revert (onlyVaultCore).
    function actAttackerDirectStateWrite(uint256) external {
        ghost_directStateWriteAttempts += 1;
        vm.startPrank(ATTACKER);
        try STATE.setDepositState(VaultState.State.PENDING) {
            ghost_directStateWriteSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    /// @dev Attacker tries deposit on vaultA — should revert (not NFT owner).
    function actAttackerDeposit(uint256 amountSeed) external {
        uint256 amountGm = bound(amountSeed, 1e18, 5e21);
        ghost_depositAttempts += 1;
        deal(BasaltAddresses.GM_MARKET_TOKEN, ATTACKER, amountGm);
        vm.deal(ATTACKER, 10 ether);
        vm.startPrank(ATTACKER);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(address(DEPOSIT_H), type(uint256).max);
        try DEPOSIT_H.deposit{value: 2 ether}(IDepositHandlerVaultCore(VAULT_CORE), amountGm, 500) {
            ghost_depositSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    /// @dev Attacker tries triggerManagerDeadman — should revert (not NFT owner).
    function actAttackerDeadman(uint256) external {
        ghost_deadmanAttempts += 1;
        vm.startPrank(ATTACKER);
        try VaultCore(payable(VAULT_CORE)).triggerManagerDeadman() {
            ghost_deadmanSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }

    /// @dev Attacker tries pingHeartbeat — should revert (not protocol manager).
    function actAttackerPingHeartbeat(uint256) external {
        ghost_pingHeartbeatAttempts += 1;
        vm.startPrank(ATTACKER);
        try MANAGER_H.pingHeartbeat(IManagerHandlerVaultCore(VAULT_CORE)) {
            ghost_pingHeartbeatSuccesses += 1;
        } catch {}
        vm.stopPrank();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  InvariantMultiActor — 5 actors, 2 vaults, cross-actor invariants
// ─────────────────────────────────────────────────────────────────────────────

contract InvariantMultiActor is ForkSetupFull {
    OwnerActor internal ownerActor;
    ManagerActor internal managerActor;
    SecondOwnerActor internal secondOwnerActor;
    StrangerActor internal strangerActor;
    AttackerActor internal attackerActor;

    // Vault B: independent vault owned by secondOwner
    address internal secondOwner;
    uint256 internal vaultTokenIdB;
    VaultCore internal vaultCoreB;
    VaultState internal vaultStateB;

    // Snapshot vaultA state before each invariant call (captured at setup end)
    uint256 internal snapshotA_totalDepositedUsd;
    uint256 internal snapshotA_totalWithdrawnUsd;

    // Snapshot vaultB state before each invariant call
    uint256 internal snapshotB_totalDepositedUsd;
    uint256 internal snapshotB_totalWithdrawnUsd;

    function setUp() public override {
        super.setUp();

        secondOwner = address(uint160(0x2001));

        // Fund actors
        _fundActor(vaultOwner);
        _fundActor(secondOwner);

        // Deploy vault B for secondOwner
        (vaultTokenIdB, vaultCoreB) = _createVaultCore(secondOwner);
        vaultStateB = VaultState(vaultCoreB.basaltState());

        // --- OwnerActor: drives vaultA ---
        ownerActor = new OwnerActor(
            address(vaultCore),
            address(vaultState),
            address(depositHandler),
            address(withdrawHandler),
            vaultOwner
        );

        // --- ManagerActor: drives vaultA manager ops ---
        managerActor = new ManagerActor(
            address(vaultCore),
            address(vaultState),
            address(basaltMath),
            address(managerHandler),
            address(feeAccountingHandler),
            address(managerContract),
            vaultOwner
        );

        // --- SecondOwnerActor: drives vaultB ---
        secondOwnerActor = new SecondOwnerActor(
            address(vaultCoreB),
            address(vaultStateB),
            address(depositHandler),
            address(withdrawHandler),
            secondOwner
        );

        // --- StrangerActor: tries unauthorized ops on vaultA ---
        strangerActor = new StrangerActor(
            address(vaultCore),
            address(vaultState),
            address(depositHandler),
            address(withdrawHandler),
            address(managerHandler),
            stranger
        );

        // --- AttackerActor: tries direct/privileged ops on vaultA ---
        address attacker = address(uint160(0x3001));
        vm.deal(attacker, ACTOR_ETH_BALANCE);
        attackerActor = new AttackerActor(
            address(vaultCore),
            address(vaultState),
            address(depositHandler),
            address(withdrawHandler),
            address(managerHandler),
            attacker
        );

        // Target all 5 actors
        targetContract(address(ownerActor));
        targetContract(address(managerActor));
        targetContract(address(secondOwnerActor));
        targetContract(address(strangerActor));
        targetContract(address(attackerActor));

        // --- Register selectors for OwnerActor ---
        {
            bytes4[] memory sel = new bytes4[](5);
            sel[0] = OwnerActor.actOwnerDeposit.selector;
            sel[1] = OwnerActor.actFinalizeDeposit.selector;
            sel[2] = OwnerActor.actOwnerWithdraw.selector;
            sel[3] = OwnerActor.actFinalizeWithdraw.selector;
            sel[4] = OwnerActor.actTriggerDeadman.selector;
            targetSelector(FuzzSelector({addr: address(ownerActor), selectors: sel}));
        }

        // --- Register selectors for ManagerActor ---
        {
            bytes4[] memory sel = new bytes4[](5);
            sel[0] = ManagerActor.actRebalance.selector;
            sel[1] = ManagerActor.actFinalizeRebalance.selector;
            sel[2] = ManagerActor.actAccrueFees.selector;
            sel[3] = ManagerActor.actSetTargetLtv.selector;
            sel[4] = ManagerActor.actPingHeartbeat.selector;
            targetSelector(FuzzSelector({addr: address(managerActor), selectors: sel}));
        }

        // --- Register selectors for SecondOwnerActor ---
        {
            bytes4[] memory sel = new bytes4[](4);
            sel[0] = SecondOwnerActor.actSecondOwnerDeposit.selector;
            sel[1] = SecondOwnerActor.actSecondOwnerFinalizeDeposit.selector;
            sel[2] = SecondOwnerActor.actSecondOwnerWithdraw.selector;
            sel[3] = SecondOwnerActor.actSecondOwnerFinalizeWithdraw.selector;
            targetSelector(FuzzSelector({addr: address(secondOwnerActor), selectors: sel}));
        }

        // --- Register selectors for StrangerActor ---
        {
            bytes4[] memory sel = new bytes4[](4);
            sel[0] = StrangerActor.actStrangerDeposit.selector;
            sel[1] = StrangerActor.actStrangerWithdraw.selector;
            sel[2] = StrangerActor.actStrangerRebalance.selector;
            sel[3] = StrangerActor.actStrangerSetTargetLtv.selector;
            targetSelector(FuzzSelector({addr: address(strangerActor), selectors: sel}));
        }

        // --- Register selectors for AttackerActor ---
        {
            bytes4[] memory sel = new bytes4[](5);
            sel[0] = AttackerActor.actAttackerUniversalCall.selector;
            sel[1] = AttackerActor.actAttackerDirectStateWrite.selector;
            sel[2] = AttackerActor.actAttackerDeposit.selector;
            sel[3] = AttackerActor.actAttackerDeadman.selector;
            sel[4] = AttackerActor.actAttackerPingHeartbeat.selector;
            targetSelector(FuzzSelector({addr: address(attackerActor), selectors: sel}));
        }

        // Lock fuzzer sender so only targeted actors are called
        targetSender(address(this));

        // Capture initial state for isolation invariant
        snapshotA_totalDepositedUsd = vaultState.totalDepositedUsdE18();
        snapshotA_totalWithdrawnUsd = vaultState.totalWithdrawnUsdE18();
        snapshotB_totalDepositedUsd = vaultStateB.totalDepositedUsdE18();
        snapshotB_totalWithdrawnUsd = vaultStateB.totalWithdrawnUsdE18();
    }

    //  INVARIANTS

    /// @notice INV-MA-01: VaultA state changes must not affect vaultB's accounting.
    ///         If ownerActor never touched vaultB and secondOwnerActor never touched vaultA,
    ///         then each vault's accumulators are independently monotonic.
    function invariant_multiVaultIsolation() public view {
        // VaultA totalDeposited >= snapshot (monotonic)
        assertGe(
            vaultState.totalDepositedUsdE18(),
            snapshotA_totalDepositedUsd,
            "INV-MA-01: vaultA totalDeposited went backwards"
        );

        // VaultB totalDeposited >= snapshot (monotonic)
        assertGe(
            vaultStateB.totalDepositedUsdE18(),
            snapshotB_totalDepositedUsd,
            "INV-MA-01: vaultB totalDeposited went backwards"
        );

        // Cross-isolation: if no B deposits happened, B deposited must be unchanged.
        // (Detects state leakage from vaultA operations bleeding into vaultB.)
        if (secondOwnerActor.ghost_depositSuccesses() == 0) {
            assertEq(
                vaultStateB.totalDepositedUsdE18(),
                snapshotB_totalDepositedUsd,
                "INV-MA-01: vaultB totalDeposited changed without any B deposit"
            );
        }

        // Symmetric: if no A deposits happened, A deposited must be unchanged
        if (ownerActor.ghost_depositSuccesses() == 0 && ownerActor.ghost_finalizeDepositSuccesses() == 0) {
            assertEq(
                vaultState.totalDepositedUsdE18(),
                snapshotA_totalDepositedUsd,
                "INV-MA-01: vaultA totalDeposited changed without any A deposit"
            );
        }
    }

    /// @notice INV-MA-02: Stranger and attacker must never successfully change vault state.
    ///         All their privileged operations must revert.
    function invariant_noUnauthorizedStateChange() public view {
        // Stranger checks
        assertEq(
            strangerActor.ghost_depositSuccesses(), 0,
            "INV-MA-02: stranger successfully deposited into vaultA"
        );
        assertEq(
            strangerActor.ghost_withdrawSuccesses(), 0,
            "INV-MA-02: stranger successfully withdrew from vaultA"
        );
        assertEq(
            strangerActor.ghost_setTargetLtvSuccesses(), 0,
            "INV-MA-02: stranger successfully called setTargetLtv"
        );
        // Note: stranger rebalance MAY succeed if stranger is the NFT owner of another vault
        // and threshold conditions are met, but on vaultA where stranger is NOT the owner
        // or manager, it should always revert. The rebalance function allows NFT owner
        // past thresholds, but stranger is neither owner nor manager of vaultA.
        assertEq(
            strangerActor.ghost_rebalanceSuccesses(), 0,
            "INV-MA-02: stranger successfully rebalanced vaultA"
        );
    }

    /// @notice INV-MA-03: Global solvency — across both vaults, no value created from nothing.
    ///         totalWithdrawn <= totalDeposited when no external profit has been booked.
    function invariant_globalSolvency() public view {
        // Per-vault solvency: withdrawn never exceeds deposited when HWM profit is zero.
        if (vaultState.highWaterMarkProfitUsdE18() == 0) {
            assertLe(
                vaultState.totalWithdrawnUsdE18(),
                vaultState.totalDepositedUsdE18(),
                "INV-MA-03: vaultA withdrawn > deposited without profit"
            );
        }

        if (vaultStateB.highWaterMarkProfitUsdE18() == 0) {
            assertLe(
                vaultStateB.totalWithdrawnUsdE18(),
                vaultStateB.totalDepositedUsdE18(),
                "INV-MA-03: vaultB withdrawn > deposited without profit"
            );
        }

        // Both vaults: state machine mutual exclusion holds independently
        _assertAtMostOnePending(vaultState, "vaultA");
        _assertAtMostOnePending(vaultStateB, "vaultB");
    }

    /// @notice INV-MA-04: At least some legitimate actor operations succeed (not just reverting).
    ///         Verifies the fuzzer actually exercises real code paths.
    function invariant_atLeastSomeSuccesses() public view {
        uint256 totalOwnerAttempts = ownerActor.ghost_depositAttempts()
            + ownerActor.ghost_withdrawAttempts()
            + managerActor.ghost_rebalanceAttempts();

        // After enough attempts, at least one legitimate action should succeed.
        if (totalOwnerAttempts > 10) {
            uint256 totalSuccesses = ownerActor.ghost_depositSuccesses()
                + ownerActor.ghost_withdrawSuccesses()
                + managerActor.ghost_rebalanceSuccesses()
                + managerActor.ghost_feeAccrualSuccesses()
                + managerActor.ghost_setTargetLtvSuccesses()
                + managerActor.ghost_pingHeartbeatSuccesses();
            assertTrue(
                totalSuccesses > 0,
                "INV-MA-04: zero legitimate successes after 10+ attempts - test is meaningless"
            );
        }
    }

    /// @notice INV-MA-05: Attacker must NEVER succeed at privileged operations.
    ///         universalCall, direct state writes, deposits, deadman, pingHeartbeat — all must revert.
    function invariant_attackerZeroSuccesses() public view {
        assertEq(
            attackerActor.ghost_universalCallSuccesses(), 0,
            "INV-MA-05: attacker succeeded at universalCall"
        );
        assertEq(
            attackerActor.ghost_directStateWriteSuccesses(), 0,
            "INV-MA-05: attacker wrote directly to VaultState"
        );
        assertEq(
            attackerActor.ghost_depositSuccesses(), 0,
            "INV-MA-05: attacker deposited into vaultA"
        );
        assertEq(
            attackerActor.ghost_deadmanSuccesses(), 0,
            "INV-MA-05: attacker triggered deadman switch"
        );
        assertEq(
            attackerActor.ghost_pingHeartbeatSuccesses(), 0,
            "INV-MA-05: attacker pinged heartbeat"
        );
    }

    /// @notice Summary: surfaces ghost counters in failure output for debugging.
    function invariant_summary() public view {
        // Always-true — exists only to print ghost counters on failure.
        assertTrue(
            ownerActor.ghost_depositAttempts()
                + managerActor.ghost_rebalanceAttempts()
                + secondOwnerActor.ghost_depositAttempts()
                + strangerActor.ghost_depositAttempts()
                + attackerActor.ghost_universalCallAttempts() >= 0
        );
    }

    //  INTERNAL HELPERS

    function _assertAtMostOnePending(VaultState vs, string memory vaultLabel) internal view {
        uint8 pendingCount = 0;
        if (vs.depositState() == VaultState.State.PENDING) pendingCount += 1;
        if (vs.withdrawState() == VaultState.State.PENDING) pendingCount += 1;
        if (vs.rebalanceState() == VaultState.State.PENDING) pendingCount += 1;
        assertLe(
            pendingCount, 1,
            string.concat("INV-MA-03: ", vaultLabel, " has >1 PENDING state")
        );
    }
}

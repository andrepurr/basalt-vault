// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ForkSetupFull} from "../helpers/ForkSetupFull.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {VaultCoreNftFactory} from "../../src/core/VaultCoreNftFactory.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";
import {DepositHandler} from "../../src/handlers/DepositHandler.sol";
import {WithdrawHandler} from "../../src/handlers/WithdrawHandler.sol";
import {FeeAccountingHandler} from "../../src/handlers/FeeAccountingHandler.sol";
import {IDepositHandlerVaultCore} from "../../src/interfaces/IDepositHandlerVaultCore.sol";
import {IWithdrawHandlerVaultCore} from "../../src/interfaces/IWithdrawHandlerVaultCore.sol";
import {IFeeAccountingHandlerVaultCore} from "../../src/interfaces/IFeeAccountingHandlerVaultCore.sol";
import {IBasaltMath} from "../../src/interfaces/IBasaltMath.sol";
import {IInitialCoreAddressBook} from "../../src/interfaces/IInitialCoreAddressBook.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  FeeAccountingActor -- drives deposit/finalize/accrue/withdraw/factory
//  sequences for INV-05, INV-FAC-001, INV-FAC-002.
// ─────────────────────────────────────────────────────────────────────────────

contract FeeAccountingActor is Test {
    address internal immutable VAULT_CORE;
    address internal immutable VAULT_OWNER;
    address internal immutable PROTOCOL_MANAGER;
    address internal immutable FACTORY_OWNER;

    VaultState internal immutable STATE;
    BasaltMath internal immutable MATH;
    DepositHandler internal immutable DEPOSIT_H;
    WithdrawHandler internal immutable WITHDRAW_H;
    FeeAccountingHandler internal immutable FEE_H;
    VaultCoreNftFactory internal immutable FACTORY;

    // -- Ghosts --
    uint256 public ghost_hwmEverSeenUsdE18;
    uint256 public ghost_maxAccruedFeeEverUsdE18;
    uint256 public ghost_feeAccrualAttempts;
    uint256 public ghost_feeAccrualSuccesses;
    uint256 public ghost_depositAttempts;
    uint256 public ghost_depositSuccesses;
    uint256 public ghost_finalizeDepositAttempts;
    uint256 public ghost_finalizeDepositSuccesses;
    uint256 public ghost_withdrawAttempts;
    uint256 public ghost_withdrawSuccesses;
    uint256 public ghost_cooldownCreationAttempts;
    uint256 public ghost_cooldownCreationSuccesses;

    constructor(
        address vaultCoreAddr,
        address vaultStateAddr,
        address mathAddr,
        address depositHandlerAddr,
        address withdrawHandlerAddr,
        address feeHandlerAddr,
        address factoryAddr,
        address vaultOwnerAddr,
        address protocolManagerAddr,
        address factoryOwnerAddr
    ) {
        VAULT_CORE = vaultCoreAddr;
        STATE = VaultState(vaultStateAddr);
        MATH = BasaltMath(mathAddr);
        DEPOSIT_H = DepositHandler(depositHandlerAddr);
        WITHDRAW_H = WithdrawHandler(withdrawHandlerAddr);
        FEE_H = FeeAccountingHandler(feeHandlerAddr);
        FACTORY = VaultCoreNftFactory(factoryAddr);
        VAULT_OWNER = vaultOwnerAddr;
        PROTOCOL_MANAGER = protocolManagerAddr;
        FACTORY_OWNER = factoryOwnerAddr;

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
            _trackAccumulators();
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
            _trackAccumulators();
        } catch {}
        vm.stopPrank();
    }

    function actAccrueFees(uint256) external {
        ghost_feeAccrualAttempts += 1;
        try FEE_H.accrueManagerFee(
            IFeeAccountingHandlerVaultCore(VAULT_CORE),
            IBasaltMath(address(MATH)),
            VAULT_OWNER
        ) {
            ghost_feeAccrualSuccesses += 1;
            _trackAccumulators();
        } catch {}
    }

    function actOwnerWithdraw(uint256 sharesSeed, uint256 slippageSeed) external {
        if (STATE.withdrawState() != VaultState.State.IDLE) return;
        if (STATE.depositState() != VaultState.State.IDLE) return;
        if (STATE.rebalanceState() != VaultState.State.IDLE) return;
        _rollPastCooldown();

        ghost_withdrawAttempts += 1;
        uint256 shares = bound(sharesSeed, 1, BasaltConstants.SHARE_UNIT);
        vm.deal(VAULT_OWNER, 10 ether);
        vm.startPrank(VAULT_OWNER);
        try WITHDRAW_H.withdraw{value: 2 ether}(
            IWithdrawHandlerVaultCore(VAULT_CORE), shares, 0
        ) {
            ghost_withdrawSuccesses += 1;
            _trackAccumulators();
        } catch {}
        vm.stopPrank();
    }

    /// @dev INV-FAC-001: Update address book (triggers cooldown), then immediately try createVaultCore.
    ///      If createVaultCore succeeds during cooldown, the guard is broken.
    function actUpdateAddressBookAndCreateVault(uint256) external {
        ghost_cooldownCreationAttempts += 1;

        // setInitialCoreAddressBook is onlyOwner on the factory.
        // The factory owner in ForkSetupFull is the managerContract.owner() = test deployer.
        // However, in the ForkSetupFull flow, the factory owner is factoryOwner (0x1001).
        // The factory's setInitialCoreAddressBook is called from managerContract.setInitialCoreAddressBook
        // which is onlyOwner on managerContract.
        // Actually, VaultCoreNftFactory.setInitialCoreAddressBook is onlyOwner (factory owner).
        // The factory's owner = factoryOwner address, and managerContract has its own
        // setInitialCoreAddressBook that calls factory.setInitialCoreAddressBook -- that requires
        // msg.sender == factory.owner() which is... factoryOwner.
        // Looking at ForkSetupFull: vaultCoreNftFactory = new VaultCoreNftFactory(initialCoreAddressBook, factoryOwner, address(managerContract))
        // So factory.owner() = factoryOwner (0x1001).
        // But setInitialCoreAddressBook on factory is onlyOwner.
        // We need Ownable2Step acceptance. Let's check: factory was constructed with Ownable(factoryOwner).
        // So factory.owner() = factoryOwner right away (no 2-step needed for constructor).

        // Update address book from factory owner to trigger cooldown.
        IInitialCoreAddressBook currentAB = FACTORY.initialCoreAddressBook();
        vm.prank(FACTORY_OWNER);
        try FACTORY.setInitialCoreAddressBook(currentAB) {
            // Cooldown is now active. Try to create a vault immediately.
            try FACTORY.createVaultCore(address(uint160(0xDEAD))) returns (uint256, address) {
                // If this succeeds, cooldown guard is broken.
                ghost_cooldownCreationSuccesses += 1;
            } catch {
                // Expected: AddressBookCooldownActive revert.
            }
        } catch {}
    }

    // -- Internal --

    function _rollPastCooldown() internal {
        uint256 end = STATE.globalActionCooldownEndBlock();
        if (block.number <= end) {
            vm.roll(end + 1);
        }
    }

    function _trackAccumulators() internal {
        uint256 hwm = STATE.highWaterMarkProfitUsdE18();
        if (hwm > ghost_hwmEverSeenUsdE18) ghost_hwmEverSeenUsdE18 = hwm;

        uint256 accrued = STATE.managerAccruedFeeUsdE18();
        if (accrued > ghost_maxAccruedFeeEverUsdE18) ghost_maxAccruedFeeEverUsdE18 = accrued;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  InvariantFeeAccounting -- INV-05 HWM/fee accounting, INV-FAC-001 cooldown,
//  INV-FAC-002 clone isolation.
// ─────────────────────────────────────────────────────────────────────────────

contract InvariantFeeAccounting is ForkSetupFull {
    uint256 internal PERFORMANCE_FEE_BPS;

    FeeAccountingActor internal actor;

    // Second clone for INV-FAC-002 isolation check.
    VaultCore internal secondVaultCore;
    VaultState internal secondVaultState;

    function setUp() public override {
        super.setUp();
        _fundActor(vaultOwner);

        PERFORMANCE_FEE_BPS = vaultState.managementFeeBps();
        require(PERFORMANCE_FEE_BPS == 2_000, "management fee init drift");

        // Deploy a second vault clone under a different owner for INV-FAC-002.
        address secondOwner = address(uint160(0x2002));
        (, secondVaultCore) = _createVaultCore(secondOwner);
        secondVaultState = VaultState(secondVaultCore.basaltState());

        actor = new FeeAccountingActor(
            address(vaultCore),
            address(vaultState),
            address(basaltMath),
            address(depositHandler),
            address(withdrawHandler),
            address(feeAccountingHandler),
            address(vaultCoreNftFactory),
            vaultOwner,
            address(managerContract),
            factoryOwner
        );

        targetContract(address(actor));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = FeeAccountingActor.actOwnerDeposit.selector;
        selectors[1] = FeeAccountingActor.actFinalizeDeposit.selector;
        selectors[2] = FeeAccountingActor.actAccrueFees.selector;
        selectors[3] = FeeAccountingActor.actOwnerWithdraw.selector;
        selectors[4] = FeeAccountingActor.actUpdateAddressBookAndCreateVault.selector;
        targetSelector(FuzzSelector({addr: address(actor), selectors: selectors}));
        targetSender(address(this));
    }

    // -- Invariants --

    /// INV-05: HWM is monotonically non-decreasing.
    function invariant_inv05_hwmMonotonic() public view {
        assertGe(
            vaultState.highWaterMarkProfitUsdE18(),
            actor.ghost_hwmEverSeenUsdE18(),
            "INV-05: HWM went backwards"
        );
    }

    /// INV-05: Accrued fee cannot exceed HWM-derived ceiling.
    function invariant_inv05_accruedFeeWithinHwmFraction() public view {
        uint256 hwm = vaultState.highWaterMarkProfitUsdE18();
        uint256 accrued = vaultState.managerAccruedFeeUsdE18();
        uint256 maxFee = (hwm * PERFORMANCE_FEE_BPS) / 10_000 + 1;
        assertLe(accrued, maxFee, "INV-05: accrued fee exceeds HWM-derived ceiling");
    }

    /// INV-05: If no deposits ever succeeded, fees must be zero.
    function invariant_inv05_feesOnlyOnRealProfit() public view {
        if (actor.ghost_depositSuccesses() == 0) {
            assertEq(
                vaultState.managerAccruedFeeUsdE18(), 0,
                "INV-05: fees accrued without any successful deposit"
            );
        }
    }

    /// INV-FAC-001: Vault creation during cooldown after address book update must revert.
    function invariant_invFac001_cooldownBlocksCreation() public view {
        assertEq(
            actor.ghost_cooldownCreationSuccesses(), 0,
            "INV-FAC-001: vault created during address book cooldown"
        );
    }

    /// INV-FAC-002: Second vault clone state remains untouched when only the first vault is operated.
    ///              The actor only drives operations on vault 1. If vault 2 state changes, isolation is broken.
    function invariant_invFac002_cloneIsolation() public view {
        // Second vault has had no deposits, so its total deposited must be 0.
        assertEq(
            secondVaultState.totalDepositedUsdE18(), 0,
            "INV-FAC-002: second clone totalDepositedUsdE18 changed"
        );
        assertEq(
            secondVaultState.totalDepositedGmE18(), 0,
            "INV-FAC-002: second clone totalDepositedGmE18 changed"
        );
        // Second clone must be paired with a different VaultCore.
        assertTrue(
            address(secondVaultCore) != address(vaultCore),
            "INV-FAC-002: second clone shares VaultCore with first"
        );
        assertTrue(
            address(secondVaultState) != address(vaultState),
            "INV-FAC-002: second clone shares VaultState with first"
        );
    }

    /// @dev At least some operations must succeed — otherwise fuzzer is just spinning on reverts
    function invariant_atLeastSomeSuccesses() public view {
        if (actor.ghost_depositAttempts() + actor.ghost_feeAccrualAttempts() > 10) {
            assertTrue(
                actor.ghost_depositSuccesses() + actor.ghost_feeAccrualSuccesses() > 0,
                "fuzzer achieved zero successes - invariant test is meaningless"
            );
        }
    }

    /// Summary: log ghost counters for debugging.
    function invariant_summary() public view {
        assertTrue(
            actor.ghost_depositAttempts() + actor.ghost_feeAccrualAttempts()
                + actor.ghost_cooldownCreationAttempts() >= 0
        );
    }
}

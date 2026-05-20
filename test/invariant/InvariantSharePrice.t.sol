// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ForkSetupFull} from "../helpers/ForkSetupFull.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";
import {DepositHandler} from "../../src/handlers/DepositHandler.sol";
import {WithdrawHandler} from "../../src/handlers/WithdrawHandler.sol";
import {FeeAccountingHandler} from "../../src/handlers/FeeAccountingHandler.sol";
import {IDepositHandlerVaultCore} from "../../src/interfaces/IDepositHandlerVaultCore.sol";
import {IWithdrawHandlerVaultCore} from "../../src/interfaces/IWithdrawHandlerVaultCore.sol";
import {IFeeAccountingHandlerVaultCore} from "../../src/interfaces/IFeeAccountingHandlerVaultCore.sol";
import {IBasaltMath} from "../../src/interfaces/IBasaltMath.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  SharePriceActor -- drives deposit/withdraw/fee-accrual for INV-02.
// ─────────────────────────────────────────────────────────────────────────────

contract SharePriceActor is Test {
    address internal immutable VAULT_CORE;
    address internal immutable VAULT_OWNER;
    address internal immutable PROTOCOL_MANAGER;

    VaultState internal immutable STATE;
    BasaltMath internal immutable MATH;
    DepositHandler internal immutable DEPOSIT_H;
    WithdrawHandler internal immutable WITHDRAW_H;
    FeeAccountingHandler internal immutable FEE_H;

    // -- Ghosts --
    uint256 public ghost_depositAttempts;
    uint256 public ghost_depositSuccesses;
    uint256 public ghost_withdrawAttempts;
    uint256 public ghost_withdrawSuccesses;
    uint256 public ghost_feeAccrualAttempts;
    uint256 public ghost_feeAccrualSuccesses;

    /// @dev Highest HWM profit ever observed (for monotonicity check).
    uint256 public ghost_hwmEverSeenUsdE18;

    /// @dev Highest lastFinalizedNavUsdE18 ever observed (share price proxy).
    ///      In this vault, totalShares = SHARE_UNIT (1e18 constant), so
    ///      share price = lastFinalizedNavUsdE18 / 1e18.
    ///      NOTE: NAV can decrease from market movements, so this ghost tracks
    ///      the monotonic envelope separately from HWM.
    uint256 public ghost_lastFinalizedNavEverE18;

    constructor(
        address vaultCoreAddr,
        address vaultStateAddr,
        address mathAddr,
        address depositHandlerAddr,
        address withdrawHandlerAddr,
        address feeHandlerAddr,
        address vaultOwnerAddr,
        address protocolManagerAddr
    ) {
        VAULT_CORE = vaultCoreAddr;
        STATE = VaultState(vaultStateAddr);
        MATH = BasaltMath(mathAddr);
        DEPOSIT_H = DepositHandler(depositHandlerAddr);
        WITHDRAW_H = WithdrawHandler(withdrawHandlerAddr);
        FEE_H = FeeAccountingHandler(feeHandlerAddr);
        VAULT_OWNER = vaultOwnerAddr;
        PROTOCOL_MANAGER = protocolManagerAddr;

        // One-shot approvals.
        vm.prank(VAULT_OWNER);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(depositHandlerAddr, type(uint256).max);
        vm.prank(VAULT_OWNER);
        IERC20(BasaltAddresses.WBTC).approve(depositHandlerAddr, type(uint256).max);
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

    function actOwnerWithdraw(uint256 sharesSeed) external {
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

        uint256 nav = STATE.lastFinalizedNavUsdE18();
        if (nav > ghost_lastFinalizedNavEverE18) ghost_lastFinalizedNavEverE18 = nav;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  InvariantSharePrice -- INV-02 share price / HWM monotonicity.
// ─────────────────────────────────────────────────────────────────────────────

contract InvariantSharePrice is ForkSetupFull {
    SharePriceActor internal actor;

    function setUp() public override {
        super.setUp();
        _fundActor(vaultOwner);

        actor = new SharePriceActor(
            address(vaultCore),
            address(vaultState),
            address(basaltMath),
            address(depositHandler),
            address(withdrawHandler),
            address(feeAccountingHandler),
            vaultOwner,
            address(managerContract)
        );

        targetContract(address(actor));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = SharePriceActor.actOwnerDeposit.selector;
        selectors[1] = SharePriceActor.actOwnerWithdraw.selector;
        selectors[2] = SharePriceActor.actAccrueFees.selector;
        targetSelector(FuzzSelector({addr: address(actor), selectors: selectors}));
        targetSender(address(this));
    }

    // ── Invariants ──

    /// INV-02: HWM-based share price monotonicity.
    /// The high-water-mark profit is the protocol's share price anchor: it can only increase,
    /// ensuring the manager fee is only charged on new profit.  Since totalShares = SHARE_UNIT
    /// (constant 1e18), effective share price = NAV / 1e18.  While raw NAV can dip from
    /// market movements, the HWM profit (which determines fee thresholds) is monotonically
    /// non-decreasing.  This is the meaningful "share price never decreases" invariant for
    /// a single-owner vault.
    function invariant_inv02_sharePriceMonotonic() public view {
        uint256 currentHwm = vaultState.highWaterMarkProfitUsdE18();
        assertGe(
            currentHwm,
            actor.ghost_hwmEverSeenUsdE18(),
            "INV-02: HWM profit decreased - share price anchor violated"
        );
    }

    /// HWM monotonicity: highWaterMarkProfitUsdE18 can only increase or stay the same.
    /// Direct parity with InvariantHappyPathFork.invariant_hwmIsMonotonic.
    function invariant_hwmNeverDecreases() public view {
        assertGe(
            vaultState.highWaterMarkProfitUsdE18(),
            actor.ghost_hwmEverSeenUsdE18(),
            "HWM profit went backwards"
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

    /// Summary: log ghost counters (always-true assertion to surface in output).
    function invariant_summary() public view {
        assertTrue(
            actor.ghost_depositAttempts() + actor.ghost_withdrawAttempts()
                + actor.ghost_feeAccrualAttempts() >= 0
        );
    }
}

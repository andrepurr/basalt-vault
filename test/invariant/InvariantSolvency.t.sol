// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ForkSetupFull} from "../helpers/ForkSetupFull.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {DepositHandler} from "../../src/handlers/DepositHandler.sol";
import {WithdrawHandler} from "../../src/handlers/WithdrawHandler.sol";
import {ManagerHandler} from "../../src/handlers/ManagerHandler.sol";
import {FeeAccountingHandler} from "../../src/handlers/FeeAccountingHandler.sol";
import {IDepositHandlerVaultCore} from "../../src/interfaces/IDepositHandlerVaultCore.sol";
import {IWithdrawHandlerVaultCore} from "../../src/interfaces/IWithdrawHandlerVaultCore.sol";
import {IManagerHandlerVaultCore} from "../../src/interfaces/IManagerHandlerVaultCore.sol";
import {IFeeAccountingHandlerVaultCore} from "../../src/interfaces/IFeeAccountingHandlerVaultCore.sol";
import {IBasaltMath} from "../../src/interfaces/IBasaltMath.sol";
import {IChainlinkAggregator} from "../../src/interfaces/IChainlinkAggregator.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  SolvencyActor -- drives deposit/withdraw/finalize sequences for INV-01.
// ─────────────────────────────────────────────────────────────────────────────

contract SolvencyActor is Test {
    address internal immutable VAULT_CORE;
    address internal immutable VAULT_OWNER;
    address internal immutable PROTOCOL_MANAGER;

    VaultState internal immutable STATE;
    BasaltMath internal immutable MATH;
    DepositHandler internal immutable DEPOSIT_H;
    WithdrawHandler internal immutable WITHDRAW_H;
    ManagerHandler internal immutable MANAGER_H;
    FeeAccountingHandler internal immutable FEE_H;

    // -- Ghosts --
    uint256 public ghost_depositAttempts;
    uint256 public ghost_depositSuccesses;
    uint256 public ghost_withdrawAttempts;
    uint256 public ghost_withdrawSuccesses;
    uint256 public ghost_finalizeDepositAttempts;
    uint256 public ghost_finalizeDepositSuccesses;
    uint256 public ghost_finalizeWithdrawAttempts;
    uint256 public ghost_finalizeWithdrawSuccesses;

    uint256 public ghost_maxDepositedUsdEverE18;
    uint256 public ghost_maxWithdrawnUsdEverE18;

    constructor(
        address vaultCoreAddr,
        address vaultStateAddr,
        address mathAddr,
        address depositHandlerAddr,
        address withdrawHandlerAddr,
        address managerHandlerAddr,
        address feeHandlerAddr,
        address vaultOwnerAddr,
        address protocolManagerAddr
    ) {
        VAULT_CORE = vaultCoreAddr;
        STATE = VaultState(vaultStateAddr);
        MATH = BasaltMath(mathAddr);
        DEPOSIT_H = DepositHandler(depositHandlerAddr);
        WITHDRAW_H = WithdrawHandler(withdrawHandlerAddr);
        MANAGER_H = ManagerHandler(managerHandlerAddr);
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

    function actFinalizeWithdraw(uint256) external {
        if (STATE.withdrawState() != VaultState.State.PENDING) return;
        _rollPastCooldown();
        vm.warp(block.timestamp + 1800);

        ghost_finalizeWithdrawAttempts += 1;
        vm.startPrank(VAULT_OWNER);
        try WITHDRAW_H.finalizeWithdraw(IWithdrawHandlerVaultCore(VAULT_CORE)) {
            ghost_finalizeWithdrawSuccesses += 1;
            _trackAccumulators();
        } catch {}
        vm.stopPrank();
    }

    // -- Internal --

    function _rollPastCooldown() internal {
        uint256 end = STATE.globalActionCooldownEndBlock();
        if (block.number <= end) {
            vm.roll(end + 1);
        }
    }

    function _trackAccumulators() internal {
        uint256 dep = STATE.totalDepositedUsdE18();
        if (dep > ghost_maxDepositedUsdEverE18) ghost_maxDepositedUsdEverE18 = dep;

        uint256 wd = STATE.totalWithdrawnUsdE18();
        if (wd > ghost_maxWithdrawnUsdEverE18) ghost_maxWithdrawnUsdEverE18 = wd;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  InvariantSolvency -- INV-01 solvency, INV-FS-001 reward conservation,
//  INV-ORACLE-001 Chainlink freshness, INV-ORACLE-002 GMX pool key validity.
// ─────────────────────────────────────────────────────────────────────────────

interface IGmxDataStoreView {
    function getUint(bytes32 key) external view returns (uint256);
}

contract InvariantSolvency is ForkSetupFull {
    SolvencyActor internal actor;

    function setUp() public override {
        super.setUp();
        _fundActor(vaultOwner);

        actor = new SolvencyActor(
            address(vaultCore),
            address(vaultState),
            address(basaltMath),
            address(depositHandler),
            address(withdrawHandler),
            address(managerHandler),
            address(feeAccountingHandler),
            vaultOwner,
            address(managerContract)
        );

        targetContract(address(actor));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = SolvencyActor.actOwnerDeposit.selector;
        selectors[1] = SolvencyActor.actOwnerWithdraw.selector;
        selectors[2] = SolvencyActor.actFinalizeDeposit.selector;
        selectors[3] = SolvencyActor.actFinalizeWithdraw.selector;
        targetSelector(FuzzSelector({addr: address(actor), selectors: selectors}));
        targetSender(address(this));
    }

    // ── Invariants ──

    /// INV-01: Solvency — after any finalized deposit the vault's NAV must cover its
    /// accrued fee obligations, totalDeposited must be monotonically non-decreasing,
    /// and totalWithdrawn must be monotonically non-decreasing.
    function invariant_inv01_solvency() public view {
        uint256 lastNav = vaultState.lastFinalizedNavUsdE18();
        uint256 accruedFee = vaultState.managerAccruedFeeUsdE18();
        uint256 totalDeposited = vaultState.totalDepositedUsdE18();
        uint256 totalWithdrawn = vaultState.totalWithdrawnUsdE18();

        // Real solvency: NAV must cover the manager's accrued fee claim.
        // If NAV < accruedFee, the vault is insolvent (cannot pay out owed fees).
        if (actor.ghost_finalizeDepositSuccesses() > 0) {
            assertGe(
                lastNav,
                accruedFee,
                "INV-01: NAV < accrued manager fee -- vault insolvent"
            );
        }

        // totalDeposited monotonically non-decreasing.
        assertGe(
            totalDeposited,
            actor.ghost_maxDepositedUsdEverE18(),
            "INV-01: totalDeposited went backwards"
        );

        // totalWithdrawn monotonically non-decreasing.
        assertGe(
            totalWithdrawn,
            actor.ghost_maxWithdrawnUsdEverE18(),
            "INV-01: totalWithdrawn went backwards"
        );
    }

    /// INV-FS-001: FeeSplitter reward conservation -- for each tracked token, the sum of
    /// all releasable amounts across known holders must not exceed the splitter's actual
    /// token balance. If releasable > balance, the splitter has over-promised and cannot
    /// pay out all claims (real accounting bug).
    function invariant_invFs001_rewardsConserved() public view {
        // In this test setup, factoryOwner holds all BFS shares (sole fee recipient).
        uint256 len = feeSplitter.trackedTokensLength();
        for (uint256 i; i < len; ++i) {
            IERC20 token = feeSplitter.trackedTokenAt(i);
            uint256 balance = token.balanceOf(address(feeSplitter));
            uint256 totalReleasable = feeSplitter.releasable(token, factoryOwner);
            // Real conservation: the splitter must hold enough tokens to cover
            // all outstanding releasable claims.
            assertGe(
                balance,
                totalReleasable,
                "INV-FS-001: FeeSplitter balance < total releasable -- over-promised"
            );
        }
    }

    /// INV-ORACLE-001: Chainlink WBTC/USD and USDC/USD feeds return fresh, positive prices.
    function invariant_invOracle001_chainlinkFreshAndPositive() public view {
        // WBTC/USD
        (, int256 wbtcPrice,, uint256 wbtcUpdatedAt,) =
            IChainlinkAggregator(BasaltAddresses.CL_WBTC_USD).latestRoundData();
        assertGt(wbtcPrice, 0, "INV-ORACLE-001: WBTC price non-positive");
        assertLe(
            block.timestamp - wbtcUpdatedAt,
            BasaltConstants.ORACLE_WBTC_MAX_AGE,
            "INV-ORACLE-001: WBTC price stale"
        );

        // USDC/USD
        (, int256 usdcPrice,, uint256 usdcUpdatedAt,) =
            IChainlinkAggregator(BasaltAddresses.CL_USDC_USD).latestRoundData();
        assertGt(usdcPrice, 0, "INV-ORACLE-001: USDC price non-positive");
        assertLe(
            block.timestamp - usdcUpdatedAt,
            BasaltConstants.ORACLE_USDC_MAX_AGE,
            "INV-ORACLE-001: USDC price stale"
        );
    }

    /// INV-ORACLE-002: GMX DataStore pool amounts for the configured GM market are non-zero.
    function invariant_invOracle002_gmxPoolKeysNonZero() public view {
        IGmxDataStoreView ds = IGmxDataStoreView(BasaltAddresses.GMX_DATA_STORE);

        // WBTC pool amount for GM market.
        bytes32 wbtcPoolKey = keccak256(
            abi.encode(BasaltConstants.GMX_KEY_POOL_AMOUNT, BasaltAddresses.GM_MARKET_TOKEN, BasaltAddresses.WBTC)
        );
        uint256 wbtcPoolAmount = ds.getUint(wbtcPoolKey);
        assertGt(wbtcPoolAmount, 0, "INV-ORACLE-002: WBTC pool amount is zero");

        // USDC pool amount for GM market.
        bytes32 usdcPoolKey = keccak256(
            abi.encode(BasaltConstants.GMX_KEY_POOL_AMOUNT, BasaltAddresses.GM_MARKET_TOKEN, BasaltAddresses.USDC)
        );
        uint256 usdcPoolAmount = ds.getUint(usdcPoolKey);
        assertGt(usdcPoolAmount, 0, "INV-ORACLE-002: USDC pool amount is zero");
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
                + actor.ghost_finalizeDepositAttempts() + actor.ghost_finalizeWithdrawAttempts() >= 0
        );
    }
}

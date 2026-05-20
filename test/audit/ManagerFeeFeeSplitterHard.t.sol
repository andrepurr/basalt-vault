// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {NotAuthorisedToNotify, NoPaymentDue} from "../../src/core/feeSplitterLibraries/FeeSplitterTypes.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";

/// @dev Controls `VaultState` fee fields as the registered `vaultCoreClone`.
contract VaultStateFeeTestDouble {
    VaultState public immutable S;

    constructor(VaultState s) {
        S = s;
    }

    function setFeeAccounting(uint256 hwm, uint256 accrued) external {
        S.setFeeAccounting(hwm, accrued);
    }

    function subAccrued(uint256 withdrawnFeeUsdE18) external {
        S.subAccruedManagerFeeUsdE18(withdrawnFeeUsdE18);
    }
}

/// @title ManagerFeeFeeSplitterHard
/// @notice Adversarial / property tests for performance-fee math, VaultState accrual debit, FeeSplitter
///         accounting, and ManagerContract fee hub — no fork.
contract ManagerFeeFeeSplitterHard is Test {
    BasaltMath internal m;
    VaultState internal v;
    VaultStateFeeTestDouble internal vc;

    function setUp() public {
        m = new BasaltMath();
        v = new VaultState();
        // Constructor sets vaultCoreClone = DISABLED_IMPL_SENTINEL to block impl init.
        // Clear slot 0 (vaultCoreClone) so initialize() can proceed in tests.
        vm.store(address(v), bytes32(0), bytes32(0));
        vc = new VaultStateFeeTestDouble(v);
        v.initialize(address(vc), address(0));
    }

    //  BasaltMath — HWM & performance fee (look for overflow / wrong floor)

    function testFuzz_perfFee_leqDelta(uint256 profit, uint256 prevHwm, uint256 feeBps) public view {
        feeBps = bound(feeBps, 0, BasaltConstants.BPS);
        prevHwm = bound(prevHwm, 0, 1_000_000_000e18);
        profit = bound(profit, 0, 1_000_000_000e18);
        (uint256 delta, uint256 fee) = m.calcPerformanceFeeByHwmProfit(profit, prevHwm, feeBps);
        if (profit <= prevHwm) {
            assertEq(delta, 0);
            assertEq(fee, 0);
        } else {
            assertEq(delta, profit - prevHwm);
            assertLe(fee, delta);
            assertEq(fee, (delta * feeBps) / BasaltConstants.BPS);
        }
    }

    function testFuzz_hwm_monotone(uint256 profit, uint256 prevHwm) public view {
        profit = bound(profit, 0, 1_000_000_000e18);
        prevHwm = bound(prevHwm, 0, 1_000_000_000e18);
        uint256 next = m.calcNextHighWaterMarkProfit(profit, prevHwm);
        assertGe(next, prevHwm);
        assertGe(next, profit);
        assertEq(next, profit > prevHwm ? profit : prevHwm);
    }

    function testFuzz_accrue_then_withdraw_saturating(uint256 prev, uint256 add, uint256 sub) public view {
        prev = bound(prev, 0, 1_000_000_000e18);
        add = bound(add, 0, 1_000_000_000e18);
        sub = bound(sub, 0, 2_000_000_000e18);
        uint256 afterAdd = m.calcNextAccruedManagerFee(prev, add);
        assertEq(afterAdd, prev + add);
        uint256 afterSub = m.calcNextAccruedManagerFeeAfterWithdraw(afterAdd, sub);
        if (afterAdd > sub) {
            assertEq(afterSub, afterAdd - sub);
        } else {
            assertEq(afterSub, 0);
        }
    }

    function test_accrueWithdraw_matches_VaultState_semantics() public {
        uint256 prev = 1000e18;
        uint256 add = 333e18;
        uint256 sub = 444e18;
        assertEq(m.calcNextAccruedManagerFee(prev, add), prev + add);
        uint256 x = prev + add;
        uint256 y = m.calcNextAccruedManagerFeeAfterWithdraw(x, sub);
        assertEq(y, x > sub ? x - sub : 0);
    }

    //  VaultState — mirrors `subAccruedManagerFeeUsdE18` / `setFeeAccounting`

    function testFuzz_vaultState_sub_saturates(uint256 start, uint256 w) public {
        start = bound(start, 0, type(uint128).max);
        w = bound(w, 0, type(uint128).max);
        vc.setFeeAccounting(0, start);
        assertEq(v.managerAccruedFeeUsdE18(), start, "accrued set correctly before sub");
        vc.subAccrued(w);
        uint256 got = v.managerAccruedFeeUsdE18();
        uint256 expect = start > w ? start - w : 0;
        assertEq(got, expect, "sub saturates at zero");
    }

    function test_vaultState_hwm_roundTrip() public {
        vc.setFeeAccounting(777e18, 42e18);
        assertEq(v.highWaterMarkProfitUsdE18(), 777e18);
        assertEq(v.managerAccruedFeeUsdE18(), 42e18);
    }

    //  FeeSplitter + ManagerContract — conservation & access

    function _deployHub() internal returns (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) {
        address me = address(this);
        token = new ERC20Mock();
        IERC20[] memory t = new IERC20[](1);
        t[0] = IERC20(address(token));
        splitter = new FeeSplitter(me, t);
        mgr = new ManagerContract(address(splitter));
        // Auto-wire was removed from ManagerContract.constructor; deployer (initialOwner) binds explicitly.
        splitter.setManagerContract(address(mgr));
        assertEq(address(mgr.feeSplitter()), address(splitter));
        assertEq(splitter.managerContract(), address(mgr));
    }

    function test_feeSplitter_notifyThenRelease_fullConservation() public {
        (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) = _deployHub();
        uint256 amount = 1_000_000e18;
        token.mint(address(splitter), amount);
        vm.prank(address(mgr));
        splitter.notifyReward(IERC20(address(token)));

        address me = address(this);
        uint256 rel = splitter.releasable(IERC20(address(token)), me);
        assertGt(rel, 0);
        splitter.release(IERC20(address(token)), me);
        assertEq(token.balanceOf(me), amount);
        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(splitter.totalReleasedByToken(IERC20(address(token))), amount);
    }

    function test_feeSplitter_proRata_threeHolders() public {
        (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) = _deployHub();
        address me = address(this);
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 u = splitter.TOTAL_SHARES();
        // 50% owner, 25% alice, 25% bob
        splitter.transfer(alice, u / 4);
        splitter.transfer(bob, u / 4);

        uint256 reward = 10_000e18;
        token.mint(address(splitter), reward);
        vm.prank(address(mgr));
        splitter.notifyReward(IERC20(address(token)));

        uint256 r0 = splitter.releasable(IERC20(address(token)), me);
        uint256 rA = splitter.releasable(IERC20(address(token)), alice);
        uint256 rB = splitter.releasable(IERC20(address(token)), bob);
        assertLe(r0 + rA + rB, reward, "releasable overcounts");
        assertGe(r0 + rA + rB, reward - 3, "releasable dust <= 2 wei across 3 holders");
        // Full release: all funds leave splitter
        splitter.release(IERC20(address(token)), me);
        splitter.release(IERC20(address(token)), alice);
        splitter.release(IERC20(address(token)), bob);
        assertEq(token.balanceOf(me) + token.balanceOf(alice) + token.balanceOf(bob), reward);
    }

    function test_feeSplitter_transfer_doesNotStealPastRewards() public {
        (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) = _deployHub();
        address me = address(this);
        address alice = makeAddr("alice");
        token.mint(address(splitter), 100e18);
        vm.prank(address(mgr));
        splitter.notifyReward(IERC20(address(token)));
        uint256 owedBefore = splitter.releasable(IERC20(address(token)), me);

        splitter.transfer(alice, splitter.TOTAL_SHARES() / 2);
        uint256 owedOwnerAfter = splitter.releasable(IERC20(address(token)), me);
        uint256 owedAlice = splitter.releasable(IERC20(address(token)), alice);
        assertEq(owedAlice, 0, "alice joined after notify - no past rewards");
        assertGe(owedOwnerAfter, owedBefore, "owner keeps full pre-transfer claim");
    }

    function test_manager_collectFees_sweepsToSplitterAndNotifies() public {
        (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) = _deployHub();
        uint256 onManager = 5000e18;
        token.mint(address(mgr), onManager);
        mgr.collectFees(_arr1(IERC20(address(token))));
        assertEq(token.balanceOf(address(mgr)), 0);
        assertEq(token.balanceOf(address(splitter)), onManager);
    }

    function test_notifyReward_rejectsStrangerWithoutShares() public {
        (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) = _deployHub();
        address rando = makeAddr("rando");
        token.mint(address(splitter), 1e18);
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorisedToNotify.selector, rando));
        splitter.notifyReward(IERC20(address(token)));
        // Manager can notify — verify reward is distributed
        vm.prank(address(mgr));
        splitter.notifyReward(IERC20(address(token)));
        assertGt(splitter.releasable(IERC20(address(token)), address(this)), 0, "reward distributed after manager notify");
    }

    function test_release_revertsWhenNothingDue() public {
        (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) = _deployHub();
        address me = address(this);
        token.mint(address(splitter), 1e18);
        vm.prank(address(mgr));
        splitter.notifyReward(IERC20(address(token)));
        splitter.release(IERC20(address(token)), me);
        assertEq(token.balanceOf(me), 1e18, "first release pays out full amount");
        // Second release with nothing owed must revert
        vm.expectRevert(abi.encodeWithSelector(NoPaymentDue.selector, me, IERC20(address(token))));
        splitter.release(IERC20(address(token)), me);
    }

    function testFuzz_profit_nonNegative_afterWithdrawFuzz(uint256 nav, uint256 dep, uint256 wd) public view {
        nav = bound(nav, 0, 1_000_000_000e18);
        dep = bound(dep, 0, 1_000_000_000e18);
        wd = bound(wd, 0, 1_000_000_000e18);
        uint256 p = m.calcProfitUsdE18(nav, dep, wd);
        uint256 gross = nav + wd;
        if (gross > dep) {
            assertEq(p, gross - dep);
        } else {
            assertEq(p, 0);
        }
    }

    function _arr1(IERC20 t) private pure returns (IERC20[] memory a) {
        a = new IERC20[](1);
        a[0] = t;
    }
}

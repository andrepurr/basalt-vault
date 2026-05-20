// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";

/// @title NavWithdrawFuzzHandler
/// @notice Records one `(nav, accrued, totalShares, ownerEligible, managerMax)` snapshot per `touch` (invariant depth step).
contract NavWithdrawFuzzHandler {
    BasaltMath public immutable basalt = new BasaltMath();

    uint256 public n;
    uint256 public a;
    uint256 public t;
    uint256 public o;
    uint256 public m;
    /// @dev `totalShares - ownerEligible - managerMax` (share-unit dust from floor/mulDiv).
    uint256 public lastShareDust;
    /// @dev Running max of `lastShareDust` (for introspection, not asserted to 0).
    uint256 public maxShareDustEver;

    function touch(uint256 nav, uint256 acc, uint256 total) external {
        nav = _bound(nav, 0, 1e28);
        acc = acc % (nav + 1);
        total = _bound(total, 1, 1e25);

        n = nav;
        a = acc;
        t = total;
        o = basalt.calcOwnerEligibleWithdrawShares(nav, acc, total);
        m = basalt.calcManagerMaxFeeWithdrawShares(nav, acc, total);
        lastShareDust = total - o - m;
        if (lastShareDust > maxShareDustEver) maxShareDustEver = lastShareDust;
    }

    function _bound(uint256 x, uint256 min_, uint256 max_) internal pure returns (uint256) {
        if (min_ > max_) (min_, max_) = (max_, min_);
        if (x < min_) return min_;
        if (x > max_) return max_;
        return x;
    }
}

/// @title NavWithdrawConservation
/// @dev Off-fork invariants: economic NAV in E18 is an exact sum of owner slice + manager accrued slice;
///      share *caps* are conservative (`owner + managerMax <= total`) — mulDiv can leave unallocated share units.
///      See `test_shareDust_mayExceedOneWei` for a small counterexample.
contract NavWithdrawConservation is Test {
    NavWithdrawFuzzHandler internal h;

    function setUp() public {
        h = new NavWithdrawFuzzHandler();
        targetContract(address(h));
        bytes4[] memory s = new bytes4[](1);
        s[0] = NavWithdrawFuzzHandler.touch.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: s}));
        targetSender(address(this));
    }

    // ── INV-9: Economic conservation — the USD value of owner-eligible shares plus the USD
    //    value of manager-fee shares must not exceed NAV. No value created from thin air. ──
    function invariant_inv9_economicConservation() public view {
        uint256 nav = h.n();
        uint256 acc = h.a();
        uint256 total = h.t();
        uint256 ownerShares = h.o();
        uint256 managerShares = h.m();

        // accrued must never exceed NAV (precondition from calcOwnerEligibleWithdrawShares).
        assertLe(acc, nav, "accrued > NAV");

        // Economic conservation: convert share caps back to USD value.
        // ownerUsd = ownerShares * nav / totalShares, managerUsd = managerShares * nav / totalShares.
        // ownerUsd + managerUsd <= nav (no value created from thin air).
        if (total > 0 && nav > 0) {
            // Use mulDiv to match the same precision as the contract.
            uint256 ownerUsd = (ownerShares * nav) / total;
            uint256 managerUsd = (managerShares * nav) / total;
            assertLe(
                ownerUsd + managerUsd,
                nav,
                "INV-9: owner USD + manager USD > NAV -- value created from thin air"
            );
        }
    }

    // ── INV-10: share *caps* never allocate more than `totalShares`; owner + managerMax <= T. ──
    function invariant_inv10_ownerPlusManagerMaxSharesLteTotal() public view {
        assertLe(h.o() + h.m(), h.t(), "INV-10: owner cap + manager cap > total shares");
    }

    /// @notice Fuzz: owner + manager USD value never exceeds NAV for any inputs.
    function testFuzz_inv9_economicConservation(uint256 nav, uint256 acc, uint256 tot) public {
        nav = bound(nav, 0, 1e28);
        acc = acc % (nav + 1);
        tot = bound(tot, 1, 1e25);
        BasaltMath b = new BasaltMath();
        uint256 o = b.calcOwnerEligibleWithdrawShares(nav, acc, tot);
        uint256 m = b.calcManagerMaxFeeWithdrawShares(nav, acc, tot);
        if (tot > 0 && nav > 0) {
            uint256 ownerUsd = (o * nav) / tot;
            uint256 managerUsd = (m * nav) / tot;
            assertLe(ownerUsd + managerUsd, nav);
        }
    }

    /// @notice `mulDiv` on shares can leave dust; T=3,N=5,a=2 → owner+manager < T.
    function test_shareDust_mayExceedOneWei() public {
        BasaltMath b = new BasaltMath();
        uint256 nav = 5;
        uint256 acc = 2;
        uint256 tot = 3;
        uint256 o = b.calcOwnerEligibleWithdrawShares(nav, acc, tot);
        uint256 m = b.calcManagerMaxFeeWithdrawShares(nav, acc, tot);
        assertEq(o, 1);
        assertEq(m, 1);
        assertEq(tot - o - m, 1);
    }

    function testFuzz_inv10_lte(uint256 nav, uint256 acc, uint256 tot) public {
        nav = bound(nav, 0, 1_000_000_000e18);
        acc = acc % (nav + 1);
        tot = bound(tot, 1, 1_000_000_000e18);
        BasaltMath b = new BasaltMath();
        uint256 o = b.calcOwnerEligibleWithdrawShares(nav, acc, tot);
        uint256 m = b.calcManagerMaxFeeWithdrawShares(nav, acc, tot);
        assertLe(o + m, tot);
    }
}

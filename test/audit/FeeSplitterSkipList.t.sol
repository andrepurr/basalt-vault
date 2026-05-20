// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {TokenIsSkipped, NotManagerContract} from "../../src/core/feeSplitterLibraries/FeeSplitterTypes.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";

contract BrokenBalanceERC20 is ERC20Mock {
    bool public broken;

    function setBroken(bool v) external {
        broken = v;
    }

    function balanceOf(address a) public view override returns (uint256) {
        if (broken) revert("balanceOf reverts");
        return super.balanceOf(a);
    }
}

contract FeeSplitterSkipListTest is Test {
    address internal me;
    address internal alice = makeAddr("alice");
    FeeSplitter internal splitter;
    ManagerContract internal mgr;
    ERC20Mock internal goodToken;
    BrokenBalanceERC20 internal badToken;

    function setUp() public {
        me = address(this);
        goodToken = new ERC20Mock();
        badToken = new BrokenBalanceERC20();

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(goodToken));
        tokens[1] = IERC20(address(badToken));

        splitter = new FeeSplitter(me, tokens);
        mgr = new ManagerContract(address(splitter));
        splitter.setManagerContract(address(mgr));
    }

    function test_brokenToken_bricksTransfer_withoutSkip() public {
        badToken.setBroken(true);
        // Pre-condition: badToken is NOT skipped, so _update will call balanceOf and revert
        assertEq(splitter.isSkipped(IERC20(address(badToken))), false, "precondition: badToken not skipped");
        uint256 balBefore = splitter.balanceOf(me);
        vm.expectRevert();
        splitter.transfer(alice, 100);
        // State unchanged after revert
        assertEq(splitter.balanceOf(me), balBefore, "balance unchanged after revert");
    }

    function test_setTokenSkipped_unbricksTransfer() public {
        badToken.setBroken(true);

        mgr.setFeeSplitterTokenSkipped(IERC20(address(badToken)), true);
        assertEq(splitter.isSkipped(IERC20(address(badToken))), true, "skipped flag set");

        splitter.transfer(alice, 100);
        assertEq(splitter.balanceOf(alice), 100, "transfer succeeded after skip");
    }

    function test_skipped_doesNotBlockGoodTokenSettlement() public {
        badToken.setBroken(true);
        mgr.setFeeSplitterTokenSkipped(IERC20(address(badToken)), true);

        goodToken.mint(address(splitter), 1_000e18);
        splitter.notifyReward(IERC20(address(goodToken)));

        splitter.transfer(alice, splitter.TOTAL_SHARES() / 4);

        uint256 myReleasable = splitter.releasable(IERC20(address(goodToken)), me);
        assertEq(myReleasable, 1_000e18, "good token still settles for old holder");

        // Alice got 25% shares but joined after reward — should have 0 releasable from pre-transfer reward
        uint256 aliceReleasable = splitter.releasable(IERC20(address(goodToken)), alice);
        assertEq(aliceReleasable, 0, "alice gets 0 from pre-transfer reward");
    }

    function test_release_onSkippedToken_reverts() public {
        badToken.setBroken(true);
        mgr.setFeeSplitterTokenSkipped(IERC20(address(badToken)), true);

        // Pre-condition: token is indeed skipped
        assertEq(splitter.isSkipped(IERC20(address(badToken))), true, "precondition: badToken is skipped");
        uint256 releasedBefore = splitter.totalReleasedByToken(IERC20(address(badToken)));

        vm.expectRevert(abi.encodeWithSelector(TokenIsSkipped.selector, IERC20(address(badToken))));
        splitter.release(IERC20(address(badToken)), me);

        // totalReleased unchanged after revert
        assertEq(splitter.totalReleasedByToken(IERC20(address(badToken))), releasedBefore, "totalReleased unchanged");
    }

    function test_notifyReward_onSkippedToken_reverts() public {
        mgr.setFeeSplitterTokenSkipped(IERC20(address(goodToken)), true);

        // Pre-condition: token is skipped
        assertEq(splitter.isSkipped(IERC20(address(goodToken))), true, "precondition: goodToken is skipped");

        vm.expectRevert(abi.encodeWithSelector(TokenIsSkipped.selector, IERC20(address(goodToken))));
        splitter.notifyReward(IERC20(address(goodToken)));
    }

    function test_releasable_onSkippedToken_returnsOnlyPending() public {
        goodToken.mint(address(splitter), 100e18);
        splitter.notifyReward(IERC20(address(goodToken)));

        mgr.setFeeSplitterTokenSkipped(IERC20(address(goodToken)), true);

        uint256 r = splitter.releasable(IERC20(address(goodToken)), me);
        assertEq(r, 0, "releasable returns only buffered pending; no fresh accrual on skipped token");
        // Token is confirmed skipped
        assertEq(splitter.isSkipped(IERC20(address(goodToken))), true, "token is indeed skipped");
    }

    function test_setTokenSkipped_asStranger_reverts() public {
        address stranger = makeAddr("stranger");
        // Pre-condition: badToken is not skipped
        assertEq(splitter.isSkipped(IERC20(address(badToken))), false, "precondition: badToken not skipped");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotManagerContract.selector, stranger));
        splitter.setTokenSkipped(IERC20(address(badToken)), true);

        // State unchanged: still not skipped
        assertEq(splitter.isSkipped(IERC20(address(badToken))), false, "badToken still not skipped after failed call");
    }

    function test_setFeeSplitterTokenSkipped_onMC_asStranger_reverts() public {
        address stranger = makeAddr("stranger");
        // Pre-condition: badToken not skipped
        assertEq(splitter.isSkipped(IERC20(address(badToken))), false, "precondition: not skipped");

        vm.prank(stranger);
        vm.expectRevert();
        mgr.setFeeSplitterTokenSkipped(IERC20(address(badToken)), true);

        // State unchanged
        assertEq(splitter.isSkipped(IERC20(address(badToken))), false, "still not skipped after unauthorized call");
    }

    function test_unskip_restoresBehavior() public {
        badToken.setBroken(true);
        mgr.setFeeSplitterTokenSkipped(IERC20(address(badToken)), true);
        splitter.transfer(alice, 100);

        badToken.setBroken(false);
        mgr.setFeeSplitterTokenSkipped(IERC20(address(badToken)), false);
        assertEq(splitter.isSkipped(IERC20(address(badToken))), false, "unskip flag");

        // Transfer succeeds now — verify share balances are correct after both transfers
        splitter.transfer(alice, 100);
        assertEq(splitter.balanceOf(alice), 200, "alice has 200 shares after two transfers");
        assertEq(splitter.balanceOf(me), splitter.TOTAL_SHARES() - 200, "me has remaining shares");
    }
}

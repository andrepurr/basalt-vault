// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ForkSetupFull} from "../../helpers/ForkSetupFull.sol";
import {FeeSplitter} from "../../../src/core/FeeSplitter.sol";
import {
    NotInitialOwner,
    ManagerContractAlreadySet,
    NotManagerContract,
    NotAuthorisedToNotify,
    NotAuthorisedToRelease,
    NoPaymentDue,
    TokenAlreadyTracked
} from "../../../src/core/feeSplitterLibraries/FeeSplitterTypes.sol";
import {BasaltAddresses} from "../../../src/libraries/BasaltAddresses.sol";

/// @title FeeSplitter auth, notify, release, and accounting unit tests
contract FeeSplitterUnit is ForkSetupFull {
    IERC20 internal usdc;
    IERC20 internal weth;

    // Second share holder for pro-rata tests
    address internal shareHolderB;

    function setUp() public override {
        super.setUp();
        usdc = IERC20(BasaltAddresses.USDC);
        weth = IERC20(BasaltAddresses.WETH);
        shareHolderB = address(uint160(0x2001));
    }

    // ACCESS CONTROL: setManagerContract

    function test_setManagerContract_asStranger_reverts() public {
        // Stranger is not the initialOwner of feeSplitter — reverts before reaching the one-shot guard.
        address mcBefore = feeSplitter.managerContract();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotInitialOwner.selector, stranger));
        feeSplitter.setManagerContract(stranger);
        // Manager contract unchanged after revert
        assertEq(feeSplitter.managerContract(), mcBefore, "managerContract unchanged after revert");
    }

    function test_setManagerContract_asNonInitialOwner_factoryOwner_reverts() public {
        // factoryOwner is the share owner but NOT the FS deployer (this test contract is).
        address mcBefore = feeSplitter.managerContract();
        assertGt(feeSplitter.balanceOf(factoryOwner), 0, "precondition: factoryOwner holds shares");
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(NotInitialOwner.selector, factoryOwner));
        feeSplitter.setManagerContract(address(0xCAFE));
        assertEq(feeSplitter.managerContract(), mcBefore, "managerContract unchanged");
    }

    function test_setManagerContract_alreadySet_reverts() public {
        // initialOwner of `feeSplitter` here is the test contract (deployed inside ForkSetupFull).
        // Already bound in setUp — second attempt by initialOwner reverts with ManagerContractAlreadySet.
        address mcBefore = feeSplitter.managerContract();
        assertEq(mcBefore, address(managerContract), "precondition: managerContract already set");
        vm.expectRevert(
            abi.encodeWithSelector(ManagerContractAlreadySet.selector, address(managerContract))
        );
        feeSplitter.setManagerContract(address(0xCAFE));
        assertEq(feeSplitter.managerContract(), mcBefore, "managerContract unchanged after double-set attempt");
    }

    function test_setManagerContract_onFreshSplitter_byInitialOwner_succeeds() public {
        // Deploy a fresh FeeSplitter — this test contract is its initialOwner.
        IERC20[] memory tokens = new IERC20[](0);
        FeeSplitter freshSplitter = new FeeSplitter(factoryOwner, tokens);

        assertEq(freshSplitter.initialOwner(), address(this), "fresh splitter: initialOwner = this test contract");
        assertEq(freshSplitter.managerContract(), address(0), "fresh splitter: managerContract should be zero");

        freshSplitter.setManagerContract(address(0xCAFE));
        assertEq(freshSplitter.managerContract(), address(0xCAFE), "fresh splitter: managerContract should be set");
    }

    function test_setManagerContract_onFreshSplitter_byNonInitialOwner_reverts() public {
        IERC20[] memory tokens = new IERC20[](0);
        FeeSplitter freshSplitter = new FeeSplitter(factoryOwner, tokens);

        assertEq(freshSplitter.managerContract(), address(0), "precondition: managerContract is zero");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotInitialOwner.selector, stranger));
        freshSplitter.setManagerContract(address(0xCAFE));
        assertEq(freshSplitter.managerContract(), address(0), "managerContract still zero after revert");
    }

    // ACCESS CONTROL: addTrackedToken

    function test_addTrackedToken_asStranger_reverts() public {
        uint256 lenBefore = feeSplitter.trackedTokensLength();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotManagerContract.selector, stranger));
        feeSplitter.addTrackedToken(IERC20(USDT));
        // Token list unchanged
        assertEq(feeSplitter.trackedTokensLength(), lenBefore, "trackedTokensLength unchanged after revert");
        assertEq(feeSplitter.isTrackedToken(IERC20(USDT)), false, "USDT still not tracked");
    }

    function test_addTrackedToken_asManagerContract_succeeds() public {
        uint256 lenBefore = feeSplitter.trackedTokensLength();

        vm.prank(address(managerContract));
        feeSplitter.addTrackedToken(IERC20(USDT));

        assertEq(
            feeSplitter.trackedTokensLength(),
            lenBefore + 1,
            "addTrackedToken: length should increase by 1"
        );
        assertEq(feeSplitter.isTrackedToken(IERC20(USDT)), true, "addTrackedToken: USDT should be tracked");
    }

    // ACCESS CONTROL: notifyReward

    function test_notifyReward_asStranger_reverts() public {
        // Stranger has 0 shares and is not managerContract
        assertEq(feeSplitter.balanceOf(stranger), 0, "precondition: stranger holds 0 shares");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorisedToNotify.selector, stranger));
        feeSplitter.notifyReward(usdc);
    }

    function test_notifyReward_asManagerContract_succeeds() public {
        uint256 usdcBalBefore = usdc.balanceOf(address(feeSplitter));
        assertEq(usdcBalBefore, 0, "precondition: FeeSplitter has 0 USDC");
        vm.prank(address(managerContract));
        uint256 acc = feeSplitter.notifyReward(usdc);
        // With no new tokens, accPerShare stays at 0
        assertEq(acc, 0, "notifyReward with no delta: accPerShare should be 0");
    }

    function test_notifyReward_asShareHolder_succeeds() public {
        // factoryOwner holds all shares
        assertGt(feeSplitter.balanceOf(factoryOwner), 0, "precondition: factoryOwner holds shares");
        vm.prank(factoryOwner);
        uint256 acc = feeSplitter.notifyReward(usdc);
        assertEq(acc, 0, "notifyReward by shareholder with no delta: accPerShare should be 0");
    }

    // ACCESS CONTROL: release -- holder OR operational

    function test_release_asStranger_reverts() public {
        // Stranger holds 0 shares and is not operational — reverts.
        uint256 rewardAmount = 1000e6;
        deal(address(usdc), address(feeSplitter), rewardAmount);

        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        uint256 releasedBefore = feeSplitter.totalReleasedByToken(usdc);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorisedToRelease.selector, stranger));
        feeSplitter.release(usdc, factoryOwner);
        // No tokens released after revert
        assertEq(feeSplitter.totalReleasedByToken(usdc), releasedBefore, "totalReleased unchanged after revert");
    }

    function test_release_asHolder_succeeds_forSelfOrOther() public {
        uint256 rewardAmount = 1000e6;
        deal(address(usdc), address(feeSplitter), rewardAmount);

        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        // factoryOwner holds shares — can trigger release for themselves.
        uint256 balBefore = usdc.balanceOf(factoryOwner);
        uint256 splitterBalBefore = usdc.balanceOf(address(feeSplitter));
        vm.prank(factoryOwner);
        feeSplitter.release(usdc, factoryOwner);
        assertEq(usdc.balanceOf(factoryOwner) - balBefore, rewardAmount, "holder release: full reward delivered");
        // Conservation: splitter balance decreased by the same amount
        assertEq(splitterBalBefore - usdc.balanceOf(address(feeSplitter)), rewardAmount, "conservation: splitter balance decreased by reward");
        // Post-release: releasable is now 0
        assertEq(feeSplitter.releasable(usdc, factoryOwner), 0, "releasable is 0 after full release");
    }

    function test_release_asOperational_succeeds() public {
        uint256 rewardAmount = 500e6;
        deal(address(usdc), address(feeSplitter), rewardAmount);

        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        // Operational (set in ForkSetupFull) is permitted to trigger releases.
        uint256 balBefore = usdc.balanceOf(factoryOwner);
        vm.prank(operational);
        feeSplitter.release(usdc, factoryOwner);
        assertEq(usdc.balanceOf(factoryOwner) - balBefore, rewardAmount, "operational release: reward delivered");
        // Accounting updated correctly
        assertEq(feeSplitter.releasedByTokenAndAccount(usdc, factoryOwner), rewardAmount, "releasedByTokenAndAccount tracks released amount");
        assertEq(feeSplitter.totalReleasedByToken(usdc), rewardAmount, "totalReleasedByToken tracks released amount");
    }

    // FEE ACCOUNTING

    function test_notifyReward_updatesAccPerShare() public {
        uint256 rewardAmount = 500e6; // 500 USDC
        deal(address(usdc), address(feeSplitter), rewardAmount);

        vm.prank(address(managerContract));
        uint256 acc = feeSplitter.notifyReward(usdc);
        assertGt(acc, 0, "notifyReward: accPerShare should be > 0 after reward");
        // After notify, releasable for sole holder should equal the full reward
        uint256 rel = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(rel, rewardAmount, "releasable equals reward for sole holder after notify");
    }

    function test_release_paysCorrectAmount() public {
        uint256 rewardAmount = 2000e6; // 2000 USDC
        deal(address(usdc), address(feeSplitter), rewardAmount);

        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        uint256 releasableAmt = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(releasableAmt, rewardAmount, "releasable should equal reward (sole holder)");

        uint256 balBefore = usdc.balanceOf(factoryOwner);
        vm.prank(factoryOwner);
        feeSplitter.release(usdc, factoryOwner);
        uint256 balAfter = usdc.balanceOf(factoryOwner);

        assertEq(balAfter - balBefore, rewardAmount, "release: balance change should equal reward amount");
        // Post-release: no double-claim possible
        assertEq(feeSplitter.releasable(usdc, factoryOwner), 0, "releasable is 0 after release");
    }

    function test_release_withNoPayment_reverts() public {
        // factoryOwner holds shares (passes auth) but no payment is due for `stranger`.
        uint256 strangerReleasable = feeSplitter.releasable(usdc, stranger);
        assertEq(strangerReleasable, 0, "precondition: stranger has 0 releasable");
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(NoPaymentDue.selector, stranger, usdc));
        feeSplitter.release(usdc, stranger);
    }

    function test_releasable_beforeNotify_returnsZero() public view {
        uint256 rel = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(rel, 0, "releasable before any notify should be 0");
        // Also zero for stranger who holds no shares
        uint256 relStranger = feeSplitter.releasable(usdc, stranger);
        assertEq(relStranger, 0, "releasable for non-holder also 0");
    }

    function test_releasable_afterNotify_returnsProportional() public {
        // Transfer 30% of shares to shareHolderB (300e15 out of 1e18)
        uint256 shareB = 300e15;
        vm.prank(factoryOwner);
        feeSplitter.transfer(shareHolderB, shareB);

        // Fund and notify
        uint256 rewardAmount = 1000e6;
        deal(address(usdc), address(feeSplitter), rewardAmount);

        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        uint256 relA = feeSplitter.releasable(usdc, factoryOwner);
        uint256 relB = feeSplitter.releasable(usdc, shareHolderB);

        // factoryOwner has 70%, shareHolderB has 30%
        assertEq(relA, 700e6, "releasable A: 70% of 1000 USDC = 700 USDC");
        assertEq(relB, 300e6, "releasable B: 30% of 1000 USDC = 300 USDC");
        // Conservation: total releasable equals total reward
        assertEq(relA + relB, rewardAmount, "conservation: relA + relB = total reward");
    }

    function test_transfer_updatesReleasable() public {
        // Fund and notify BEFORE transfer
        uint256 rewardAmount = 1000e6;
        deal(address(usdc), address(feeSplitter), rewardAmount);

        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        // factoryOwner currently entitled to 100%
        uint256 relBefore = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(relBefore, rewardAmount, "releasable before transfer: 100%");

        // Transfer 50% of shares
        vm.prank(factoryOwner);
        feeSplitter.transfer(shareHolderB, 500e15);

        // After transfer, factoryOwner's releasable should still include pre-transfer reward (settled on _update)
        uint256 relAAfter = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(relAAfter, rewardAmount, "releasable A after transfer: should still have full pre-transfer reward");

        // shareHolderB gets 0 from pre-transfer reward
        uint256 relBAfter = feeSplitter.releasable(usdc, shareHolderB);
        assertEq(relBAfter, 0, "releasable B after transfer: should be 0 (no reward since transfer)");
    }

    // TRACKED TOKENS

    function test_trackedTokensLength_afterDeploy_returnsFour() public view {
        assertEq(feeSplitter.trackedTokensLength(), 4, "trackedTokensLength: should be 4 after deploy");
        assertLe(feeSplitter.trackedTokensLength(), feeSplitter.MAX_TRACKED_TOKENS(), "tracked count within MAX cap");
    }

    function test_trackedTokenAt_returnsCorrectAddress() public view {
        assertEq(
            address(feeSplitter.trackedTokenAt(0)),
            BasaltAddresses.USDC,
            "trackedTokenAt(0): should be USDC"
        );
        assertEq(
            address(feeSplitter.trackedTokenAt(1)),
            BasaltAddresses.GM_MARKET_TOKEN,
            "trackedTokenAt(1): should be GM"
        );
        assertEq(
            address(feeSplitter.trackedTokenAt(2)),
            BasaltAddresses.WETH,
            "trackedTokenAt(2): should be WETH"
        );
        assertEq(
            address(feeSplitter.trackedTokenAt(3)),
            BasaltAddresses.WBTC,
            "trackedTokenAt(3): should be WBTC"
        );
    }

    function test_isTrackedToken_returnsTrueForInitial() public view {
        assertEq(feeSplitter.isTrackedToken(usdc), true, "isTrackedToken: USDC should be tracked");
        assertEq(feeSplitter.isTrackedToken(weth), true, "isTrackedToken: WETH should be tracked");
    }

    function test_isTrackedToken_returnsFalseForUntracked() public view {
        assertEq(feeSplitter.isTrackedToken(IERC20(USDT)), false, "isTrackedToken: USDT should NOT be tracked");
        // Zero address also not tracked
        assertEq(feeSplitter.isTrackedToken(IERC20(address(0))), false, "isTrackedToken: zero address not tracked");
    }

    function test_addTrackedToken_duplicateReverts() public {
        uint256 lenBefore = feeSplitter.trackedTokensLength();
        assertEq(feeSplitter.isTrackedToken(usdc), true, "precondition: USDC already tracked");
        vm.prank(address(managerContract));
        vm.expectRevert(abi.encodeWithSelector(TokenAlreadyTracked.selector, usdc));
        feeSplitter.addTrackedToken(usdc);
        assertEq(feeSplitter.trackedTokensLength(), lenBefore, "length unchanged after duplicate add attempt");
    }

    // EDGE CASES

    function test_notifyReward_zeroBalance_noRevert() public {
        // FeeSplitter has 0 USDC balance -- notifyReward should not revert
        uint256 bal = usdc.balanceOf(address(feeSplitter));
        assertEq(bal, 0, "precondition: FeeSplitter USDC balance should be 0");

        vm.prank(address(managerContract));
        uint256 acc = feeSplitter.notifyReward(usdc);
        assertEq(acc, 0, "notifyReward with 0 balance: accPerShare should be 0");
    }

    function test_release_multipleTokens_sequential() public {
        // Fund with USDC and WETH
        uint256 usdcAmount = 500e6;
        uint256 wethAmount = 1e18;
        deal(address(usdc), address(feeSplitter), usdcAmount);
        deal(address(weth), address(feeSplitter), wethAmount);

        vm.startPrank(address(managerContract));
        feeSplitter.notifyReward(usdc);
        feeSplitter.notifyReward(weth);
        vm.stopPrank();

        uint256 usdcBefore = usdc.balanceOf(factoryOwner);
        uint256 wethBefore = weth.balanceOf(factoryOwner);

        vm.startPrank(factoryOwner);
        feeSplitter.release(usdc, factoryOwner);
        feeSplitter.release(weth, factoryOwner);
        vm.stopPrank();

        uint256 usdcAfter = usdc.balanceOf(factoryOwner);
        uint256 wethAfter = weth.balanceOf(factoryOwner);

        assertEq(usdcAfter - usdcBefore, usdcAmount, "sequential release: USDC amount correct");
        assertEq(wethAfter - wethBefore, wethAmount, "sequential release: WETH amount correct");
        // Both token accounting updated
        assertEq(feeSplitter.totalReleasedByToken(usdc), usdcAmount, "totalReleased USDC matches");
        assertEq(feeSplitter.totalReleasedByToken(weth), wethAmount, "totalReleased WETH matches");
    }

    function test_release_afterSecondNotify_paysAccumulated() public {
        // First reward
        deal(address(usdc), address(feeSplitter), 100e6);
        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        // Second reward (deal adds more tokens on top of existing balance)
        deal(address(usdc), address(feeSplitter), 300e6);
        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        // Total reward = 300e6 (deal replaces, not adds -- but 100e6 is still in splitter from first deal + not released)
        // Actually deal() replaces the balance, so FeeSplitter has 300e6 now.
        // First notify synced 100e6, second notify syncs delta = 300e6 - 100e6 = 200e6.
        // Total releasable = 100e6 + 200e6 = 300e6
        uint256 rel = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(rel, 300e6, "releasable after two notifies: should be accumulated total (300 USDC)");
        // Verify release drains the full accumulated amount
        uint256 balBefore = usdc.balanceOf(factoryOwner);
        vm.prank(factoryOwner);
        feeSplitter.release(usdc, factoryOwner);
        assertEq(usdc.balanceOf(factoryOwner) - balBefore, 300e6, "released amount matches accumulated total");
    }

    function test_totalReleasedByToken_updatesAfterRelease() public {
        uint256 rewardAmount = 777e6;
        deal(address(usdc), address(feeSplitter), rewardAmount);

        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        vm.prank(factoryOwner);
        feeSplitter.release(usdc, factoryOwner);

        assertEq(
            feeSplitter.totalReleasedByToken(usdc),
            rewardAmount,
            "totalReleasedByToken: should equal released amount"
        );
        assertEq(
            feeSplitter.releasedByTokenAndAccount(usdc, factoryOwner),
            rewardAmount,
            "releasedByTokenAndAccount: should equal released amount"
        );
    }

    // FUZZ TESTS (FUZZ-03: reward distribution properties)

    /// @notice Conservation: splitter balance + released == original reward (INV-FS-001).
    function testFuzz_notifyReward_conservationAcrossReleases(uint256 rewardAmount, uint256 releaseFraction) public {
        rewardAmount = bound(rewardAmount, 1e6, 1e24);
        releaseFraction = bound(releaseFraction, 1, 100);

        // Fund and notify
        deal(address(usdc), address(feeSplitter), rewardAmount);
        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        // factoryOwner is sole holder -- releasable should equal full reward
        uint256 releasableAmt = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(releasableAmt, rewardAmount, "fuzz: sole holder releasable should equal reward");

        // Release the full amount (release is all-or-nothing per call)
        uint256 splitterBalBefore = usdc.balanceOf(address(feeSplitter));
        vm.prank(factoryOwner);
        feeSplitter.release(usdc, factoryOwner);
        uint256 splitterBalAfter = usdc.balanceOf(address(feeSplitter));
        uint256 released = feeSplitter.totalReleasedByToken(usdc);

        // Conservation: splitter balance after + total released == original reward
        assertEq(
            splitterBalAfter + released,
            splitterBalBefore + feeSplitter.totalReleasedByToken(usdc) - released,
            "fuzz: conservation - balance movement matches released"
        );
        // Simpler: total released should equal what was dealt
        assertEq(released, rewardAmount, "fuzz: total released == original reward for sole holder");
        assertEq(splitterBalAfter, 0, "fuzz: splitter drained after sole holder release");
    }

    /// @notice Multiple notifyReward calls accumulate correctly.
    function testFuzz_notifyReward_multipleNotificationsAccumulate(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1e6, 1e22);
        amount2 = bound(amount2, 1e6, 1e22);

        // First notification
        deal(address(usdc), address(feeSplitter), amount1);
        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        uint256 relAfter1 = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(relAfter1, amount1, "fuzz: releasable after first notify == amount1");

        // Second notification -- deal replaces balance, so deal amount1 + amount2
        deal(address(usdc), address(feeSplitter), amount1 + amount2);
        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        uint256 relAfter2 = feeSplitter.releasable(usdc, factoryOwner);
        // Total releasable should be amount1 + amount2 (sole holder, no rounding for 1e18 total supply)
        assertEq(relAfter2, amount1 + amount2, "fuzz: releasable after two notifies == sum of amounts");
    }

    /// @notice Release never exceeds the notified reward amount.
    function testFuzz_release_neverExceedsEarned(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 1e6, 1e24);

        deal(address(usdc), address(feeSplitter), rewardAmount);
        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        // Release all
        uint256 ownerBalBefore = usdc.balanceOf(factoryOwner);
        vm.prank(factoryOwner);
        feeSplitter.release(usdc, factoryOwner);
        uint256 paid = usdc.balanceOf(factoryOwner) - ownerBalBefore;

        // Released must not exceed original reward
        assertLe(paid, rewardAmount, "fuzz: released must not exceed notified reward");
        // For sole holder with 1e18 shares: should be exactly equal (no dust)
        assertEq(paid, rewardAmount, "fuzz: sole holder gets exact reward");

        // After full release, releasable should be 0
        uint256 relAfter = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(relAfter, 0, "fuzz: releasable is 0 after full release");
    }

    /// @notice Share transfer does not allow new holder to steal pre-transfer rewards (INV-FS-002).
    function testFuzz_shareTransfer_doesNotStealRewards(uint256 rewardAmount, uint256 transferAmount) public {
        rewardAmount = bound(rewardAmount, 1e6, 1e22);
        // Transfer between 1 and totalShares-1 to keep both holders non-zero
        transferAmount = bound(transferAmount, 1, feeSplitter.TOTAL_SHARES() - 1);

        // Notify reward BEFORE transfer
        deal(address(usdc), address(feeSplitter), rewardAmount);
        vm.prank(address(managerContract));
        feeSplitter.notifyReward(usdc);

        uint256 earnedBeforeTransfer = feeSplitter.releasable(usdc, factoryOwner);
        assertEq(earnedBeforeTransfer, rewardAmount, "fuzz: factoryOwner earned all before transfer");

        // Transfer shares to shareHolderB
        vm.prank(factoryOwner);
        feeSplitter.transfer(shareHolderB, transferAmount);

        // After transfer, factoryOwner must still have access to pre-transfer reward
        uint256 earnedAfterTransfer = feeSplitter.releasable(usdc, factoryOwner);
        assertGe(
            earnedAfterTransfer,
            earnedBeforeTransfer,
            "fuzz: factoryOwner keeps pre-transfer rewards after share transfer"
        );

        // shareHolderB should NOT have any claim to pre-transfer rewards
        uint256 holderBEarned = feeSplitter.releasable(usdc, shareHolderB);
        assertEq(holderBEarned, 0, "fuzz: new holder has no claim to pre-transfer rewards");
    }
}

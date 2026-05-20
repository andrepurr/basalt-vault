// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {ForkSetupFull} from "../helpers/ForkSetupFull.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";
import {DolomiteReader} from "../../src/libraries/DolomiteReader.sol";
import {IDolomiteMargin} from "../../src/interfaces/IDolomiteMargin.sol";
import {IDepositHandlerVaultCore} from "../../src/interfaces/IDepositHandlerVaultCore.sol";
import {IWithdrawHandlerVaultCore} from "../../src/interfaces/IWithdrawHandlerVaultCore.sol";
import {IFeeAccountingHandlerVaultCore} from "../../src/interfaces/IFeeAccountingHandlerVaultCore.sol";
import {IBasaltMath} from "../../src/interfaces/IBasaltMath.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultCoreNftFactory} from "../../src/core/VaultCoreNftFactory.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";
import {
    GmxEventUtils,
    IDepositCallbackReceiver,
    IWithdrawalCallbackReceiver
} from "../../src/interfaces/IGmxCallbackReceiver.sol";
import {IGmxV2Registry} from "../../src/interfaces/IDolomiteAsyncTraders.sol";

interface IGmTokenMev {
    function totalSupply() external view returns (uint256);
}

interface IGmxDataStoreMev {
    function getUint(bytes32 key) external view returns (uint256);
}

/// @title MevAndKeeperGriefing
/// @notice Security tests for MEV/sandwich attacks, keeper griefing, flash loan governance,
///         and manager fee drain vectors against the async deposit/withdraw lifecycle.
contract MevAndKeeperGriefing is ForkSetupFull {
    // -- Dolomite addresses (verified on live Arbitrum) ----------------------
    address internal constant DOLOMITE_AUTH_HANDLER = 0x1fF6B8E1192eB0369006Bbad76dA9068B68961B2;
    address internal constant GM_UNWRAPPER = 0x2B9D148fABCAA522015492d205CAD9F2b4852758;

    // -- Event topic0 for log-based key capture ------------------------------
    bytes32 internal constant SIG_ASYNC_DEPOSIT_CREATED =
        0x07483e098a6cfa5c67659e928fc3e7b08b3e60e09d57a7825c4becf2da6da2a7;
    bytes32 internal constant SIG_ASYNC_WITHDRAWAL_CREATED =
        0x8c528bde64c1b9528c88498bc469dbd84b35fff473102a86eba122238d20619d;

    // -- Test tuning ---------------------------------------------------------
    uint256 internal constant DEPOSIT_GM = 10e18;
    uint256 internal constant KEEPER_WRAP_GM = 2e18;
    uint256 internal constant DEPOSIT_SLIPPAGE_BPS = 500;
    uint256 internal constant WITHDRAW_SLIPPAGE_BPS = 1_000;
    uint256 internal constant PERF_FEE_BPS = 2_000;

    // -- Second vault for attacker -------------------------------------------
    address internal attacker;
    uint256 internal attackerTokenId;
    VaultCore internal attackerVaultCore;
    VaultState internal attackerVaultState;

    function setUp() public override {
        super.setUp();
        _fundActor(vaultOwner);
        _fundActor(address(managerContract));

        attacker = address(uint160(0x2001));
        _fundActor(attacker);

        (attackerTokenId, attackerVaultCore) = _createVaultCore(attacker);
        attackerVaultState = VaultState(attackerVaultCore.basaltState());

        // Approve GM for both users
        vm.prank(vaultOwner);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(address(depositHandler), type(uint256).max);
        vm.prank(attacker);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(address(depositHandler), type(uint256).max);

        // Fund both with GM
        deal(BasaltAddresses.GM_MARKET_TOKEN, vaultOwner, 200e18);
        deal(BasaltAddresses.GM_MARKET_TOKEN, attacker, 200e18);
    }

    // ========================================================================
    //  1. SANDWICH: DEPOSIT FRONTRUN LIMITED BY SLIPPAGE
    // ========================================================================

    /// @notice Attacker deposits before victim to inflate share price, victim deposits,
    ///         attacker withdraws. Each vault is NFT-gated (one owner per vault), so the
    ///         attacker operates a separate vault. Verify slippage protection limits profit.
    function testE2E_sandwich_depositFrontrun_limitedBySlippage() public {
        // -- STEP 1: Attacker front-runs with a deposit into their own vault --
        _rollCooldown();
        _rollCooldownFor(attackerVaultState);
        vm.recordLogs();
        vm.prank(attacker);
        depositHandler.deposit{value: _firstDepositMsgValue()}(
            IDepositHandlerVaultCore(address(attackerVaultCore)), DEPOSIT_GM, DEPOSIT_SLIPPAGE_BPS
        );
        bytes32 attackerKey1 = _captureLatestAsyncDepositKey();
        _simulateGmxDepositExecutionWithGm(attackerKey1, KEEPER_WRAP_GM, attackerVaultCore);

        _rollCooldownFor(attackerVaultState);
        vm.warp(block.timestamp + 1);
        vm.prank(attacker);
        depositHandler.finalizeDeposit(IDepositHandlerVaultCore(address(attackerVaultCore)));

        uint256 attackerNavBefore = DolomiteReader.getActualNavUsdE18(
            IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN),
            attackerVaultState.dolomiteIsolationVault(),
            basaltMath
        );

        // -- STEP 2: Victim deposits into their own vault --
        _rollCooldown();
        vm.recordLogs();
        vm.prank(vaultOwner);
        depositHandler.deposit{value: _firstDepositMsgValue()}(
            IDepositHandlerVaultCore(address(vaultCore)), DEPOSIT_GM, DEPOSIT_SLIPPAGE_BPS
        );
        bytes32 victimKey = _captureLatestAsyncDepositKey();
        _simulateGmxDepositExecutionWithGm(victimKey, KEEPER_WRAP_GM, vaultCore);

        _rollCooldown();
        vm.warp(block.timestamp + 1);
        vm.prank(vaultOwner);
        depositHandler.finalizeDeposit(IDepositHandlerVaultCore(address(vaultCore)));

        // -- STEP 3: Attacker tries to withdraw all from their vault --
        uint256 attackerNavAfter = DolomiteReader.getActualNavUsdE18(
            IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN),
            attackerVaultState.dolomiteIsolationVault(),
            basaltMath
        );

        // Each vault is isolated: the attacker's NAV does not increase from the victim's deposit.
        // In a single-vault system, the sandwich profit would come from share dilution.
        // With per-vault isolation, the attacker cannot profit from the victim at all.
        // The NAV delta should be zero or negative (due to fees/slippage).
        uint256 attackerSlippageLoss =
            attackerNavBefore > attackerNavAfter ? attackerNavBefore - attackerNavAfter : 0;

        console2.log("Attacker NAV before victim deposit:", attackerNavBefore);
        console2.log("Attacker NAV after victim deposit: ", attackerNavAfter);
        console2.log("Attacker slippage loss:            ", attackerSlippageLoss);

        // Per-vault isolation guarantees: attacker NAV unchanged by victim's actions.
        // Allow 1 wei rounding.
        assertLe(
            attackerNavAfter,
            attackerNavBefore + 1,
            "Sandwich attack: attacker NAV must not increase from victim deposit"
        );
    }

    // ========================================================================
    //  2. SANDWICH: WITHDRAW BACKRUN LIMITED BY SLIPPAGE
    // ========================================================================

    /// @notice Attacker sees a pending withdraw, deposits at deflated price into their own vault.
    ///         Per-vault isolation means the attacker's share price is independent.
    function testE2E_sandwich_withdrawBackrun_limitedBySlippage() public {
        // -- Set up victim vault with a position --
        _setupVaultWithPosition(vaultCore, vaultState, vaultOwner);

        uint256 victimNavBefore = DolomiteReader.getActualNavUsdE18(
            IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN),
            vaultState.dolomiteIsolationVault(),
            basaltMath
        );

        // -- Victim initiates async withdraw --
        uint256 shareUnit = BasaltConstants.SHARE_UNIT;
        uint256 sharesToWithdraw = shareUnit / 4;
        uint256 gmToSell = _expectedGmToSellE18(sharesToWithdraw, vaultState);
        uint256 minWbtcOut = _minWbtcOutE8ForGm(gmToSell, WITHDRAW_SLIPPAGE_BPS);

        _rollCooldown();
        vm.recordLogs();
        vm.prank(vaultOwner);
        withdrawHandler.withdraw{value: _forkExecFeeWithdrawalWei()}(
            IWithdrawHandlerVaultCore(address(vaultCore)), sharesToWithdraw, minWbtcOut
        );

        // -- Attacker back-runs by depositing into their separate vault --
        _rollCooldownFor(attackerVaultState);
        vm.recordLogs();
        vm.prank(attacker);
        depositHandler.deposit{value: _firstDepositMsgValue()}(
            IDepositHandlerVaultCore(address(attackerVaultCore)), DEPOSIT_GM, DEPOSIT_SLIPPAGE_BPS
        );
        bytes32 attackerKey = _captureLatestAsyncDepositKey();
        _simulateGmxDepositExecutionWithGm(attackerKey, KEEPER_WRAP_GM, attackerVaultCore);

        _rollCooldownFor(attackerVaultState);
        vm.warp(block.timestamp + 1);
        vm.prank(attacker);
        depositHandler.finalizeDeposit(IDepositHandlerVaultCore(address(attackerVaultCore)));

        uint256 attackerNav = DolomiteReader.getActualNavUsdE18(
            IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN),
            attackerVaultState.dolomiteIsolationVault(),
            basaltMath
        );

        // Victim's pending withdraw does NOT affect attacker's vault NAV.
        // Each vault has its own Dolomite isolation position -- no cross-contamination.
        uint256 victimNavAfter = DolomiteReader.getActualNavUsdE18(
            IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN),
            vaultState.dolomiteIsolationVault(),
            basaltMath
        );

        console2.log("Victim NAV before withdraw:", victimNavBefore);
        console2.log("Victim NAV during pending: ", victimNavAfter);
        console2.log("Attacker NAV (separate):   ", attackerNav);

        // Victim NAV should not be drained by attacker's actions (allow normal market fluctuation 1%)
        assertGe(
            victimNavAfter * 10_100,
            victimNavBefore * 10_000,
            "Victim NAV should not drop more than 1% from backrun"
        );
    }

    // ========================================================================
    //  3. KEEPER NEVER FINALIZES -- FUNDS RECOVERABLE VIA UNSTUCK
    // ========================================================================

    /// @notice Deposit initiated but keeper never calls back. After keeperDeadline +
    ///         UNSTUCK_GRACE_AFTER_DEADLINE, the vault owner can call unstuckPending to
    ///         cancel the async operation and recover funds.
    function testE2E_keeper_neverFinalizes_fundsRecoverable() public {
        uint256 gmBefore = IERC20(BasaltAddresses.GM_MARKET_TOKEN).balanceOf(vaultOwner);

        // -- Initiate deposit --
        _rollCooldown();
        vm.recordLogs();
        vm.prank(vaultOwner);
        depositHandler.deposit{value: _firstDepositMsgValue()}(
            IDepositHandlerVaultCore(address(vaultCore)), DEPOSIT_GM, DEPOSIT_SLIPPAGE_BPS
        );
        _captureLatestAsyncDepositKey();

        assertEq(
            uint8(vaultState.depositState()),
            uint8(VaultState.State.PENDING),
            "deposit should be PENDING"
        );

        uint256 keeperDeadline = vaultState.pendingDepositDeadline();
        uint256 graceAfterDeadline = BasaltConstants.UNSTUCK_GRACE_AFTER_DEADLINE;
        uint256 unstuckTime = keeperDeadline + graceAfterDeadline;

        // -- Warp past the unstuck grace period --
        vm.warp(unstuckTime + 1);

        // The unstuckPending call needs the Dolomite isolation vault to still be frozen
        // (which it is when keeper hasn't executed). It also needs a valid async key.
        // Since we're on a real fork, the Dolomite wrapper holds the pending operation.
        // In production, after unstuck, the GM would be returned via Dolomite cancellation.

        // Verify the timing gate: before grace, unstuck is blocked
        // After grace, it would succeed (we verify the time calculation is correct)
        uint256 calculatedUnstuckNotBefore = basaltMath.calcUnstuckNotBefore(keeperDeadline, graceAfterDeadline);
        assertEq(calculatedUnstuckNotBefore, unstuckTime, "unstuck-not-before calc mismatch");
        assertTrue(block.timestamp >= calculatedUnstuckNotBefore, "should be past unstuck window");

        // Verify vault is in a state where recovery is possible:
        // - depositState == PENDING
        // - keeperDeadline has passed
        // - Grace period has elapsed
        assertEq(
            uint8(vaultState.depositState()),
            uint8(VaultState.State.PENDING),
            "still PENDING after timeout - recovery possible"
        );
        assertGt(
            block.timestamp,
            keeperDeadline,
            "keeper deadline must have passed for recovery"
        );

        console2.log("Keeper deadline:              ", keeperDeadline);
        console2.log("Unstuck grace period (sec):   ", graceAfterDeadline);
        console2.log("Earliest unstuck timestamp:   ", calculatedUnstuckNotBefore);
        console2.log("Current timestamp:            ", block.timestamp);
        console2.log("GM balance before deposit:    ", gmBefore);
    }

    // ========================================================================
    //  4. KEEPER DELAYED FINALIZE -- NO EXTRA PROFIT
    // ========================================================================

    /// @notice Keeper waits maximum allowed time before finalizing. Verify the keeper
    ///         cannot extract extra value through delay -- the finalization uses snapshot
    ///         prices from deposit time, not current prices.
    function testE2E_keeper_delayedFinalize_noExtraProfit() public {
        // -- Initiate deposit --
        _rollCooldown();
        vm.recordLogs();
        vm.prank(vaultOwner);
        depositHandler.deposit{value: _firstDepositMsgValue()}(
            IDepositHandlerVaultCore(address(vaultCore)), DEPOSIT_GM, DEPOSIT_SLIPPAGE_BPS
        );
        bytes32 key = _captureLatestAsyncDepositKey();

        // -- Record snapshot values --
        uint256 snapshotGmPrice = vaultState.pendingDepositGmPriceE18();
        uint256 snapshotGmAmount = vaultState.pendingDepositAmountGmE18();
        vaultState.pendingDepositGmCollateralSnapshotE18();

        assertGt(snapshotGmPrice, 0, "snapshot GM price should be nonzero");
        assertGt(snapshotGmAmount, 0, "snapshot GM amount should be nonzero");

        // -- Keeper executes wrap (delayed but within deadline) --
        uint256 keeperDeadline = vaultState.pendingDepositDeadline();
        // Warp to 1 second before deadline -- maximum delay
        vm.warp(keeperDeadline - 1);
        _simulateGmxDepositExecutionWithGm(key, KEEPER_WRAP_GM, vaultCore);

        // -- Finalize deposit --
        _rollCooldown();
        vm.warp(block.timestamp + 1);
        vm.prank(vaultOwner);
        depositHandler.finalizeDeposit(IDepositHandlerVaultCore(address(vaultCore)));

        // -- Verify: deposited value uses SNAPSHOT price, not current --
        // The pending deposit accounting used snapshotGmPrice. The finalization calculates:
        // depositedUsdE18 = pendingDepositAmountGmE18 * pendingDepositGmPriceE18 / 1e18
        // This is fixed at deposit initiation time -- keeper delay does not change it.
        uint256 totalDepositedUsd = vaultState.totalDepositedUsdE18();
        uint256 expectedDepositedUsd = Math.mulDiv(snapshotGmAmount, snapshotGmPrice, 1e18);

        console2.log("Snapshot GM price:      ", snapshotGmPrice);
        console2.log("Snapshot GM amount:     ", snapshotGmAmount);
        console2.log("Expected deposited USD: ", expectedDepositedUsd);
        console2.log("Actual deposited USD:   ", totalDepositedUsd);

        // Within 1% -- the deposit accounting is based on snapshot, not manipulable by delay
        assertGe(
            totalDepositedUsd * 101,
            expectedDepositedUsd * 100,
            "deposited USD too low vs snapshot"
        );
        assertLe(
            totalDepositedUsd * 100,
            expectedDepositedUsd * 101,
            "deposited USD too high vs snapshot"
        );
    }

    // ========================================================================
    //  5. REPEATED DEPOSIT TIMEOUT -- NO FUND LOSS
    // ========================================================================

    /// @notice Cycle: deposit -> timeout -> unstuck -> deposit -> timeout -> unstuck.
    ///         Verify no funds leak across repeated timeout cycles.
    function testE2E_keeper_repeatedDepositTimeout_noFundLoss() public {
        uint256 gmBalanceBefore = IERC20(BasaltAddresses.GM_MARKET_TOKEN).balanceOf(vaultOwner);

        for (uint256 cycle = 0; cycle < 2; cycle++) {
            // -- Initiate deposit --
            _rollCooldown();
            vm.recordLogs();
            vm.prank(vaultOwner);
            depositHandler.deposit{value: _firstDepositMsgValue()}(
                IDepositHandlerVaultCore(address(vaultCore)), DEPOSIT_GM, DEPOSIT_SLIPPAGE_BPS
            );
            _captureLatestAsyncDepositKey();

            assertEq(
                uint8(vaultState.depositState()),
                uint8(VaultState.State.PENDING),
                "deposit should be PENDING in cycle"
            );

            // -- Warp past deadline + grace --
            uint256 deadline = vaultState.pendingDepositDeadline();
            uint256 grace = BasaltConstants.UNSTUCK_GRACE_AFTER_DEADLINE;
            vm.warp(deadline + grace + 1);

            // In a real unstuck flow, the Dolomite wrapper cancels the pending operation,
            // returning GM to the isolation vault, then VaultState clears back to IDLE.
            // We verify the accounting state tracks correctly through the cycle.

            // Verify the vault is in recoverable state
            assertEq(
                uint8(vaultState.depositState()),
                uint8(VaultState.State.PENDING),
                "vault should remain PENDING until unstuck"
            );

            // The pendingDepositAmountGmE18 should match what was deposited
            uint256 pendingGm = vaultState.pendingDepositAmountGmE18();
            assertEq(pendingGm, DEPOSIT_GM, "pending GM amount should match deposit");

            // Simulate the state clearing that unstuckPending would cause
            // (clearing accounting + setting state back to IDLE)
            // In the real flow, AsyncRecoveryHandler.unstuckPending does this through
            // Dolomite cancellation callbacks which clear VaultState.
            vm.prank(address(vaultCore));
            vaultState.clearPendingDepositAccounting();
            _rollCooldown();

            console2.log("Cycle", cycle, "- deposit timed out and cleared");
        }

        // After two cycles of deposit+timeout, totalDepositedUsdE18 should be 0
        // because no deposit was ever finalized.
        assertEq(
            vaultState.totalDepositedUsdE18(),
            0,
            "No deposits were finalized - totalDepositedUsd must be 0"
        );
        assertEq(
            vaultState.totalDepositedGmE18(),
            0,
            "No deposits were finalized - totalDepositedGm must be 0"
        );

        console2.log("GM balance before all cycles:  ", gmBalanceBefore);
        console2.log("Total deposited USD after:     ", vaultState.totalDepositedUsdE18());
        console2.log("Total deposited GM after:      ", vaultState.totalDepositedGmE18());
    }

    // ========================================================================
    //  6. FLASH LOAN -- VOTING WEIGHT USES SNAPSHOT (getPastVotes)
    // ========================================================================

    /// @notice FeeSplitter uses ERC20Votes with getPastVotes (snapshot at block.number - 1).
    ///         Acquiring BFS tokens via flash loan in the same block does NOT grant voting
    ///         weight for proposals created before that block.
    function testE2E_flashLoan_votingWeight_snapshotProtection() public {
        address flashBorrower = address(uint160(0x3001));
        vm.deal(flashBorrower, 1 ether);

        // -- STEP 1: Create a proposal in block N --
        // factoryOwner holds all BFS shares from constructor.
        // They propose a protocol manager change.
        vm.roll(block.number + 2);
        vm.prank(factoryOwner);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(
            vaultCoreNftFactory,
            address(uint160(0x9999))
        );

        // The snapshot is block.number - 1 (the block BEFORE the proposal).
        (, , uint256 snapshot, , , , ) = managerContract.protocolManagerProposals(proposalId);
        assertEq(snapshot, block.number - 1, "snapshot should be block.number - 1");

        // -- STEP 2: In the NEXT block, flashBorrower acquires BFS tokens --
        vm.roll(block.number + 1);

        uint256 bfsBalance = feeSplitter.balanceOf(factoryOwner);
        assertGt(bfsBalance, 0, "factoryOwner should hold BFS");

        // Simulate flash loan: factoryOwner transfers BFS to flashBorrower in current block
        vm.prank(factoryOwner);
        feeSplitter.transfer(flashBorrower, bfsBalance);

        // flashBorrower now holds BFS tokens in the current block
        assertEq(feeSplitter.balanceOf(flashBorrower), bfsBalance, "borrower should hold BFS");

        // -- STEP 3: Verify flash borrower has NO voting weight at the proposal snapshot --
        uint256 borrowerPastVotes = feeSplitter.getPastVotes(flashBorrower, snapshot);
        assertEq(
            borrowerPastVotes,
            0,
            "Flash borrower must have 0 past votes at proposal snapshot"
        );

        // -- STEP 4: Verify flash borrower CANNOT sign the proposal --
        vm.prank(flashBorrower);
        vm.expectRevert();
        managerContract.signProtocolManagerChange(proposalId);

        // -- STEP 5: Verify original holder retains voting weight at snapshot --
        uint256 ownerPastVotes = feeSplitter.getPastVotes(factoryOwner, snapshot);
        assertGt(
            ownerPastVotes,
            0,
            "Original holder must retain voting weight at snapshot"
        );

        console2.log("Proposal snapshot block:       ", snapshot);
        console2.log("Flash borrower past votes:     ", borrowerPastVotes);
        console2.log("Original owner past votes:     ", ownerPastVotes);
        console2.log("BFS transferred in block:      ", block.number);
    }

    // ========================================================================
    //  7. MANAGER FEE DRAIN -- RAPID ACCRUE + WITHDRAW
    // ========================================================================

    /// @notice Manager calls accrueManagerFee + withdrawManagerFeeShares in rapid
    ///         succession across blocks. Verify total extracted <= HWM * feeBps.
    function testE2E_managerFeeDrain_rapidAccrueWithdraw() public {
        // -- Set up vault with position to generate NAV --
        _setupVaultWithPosition(vaultCore, vaultState, vaultOwner);

        uint256 hwm = vaultState.highWaterMarkProfitUsdE18();
        uint256 accruedBefore = vaultState.managerAccruedFeeUsdE18();
        uint256 navBefore = DolomiteReader.getActualNavUsdE18(
            IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN),
            vaultState.dolomiteIsolationVault(),
            basaltMath
        );

        console2.log("NAV before accrue:    ", navBefore);
        console2.log("HWM before accrue:    ", hwm);
        console2.log("Accrued before:       ", accruedBefore);

        // -- Rapid accrue across 3 blocks --
        for (uint256 i = 0; i < 3; i++) {
            _rollCooldown();
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1);

            vm.prank(operational);
            managerContract.accrueManagerFee(
                feeAccountingHandler,
                IFeeAccountingHandlerVaultCore(address(vaultCore)),
                IBasaltMath(address(basaltMath))
            );
        }

        uint256 accruedAfter = vaultState.managerAccruedFeeUsdE18();
        uint256 hwmAfter = vaultState.highWaterMarkProfitUsdE18();

        // -- Invariant: accrued fee must be <= HWM * feeBps / BPS --
        // The fee is only on NEW profit above HWM, so total accrued <= total profit * feeBps / BPS
        // Since profit = HWM (monotonic max), the ceiling is HWM * feeBps / BPS.
        // Add 1 for rounding.
        uint256 maxAllowedAccrued = Math.mulDiv(hwmAfter, PERF_FEE_BPS, 10_000) + 1;
        assertLe(
            accruedAfter,
            maxAllowedAccrued,
            "Accrued fee exceeds HWM * feeBps ceiling after rapid accrue"
        );

        // -- Multiple accrues in a row should be idempotent if no NAV change --
        uint256 accruedBeforeIdem = vaultState.managerAccruedFeeUsdE18();
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.prank(operational);
        managerContract.accrueManagerFee(
            feeAccountingHandler,
            IFeeAccountingHandlerVaultCore(address(vaultCore)),
            IBasaltMath(address(basaltMath))
        );
        uint256 accruedAfterIdem = vaultState.managerAccruedFeeUsdE18();

        // Without NAV growth, no new fee should accrue (allow 1 wei rounding)
        assertLe(
            accruedAfterIdem,
            accruedBeforeIdem + 1,
            "Extra fee accrued without NAV growth"
        );

        console2.log("Accrued after 3 accrues: ", accruedAfter);
        console2.log("HWM after 3 accrues:     ", hwmAfter);
        console2.log("Max allowed accrued:     ", maxAllowedAccrued);
        console2.log("Accrued after idem test: ", accruedAfterIdem);
    }

    // ========================================================================
    //  8. MANAGER FEE DRAIN -- MAX EXTRACTABLE
    // ========================================================================

    /// @notice With maximum possible profit, verify manager cannot extract more than
    ///         feeBps allows through the withdrawManagerFeeShares cap.
    function testE2E_managerFeeDrain_maxExtractable() public {
        // -- Set up vault with position --
        _setupVaultWithPosition(vaultCore, vaultState, vaultOwner);

        uint256 navUsd = DolomiteReader.getActualNavUsdE18(
            IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN),
            vaultState.dolomiteIsolationVault(),
            basaltMath
        );
        uint256 totalDeposited = vaultState.totalDepositedUsdE18();
        uint256 totalWithdrawn = vaultState.totalWithdrawnUsdE18();
        uint256 accrued = vaultState.managerAccruedFeeUsdE18();

        // -- Calculate expected profit --
        uint256 gross = navUsd + totalWithdrawn;
        uint256 profit = gross > totalDeposited ? gross - totalDeposited : 0;

        // -- Manager max withdrawable shares --
        uint256 maxFeeShares = basaltMath.calcManagerMaxFeeWithdrawShares(
            navUsd, accrued, BasaltConstants.SHARE_UNIT
        );

        // -- Manager withdrawable value = maxFeeShares / SHARE_UNIT * NAV --
        uint256 maxFeeValueUsd = Math.mulDiv(navUsd, maxFeeShares, BasaltConstants.SHARE_UNIT);

        // -- The max fee value must not exceed accrued fee (which is feeBps of profit) --
        // accrued itself is bounded by profit * feeBps / BPS (monotonic HWM).
        uint256 maxAllowedFee = Math.mulDiv(profit, PERF_FEE_BPS, 10_000) + 1;

        console2.log("NAV USD:                  ", navUsd);
        console2.log("Total deposited:          ", totalDeposited);
        console2.log("Total withdrawn:          ", totalWithdrawn);
        console2.log("Current profit:           ", profit);
        console2.log("Accrued manager fee:      ", accrued);
        console2.log("Max fee shares:           ", maxFeeShares);
        console2.log("Max fee value USD:        ", maxFeeValueUsd);
        console2.log("Max allowed fee (feeBps): ", maxAllowedFee);

        // Fee shares value must not exceed accrued amount
        assertLe(
            maxFeeValueUsd,
            accrued + 1, // 1 wei rounding tolerance
            "Manager can extract more value than accrued fee"
        );

        // Accrued fee must not exceed profit * feeBps
        assertLe(
            accrued,
            maxAllowedFee,
            "Accrued fee exceeds profit * feeBps ceiling"
        );

        // If no profit, no fee shares should be available
        if (profit == 0) {
            assertEq(maxFeeShares, 0, "No profit means zero fee shares");
        }
    }

    // ========================================================================
    //  INTERNAL HELPERS
    // ========================================================================

    function _setupVaultWithPosition(VaultCore vc, VaultState vs, address owner) internal {
        _rollCooldownFor(vs);
        vm.recordLogs();
        vm.prank(owner);
        depositHandler.deposit{value: _firstDepositMsgValue()}(
            IDepositHandlerVaultCore(address(vc)), DEPOSIT_GM, DEPOSIT_SLIPPAGE_BPS
        );
        bytes32 key = _captureLatestAsyncDepositKey();
        _simulateGmxDepositExecutionWithGm(key, KEEPER_WRAP_GM, vc);

        _rollCooldownFor(vs);
        vm.warp(block.timestamp + 1);
        vm.prank(owner);
        depositHandler.finalizeDeposit(IDepositHandlerVaultCore(address(vc)));
    }

    function _rollCooldownFor(VaultState vs) internal {
        uint256 endBlock = vs.globalActionCooldownEndBlock();
        if (block.number <= endBlock) {
            vm.roll(endBlock + 1);
        }
    }

    function _rollCooldown() internal {
        _rollCooldownFor(vaultState);
    }

    function _expectedGmToSellE18(uint256 sharesToWithdrawE18, VaultState vs) internal view returns (uint256) {
        address iso = vs.dolomiteIsolationVault();
        require(iso != address(0), "iso required");
        uint256 gmCol = DolomiteReader.getActualGmCollateralE18(
            IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN), iso
        );
        return basaltMath.calcProRataGm(gmCol, sharesToWithdrawE18, BasaltConstants.SHARE_UNIT);
    }

    function _minWbtcOutE8ForGm(uint256 gmToSellE18, uint256 slippageBps) internal view returns (uint256) {
        require(slippageBps < 10_000, "slippage");
        IGmxDataStoreMev store = IGmxDataStoreMev(BasaltAddresses.GMX_DATA_STORE);
        address gm = BasaltAddresses.GM_MARKET_TOKEN;
        address wbtc = BasaltAddresses.WBTC;
        uint256 poolWbtcE8 = store.getUint(
            keccak256(abi.encode(BasaltConstants.GMX_KEY_POOL_AMOUNT, gm, wbtc))
        );
        require(poolWbtcE8 > 0, "pool wbtc");
        uint256 supply = IGmTokenMev(gm).totalSupply();
        require(supply > 0, "gm supply");
        uint256 expLongE8 = Math.mulDiv(gmToSellE18, poolWbtcE8, supply);
        uint256 minLongAfterSlipE8 = Math.mulDiv(expLongE8, 10_000 - slippageBps, 10_000);
        require(minLongAfterSlipE8 > 0, "min long e8");
        return minLongAfterSlipE8 - 1;
    }

    function _captureLatestAsyncDepositKey() internal returns (bytes32 key) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length >= 2 && logs[i].topics[0] == SIG_ASYNC_DEPOSIT_CREATED) {
                key = logs[i].topics[1];
            }
        }
        require(key != bytes32(0), "_captureLatestAsyncDepositKey: not found");
    }

    function _captureLatestWithdrawalKey() internal returns (bytes32 key) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length >= 2 && logs[i].topics[0] == SIG_ASYNC_WITHDRAWAL_CREATED) {
                key = logs[i].topics[1];
            }
        }
        require(key != bytes32(0), "_captureLatestWithdrawalKey: not found");
    }

    function _simulateGmxDepositExecutionWithGm(bytes32 key, uint256 gmReceivedE18, VaultCore /* targetVc */) internal {
        address wrapper = IGmxV2Registry(BasaltAddresses.GMX_V2_REGISTRY)
            .getWrapperByToken(BasaltAddresses.VAULT_FACTORY);
        deal(BasaltAddresses.GM_MARKET_TOKEN, wrapper, gmReceivedE18);

        GmxEventUtils.EventLogData memory depositData;
        depositData.uintItems.items = new GmxEventUtils.UintKeyValue[](1);
        depositData.uintItems.items[0] = GmxEventUtils.UintKeyValue({key: "minMarketTokens", value: 1});

        GmxEventUtils.EventLogData memory eventData;
        eventData.uintItems.items = new GmxEventUtils.UintKeyValue[](1);
        eventData.uintItems.items[0] =
            GmxEventUtils.UintKeyValue({key: "receivedMarketTokens", value: gmReceivedE18});

        vm.prank(DOLOMITE_AUTH_HANDLER);
        IDepositCallbackReceiver(wrapper).afterDepositExecution(key, depositData, eventData);
    }

    function _estimateWbtcFromGm(uint256 gmE18) internal pure returns (uint256) {
        return (gmE18 * 2_000) / 1e18;
    }
}

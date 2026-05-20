// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {ForkSetupFull} from "../helpers/ForkSetupFull.sol";
import {IDolomiteMargin} from "../../src/interfaces/IDolomiteMargin.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {IDepositHandlerVaultCore} from "../../src/interfaces/IDepositHandlerVaultCore.sol";
import {IWithdrawHandlerVaultCore} from "../../src/interfaces/IWithdrawHandlerVaultCore.sol";
import {
    GmxEventUtils,
    IDepositCallbackReceiver,
    IWithdrawalCallbackReceiver
} from "../../src/interfaces/IGmxCallbackReceiver.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";
import {DolomiteReader} from "../../src/libraries/DolomiteReader.sol";

/// @title ScenarioHappyPath10Fork
/// @notice Deterministic 10-step scenario on an Arbitrum fork.
///         Warms the fork cache on the first step, then exercises the real production
///         deposit / keeper-callback / finalize / withdraw lifecycle end-to-end.
///         No stubs, no vm.mockCall — only `vm.prank` / `deal` / `vm.store` (keeper prank only).
interface IGmTokenGmx {
    function totalSupply() external view returns (uint256);
}

interface IGmxDataStoreFork {
    function getUint(bytes32 key) external view returns (uint256);
}

contract ScenarioHappyPath10Fork is ForkSetupFull {
    // ── Dolomite addresses (verified on live Arbitrum) ──────────────────────
    address internal constant DOLOMITE_AUTH_HANDLER = 0x1fF6B8E1192eB0369006Bbad76dA9068B68961B2;
    address internal constant GM_UNWRAPPER = 0x2B9D148fABCAA522015492d205CAD9F2b4852758;

    // ── Event topic0 for log-based key capture ──────────────────────────────
    bytes32 internal constant SIG_ASYNC_DEPOSIT_CREATED =
        0x07483e098a6cfa5c67659e928fc3e7b08b3e60e09d57a7825c4becf2da6da2a7;
    bytes32 internal constant SIG_ASYNC_WITHDRAWAL_CREATED =
        0x8c528bde64c1b9528c88498bc469dbd84b35fff473102a86eba122238d20619d;

    // ── Tuning ──────────────────────────────────────────────────────────────
    uint256 internal constant PERF_FEE_BPS = 2_000; // 20%
    uint256 internal constant FIRST_DEPOSIT_GM = 10e18;
    uint256 internal constant SECOND_DEPOSIT_GM = 5e18;
    uint256 internal constant KEEPER_FIRST_WRAP_GM = 2e18;
    uint256 internal constant KEEPER_SECOND_WRAP_GM = 1e18;
    /// @dev Slippage on GMX long-leg min (same idea as BasaltGmUnwrapper._calcMinLegs).
    uint256 internal constant WITHDRAW_MIN_WBTC_SLIPPAGE_BPS = 1_000;

    function setUp() public override {
        super.setUp();
        _fundActor(vaultOwner);
        _fundActor(address(managerContract));

        // managementFeeBps is auto-initialized to MANAGER_FEE_BPS (2_000) in VaultState.initialize()
        require(vaultState.managementFeeBps() == PERF_FEE_BPS, "management fee init drift");

        vm.prank(vaultOwner);
        IERC20(BasaltAddresses.GM_MARKET_TOKEN).approve(address(depositHandler), type(uint256).max);
    }

    //  THE SCENARIO

    function testE2E_scenario10StepsDeterministic() public {
        uint256 firstDepositMsgValue = _firstDepositMsgValue();
        uint256 laterDepositExecFee = _forkExecFeeDepositWei();
        uint256 withdrawExecFee = _forkExecFeeWithdrawalWei();

        // ── STEP 1: fund vault owner with GM, pin performance fee ──────────
        deal(BasaltAddresses.GM_MARKET_TOKEN, vaultOwner, 100e18);
        _logStep(1, "funded vaultOwner with 100 GM, perf fee pinned at 20%");

        // ── STEP 2: first deposit — creates isolation vault + initiates async wrap ─
        _rollCooldown();
        vm.recordLogs();
        vm.startPrank(vaultOwner);
        depositHandler.deposit{value: firstDepositMsgValue}(
            IDepositHandlerVaultCore(address(vaultCore)), FIRST_DEPOSIT_GM, 500
        );
        vm.stopPrank();
        bytes32 key1 = _captureLatestAsyncDepositKey();

        assertTrue(vaultState.dolomiteIsolationVault() != address(0), "iso vault missing after step 2");
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.PENDING), "deposit not PENDING after step 2");
        _logStep(2, "first deposit 10 GM initiated, iso vault created, key1 captured");

        // ── STEP 3: simulate GMX keeper executing the wrap ─────────────────
        _simulateGmxDepositExecutionWithGm(key1, KEEPER_FIRST_WRAP_GM);
        _logStep(3, "keeper callback fired, 2 GM credited to iso position");

        // ── STEP 4: finalize deposit → NAV grows, totalDepositedUsd > 0 ────
        _rollCooldown();
        vm.warp(block.timestamp + 1);
        vm.startPrank(vaultOwner);
        depositHandler.finalizeDeposit(IDepositHandlerVaultCore(address(vaultCore)));
        vm.stopPrank();

        uint256 totalDepositedStep4 = vaultState.totalDepositedUsdE18();
        uint256 totalDepositedGmStep4 = vaultState.totalDepositedGmE18();
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.IDLE), "deposit not IDLE after step 4");
        assertGt(totalDepositedStep4, 0, "totalDepositedUsd should be > 0 after step 4");
        assertEq(totalDepositedGmStep4, FIRST_DEPOSIT_GM, "totalDepositedGm mismatch");
        _logStep(4, "finalize deposit OK, totalDepositedUsdE18:", totalDepositedStep4);

        // ── STEP 5: second deposit (Standard branch — iso vault exists + has debt) ─
        _rollCooldown();
        vm.recordLogs();
        vm.startPrank(vaultOwner);
        depositHandler.deposit{value: laterDepositExecFee}(
            IDepositHandlerVaultCore(address(vaultCore)), SECOND_DEPOSIT_GM, 500
        );
        vm.stopPrank();
        bytes32 key2 = _captureLatestAsyncDepositKey();
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.PENDING), "deposit not PENDING after step 5");
        _logStep(5, "second deposit 5 GM initiated, Standard branch, key2 captured");

        // ── STEP 6: keeper + finalize second deposit ───────────────────────
        _simulateGmxDepositExecutionWithGm(key2, KEEPER_SECOND_WRAP_GM);
        _rollCooldown();
        vm.warp(block.timestamp + 1);
        vm.startPrank(vaultOwner);
        depositHandler.finalizeDeposit(IDepositHandlerVaultCore(address(vaultCore)));
        vm.stopPrank();

        uint256 totalDepositedStep6 = vaultState.totalDepositedUsdE18();
        uint256 totalDepositedGmStep6 = vaultState.totalDepositedGmE18();
        assertGt(totalDepositedStep6, totalDepositedStep4, "totalDepositedUsd did not grow after step 6");
        assertEq(totalDepositedGmStep6, FIRST_DEPOSIT_GM + SECOND_DEPOSIT_GM, "totalDepositedGm mismatch step 6");
        _logStep(6, "keeper + finalize second deposit OK, totalDepositedUsdE18:", totalDepositedStep6);

        // ── STEP 7: owner withdraws 25% of SHARE_UNIT ──────────────────────
        uint256 shareUnit = BasaltConstants.SHARE_UNIT;
        uint256 sharesToWithdraw = shareUnit / 4; // 25%
        uint256 gmToSellE18 = _expectedGmToSellE18(sharesToWithdraw);
        uint256 minWbtcOutE8 = _minWbtcOutE8ForGmAsLongLeg(gmToSellE18, WITHDRAW_MIN_WBTC_SLIPPAGE_BPS);
        _rollCooldown();
        vm.recordLogs();
        vm.startPrank(vaultOwner);
        withdrawHandler.withdraw{value: withdrawExecFee}(
            IWithdrawHandlerVaultCore(address(vaultCore)), sharesToWithdraw, minWbtcOutE8
        );
        vm.stopPrank();
        uint8 withdrawStateAfterCall = uint8(vaultState.withdrawState());
        _logStep(7, "owner.withdraw(25%) called, withdrawState:", withdrawStateAfterCall);

        // ── STEP 8: if async path taken, simulate keeper + finalize ────────
        if (withdrawStateAfterCall == uint8(VaultState.State.PENDING)) {
            bytes32 wkey = _captureLatestWithdrawalKey();
            uint256 gmToSell = vaultState.pendingWithdrawGmToSellE18();
            uint256 wbtcReceivedByKeeper = _estimateWbtcFromGm(gmToSell);
            _simulateGmxWithdrawalExecutionWithWbtc(wkey, gmToSell, wbtcReceivedByKeeper);

            _rollCooldown();
            vm.warp(block.timestamp + 1);
            vm.startPrank(vaultOwner);
            withdrawHandler.finalizeWithdraw(IWithdrawHandlerVaultCore(address(vaultCore)));
            vm.stopPrank();
        }
        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "withdraw not IDLE after step 8");
        uint256 totalWithdrawnStep8 = vaultState.totalWithdrawnUsdE18();
        _logStep(8, "withdraw flow completed, totalWithdrawnUsdE18:", totalWithdrawnStep8);

        // ── STEP 9: invariants — HWM ≥ 0, accrued fee ≤ HWM * feeBps ───────
        uint256 hwm = vaultState.highWaterMarkProfitUsdE18();
        uint256 accrued = vaultState.managerAccruedFeeUsdE18();
        uint256 maxAllowedAccrued = (hwm * PERF_FEE_BPS) / 10_000 + 1;
        assertLe(accrued, maxAllowedAccrued, "accrued fee exceeds HWM-derived ceiling");
        _logStep(9, "HWM profit:", hwm);
        console2.log("         accrued fee:", accrued);
        console2.log("         max allowed fee:", maxAllowedAccrued);

        // ── STEP 10: final sanity — all states IDLE, accumulators monotonic ─
        assertEq(uint8(vaultState.depositState()), uint8(VaultState.State.IDLE), "deposit state not IDLE at end");
        assertEq(uint8(vaultState.withdrawState()), uint8(VaultState.State.IDLE), "withdraw state not IDLE at end");
        assertEq(uint8(vaultState.rebalanceState()), uint8(VaultState.State.IDLE), "rebalance state not IDLE at end");
        assertGe(vaultState.totalDepositedUsdE18(), totalDepositedStep6, "totalDeposited regressed");
        assertGe(vaultState.totalWithdrawnUsdE18(), totalWithdrawnStep8, "totalWithdrawn regressed");
        _logStep(10, "scenario complete - all states IDLE, accumulators monotonic");
    }

    //  INTERNAL HELPERS

    /// @dev Same pro-rata as WithdrawHandler async branch (denominator SHARE_UNIT).
    function _expectedGmToSellE18(uint256 sharesToWithdrawE18) internal view returns (uint256) {
        address iso = vaultState.dolomiteIsolationVault();
        require(iso != address(0), "iso required");
        uint256 gmCol = DolomiteReader.getActualGmCollateralE18(
            IDolomiteMargin(BasaltAddresses.DOLOMITE_MARGIN), iso
        );
        return basaltMath.calcProRataGm(gmCol, sharesToWithdrawE18, BasaltConstants.SHARE_UNIT);
    }

    /// @dev Pool-composition long leg (E8) then slippage; WithdrawHandler passes minWbtc+1 to Dolomite.
    function _minWbtcOutE8ForGmAsLongLeg(uint256 gmToSellE18, uint256 slippageBps)
        internal
        view
        returns (uint256 minWbtcOutE8)
    {
        require(slippageBps < 10_000, "slippage");
        IGmxDataStoreFork store = IGmxDataStoreFork(BasaltAddresses.GMX_DATA_STORE);
        address gm = BasaltAddresses.GM_MARKET_TOKEN;
        address wbtc = BasaltAddresses.WBTC;
        uint256 poolWbtcE8 = store.getUint(
            keccak256(abi.encode(BasaltConstants.GMX_KEY_POOL_AMOUNT, gm, wbtc))
        );
        require(poolWbtcE8 > 0, "pool wbtc");
        uint256 supply = IGmTokenGmx(gm).totalSupply();
        require(supply > 0, "gm supply");
        uint256 expLongE8 = Math.mulDiv(gmToSellE18, poolWbtcE8, supply);
        uint256 minLongAfterSlipE8 = Math.mulDiv(expLongE8, 10_000 - slippageBps, 10_000);
        require(minLongAfterSlipE8 > 0, "min long e8");
        // asyncUnwrap passes minWbtcOutE8 + 1; target Dolomite min == minLongAfterSlipE8
        minWbtcOutE8 = minLongAfterSlipE8 - 1;
    }

    function _rollCooldown() internal {
        uint256 endBlock = vaultState.globalActionCooldownEndBlock();
        if (block.number <= endBlock) {
            vm.roll(endBlock + 1);
        }
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

    /// @dev Simulate GMX executing an async deposit — deal GM to Dolomite wrapper,
    ///      prank Dolomite handler, fire the callback with `receivedMarketTokens` set.
    function _simulateGmxDepositExecutionWithGm(bytes32 key, uint256 gmReceivedE18) internal {
        deal(BasaltAddresses.GM_MARKET_TOKEN, _dolomiteGmWrapper(), gmReceivedE18);

        GmxEventUtils.EventLogData memory depositData;
        depositData.uintItems.items = new GmxEventUtils.UintKeyValue[](1);
        depositData.uintItems.items[0] = GmxEventUtils.UintKeyValue({
            key: "minMarketTokens",
            value: 1
        });

        GmxEventUtils.EventLogData memory eventData;
        eventData.uintItems.items = new GmxEventUtils.UintKeyValue[](1);
        eventData.uintItems.items[0] = GmxEventUtils.UintKeyValue({
            key: "receivedMarketTokens",
            value: gmReceivedE18
        });

        vm.prank(DOLOMITE_AUTH_HANDLER);
        IDepositCallbackReceiver(_dolomiteGmWrapper()).afterDepositExecution(
            key, depositData, eventData
        );
    }

    /// @dev Simulate GMX executing an async withdrawal — deal WBTC to Dolomite unwrapper,
    ///      prank Dolomite handler, fire callback with output amounts set.
    function _simulateGmxWithdrawalExecutionWithWbtc(bytes32 key, uint256 gmSoldE18, uint256 wbtcReceivedE8) internal {
        deal(BasaltAddresses.WBTC, GM_UNWRAPPER, wbtcReceivedE8);

        GmxEventUtils.EventLogData memory withdrawalData;
        withdrawalData.uintItems.items = new GmxEventUtils.UintKeyValue[](1);
        withdrawalData.uintItems.items[0] = GmxEventUtils.UintKeyValue({
            key: "marketTokenAmount",
            value: gmSoldE18
        });

        GmxEventUtils.EventLogData memory eventData;
        eventData.addressItems.items = new GmxEventUtils.AddressKeyValue[](2);
        eventData.addressItems.items[0] = GmxEventUtils.AddressKeyValue({
            key: "outputToken",
            value: BasaltAddresses.WBTC
        });
        eventData.addressItems.items[1] = GmxEventUtils.AddressKeyValue({
            key: "secondaryOutputToken",
            value: BasaltAddresses.WBTC
        });
        eventData.uintItems.items = new GmxEventUtils.UintKeyValue[](2);
        eventData.uintItems.items[0] = GmxEventUtils.UintKeyValue({
            key: "outputAmount",
            value: wbtcReceivedE8
        });
        eventData.uintItems.items[1] = GmxEventUtils.UintKeyValue({
            key: "secondaryOutputAmount",
            value: 0
        });

        vm.prank(DOLOMITE_AUTH_HANDLER);
        IWithdrawalCallbackReceiver(GM_UNWRAPPER).afterWithdrawalExecution(key, withdrawalData, eventData);
    }

    /// @dev Rough linear estimate of WBTC that GMX would pay out for selling `gmE18` GM
    ///      at a conservative ~1 GM ≈ 0.00002 WBTC (E8). Only used inside the keeper
    ///      simulation — real on-chain price discovery is not needed, just a non-zero value.
    function _estimateWbtcFromGm(uint256 gmE18) internal pure returns (uint256) {
        return (gmE18 * 2_000) / 1e18; // ~2000 sats per 1 GM (tiny but > dust threshold)
    }

    function _logStep(uint256 n, string memory msgStr) internal pure {
        console2.log("STEP", n, msgStr);
    }

    function _logStep(uint256 n, string memory msgStr, uint256 value) internal pure {
        console2.log("STEP", n, msgStr, value);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IDolomiteMargin} from "../interfaces/IDolomiteMargin.sol";
import {IDolomiteIsolationVault} from "../interfaces/IDolomiteVault.sol";
import {IWithdrawHandlerVaultCore} from "../interfaces/IWithdrawHandlerVaultCore.sol";
import {VaultState} from "../core/VaultState.sol";

/// @notice One-shot recovery handler for stuck PENDING withdraw.
///         Leaves 1 sat WBTC in Dolomite position so execution fee is not refunded.
contract WithdrawRecoveryHandler {
    address constant DOLOMITE_MARGIN = 0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    uint256 constant ISOLATION_ACCOUNT = 100;
    uint256 constant MARKET_WBTC = 4;

    function recover(IWithdrawHandlerVaultCore vaultCore) external {
        VaultState vaultState = VaultState(vaultCore.basaltState());
        require(vaultState.withdrawState() == VaultState.State.PENDING, "not pending");

        address withdrawer = vaultState.pendingWithdrawer();
        address isoVault = vaultState.dolomiteIsolationVault();

        // Read current WBTC surplus in ISO vault account 100
        IDolomiteMargin.Wei memory wbtcWei = IDolomiteMargin(DOLOMITE_MARGIN).getAccountWei(
            IDolomiteMargin.AccountInfo({owner: isoVault, number: ISOLATION_ACCOUNT}),
            MARKET_WBTC
        );
        require(wbtcWei.sign && wbtcWei.value > 1, "no surplus to recover");
        uint256 toWithdraw = wbtcWei.value - 1; // leave 1 sat

        // Step 1: Move (surplus - 1) WBTC from ISO position (account 100) to VaultCore (account 0)
        vaultCore.universalCall(
            msg.sender,
            isoVault,
            abi.encodeCall(
                IDolomiteIsolationVault.transferFromPositionWithOtherToken,
                (ISOLATION_ACCOUNT, 0, MARKET_WBTC, toWithdraw, uint8(3))
            ),
            0,
            false
        );

        // Step 2: Read actual WBTC wei in VaultCore account 0 (par → wei conversion)
        IDolomiteMargin.Par memory par = IDolomiteMargin(DOLOMITE_MARGIN).getAccountPar(
            IDolomiteMargin.AccountInfo({owner: address(vaultCore), number: 0}),
            MARKET_WBTC
        );
        uint256 actualE8 = 0;
        if (par.sign && par.value > 0) {
            uint256 supplyIndex = uint256(
                IDolomiteMargin(DOLOMITE_MARGIN).getMarketCurrentIndex(MARKET_WBTC).supply
            );
            actualE8 = (uint256(par.value) * supplyIndex) / 1e18;
        }
        require(actualE8 > 0, "nothing in account 0");

        // Step 3: Withdraw WBTC from Dolomite account 0 to VaultCore
        IDolomiteMargin.AccountInfo[] memory accounts = new IDolomiteMargin.AccountInfo[](1);
        accounts[0] = IDolomiteMargin.AccountInfo({owner: address(vaultCore), number: 0});

        IDolomiteMargin.ActionArgs[] memory actions = new IDolomiteMargin.ActionArgs[](1);
        actions[0] = IDolomiteMargin.ActionArgs({
            actionType: 1, // WITHDRAW
            accountId: 0,
            amount: IDolomiteMargin.AssetAmount({sign: false, denomination: 0, ref: 0, value: actualE8}),
            primaryMarketId: MARKET_WBTC,
            secondaryMarketId: 0,
            otherAddress: address(vaultCore),
            otherAccountId: 0,
            data: new bytes(0)
        });

        vaultCore.universalCall(
            msg.sender,
            DOLOMITE_MARGIN,
            abi.encodeCall(IDolomiteMargin.operate, (accounts, actions)),
            0,
            false
        );

        // Step 4: Transfer WBTC from VaultCore to withdrawer
        vaultCore.universalCall(
            msg.sender,
            WBTC,
            abi.encodeWithSelector(IERC20.transfer.selector, withdrawer, actualE8),
            0,
            false
        );

        // Step 5: Clear pending withdraw state
        vaultCore.universalCall(
            msg.sender,
            address(vaultState),
            abi.encodeCall(VaultState.clearPendingWithdrawAccounting, ()),
            0,
            false
        );
    }
}

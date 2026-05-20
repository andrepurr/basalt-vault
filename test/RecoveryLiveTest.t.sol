// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {WithdrawRecoveryHandler} from "../src/handlers/WithdrawRecoveryHandler.sol";
import {VaultState} from "../src/core/VaultState.sol";
import {IWithdrawHandlerVaultCore} from "../src/interfaces/IWithdrawHandlerVaultCore.sol";

interface IVaultCore {
    function basaltState() external view returns (address);
    function extensionHandler1() external view returns (address);
    function acceptHandler() external;
    function handlerProposal() external view returns (address oldHandler, address newHandler, bool exists);
}

/// @notice Tests the EXACT steps a user would do via Arbiscan on live state.
///         Proposal is already submitted on-chain — this test only does accept + recover.
contract RecoveryLiveTest is Test {
    address constant VAULT = 0xaCf7053e6345cE181A85583C1651d07511589E36;
    address constant RECOVERY = 0x9B9824CF4834dE8b9213e1D5E4B6C009141268e8;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address constant NFT_OWNER = 0xfb2acA261cdd28537E1b57d02a723bE7390A27f3;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
    }

    function test_userAcceptAndRecover() public {
        VaultState vs = VaultState(IVaultCore(VAULT).basaltState());

        // Pre-checks
        assertEq(uint8(vs.withdrawState()), 1, "should be PENDING");
        (address oldH, address newH, bool exists) = IVaultCore(VAULT).handlerProposal();
        assertTrue(exists, "proposal should exist");
        assertEq(newH, RECOVERY, "proposal should be for recovery handler");

        uint256 wbtcBefore = IERC20(WBTC).balanceOf(NFT_OWNER);

        // Step 1: NFT owner accepts handler (Arbiscan Write #1)
        vm.prank(NFT_OWNER);
        IVaultCore(VAULT).acceptHandler();

        // Verify handler is now in slot
        assertEq(IVaultCore(VAULT).extensionHandler1(), RECOVERY, "recovery handler should be in extensionHandler1");

        // Step 2: NFT owner calls recover (Arbiscan Write #2)
        vm.prank(NFT_OWNER);
        WithdrawRecoveryHandler(RECOVERY).recover(IWithdrawHandlerVaultCore(VAULT));

        // Post-checks
        assertEq(uint8(vs.withdrawState()), 0, "should be IDLE");
        uint256 wbtcAfter = IERC20(WBTC).balanceOf(NFT_OWNER);
        assertGt(wbtcAfter, wbtcBefore, "should have received WBTC");
        emit log_named_uint("WBTC received (sats)", wbtcAfter - wbtcBefore);
    }
}

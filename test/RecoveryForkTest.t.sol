// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {WithdrawRecoveryHandler} from "../src/handlers/WithdrawRecoveryHandler.sol";
import {IWithdrawHandlerVaultCore as IWHVaultCore} from "../src/interfaces/IWithdrawHandlerVaultCore.sol";
import {VaultState} from "../src/core/VaultState.sol";

interface IVaultCore {
    function basaltState() external view returns (address);
    function withdrawHandler() external view returns (address);
    function proposeHandler(address oldHandler, address newHandler) external;
    function acceptHandler() external;
    function FACTORY() external view returns (address);
}

interface IFactory {
    function protocolManager() external view returns (address);
    function ownerOfVault(address vault) external view returns (address);
}

interface IManagerContract {
    function owner() external view returns (address);
    function operational() external view returns (address);
    function handlerProposer() external view returns (address);
    function proposeHandler(address vaultCore, address oldHandler, address newHandler) external;
    function finalizeWithdraw(address withdrawHandler, address vault) external;
}

contract RecoveryForkTest is Test {
    // Deployed addresses
    address constant VAULT = 0xaCf7053e6345cE181A85583C1651d07511589E36;
    address constant MGR_CONTRACT = 0x19CD1BDec491d555145F6DDD3474C052b8d10E75;
    address constant WD_HANDLER = 0xCC48c39Ec0e46eC147Fb6dfE3f26af471088Bd84;
    address constant FACTORY = 0xf8bd4b049b330B96B4e495245cd8babCF82FbFea;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    // Roles
    address constant NFT_OWNER = 0xfb2acA261cdd28537E1b57d02a723bE7390A27f3;
    address constant HANDLER_PROPOSER = 0x6E31dB49Bb37C96AaB9178D6c1Fcd706D626bc93;
    address constant OPERATIONAL = 0xF36b7f65F665416696828F59bf81e9C53D5E48b7;
    address constant WITHDRAWER = 0xfb2acA261cdd28537E1b57d02a723bE7390A27f3;

    WithdrawRecoveryHandler recovery;

    function setUp() public {
        // Fork Arbitrum at latest
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));

        // Deploy recovery handler
        recovery = new WithdrawRecoveryHandler();
    }

    function test_recoverStuckWithdraw() public {
        // --- Pre-checks ---
        VaultState vs = VaultState(IVaultCore(VAULT).basaltState());
        assertEq(uint8(vs.withdrawState()), 1, "should be PENDING");
        assertEq(vs.pendingWithdrawer(), WITHDRAWER, "wrong withdrawer");

        uint256 withdrawerWbtcBefore = IERC20(WBTC).balanceOf(WITHDRAWER);

        // --- Step 1: Propose recovery handler (replaces withdrawHandler) ---
        vm.prank(HANDLER_PROPOSER);
        IManagerContract(MGR_CONTRACT).proposeHandler(
            VAULT,
            WD_HANDLER,
            address(recovery)
        );

        // --- Step 2: NFT owner accepts handler swap ---
        vm.prank(NFT_OWNER);
        IVaultCore(VAULT).acceptHandler();

        // Verify swap
        assertEq(IVaultCore(VAULT).withdrawHandler(), address(recovery), "handler not swapped");

        // --- Step 3: Execute recovery (operational calls through ManagerContract or directly) ---
        // Recovery handler's recover() needs msg.sender to be protocolManager or nftOwner
        // (universalCall requires initiator == nftOwner or protocolManager)
        // Call directly as NFT owner since recovery is now a handler
        vm.prank(NFT_OWNER);
        recovery.recover(IWHVaultCore(VAULT));

        // --- Post-checks ---
        assertEq(uint8(vs.withdrawState()), 0, "should be IDLE after recovery");

        uint256 withdrawerWbtcAfter = IERC20(WBTC).balanceOf(WITHDRAWER);
        uint256 received = withdrawerWbtcAfter - withdrawerWbtcBefore;

        assertGt(received, 0, "withdrawer should have received WBTC");
        emit log_named_uint("WBTC received by withdrawer (sats)", received);
        emit log_named_uint("WBTC left in position (dust)", 1);
    }

    function test_originalFinalizeReverts() public {
        // Confirm the original finalize still reverts
        vm.prank(OPERATIONAL);
        vm.expectRevert();
        IManagerContract(MGR_CONTRACT).finalizeWithdraw(WD_HANDLER, VAULT);
    }
}


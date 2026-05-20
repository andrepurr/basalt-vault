// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";
import {NotAuthorisedToFinalizeProposal} from "../../src/core/managerContractLibraries/ManagerContractTypes.sol";
import {VaultCoreNftFactory} from "../../src/core/VaultCoreNftFactory.sol";
import {InitialCoreAddressBook} from "../../src/core/InitialCoreAddressBook.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";
import {DepositHandler} from "../../src/handlers/DepositHandler.sol";
import {WithdrawHandler} from "../../src/handlers/WithdrawHandler.sol";
import {ManagerHandler} from "../../src/handlers/ManagerHandler.sol";
import {AsyncRecoveryHandler} from "../../src/handlers/AsyncRecoveryHandler.sol";
import {FeeAccountingHandler} from "../../src/handlers/FeeAccountingHandler.sol";

/// @title GovernanceFinalizeAcl
/// @notice REGRESSION tests for the BAS audit ACL on `executeProtocolManagerChange` /
///         `cancelProtocolManagerChange`. Pre-fix both functions were permissionless once the
///         vote threshold was met. Post-fix they require the caller to be either a snapshot
///         holder (`getPastVotes(msg.sender, snapshot) > 0`) or the `operational` role.
///         File: src/core/ManagerContract.sol _requireSnapshotHolderOrOperational
contract GovernanceFinalizeAclTest is Test {
    address deployer = makeAddr("deployer");
    address holder = makeAddr("holder");
    address otherHolder = makeAddr("otherHolder");
    address operational = makeAddr("operational");
    address stranger = makeAddr("stranger");

    FeeSplitter feeSplitter;
    ManagerContract managerContract;
    VaultCoreNftFactory factory;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) rpc = vm.envOr("LOCAL_RPC_URL", string(""));
        if (bytes(rpc).length == 0) rpc = vm.envString("ARBITRUM_RPC_URL");
        vm.createSelectFork(rpc);

        vm.startPrank(deployer);
        IERC20[] memory tokens = new IERC20[](0);
        feeSplitter = new FeeSplitter(deployer, tokens);
        // Holder gets 90% so quorum (80%) is reachable from one signer.
        feeSplitter.transfer(holder, 0.9e18);
        // otherHolder picks up a non-zero crumb so they have snapshot weight (used as alt-signer).
        feeSplitter.transfer(otherHolder, 0.05e18);

        managerContract = new ManagerContract(address(feeSplitter));
        feeSplitter.setManagerContract(address(managerContract));
        managerContract.setOperational(operational);
        vm.stopPrank();

        BasaltMath basaltMath = new BasaltMath();
        DepositHandler depositHandler = new DepositHandler();
        WithdrawHandler withdrawHandler = new WithdrawHandler();
        ManagerHandler managerHandler = new ManagerHandler();
        AsyncRecoveryHandler asyncRecoveryHandler =
            new AsyncRecoveryHandler(address(0), address(0), address(0));
        FeeAccountingHandler feeAccountingHandler = new FeeAccountingHandler();

        InitialCoreAddressBook addressBook = new InitialCoreAddressBook(
            InitialCoreAddressBook.InitialCoreAddresses({
                vaultCore: address(new VaultCore()),
                depositHandler: address(depositHandler),
                withdrawHandler: address(withdrawHandler),
                managerHandler: address(managerHandler),
                asyncRecoveryHandler: address(asyncRecoveryHandler),
                feeAccountingHandler: address(feeAccountingHandler),
                extensionHandler1: address(1),
                extensionHandler2: address(2),
                extensionHandler3: address(3),
                basaltState: address(new VaultState()),
                basaltMath: address(basaltMath),
                dolomiteVault: BasaltAddresses.VAULT_FACTORY
            })
        );

        factory = new VaultCoreNftFactory(addressBook, deployer, address(managerContract));
        vm.roll(block.number + 2);
    }

    // ──────────────────────────────────────────────────────────────────────
    //  EXECUTE
    // ──────────────────────────────────────────────────────────────────────

    function test_execute_asStranger_reverts() public {
        uint256 proposalId = _proposeAndPassYesQuorum();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(NotAuthorisedToFinalizeProposal.selector, stranger)
        );
        managerContract.executeProtocolManagerChange(proposalId);
        // Proposal remains unexecuted after revert
        (,,,,, bool executed,) = managerContract.protocolManagerProposals(proposalId);
        assertEq(executed, false, "proposal not executed after stranger revert");
    }

    function test_execute_asSnapshotHolder_succeeds() public {
        uint256 proposalId = _proposeAndPassYesQuorum();
        address expected = _readProposalNextManager(proposalId);
        // Same proposal — `holder` voted YES and has snapshot weight; can finalize.
        vm.prank(holder);
        managerContract.executeProtocolManagerChange(proposalId);
        // Confirm the side-effects.
        assertEq(factory.protocolManager(), expected, "protocolManager rotated");
        (,,,,, bool executed,) = managerContract.protocolManagerProposals(proposalId);
        assertEq(executed, true, "proposal marked as executed");
    }

    function test_execute_asOtherSnapshotHolder_succeeds() public {
        uint256 proposalId = _proposeAndPassYesQuorum();
        address expected = _readProposalNextManager(proposalId);
        // otherHolder did NOT sign yes but has 5% snapshot weight — still authorised to finalize.
        vm.prank(otherHolder);
        managerContract.executeProtocolManagerChange(proposalId);
        assertEq(factory.protocolManager(), expected, "protocolManager rotated by otherHolder");
        (,,,,, bool executed,) = managerContract.protocolManagerProposals(proposalId);
        assertEq(executed, true, "proposal marked as executed");
    }

    function test_execute_asOperational_succeeds() public {
        uint256 proposalId = _proposeAndPassYesQuorum();
        address expected = _readProposalNextManager(proposalId);
        vm.prank(operational);
        managerContract.executeProtocolManagerChange(proposalId);
        assertEq(factory.protocolManager(), expected, "protocolManager rotated by operational");
        (,,,,, bool executed,) = managerContract.protocolManagerProposals(proposalId);
        assertEq(executed, true, "proposal marked as executed");
    }

    // ──────────────────────────────────────────────────────────────────────
    //  CANCEL
    // ──────────────────────────────────────────────────────────────────────

    function test_cancel_asStranger_reverts() public {
        uint256 proposalId = _proposeAndPassCancelQuorum();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(NotAuthorisedToFinalizeProposal.selector, stranger)
        );
        managerContract.cancelProtocolManagerChange(proposalId);
        // Proposal remains not cancelled after revert
        (,,,,,, bool cancelled) = managerContract.protocolManagerProposals(proposalId);
        assertEq(cancelled, false, "proposal not cancelled after stranger revert");
    }

    function test_cancel_asSnapshotHolder_succeeds() public {
        uint256 proposalId = _proposeAndPassCancelQuorum();
        vm.prank(holder);
        managerContract.cancelProtocolManagerChange(proposalId);
        (,,,, , , bool cancelled) = managerContract.protocolManagerProposals(proposalId);
        assertTrue(cancelled, "proposal should be cancelled");
    }

    function test_cancel_asOperational_succeeds() public {
        uint256 proposalId = _proposeAndPassCancelQuorum();
        vm.prank(operational);
        managerContract.cancelProtocolManagerChange(proposalId);
        (,,,, , , bool cancelled) = managerContract.protocolManagerProposals(proposalId);
        assertTrue(cancelled, "proposal should be cancelled");
    }

    // ──────────────────────────────────────────────────────────────────────
    //  SETUP HELPERS
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Open a proposal, advance the snapshot block, then have `holder` sign YES (90% weight ≥ 80% threshold).
    function _proposeAndPassYesQuorum() internal returns (uint256 proposalId) {
        address newManager = makeAddr("newManagerYes");
        vm.prank(holder);
        proposalId = managerContract.proposeProtocolManagerChange(factory, newManager);

        vm.roll(block.number + 1);

        vm.prank(holder);
        managerContract.signProtocolManagerChange(proposalId);
    }

    function _proposeAndPassCancelQuorum() internal returns (uint256 proposalId) {
        address newManager = makeAddr("newManagerCancel");
        vm.prank(holder);
        proposalId = managerContract.proposeProtocolManagerChange(factory, newManager);

        vm.roll(block.number + 1);

        vm.prank(holder);
        managerContract.signProtocolManagerChangeCancel(proposalId);
    }

    /// @dev Read `proposal.nextProtocolManager` from the public mapping for assertions.
    function _readProposalNextManager(uint256 proposalId) internal view returns (address) {
        (, address nextProtocolManager,,,,,) = managerContract.protocolManagerProposals(proposalId);
        return nextProtocolManager;
    }
}

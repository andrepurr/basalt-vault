// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";
import {AlreadySignedOpposite} from "../../src/core/managerContractLibraries/ManagerContractTypes.sol";
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

/// @title VotingDualSign — REGRESSION
/// @notice Pre-fix: `signProtocolManagerChange` and `signProtocolManagerChangeCancel` each
///         only checked their own mapping. A single holder could sign BOTH yes AND cancel on
///         the same proposal, double-counting their weight and creating a governance race
///         (yesWeight + cancelWeight > pastSupply).
///
///         Post-fix: each function additionally checks the OPPOSITE mapping and reverts with
///         `AlreadySignedOpposite` if the holder already voted on the other side.
///
///         File: src/core/ManagerContract.sol signProtocolManagerChange / signProtocolManagerChangeCancel
contract VotingDualSignTest is Test {
    address deployer = makeAddr("deployer");
    address holder = makeAddr("holder");
    address attacker = makeAddr("attacker");

    FeeSplitter feeSplitter;
    ManagerContract managerContract;
    VaultCoreNftFactory factory;

    function setUp() public {
        // Fork Arbitrum to have real addresses
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) rpc = vm.envOr("LOCAL_RPC_URL", string(""));
        if (bytes(rpc).length == 0) rpc = vm.envString("ARBITRUM_RPC_URL");
        vm.createSelectFork(rpc);

        vm.startPrank(deployer);

        // Deploy FeeSplitter giving 100% shares to deployer
        IERC20[] memory tokens = new IERC20[](0);
        feeSplitter = new FeeSplitter(deployer, tokens);

        // Transfer 80% to holder (who will be the attacker in test_dualSign)
        feeSplitter.transfer(holder, 0.8e18); // 80% of 1e18

        vm.stopPrank();

        // Deploy ManagerContract — auto-wire to FeeSplitter was removed; deployer must bind explicitly.
        vm.prank(deployer);
        managerContract = new ManagerContract(address(feeSplitter));
        vm.prank(deployer);
        feeSplitter.setManagerContract(address(managerContract));

        // Deploy minimal factory infrastructure
        BasaltMath basaltMath = new BasaltMath();
        DepositHandler depositHandler = new DepositHandler();
        WithdrawHandler withdrawHandler = new WithdrawHandler();
        ManagerHandler managerHandler = new ManagerHandler();
        AsyncRecoveryHandler asyncRecoveryHandler = new AsyncRecoveryHandler(address(0), address(0), address(0));
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

        // Advance 2 blocks so snapshot is available
        vm.roll(block.number + 2);
    }

    /// @notice REGRESSION: holder votes YES first, then attempts CANCEL — second call reverts.
    function test_regression_yesThenCancel_reverts() public {
        uint256 holderVotes = feeSplitter.getVotes(holder);
        assertEq(holderVotes, 0.8e18, "holder should have 80% votes");

        address newManager = makeAddr("newManager");
        vm.prank(holder);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(factory, newManager);

        vm.roll(block.number + 1);

        // First side passes.
        vm.prank(holder);
        managerContract.signProtocolManagerChange(proposalId);

        // Opposite side reverts with AlreadySignedOpposite.
        vm.prank(holder);
        vm.expectRevert(AlreadySignedOpposite.selector);
        managerContract.signProtocolManagerChangeCancel(proposalId);

        // yesWeight stays at the holder's full weight; cancelWeight stays 0.
        (,,, uint256 yesWeight, uint256 cancelWeight,,) = managerContract.protocolManagerProposals(proposalId);
        assertEq(yesWeight, 0.8e18, "yesWeight = holder's full weight");
        assertEq(cancelWeight, 0, "cancelWeight blocked at 0");
    }

    /// @notice REGRESSION: symmetric — CANCEL first, then YES — second call reverts.
    function test_regression_cancelThenYes_reverts() public {
        address newManager = makeAddr("newManagerSymmetric");
        vm.prank(holder);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(factory, newManager);

        vm.roll(block.number + 1);

        vm.prank(holder);
        managerContract.signProtocolManagerChangeCancel(proposalId);

        vm.prank(holder);
        vm.expectRevert(AlreadySignedOpposite.selector);
        managerContract.signProtocolManagerChange(proposalId);

        (,,, uint256 yesWeight, uint256 cancelWeight,,) = managerContract.protocolManagerProposals(proposalId);
        assertEq(yesWeight, 0, "yesWeight blocked at 0");
        assertEq(cancelWeight, 0.8e18, "cancelWeight = holder's full weight");
    }

    /// @notice REGRESSION: total participation never exceeds 100% across yes + cancel.
    function test_regression_totalParticipationCappedAtSupply() public {
        // 50/30/20 split: holder→50, attacker→30, deployer→20
        vm.prank(holder);
        feeSplitter.transfer(attacker, 0.3e18);

        vm.roll(block.number + 2);

        address newManager = makeAddr("newManagerCap");
        vm.prank(attacker);
        uint256 proposalId = managerContract.proposeProtocolManagerChange(factory, newManager);

        vm.roll(block.number + 1);

        // Attacker signs YES.
        vm.prank(attacker);
        managerContract.signProtocolManagerChange(proposalId);

        // Attacker tries CANCEL on top — reverts.
        vm.prank(attacker);
        vm.expectRevert(AlreadySignedOpposite.selector);
        managerContract.signProtocolManagerChangeCancel(proposalId);

        // Holder signs YES (legit).
        vm.prank(holder);
        managerContract.signProtocolManagerChange(proposalId);

        // yesWeight = 30 + 50 = 80; cancelWeight = 0; sum = 80 ≤ 100.
        (,,, uint256 yesWeight, uint256 cancelWeight,,) = managerContract.protocolManagerProposals(proposalId);
        assertEq(yesWeight, 0.8e18, "yesWeight = 80%");
        assertEq(cancelWeight, 0, "cancelWeight = 0");
        assertLe(yesWeight + cancelWeight, 1e18, "total participation <= 100% of supply");
    }
}

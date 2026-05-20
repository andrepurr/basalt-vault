// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {
    NotInitialOwner,
    NotManagerContract,
    ManagerContractAlreadySet
} from "../../src/core/feeSplitterLibraries/FeeSplitterTypes.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";

/// @title FeeSplitterSetManagerFrontrun — REGRESSION
/// @notice Pre-fix: `FeeSplitter.setManagerContract` had no caller ACL, only the one-shot guard.
///         Between FeeSplitter deploy and ManagerContract deploy, an attacker could front-run
///         the binding and seize admin rights over the tracked-token list.
///
///         Post-fix: only `initialOwner` (msg.sender at FeeSplitter constructor time) may call
///         `setManagerContract`. Any other caller reverts with `NotInitialOwner`.
///         Auto-wire from `ManagerContract.constructor` was removed for the same reason —
///         the deployer must explicitly call `feeSplitter.setManagerContract(address(mc))`
///         in the same broadcast as FS deployment.
///
///         File: src/core/FeeSplitter.sol setManagerContract
contract FeeSplitterSetManagerFrontrunTest is Test {
    address deployer = makeAddr("deployer");
    address attacker = makeAddr("attacker");

    /// @notice REGRESSION: attacker frontrunning the binding now reverts with NotInitialOwner.
    function test_regression_attackerFrontrunReverts() public {
        vm.prank(deployer);
        IERC20[] memory tokens = new IERC20[](0);
        FeeSplitter splitter = new FeeSplitter(deployer, tokens);

        assertEq(splitter.managerContract(), address(0));
        assertEq(splitter.initialOwner(), deployer, "initialOwner captured at FS deploy");

        // Attacker tries to seize the binding — reverts because msg.sender != initialOwner.
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(NotInitialOwner.selector, attacker));
        splitter.setManagerContract(attacker);

        // Binding still empty — deployer can complete it.
        assertEq(splitter.managerContract(), address(0));
        vm.prank(deployer);
        ManagerContract mc = new ManagerContract(address(splitter));
        vm.prank(deployer);
        splitter.setManagerContract(address(mc));
        assertEq(splitter.managerContract(), address(mc));
    }

    /// @notice REGRESSION: even after deployer binds, attacker still can't poison tracked tokens.
    function test_regression_attackerCannotAddTrackedTokensAfterFix() public {
        vm.prank(deployer);
        IERC20[] memory tokens = new IERC20[](0);
        FeeSplitter splitter = new FeeSplitter(deployer, tokens);

        // Deployer follows the new explicit-binding flow.
        vm.prank(deployer);
        ManagerContract mc = new ManagerContract(address(splitter));
        vm.prank(deployer);
        splitter.setManagerContract(address(mc));

        // Attacker cannot call addTrackedToken — only managerContract can.
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(NotManagerContract.selector, attacker));
        splitter.addTrackedToken(IERC20(address(0xdead)));

        // Attacker also cannot rebind setManagerContract (already set).
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(NotInitialOwner.selector, attacker));
        splitter.setManagerContract(attacker);

        // Even initialOwner (deployer) cannot rebind — write-once.
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(ManagerContractAlreadySet.selector, address(mc))
        );
        splitter.setManagerContract(address(0xCAFE));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";
import {NotAuthorisedToCollectFees} from "../../src/core/managerContractLibraries/ManagerContractTypes.sol";

/// @title ManagerCollectFeesTwentyVaultCores
/// @notice Integration: simulate 20 distinct notional `VaultCore` addresses each pushing fee token to
///         `ManagerContract`; the canonical fee-share holder OR `operational` runs `collectFees`
///         → `FeeSplitter`. `collectFees` is restricted (BAS audit fix): only holders or operational.
contract ManagerCollectFeesTwentyVaultCores is Test {
    uint256 internal constant N_VAULTS = 20;
    uint256 internal constant FEE_PER_VAULT = 50e18;
    address internal me;

    function setUp() public {
        me = address(this);
    }

    function _hub() internal returns (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) {
        token = new ERC20Mock();
        IERC20[] memory t = new IERC20[](1);
        t[0] = IERC20(address(token));
        splitter = new FeeSplitter(me, t);
        mgr = new ManagerContract(address(splitter));
        // Auto-wire removed from MC.constructor; deployer (initialOwner) binds explicitly.
        splitter.setManagerContract(address(mgr));
    }

    function _vaultCores() internal pure returns (address[N_VAULTS] memory a) {
        for (uint256 i; i < N_VAULTS; i++) {
            a[i] = address(uint160(uint256(keccak256(abi.encode("NOTIONAL_VAULT_CORE", i)))));
        }
    }

    function test_integration_twentyNotionalVaultCores_sweepInOneCollect() public {
        (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) = _hub();
        address[N_VAULTS] memory vaults = _vaultCores();
        uint256 total;

        for (uint256 i; i < N_VAULTS; i++) {
            address v = vaults[i];
            token.mint(v, FEE_PER_VAULT);
            vm.prank(v);
            token.transfer(address(mgr), FEE_PER_VAULT);
            total += FEE_PER_VAULT;
        }
        assertEq(token.balanceOf(address(mgr)), total);
        assertGt(total, 0);

        // Random EOA (no shares, not operational) is rejected by `collectFees` ACL.
        address bot = makeAddr("permissionlessSweeper");
        vm.prank(bot);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorisedToCollectFees.selector, bot));
        mgr.collectFees(_single(IERC20(address(token))));

        // The fee-share holder (`me` holds full TOTAL_SHARES) can sweep.
        mgr.collectFees(_single(IERC20(address(token))));

        assertEq(token.balanceOf(address(mgr)), 0);
        assertEq(token.balanceOf(address(splitter)), total);
    }

    function test_integration_twentyVaultCores_collectAfterEachTransfer_operational() public {
        (ERC20Mock token, FeeSplitter splitter, ManagerContract mgr) = _hub();
        address operational = makeAddr("operational");
        vm.prank(mgr.owner());
        mgr.setOperational(operational);

        address[N_VAULTS] memory vaults = _vaultCores();
        IERC20 pay = IERC20(address(token));
        uint256 expected;

        for (uint256 i; i < N_VAULTS; i++) {
            address v = vaults[i];
            token.mint(v, FEE_PER_VAULT);
            vm.prank(v);
            token.transfer(address(mgr), FEE_PER_VAULT);
            expected += FEE_PER_VAULT;

            vm.prank(operational);
            mgr.collectFees(_single(pay));

            assertEq(
                token.balanceOf(address(mgr)), 0, "manager should be swept clean each round"
            );
            assertEq(
                token.balanceOf(address(splitter)),
                expected,
                "splitter accrual matches cumulative notional fees"
            );
        }
    }

    function _single(IERC20 t) private pure returns (IERC20[] memory a) {
        a = new IERC20[](1);
        a[0] = t;
    }
}

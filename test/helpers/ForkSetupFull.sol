// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {FeeSplitter} from "../../src/core/FeeSplitter.sol";
import {InitialCoreAddressBook} from "../../src/core/InitialCoreAddressBook.sol";
import {ManagerContract} from "../../src/core/ManagerContract.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultCoreNftFactory} from "../../src/core/VaultCoreNftFactory.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {AsyncRecoveryHandler} from "../../src/handlers/AsyncRecoveryHandler.sol";
import {DepositHandler} from "../../src/handlers/DepositHandler.sol";
import {FeeAccountingHandler} from "../../src/handlers/FeeAccountingHandler.sol";
import {ManagerHandler} from "../../src/handlers/ManagerHandler.sol";
import {WithdrawHandler} from "../../src/handlers/WithdrawHandler.sol";
import {
    GmxEventUtils,
    IDepositCallbackReceiver,
    IWithdrawalCallbackReceiver
} from "../../src/interfaces/IGmxCallbackReceiver.sol";
import {IGmxV2Registry} from "../../src/interfaces/IDolomiteAsyncTraders.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";

/// @dev Distinct inert handler slots for extension surfaces that do not exist in this workspace snapshot.
contract ForkSetupFullNoopExtensionHandler {}

/// @title ForkSetupFull
/// @notice Production-like Arbitrum fork fixture: real handlers, address book, factory clones, governance hub,
///         deterministic actors, and GMX keeper callback simulation helpers.
abstract contract ForkSetupFull is Test {

    uint256 internal constant FORK_BLOCK = 450_995_113;
    uint256 internal constant ACTOR_ETH_BALANCE = 100 ether;
    /// @dev `script/helpers/exec-fee.py --fee <op> <mult%>`; default 130% matches `exec-fee.py` CLI.
    uint256 internal constant FORK_EXEC_FEE_SAFETY_PCT = 130;
    uint256 internal constant FIRST_DEPOSIT_EXTRA_ETH_WEI = 0.001 ether;

    address internal constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    address internal factoryOwner;
    address internal vaultOwner;
    address internal keeper;
    address internal configurator;
    address internal operational;
    address internal feeCollector;
    address internal stranger;

    BasaltMath internal basaltMath;
    DepositHandler internal depositHandler;
    WithdrawHandler internal withdrawHandler;
    ManagerHandler internal managerHandler;
    AsyncRecoveryHandler internal asyncRecoveryHandler;
    FeeAccountingHandler internal feeAccountingHandler;

    ForkSetupFullNoopExtensionHandler internal extensionHandler1;
    ForkSetupFullNoopExtensionHandler internal extensionHandler2;
    ForkSetupFullNoopExtensionHandler internal extensionHandler3;

    InitialCoreAddressBook internal initialCoreAddressBook;
    FeeSplitter internal feeSplitter;
    ManagerContract internal managerContract;
    VaultCoreNftFactory internal vaultCoreNftFactory;
    uint256 internal vaultTokenId;
    VaultCore internal vaultCore;
    VaultState internal vaultState;

    ERC20Mock internal shareToken;

    function setUp() public virtual {
        _selectArbitrumFork();
        _initActors();
        _deployFullCoreStack();
        cachedDolomiteGmWrapper =
            IGmxV2Registry(BasaltAddresses.GMX_V2_REGISTRY).getWrapperByToken(BasaltAddresses.VAULT_FACTORY);
    }

    function _selectArbitrumFork() internal {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            rpc = vm.envOr("LOCAL_RPC_URL", string(""));
        }
        if (bytes(rpc).length == 0) {
            rpc = vm.envString("ARBITRUM_RPC_URL");
        }
        if (_isLocalAnvil(rpc)) {
            vm.createSelectFork(rpc);
        } else {
            vm.createSelectFork(rpc, FORK_BLOCK);
        }
        require(block.chainid == 42_161, "ForkSetupFull: expected Arbitrum One");
    }

    function _isLocalAnvil(string memory rpc) internal pure returns (bool) {
        bytes32 h = keccak256(bytes(rpc));
        return h == keccak256(bytes("http://127.0.0.1:8545")) || h == keccak256(bytes("http://localhost:8545"));
    }

    function _initActors() internal {
        factoryOwner = address(uint160(0x1001));
        vaultOwner = address(uint160(0x1002));
        keeper = address(uint160(0x1003));
        configurator = address(uint160(0x1004));
        operational = address(uint160(0x1005));
        feeCollector = address(uint160(0x1006));
        stranger = address(uint160(0x1007));
    }

    function _deployFullCoreStack() internal {
        basaltMath = new BasaltMath();
        depositHandler = new DepositHandler();
        withdrawHandler = new WithdrawHandler();
        managerHandler = new ManagerHandler();
        asyncRecoveryHandler = new AsyncRecoveryHandler(address(0), address(0), address(0));
        feeAccountingHandler = new FeeAccountingHandler();
        extensionHandler1 = new ForkSetupFullNoopExtensionHandler();
        extensionHandler2 = new ForkSetupFullNoopExtensionHandler();
        extensionHandler3 = new ForkSetupFullNoopExtensionHandler();

        initialCoreAddressBook = new InitialCoreAddressBook(
            InitialCoreAddressBook.InitialCoreAddresses({
                vaultCore: address(new VaultCore()),
                depositHandler: address(depositHandler),
                withdrawHandler: address(withdrawHandler),
                managerHandler: address(managerHandler),
                asyncRecoveryHandler: address(asyncRecoveryHandler),
                feeAccountingHandler: address(feeAccountingHandler),
                extensionHandler1: address(extensionHandler1),
                extensionHandler2: address(extensionHandler2),
                extensionHandler3: address(extensionHandler3),
                basaltState: address(new VaultState()),
                basaltMath: address(basaltMath),
                dolomiteVault: BasaltAddresses.VAULT_FACTORY
            })
        );

        // Seed with the same 4 canonical reward tokens used in mainnet deploy so fork tests can drive
        // the real `collectFees` / `release` flows through USDC / GM / WETH / WBTC without extra wiring.
        IERC20[] memory initialTrackedTokens = new IERC20[](4);
        initialTrackedTokens[0] = IERC20(BasaltAddresses.USDC);
        initialTrackedTokens[1] = IERC20(BasaltAddresses.GM_MARKET_TOKEN);
        initialTrackedTokens[2] = IERC20(BasaltAddresses.WETH);
        initialTrackedTokens[3] = IERC20(BasaltAddresses.WBTC);
        feeSplitter = new FeeSplitter(factoryOwner, initialTrackedTokens);
        managerContract = new ManagerContract(address(feeSplitter));
        feeSplitter.setManagerContract(address(managerContract));
        vaultCoreNftFactory = new VaultCoreNftFactory(initialCoreAddressBook, factoryOwner, address(managerContract));

        vm.startPrank(managerContract.owner());
        managerContract.setConfigurator(configurator);
        managerContract.setOperational(operational);
        managerContract.proposeFeeCollector(feeCollector);
        vm.stopPrank();

        vm.prank(feeCollector);
        managerContract.acceptFeeCollector();

        (vaultTokenId, vaultCore) = _createVaultCore(vaultOwner);
        vaultState = VaultState(vaultCore.basaltState());

        shareToken = new ERC20Mock();
    }

    function _createVaultCore(address owner) internal returns (uint256 tokenId, VaultCore createdVaultCore) {
        (uint256 id, address vaultCoreAddress) = vaultCoreNftFactory.createVaultCore(owner);
        return (id, VaultCore(payable(vaultCoreAddress)));
    }

    function _fundActor(address actor) internal {
        vm.deal(actor, ACTOR_ETH_BALANCE);
    }

    address internal cachedDolomiteGmWrapper;

    function _dolomiteGmWrapper() internal returns (address) {
        if (cachedDolomiteGmWrapper == address(0)) {
            cachedDolomiteGmWrapper =
                IGmxV2Registry(BasaltAddresses.GMX_V2_REGISTRY).getWrapperByToken(BasaltAddresses.VAULT_FACTORY);
        }
        return cachedDolomiteGmWrapper;
    }

    /// @dev GMX execution fee at fork block 450_995_113 (deposit, 130% safety).
    ///      Value from InsufficientExecutionFee revert on this fork block.
    ///      Replaces vm.ffi("exec-fee.py") to avoid --ffi requirement.
    uint256 private constant EXEC_FEE_WEI = 10_700_000_000_000_000; // 0.0107 ETH

    function _forkExecFeeDepositWei() internal pure returns (uint256) {
        return EXEC_FEE_WEI;
    }

    function _forkExecFeeWithdrawalWei() internal pure returns (uint256) {
        return EXEC_FEE_WEI;
    }

    /// @dev 0.001 ETH (product) + full execution fee from `exec-fee.py` (deposit, 130%).
    function _firstDepositMsgValue() internal returns (uint256) {
        return FIRST_DEPOSIT_EXTRA_ETH_WEI + _forkExecFeeDepositWei();
    }

    function _simulateGmxDepositExecution(address callbackReceiver, bytes32 key) internal {
        GmxEventUtils.EventLogData memory depositData;
        GmxEventUtils.EventLogData memory eventData;
        vm.prank(BasaltAddresses.GMX_DEPOSIT_HANDLER);
        IDepositCallbackReceiver(callbackReceiver).afterDepositExecution(key, depositData, eventData);
    }

    function _simulateGmxDepositCancellation(address callbackReceiver, bytes32 key) internal {
        GmxEventUtils.EventLogData memory depositData;
        GmxEventUtils.EventLogData memory eventData;
        vm.prank(BasaltAddresses.GMX_DEPOSIT_HANDLER);
        IDepositCallbackReceiver(callbackReceiver).afterDepositCancellation(key, depositData, eventData);
    }

    function _simulateGmxWithdrawalExecution(address callbackReceiver, bytes32 key) internal {
        GmxEventUtils.EventLogData memory withdrawalData;
        GmxEventUtils.EventLogData memory eventData;
        vm.prank(BasaltAddresses.GMX_WITHDRAWAL_HANDLER);
        IWithdrawalCallbackReceiver(callbackReceiver).afterWithdrawalExecution(key, withdrawalData, eventData);
    }

    function _simulateGmxWithdrawalCancellation(address callbackReceiver, bytes32 key) internal {
        GmxEventUtils.EventLogData memory withdrawalData;
        GmxEventUtils.EventLogData memory eventData;
        vm.prank(BasaltAddresses.GMX_WITHDRAWAL_HANDLER);
        IWithdrawalCallbackReceiver(callbackReceiver).afterWithdrawalCancellation(key, withdrawalData, eventData);
    }
}

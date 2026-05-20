// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {BasaltAddresses} from "../src/libraries/BasaltAddresses.sol";
import {BasaltMath} from "../src/pure/BasaltMath.sol";

import {DepositHandler} from "../src/handlers/DepositHandler.sol";
import {WithdrawHandler} from "../src/handlers/WithdrawHandler.sol";
import {ManagerHandler} from "../src/handlers/ManagerHandler.sol";
import {AsyncRecoveryHandler} from "../src/handlers/AsyncRecoveryHandler.sol";
import {FeeAccountingHandler} from "../src/handlers/FeeAccountingHandler.sol";

import {VaultCore} from "../src/core/VaultCore.sol";
import {VaultState} from "../src/core/VaultState.sol";
import {InitialCoreAddressBook} from "../src/core/InitialCoreAddressBook.sol";
import {FeeSplitter} from "../src/core/FeeSplitter.sol";
import {ManagerContract} from "../src/core/ManagerContract.sol";
import {VaultCoreNftFactory} from "../src/core/VaultCoreNftFactory.sol";

import {BasaltZapIn} from "../src/ux/BasaltZapIn.sol";
import {BasaltZapOut} from "../src/ux/BasaltZapOut.sol";
import {BasaltGmUnwrapper} from "../src/ux/BasaltGmUnwrapper.sol";

/// @title  DeployMainnet
/// @notice One-shot deployment of the full Basalt Vault system to Arbitrum One
///         for the canary test. Broadcasts the factory (NFT-per-vault),
///         stateless handler singletons, and the thin stateless Zap wrappers.
///
/// ## Execution
///
/// Target: Arbitrum One (chainId 42161). `run()` reverts on any other chain.
///
/// Required env:
///   - `PRIVATE_KEY`    (or equivalent Foundry wallet flag) — funds ~0.05 ETH
///   - `PROTOCOL_OWNER` — future owner of ManagerContract + VaultCoreNftFactory.
///                       Defaults to deployer if unset.
///
/// ```bash
/// forge script script/DeployMainnet.s.sol:DeployMainnet \
///   --rpc-url "$ARBITRUM_ONE_RPC_URL" \
///   --broadcast
/// ```
///
/// Add `--verify --verifier-url https://api.arbiscan.io/api --etherscan-api-key "$ARBISCAN_API_KEY"`
/// for source verification.
///
/// ## Architecture notes
///
/// - Handlers (`DepositHandler`, `WithdrawHandler`, `ManagerHandler`,
///   `AsyncRecoveryHandler`, `FeeAccountingHandler`) are **stateless
///   singletons** — each vault clone points at these shared implementations
///   through the `InitialCoreAddressBook`.
/// - `VaultCore` and `VaultState` are deployed once as **clone
///   implementations**; per-user vaults are minted lazily through
///   `VaultCoreNftFactory.issueVault(...)` and are not created here.
/// - Extension handler slots (`extensionHandler1/2/3`) are intentionally
///   left as `address(0)` for the canary — governance can rotate real
///   extensions in via the factory's address-book cooldown mechanism.
/// - `Zap*` contracts are **thin stateless swap routers**; the NFT-owner
///   still calls `DepositHandler.deposit` / `WithdrawHandler.withdraw`
///   from their own wallet after the async GMX leg settles.
///   See `docs/zap-ux-flow.md`.
contract DeployMainnet is Script {
    // ── Deployed instances ──

    BasaltMath public basaltMath;
    DepositHandler public depositHandler;
    WithdrawHandler public withdrawHandler;
    ManagerHandler public managerHandler;
    AsyncRecoveryHandler public asyncRecoveryHandler;
    FeeAccountingHandler public feeAccountingHandler;

    VaultCore public vaultCoreImpl;
    VaultState public vaultStateImpl;
    InitialCoreAddressBook public initialCoreAddressBook;

    FeeSplitter public feeSplitter;
    ManagerContract public managerContract;
    VaultCoreNftFactory public vaultCoreNftFactory;

    BasaltZapIn public zapIn;
    BasaltZapOut public zapOut;
    BasaltGmUnwrapper public gmUnwrapper;

    function run() external {
        address protocolOwner = vm.envAddress("PROTOCOL_OWNER");
        require(protocolOwner != address(0), "DeployMainnet: PROTOCOL_OWNER not set in .env");

        console.log("=== Basalt Vault Arbitrum One deployment ===");
        console.log("Protocol owner: ", protocolOwner);
        console.log("Chain ID:       ", block.chainid);
        require(block.chainid == 42_161, "DeployMainnet: wrong chain - expected Arbitrum One (42161)");

        vm.startBroadcast();

        _deployHandlers();
        _deployCoreImplsAndAddressBook();
        _deployGovernance(protocolOwner);
        _deployFactory(protocolOwner);
        _deployZaps();

        vm.stopBroadcast();

        _logEnvDump(protocolOwner);
    }

    // ────────────────────────────────────────────────────────────────────────
    //  PHASE 1 — Stateless handler singletons
    // ────────────────────────────────────────────────────────────────────────

    function _deployHandlers() internal {
        basaltMath = new BasaltMath();
        depositHandler = new DepositHandler();
        withdrawHandler = new WithdrawHandler();
        managerHandler = new ManagerHandler();
        // AsyncRecoveryHandler's constructor args are legacy / unused — any
        // three addresses are accepted. Pass zero to avoid wiring confusion
        // with any real address.
        asyncRecoveryHandler = new AsyncRecoveryHandler(address(0), address(0), address(0));
        feeAccountingHandler = new FeeAccountingHandler();

        console.log("BasaltMath:            ", address(basaltMath));
        console.log("DepositHandler:        ", address(depositHandler));
        console.log("WithdrawHandler:       ", address(withdrawHandler));
        console.log("ManagerHandler:        ", address(managerHandler));
        console.log("AsyncRecoveryHandler:  ", address(asyncRecoveryHandler));
        console.log("FeeAccountingHandler:  ", address(feeAccountingHandler));
    }

    // ────────────────────────────────────────────────────────────────────────
    //  PHASE 2 — VaultCore / VaultState impls + InitialCoreAddressBook
    // ────────────────────────────────────────────────────────────────────────

    function _deployCoreImplsAndAddressBook() internal {
        vaultCoreImpl = new VaultCore();
        vaultStateImpl = new VaultState();

        initialCoreAddressBook = new InitialCoreAddressBook(
            InitialCoreAddressBook.InitialCoreAddresses({
                vaultCore: address(vaultCoreImpl),
                depositHandler: address(depositHandler),
                withdrawHandler: address(withdrawHandler),
                managerHandler: address(managerHandler),
                asyncRecoveryHandler: address(asyncRecoveryHandler),
                feeAccountingHandler: address(feeAccountingHandler),
                // Extension slots unused in canary — rotate in via governance
                // later when real extensions are designed.
                extensionHandler1: address(0),
                extensionHandler2: address(0),
                extensionHandler3: address(0),
                basaltState: address(vaultStateImpl),
                basaltMath: address(basaltMath),
                dolomiteVault: BasaltAddresses.VAULT_FACTORY
            })
        );

        console.log("VaultCore impl:        ", address(vaultCoreImpl));
        console.log("VaultState impl:       ", address(vaultStateImpl));
        console.log("InitialCoreAddressBook:", address(initialCoreAddressBook));
    }

    // ────────────────────────────────────────────────────────────────────────
    //  PHASE 3 — Governance (FeeSplitter + ManagerContract)
    // ────────────────────────────────────────────────────────────────────────

    function _deployGovernance(address protocolOwner) internal {
        // Seed `FeeSplitter` with the 4 canonical reward tokens users will claim fees in
        // (USDC, GM, WETH, WBTC). Slots are part of the hard cap (`MAX_TRACKED_TOKENS = 20`), so
        // ~16 slots remain for the `owner` to whitelist more fee tokens via
        // `ManagerContract.addFeeSplitterTrackedToken`. Append-only — tokens can't be removed.
        IERC20[] memory initialTrackedTokens = new IERC20[](4);
        initialTrackedTokens[0] = IERC20(BasaltAddresses.USDC);
        initialTrackedTokens[1] = IERC20(BasaltAddresses.GM_MARKET_TOKEN);
        initialTrackedTokens[2] = IERC20(BasaltAddresses.WETH);
        initialTrackedTokens[3] = IERC20(BasaltAddresses.WBTC);

        // Full 1e18 of BFS fee shares mint to `protocolOwner`; they can later
        // transfer / split between team, treasury, investors without on-chain
        // migration.
        feeSplitter = new FeeSplitter(protocolOwner, initialTrackedTokens);

        // ManagerContract mints every role (configurator/operational/
        // handlerProposer/addressProposer/feeCollector) to `msg.sender`,
        // which at broadcast time is the deployer. If the protocolOwner
        // differs from the deployer, the deployer must hand these off
        // post-deploy (setConfigurator/setOperational/…).
        managerContract = new ManagerContract(address(feeSplitter));
        feeSplitter.setManagerContract(address(managerContract));

        // Ensure all ManagerContract roles point to protocolOwner
        managerContract.setConfigurator(protocolOwner);
        managerContract.setOperational(protocolOwner);
        managerContract.setHandlerProposer(protocolOwner);
        managerContract.setAddressProposer(protocolOwner);
        managerContract.transferOwnership(protocolOwner);

        console.log("FeeSplitter:           ", address(feeSplitter));
        console.log("  tracked tokens:      ", feeSplitter.trackedTokensLength());
        console.log("ManagerContract:       ", address(managerContract));
        console.log("  splitter.manager:    ", feeSplitter.managerContract());
    }

    // ────────────────────────────────────────────────────────────────────────
    //  PHASE 4 — VaultCoreNftFactory
    // ────────────────────────────────────────────────────────────────────────

    function _deployFactory(address protocolOwner) internal {
        vaultCoreNftFactory = new VaultCoreNftFactory(
            initialCoreAddressBook,
            // Ownable2Step: owner receives the admin role and must claim via
            // acceptOwnership() if we pre-assign a non-deployer owner. Here
            // we set the owner directly to protocolOwner — the factory's
            // Ownable constructor accepts any non-zero initial owner.
            protocolOwner,
            address(managerContract)
        );

        console.log("VaultCoreNftFactory:   ", address(vaultCoreNftFactory));
        console.log("  owner:               ", vaultCoreNftFactory.owner());
        console.log("  protocolManager:     ", vaultCoreNftFactory.protocolManager());
    }

    // ────────────────────────────────────────────────────────────────────────
    //  PHASE 5 — Thin stateless Zaps
    // ────────────────────────────────────────────────────────────────────────

    function _deployZaps() internal {
        zapIn = new BasaltZapIn(
            BasaltZapIn.Config({
                swapRouter: BasaltAddresses.UNI_V3_SWAP_ROUTER,
                exchangeRouter: BasaltAddresses.GMX_EXCHANGE_ROUTER,
                gmxRouter: BasaltAddresses.GMX_V2_ROUTER,
                gmxDepositVault: BasaltAddresses.GMX_DEPOSIT_VAULT,
                usdc: BasaltAddresses.USDC,
                wbtc: BasaltAddresses.WBTC,
                gmToken: BasaltAddresses.GM_MARKET_TOKEN,
                gmxDataStore: BasaltAddresses.GMX_DATA_STORE,
                wbtcOracle: BasaltAddresses.CL_WBTC_USD,
                usdcOracle: BasaltAddresses.CL_USDC_USD,
                sequencerOracle: BasaltAddresses.CL_SEQUENCER
            })
        );

        zapOut = new BasaltZapOut(
            BasaltZapOut.Config({
                swapRouter: BasaltAddresses.UNI_V3_SWAP_ROUTER,
                wbtc: BasaltAddresses.WBTC,
                usdc: BasaltAddresses.USDC,
                wbtcOracle: BasaltAddresses.CL_WBTC_USD,
                usdcOracle: BasaltAddresses.CL_USDC_USD,
                sequencerOracle: BasaltAddresses.CL_SEQUENCER
            })
        );

        gmUnwrapper = new BasaltGmUnwrapper(
            BasaltGmUnwrapper.Config({
                exchangeRouter: BasaltAddresses.GMX_EXCHANGE_ROUTER,
                gmxRouter: BasaltAddresses.GMX_V2_ROUTER,
                gmxWithdrawalVault: BasaltAddresses.GMX_WITHDRAWAL_VAULT,
                gmToken: BasaltAddresses.GM_MARKET_TOKEN,
                wbtc: BasaltAddresses.WBTC,
                usdc: BasaltAddresses.USDC,
                gmxDataStore: BasaltAddresses.GMX_DATA_STORE,
                wbtcOracle: BasaltAddresses.CL_WBTC_USD,
                usdcOracle: BasaltAddresses.CL_USDC_USD,
                sequencerOracle: BasaltAddresses.CL_SEQUENCER
            })
        );

        console.log("BasaltZapIn:           ", address(zapIn));
        console.log("BasaltZapOut:          ", address(zapOut));
        console.log("BasaltGmUnwrapper:     ", address(gmUnwrapper));
    }

    // ────────────────────────────────────────────────────────────────────────
    //  POST-DEPLOY — Copy/paste env dump
    // ────────────────────────────────────────────────────────────────────────

    function _logEnvDump(address protocolOwner) internal view {
        console.log("=== Deployment complete ===");
        console.log("=== Copy to .env / deploy/arbitrum.env ===");
        console.log("PROTOCOL_OWNER=",               protocolOwner);
        console.log("BASALT_MATH=",                  address(basaltMath));
        console.log("DEPOSIT_HANDLER=",              address(depositHandler));
        console.log("WITHDRAW_HANDLER=",             address(withdrawHandler));
        console.log("MANAGER_HANDLER=",              address(managerHandler));
        console.log("ASYNC_RECOVERY_HANDLER=",       address(asyncRecoveryHandler));
        console.log("FEE_ACCOUNTING_HANDLER=",       address(feeAccountingHandler));
        console.log("VAULT_CORE_IMPL=",              address(vaultCoreImpl));
        console.log("VAULT_STATE_IMPL=",             address(vaultStateImpl));
        console.log("INITIAL_CORE_ADDRESS_BOOK=",    address(initialCoreAddressBook));
        console.log("FEE_SPLITTER=",                 address(feeSplitter));
        console.log("MANAGER_CONTRACT=",             address(managerContract));
        console.log("VAULT_CORE_NFT_FACTORY=",       address(vaultCoreNftFactory));
        console.log("ZAP_IN=",                       address(zapIn));
        console.log("ZAP_OUT=",                      address(zapOut));
        console.log("GM_UNWRAPPER=",                 address(gmUnwrapper));
    }
}

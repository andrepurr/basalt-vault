// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {IVaultCoreNftFactory} from "../../src/interfaces/IVaultCoreNftFactory.sol";
import {
    NotManager,
    NotHandler,
    NotNftOwner,
    NotManagerOrNftOwner
} from "../../src/core/vaultCoreLibraries/VaultCoreTypes.sol";

/// @title Minimal mock factory for off-fork Halmos testing
/// @dev Returns deterministic owner/manager without any ERC721 or RPC dependency.
contract HalmosMockFactory is IVaultCoreNftFactory {
    address public immutable _owner;
    address public immutable _protocolManager;
    mapping(address => address) public vaultOwners;

    constructor(address owner_, address protocolManager_) {
        _owner = owner_;
        _protocolManager = protocolManager_;
    }

    function register(address vc, address nftOwner) external {
        vaultOwners[vc] = nftOwner;
    }

    function owner() external view returns (address) { return _owner; }
    function ownerOfVault(address vc) external view returns (address) { return vaultOwners[vc]; }
    function protocolManager() external view returns (address) { return _protocolManager; }
}

/// @title AccessControl -- Halmos formal verification
/// @notice Proves that VaultCore access control gates cannot be bypassed:
///   1. universalCall reverts for any caller that is not a registered handler slot.
///   2. universalCall reverts when the initiator is neither the NFT owner nor the protocol manager.
///   3. acceptHandler is callable only by the NFT owner -- no other address can finalize a handler swap.
///   4. proposeHandler is callable only by the protocol manager (onlyManager).
contract AccessControlTest is Test {

    address constant NFT_OWNER = address(0xA001);
    address constant PROTOCOL_MANAGER = address(0xA002);
    address constant FACTORY_OWNER = address(0xA003);

    // Eight distinct handler addresses -- mirrors production slot count
    address constant H_DEPOSIT = address(0xD001);
    address constant H_WITHDRAW = address(0xD002);
    address constant H_MANAGER = address(0xD003);
    address constant H_ASYNC = address(0xD004);
    address constant H_FEE = address(0xD005);
    address constant H_EXT1 = address(0xD006);
    address constant H_EXT2 = address(0xD007);
    address constant H_EXT3 = address(0xD008);

    HalmosMockFactory factory;
    VaultCore vaultCore;
    VaultState vaultState;

    function setUp() public {
        factory = new HalmosMockFactory(FACTORY_OWNER, PROTOCOL_MANAGER);

        // Deploy implementation then clone (mirrors factory pattern)
        VaultCore impl = new VaultCore();
        address clone = Clones.clone(address(impl));
        vaultCore = VaultCore(payable(clone));

        VaultState stateImpl = new VaultState();
        address stateClone = Clones.clone(address(stateImpl));
        vaultState = VaultState(stateClone);

        vaultCore.initialize(
            address(factory),
            address(0xBEEF), // basaltMath (unused in ACL tests)
            H_DEPOSIT,
            H_WITHDRAW,
            H_MANAGER,
            H_ASYNC,
            H_FEE,
            address(vaultState),
            H_EXT1,
            H_EXT2,
            H_EXT3
        );
        vaultState.initialize(address(vaultCore), NFT_OWNER);
        factory.register(address(vaultCore), NFT_OWNER);
    }

    // -----------------------------------------------------------------------
    //  INV-1: universalCall rejects non-handler callers
    // -----------------------------------------------------------------------

    /// @notice For any symbolic address that is NOT one of the 8 handler slots,
    ///         universalCall must revert with NotHandler.
    function check_universalCall_rejects_nonHandler(address caller) public {
        // Exclude all valid handler addresses
        vm.assume(caller != H_DEPOSIT);
        vm.assume(caller != H_WITHDRAW);
        vm.assume(caller != H_MANAGER);
        vm.assume(caller != H_ASYNC);
        vm.assume(caller != H_FEE);
        vm.assume(caller != H_EXT1);
        vm.assume(caller != H_EXT2);
        vm.assume(caller != H_EXT3);

        vm.prank(caller);
        vm.expectRevert(NotHandler.selector);
        vaultCore.universalCall(NFT_OWNER, address(0), "", 0, false);
    }

    // -----------------------------------------------------------------------
    //  INV-2: universalCall rejects invalid initiator even from valid handler
    // -----------------------------------------------------------------------

    /// @notice Even when called from a legitimate handler, universalCall must
    ///         revert if the initiator is not the NFT owner or protocol manager.
    function check_universalCall_rejects_badInitiator(address initiator) public {
        vm.assume(initiator != NFT_OWNER);
        vm.assume(initiator != PROTOCOL_MANAGER);

        vm.prank(H_DEPOSIT);
        vm.expectRevert(NotManagerOrNftOwner.selector);
        vaultCore.universalCall(initiator, address(0), "", 0, false);
    }

    // -----------------------------------------------------------------------
    //  INV-3: acceptHandler is NFT-owner-exclusive
    // -----------------------------------------------------------------------

    /// @notice No address other than the NFT owner can call acceptHandler.
    ///         This is the critical user-consent gate for handler rotation.
    function check_acceptHandler_onlyOwner(address caller) public {
        vm.assume(caller != NFT_OWNER);

        // Seed a pending proposal so acceptHandler doesn't hit NoHandlerProposal first
        vm.prank(PROTOCOL_MANAGER);
        vaultCore.proposeHandler(H_DEPOSIT, address(0xAE01));

        vm.prank(caller);
        vm.expectRevert(NotNftOwner.selector);
        vaultCore.acceptHandler();
    }

    // -----------------------------------------------------------------------
    //  INV-4: proposeHandler requires onlyManager
    // -----------------------------------------------------------------------

    /// @notice No address other than the protocol manager can propose a handler change.
    function check_proposeHandler_onlyManager(address caller) public {
        vm.assume(caller != PROTOCOL_MANAGER);
        // Also exclude NFT owner in non-deadman mode (deadman not triggered)
        // In normal mode, only protocolManager passes onlyManager

        vm.prank(caller);
        vm.expectRevert(NotManager.selector);
        vaultCore.proposeHandler(H_DEPOSIT, address(0xAE02));
    }
}

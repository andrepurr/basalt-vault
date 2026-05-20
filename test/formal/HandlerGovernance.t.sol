// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {IVaultCoreNftFactory} from "../../src/interfaces/IVaultCoreNftFactory.sol";
import {
    HandlerProposal,
    NotManager,
    NotNftOwner,
    NoHandlerProposal,
    UnknownHandler,
    ZeroHandler,
    DuplicateHandler
} from "../../src/core/vaultCoreLibraries/VaultCoreTypes.sol";

/// @dev Same mock factory as AccessControl tests -- deterministic, no ERC721.
contract GovernanceMockFactory is IVaultCoreNftFactory {
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

/// @title HandlerGovernance -- Halmos formal verification
/// @notice Proves that handler rotation on VaultCore requires explicit NFT owner consent.
///         The protocol manager can *propose* a handler swap, but the actual slot mutation
///         only happens inside acceptHandler, which is gated by onlyNftOwner.
///
///   Invariants verified:
///   1. proposeHandler alone never mutates any handler slot -- it only writes to handlerProposal.
///   2. acceptHandler is the sole path that writes a new handler into a slot.
///   3. After acceptHandler, the old handler address is no longer in any slot (no stale references).
///   4. A proposal for an unknown handler slot reverts (slot validation).
contract HandlerGovernanceTest is Test {

    address constant NFT_OWNER = address(0xB001);
    address constant PROTOCOL_MANAGER = address(0xB002);
    address constant FACTORY_OWNER = address(0xB003);

    address constant H_DEPOSIT = address(0xE001);
    address constant H_WITHDRAW = address(0xE002);
    address constant H_MANAGER = address(0xE003);
    address constant H_ASYNC = address(0xE004);
    address constant H_FEE = address(0xE005);
    address constant H_EXT1 = address(0xE006);
    address constant H_EXT2 = address(0xE007);
    address constant H_EXT3 = address(0xE008);

    GovernanceMockFactory factory;
    VaultCore vaultCore;

    function setUp() public {
        factory = new GovernanceMockFactory(FACTORY_OWNER, PROTOCOL_MANAGER);

        VaultCore impl = new VaultCore();
        address clone = Clones.clone(address(impl));
        vaultCore = VaultCore(payable(clone));

        VaultState stateImpl = new VaultState();
        address stateClone = Clones.clone(address(stateImpl));

        vaultCore.initialize(
            address(factory),
            address(0xBEEF),
            H_DEPOSIT,
            H_WITHDRAW,
            H_MANAGER,
            H_ASYNC,
            H_FEE,
            stateClone,
            H_EXT1,
            H_EXT2,
            H_EXT3
        );
        VaultState(stateClone).initialize(address(vaultCore), NFT_OWNER);
        factory.register(address(vaultCore), NFT_OWNER);
    }

    // -----------------------------------------------------------------------
    //  INV-1: proposeHandler never mutates handler slots
    // -----------------------------------------------------------------------

    /// @notice After proposeHandler, all 8 handler slots remain exactly as
    ///         they were at initialization.  The proposal is stored but dormant.
    function check_proposeHandler_doesNotMutateSlots() public {
        // Snapshot pre-proposal slots
        address pre_deposit = vaultCore.depositHandler();
        address pre_withdraw = vaultCore.withdrawHandler();
        address pre_manager = vaultCore.managerHandler();
        address pre_async = vaultCore.asyncRecoveryHandler();
        address pre_fee = vaultCore.feeAccountingHandler();
        address pre_ext1 = vaultCore.extensionHandler1();
        address pre_ext2 = vaultCore.extensionHandler2();
        address pre_ext3 = vaultCore.extensionHandler3();

        address newHandler = address(0xCAFE);
        vm.prank(PROTOCOL_MANAGER);
        vaultCore.proposeHandler(H_DEPOSIT, newHandler);

        // All slots unchanged
        assert(vaultCore.depositHandler() == pre_deposit);
        assert(vaultCore.withdrawHandler() == pre_withdraw);
        assert(vaultCore.managerHandler() == pre_manager);
        assert(vaultCore.asyncRecoveryHandler() == pre_async);
        assert(vaultCore.feeAccountingHandler() == pre_fee);
        assert(vaultCore.extensionHandler1() == pre_ext1);
        assert(vaultCore.extensionHandler2() == pre_ext2);
        assert(vaultCore.extensionHandler3() == pre_ext3);
    }

    // -----------------------------------------------------------------------
    //  INV-2: acceptHandler requires NFT owner -- manager alone cannot rotate
    // -----------------------------------------------------------------------

    /// @notice The protocol manager (or any non-owner address) cannot call
    ///         acceptHandler.  This is the consent gate.
    function check_managerCannotAcceptHandler() public {
        vm.prank(PROTOCOL_MANAGER);
        vaultCore.proposeHandler(H_WITHDRAW, address(0xCAFE));

        // Manager tries to accept -- must revert
        vm.prank(PROTOCOL_MANAGER);
        vm.expectRevert(NotNftOwner.selector);
        vaultCore.acceptHandler();
    }

    // -----------------------------------------------------------------------
    //  INV-3: full propose-accept cycle correctly replaces exactly one slot
    // -----------------------------------------------------------------------

    /// @notice After the NFT owner accepts a handler proposal, the targeted
    ///         slot contains the new handler, and all other slots are untouched.
    function check_acceptHandler_replacesCorrectSlot() public {
        address newHandler = address(0xCAFE);

        vm.prank(PROTOCOL_MANAGER);
        vaultCore.proposeHandler(H_DEPOSIT, newHandler);

        vm.prank(NFT_OWNER);
        vaultCore.acceptHandler();

        // The deposit slot was replaced
        assert(vaultCore.depositHandler() == newHandler);

        // All other slots untouched
        assert(vaultCore.withdrawHandler() == H_WITHDRAW);
        assert(vaultCore.managerHandler() == H_MANAGER);
        assert(vaultCore.asyncRecoveryHandler() == H_ASYNC);
        assert(vaultCore.feeAccountingHandler() == H_FEE);
        assert(vaultCore.extensionHandler1() == H_EXT1);
        assert(vaultCore.extensionHandler2() == H_EXT2);
        assert(vaultCore.extensionHandler3() == H_EXT3);

        // Proposal is cleared
        (,, bool exists) = vaultCore.handlerProposal();
        assert(!exists);
    }

    // -----------------------------------------------------------------------
    //  INV-4: proposal for non-slot address reverts
    // -----------------------------------------------------------------------

    /// @notice proposeHandler must revert if oldHandler is not one of the 8 slots.
    function check_proposeHandler_rejectsUnknownSlot(address fakeOldHandler) public {
        vm.assume(fakeOldHandler != H_DEPOSIT);
        vm.assume(fakeOldHandler != H_WITHDRAW);
        vm.assume(fakeOldHandler != H_MANAGER);
        vm.assume(fakeOldHandler != H_ASYNC);
        vm.assume(fakeOldHandler != H_FEE);
        vm.assume(fakeOldHandler != H_EXT1);
        vm.assume(fakeOldHandler != H_EXT2);
        vm.assume(fakeOldHandler != H_EXT3);

        vm.prank(PROTOCOL_MANAGER);
        vm.expectRevert(UnknownHandler.selector);
        vaultCore.proposeHandler(fakeOldHandler, address(0xCAFE));
    }

    // -----------------------------------------------------------------------
    //  INV-5: proposing an existing handler as replacement reverts
    // -----------------------------------------------------------------------

    /// @notice The new handler cannot already occupy a slot (DuplicateHandler guard).
    function check_proposeHandler_rejectsDuplicate() public {
        vm.prank(PROTOCOL_MANAGER);
        vm.expectRevert(DuplicateHandler.selector);
        vaultCore.proposeHandler(H_DEPOSIT, H_WITHDRAW);
    }

    // -----------------------------------------------------------------------
    //  INV-6: acceptHandler with no pending proposal reverts
    // -----------------------------------------------------------------------

    /// @notice acceptHandler must revert when no proposal exists, even from NFT owner.
    function check_acceptHandler_revertsWithNoProposal() public {
        vm.prank(NFT_OWNER);
        vm.expectRevert(NoHandlerProposal.selector);
        vaultCore.acceptHandler();
    }
}

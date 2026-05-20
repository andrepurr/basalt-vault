// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {IVaultCoreNftFactory} from "../../src/interfaces/IVaultCoreNftFactory.sol";

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

/// @title AccessControl — halmos formal verification of VaultCore ACL invariants
/// @dev Low-level calls instead of vm.expectRevert (unsupported in halmos 0.3.x).
contract AccessControlTest is Test {

    address constant NFT_OWNER = address(0xA001);
    address constant PROTOCOL_MANAGER = address(0xA002);
    address constant FACTORY_OWNER = address(0xA003);

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

        VaultCore impl = new VaultCore();
        address clone = Clones.clone(address(impl));
        vaultCore = VaultCore(payable(clone));

        VaultState stateImpl = new VaultState();
        address stateClone = Clones.clone(address(stateImpl));
        vaultState = VaultState(stateClone);

        vaultCore.initialize(
            address(factory),
            address(0xBEEF),
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

    function check_universalCall_rejects_nonHandler(address caller) public {
        vm.assume(caller != H_DEPOSIT);
        vm.assume(caller != H_WITHDRAW);
        vm.assume(caller != H_MANAGER);
        vm.assume(caller != H_ASYNC);
        vm.assume(caller != H_FEE);
        vm.assume(caller != H_EXT1);
        vm.assume(caller != H_EXT2);
        vm.assume(caller != H_EXT3);

        vm.prank(caller);
        (bool success,) = address(vaultCore).call(
            abi.encodeWithSelector(vaultCore.universalCall.selector, NFT_OWNER, address(0), "", 0, false)
        );
        assert(!success);
    }

    // -----------------------------------------------------------------------
    //  INV-2: universalCall rejects invalid initiator even from valid handler
    // -----------------------------------------------------------------------

    function check_universalCall_rejects_badInitiator(address initiator) public {
        vm.assume(initiator != NFT_OWNER);
        vm.assume(initiator != PROTOCOL_MANAGER);

        vm.prank(H_DEPOSIT);
        (bool success,) = address(vaultCore).call(
            abi.encodeWithSelector(vaultCore.universalCall.selector, initiator, address(0), "", 0, false)
        );
        assert(!success);
    }

    // -----------------------------------------------------------------------
    //  INV-3: acceptHandler is NFT-owner-exclusive
    // -----------------------------------------------------------------------

    function check_acceptHandler_onlyOwner(address caller) public {
        vm.assume(caller != NFT_OWNER);

        // Seed a pending proposal
        vm.prank(PROTOCOL_MANAGER);
        vaultCore.proposeHandler(H_DEPOSIT, address(0xAE01));

        vm.prank(caller);
        (bool success,) = address(vaultCore).call(
            abi.encodeWithSelector(vaultCore.acceptHandler.selector)
        );
        assert(!success);
    }

    // -----------------------------------------------------------------------
    //  INV-4: proposeHandler requires onlyManager
    // -----------------------------------------------------------------------

    function check_proposeHandler_onlyManager(address caller) public {
        vm.assume(caller != PROTOCOL_MANAGER);

        vm.prank(caller);
        (bool success,) = address(vaultCore).call(
            abi.encodeWithSelector(vaultCore.proposeHandler.selector, H_DEPOSIT, address(0xAE02))
        );
        assert(!success);
    }
}

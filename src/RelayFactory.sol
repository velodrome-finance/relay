// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IRelayFactory} from "./interfaces/IRelayFactory.sol";
import {Relay} from "./Relay.sol";

import {IVotingEscrow} from "@velodrome/contracts/interfaces/IVotingEscrow.sol";
import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";
import {IVoter} from "@velodrome/contracts/interfaces/IVoter.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title RelayFactory
/// @author velodrome.finance, @airtoonricardo
/// @notice Factory contract to create Relays and manage their authorized callers
abstract contract RelayFactory is IRelayFactory, ERC2771Context {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable forwarder;
    address public immutable router;
    address public immutable voter;

    Ownable public immutable factoryRegistry;
    IVotingEscrow public immutable ve;

    EnumerableSet.AddressSet private _keepers;
    EnumerableSet.AddressSet internal _relays;

    constructor(
        address _forwarder,
        address _voter,
        address _router,
        address _factoryRegistry
    ) ERC2771Context(_forwarder) {
        forwarder = _forwarder;
        voter = _voter;
        router = _router;

        factoryRegistry = Ownable(_factoryRegistry);
        ve = IVotingEscrow(IVoter(voter).ve());
    }

    // -------------------------------------------------
    // Relay Functions
    // -------------------------------------------------

    /// @dev Deploys new Relay instance
    ///      To be implemented in RelayFactories
    function _deployRelayInstance(
        address _admin,
        string calldata _name,
        bytes calldata data
    ) internal virtual returns (address);

    /// @inheritdoc IRelayFactory
    function createRelay(
        address _admin,
        uint256 _mTokenId,
        string calldata _name,
        bytes calldata _data
    ) external returns (address relay) {
        address sender = _msgSender();
        if (_admin == address(0)) revert ZeroAddress();
        if (_mTokenId == 0) revert TokenIdZero();
        if (!ve.isApprovedOrOwner(sender, _mTokenId)) revert TokenIdNotApproved();
        if (ve.escrowType(_mTokenId) != IVotingEscrow.EscrowType.MANAGED) revert TokenIdNotManaged();

        // create the relay contract
        relay = _deployRelayInstance(_admin, _name, _data);

        // transfer nft to relay
        ve.safeTransferFrom(ve.ownerOf(_mTokenId), relay, _mTokenId);
        Relay(relay).initialize(_mTokenId);

        _relays.add(relay);
        emit CreateRelay(sender, _admin, _name, relay);
    }

    /// @inheritdoc IRelayFactory
    function relays() external view returns (address[] memory) {
        return _relays.values();
    }

    /// @inheritdoc IRelayFactory
    function isRelay(address _relay) external view returns (bool) {
        return _relays.contains(_relay);
    }

    /// @inheritdoc IRelayFactory
    function relaysLength() external view returns (uint256) {
        return _relays.length();
    }

    // -------------------------------------------------
    // Keeper Functions
    // -------------------------------------------------

    /// @inheritdoc IRelayFactory
    function addKeeper(address _keeper) external {
        if (_msgSender() != factoryRegistry.owner()) revert NotTeam();
        if (_keeper == address(0)) revert ZeroAddress();
        if (isKeeper(_keeper)) revert KeeperAlreadyExists();
        _keepers.add(_keeper);
        emit AddKeeper(_keeper);
    }

    /// @inheritdoc IRelayFactory
    function removeKeeper(address _keeper) external {
        if (_msgSender() != factoryRegistry.owner()) revert NotTeam();
        if (_keeper == address(0)) revert ZeroAddress();
        if (!isKeeper(_keeper)) revert KeeperDoesNotExist();
        _keepers.remove(_keeper);
        emit RemoveKeeper(_keeper);
    }

    /// @inheritdoc IRelayFactory
    function keepers() external view returns (address[] memory) {
        return _keepers.values();
    }

    /// @inheritdoc IRelayFactory
    function isKeeper(address _keeper) public view returns (bool) {
        return _keepers.contains(_keeper);
    }

    /// @inheritdoc IRelayFactory
    function keepersLength() external view returns (uint256) {
        return _keepers.length();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IAutoConverterFactory} from "../interfaces/IAutoConverterFactory.sol";
import {AutoConverter} from "./AutoConverter.sol";

import {IVoter} from "@velodrome/contracts/interfaces/IVoter.sol";
import {IVotingEscrow} from "@velodrome/contracts/interfaces/IVotingEscrow.sol";
import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

/// @title AutoConverterFactory
/// @author velodrome.finance, @pegahcarter
/// @notice Factory contract to create AutoConverters and manage authorized callers of the AutoConverters
contract AutoConverterFactory is IAutoConverterFactory, ERC2771Context {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable forwarder;
    address public immutable router;
    address public immutable voter;
    Ownable public immutable factoryRegistry;
    IVotingEscrow public immutable ve;

    EnumerableSet.AddressSet private _highLiquidityTokens;
    EnumerableSet.AddressSet private _autoConverters;
    EnumerableSet.AddressSet private _keepers;

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

    /// @inheritdoc IAutoConverterFactory
    function createAutoConverter(
        address _token,
        address _admin,
        uint256 _mTokenId
    ) external returns (address autoConverter) {
        address sender = _msgSender();
        if (_admin == address(0)) revert ZeroAddress();
        if (_mTokenId == 0) revert TokenIdZero();
        if (!ve.isApprovedOrOwner(sender, _mTokenId)) revert TokenIdNotApproved();
        if (ve.escrowType(_mTokenId) != IVotingEscrow.EscrowType.MANAGED) revert TokenIdNotManaged();

        // create the autoconverter contract
        autoConverter = address(new AutoConverter(forwarder, router, voter, _token, _admin));

        // transfer nft to autoconverter
        ve.safeTransferFrom(ve.ownerOf(_mTokenId), autoConverter, _mTokenId);
        AutoConverter(autoConverter).initialize(_mTokenId);

        _autoConverters.add(autoConverter);
        emit CreateAutoConverter(sender, _admin, autoConverter);
    }

    /// @inheritdoc IAutoConverterFactory
    function addKeeper(address _keeper) external {
        if (_msgSender() != factoryRegistry.owner()) revert NotTeam();
        if (_keeper == address(0)) revert ZeroAddress();
        if (isKeeper(_keeper)) revert KeeperAlreadyExists();
        _keepers.add(_keeper);
        emit AddKeeper(_keeper);
    }

    /// @inheritdoc IAutoConverterFactory
    function removeKeeper(address _keeper) external {
        if (_msgSender() != factoryRegistry.owner()) revert NotTeam();
        if (_keeper == address(0)) revert ZeroAddress();
        if (!isKeeper(_keeper)) revert KeeperDoesNotExist();
        _keepers.remove(_keeper);
        emit RemoveKeeper(_keeper);
    }

    /// @inheritdoc IAutoConverterFactory
    function isKeeper(address _keeper) public view returns (bool) {
        return _keepers.contains(_keeper);
    }

    /// @inheritdoc IAutoConverterFactory
    function keepers() external view returns (address[] memory) {
        return _keepers.values();
    }

    /// @inheritdoc IAutoConverterFactory
    function keepersLength() external view returns (uint256) {
        return _keepers.length();
    }

    /// @inheritdoc IAutoConverterFactory
    function autoConverters() external view returns (address[] memory) {
        return _autoConverters.values();
    }

    /// @inheritdoc IAutoConverterFactory
    function autoConvertersLength() external view returns (uint256) {
        return _autoConverters.length();
    }

    /// @inheritdoc IAutoConverterFactory
    function isAutoConverter(address _autoConverter) external view returns (bool) {
        return _autoConverters.contains(_autoConverter);
    }
}

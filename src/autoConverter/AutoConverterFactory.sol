// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IAutoConverterFactory} from "../interfaces/IAutoConverterFactory.sol";
import {AutoConverter} from "./AutoConverter.sol";
import {RelayFactory} from "../RelayFactory.sol";

import {IVotingEscrow} from "@velodrome/contracts/interfaces/IVotingEscrow.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AutoConverterFactory
/// @author velodrome.finance, @pegahcarter, @airtoonricardo
/// @notice Factory contract to create AutoConverters and manage authorized callers of the AutoConverters
contract AutoConverterFactory is IAutoConverterFactory, RelayFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        address _forwarder,
        address _voter,
        address _router,
        address _factoryRegistry
    ) RelayFactory(_forwarder, _voter, _router, _factoryRegistry) {}

    function _deployRelayInstance(
        address _admin,
        string calldata _name,
        bytes calldata _data
    ) internal override returns (address autoConverter) {
        address _token = abi.decode(_data, (address));

        autoConverter = address(new AutoConverter(forwarder, voter, _admin, _name, router, _token));
    }
}

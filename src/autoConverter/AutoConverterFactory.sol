// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {AutoConverter} from "./AutoConverter.sol";
import {RelayFactory} from "../RelayFactory.sol";

import {IVotingEscrow} from "@velodrome/contracts/interfaces/IVotingEscrow.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title AutoConverterFactory
/// @author velodrome.finance, @pegahcarter, @airtoonricardo, @pedrovalido
/// @notice Factory contract to create AutoConverters and manage authorized callers of the AutoConverters
contract AutoConverterFactory is RelayFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        address _voter,
        address _router,
        address _keeperRegistry,
        address _optimizerRegistry,
        address _defaultOptimizer,
        address[] memory highLiquidityTokens_
    ) RelayFactory(_voter, _router, _keeperRegistry, _optimizerRegistry, _defaultOptimizer, highLiquidityTokens_) {}

    function _deployRelayInstance(
        address _admin,
        string calldata _name,
        bytes calldata _data
    ) internal override returns (address autoConverter) {
        address _token = abi.decode(_data, (address));
        if (_token == address(0)) revert ZeroAddress();

        autoConverter = address(
            new AutoConverter(voter, _admin, _name, router, _token, defaultOptimizer, address(this))
        );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IAutoCompounderFactory} from "../interfaces/IAutoCompounderFactory.sol";
import {AutoCompounder} from "./AutoCompounder.sol";
import {RelayFactory} from "../RelayFactory.sol";

import {IVotingEscrow} from "@velodrome/contracts/interfaces/IVotingEscrow.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

/// @title AutoCompounderFactory
/// @author velodrome.finance, @pegahcarter, @airtoonricardo
/// @notice Factory contract to create AutoCompounders and manage authorized callers of the AutoCompounders
contract AutoCompounderFactory is IAutoCompounderFactory, RelayFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IAutoCompounderFactory
    uint256 public rewardAmount = 10 * 1e18;
    /// @inheritdoc IAutoCompounderFactory
    uint256 public constant MAX_REWARD_AMOUNT = 1_000 * 1e18;
    /// @inheritdoc IAutoCompounderFactory
    uint256 public constant MIN_REWARD_AMOUNT = 1e17;

    address public immutable optimizer;

    EnumerableSet.AddressSet private _highLiquidityTokens;

    constructor(
        address _forwarder,
        address _voter,
        address _router,
        address _optimizer,
        address _keeperRegistry,
        address[] memory highLiquidityTokens_
    ) RelayFactory(_forwarder, _voter, _router, _keeperRegistry) {
        optimizer = _optimizer;

        uint256 length = highLiquidityTokens_.length;
        for (uint256 i = 0; i < length; i++) {
            _addHighLiquidityToken(highLiquidityTokens_[i]);
        }
    }

    function _deployRelayInstance(
        address _admin,
        string calldata _name,
        bytes calldata //_data
    ) internal override returns (address autoCompounder) {
        autoCompounder = address(new AutoCompounder(forwarder, voter, _admin, _name, router, optimizer, address(this)));
    }

    /// @inheritdoc IAutoCompounderFactory
    function setRewardAmount(uint256 _rewardAmount) external onlyOwner {
        if (_rewardAmount == rewardAmount) revert AmountSame();
        if (_rewardAmount < MIN_REWARD_AMOUNT || _rewardAmount > MAX_REWARD_AMOUNT) revert AmountOutOfAcceptableRange();
        rewardAmount = _rewardAmount;
        emit SetRewardAmount(_rewardAmount);
    }

    /// @inheritdoc IAutoCompounderFactory
    function addHighLiquidityToken(address _token) external onlyOwner {
        _addHighLiquidityToken(_token);
    }

    function _addHighLiquidityToken(address _token) private {
        if (_token == address(0)) revert ZeroAddress();
        if (isHighLiquidityToken(_token)) revert HighLiquidityTokenAlreadyExists();
        _highLiquidityTokens.add(_token);
        emit AddHighLiquidityToken(_token);
    }

    /// @inheritdoc IAutoCompounderFactory
    function isHighLiquidityToken(address _token) public view returns (bool) {
        return _highLiquidityTokens.contains(_token);
    }

    /// @inheritdoc IAutoCompounderFactory
    function highLiquidityTokens() external view returns (address[] memory) {
        return _highLiquidityTokens.values();
    }

    /// @inheritdoc IAutoCompounderFactory
    function highLiquidityTokensLength() external view returns (uint256) {
        return _highLiquidityTokens.length();
    }
}

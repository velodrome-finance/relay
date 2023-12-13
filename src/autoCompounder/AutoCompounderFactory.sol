// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IAutoCompounderFactory} from "../interfaces/IAutoCompounderFactory.sol";
import {AutoCompounder} from "./AutoCompounder.sol";
import {RelayFactory} from "../RelayFactory.sol";

import {IVotingEscrow} from "@velodrome/contracts/interfaces/IVotingEscrow.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

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
        bytes calldata //_data
    ) internal override returns (address autoCompounder) {
        autoCompounder = address(new AutoCompounder(voter, _admin, _name, router, defaultOptimizer, address(this)));
    }

    /// @inheritdoc IAutoCompounderFactory
    function setRewardAmount(uint256 _rewardAmount) external onlyOwner {
        if (_rewardAmount == rewardAmount) revert AmountSame();
        if (_rewardAmount < MIN_REWARD_AMOUNT || _rewardAmount > MAX_REWARD_AMOUNT) revert AmountOutOfAcceptableRange();
        rewardAmount = _rewardAmount;
        emit SetRewardAmount(_rewardAmount);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IRelayFactory.sol";

interface IAutoCompounderFactory is IRelayFactory {
    error HighLiquidityTokenAlreadyExists();
    error AmountOutOfAcceptableRange();
    error AmountSame();

    event AddHighLiquidityToken(address indexed _token);
    event SetRewardAmount(uint256 _rewardAmount);

    /// @notice Maximum fixed VELO reward rate from calling AutoCompounder.claimXAndCompound()
    ///         Set to 1,000 VELO
    function MAX_REWARD_AMOUNT() external view returns (uint256);

    /// @notice Minimum fixed VELO reward rate from calling AutoCompounder.claimXAndCompound()
    ///         Set to 0.1 VELO
    function MIN_REWARD_AMOUNT() external view returns (uint256);

    /// @notice The amount rewarded per token a caller earns from calling AutoCompounder.claimXAndCompound()
    function rewardAmount() external view returns (uint256);

    /// @notice Set the amount of VELO to reward a public caller of `AutoCompounder.claimXAndCompound()`
    ///         Callable by Owner
    /// @param _rewardAmount Amount of VELO
    function setRewardAmount(uint256 _rewardAmount) external;

    /// @notice Register a token address with high liquidity
    ///         Callable by Owner
    /// @dev Once an address is added, it cannot be removed
    /// @param _token Address of token to register
    function addHighLiquidityToken(address _token) external;

    /// @notice View if an address is registered as a high liquidity token
    ///         This indicates a token has significant liquidity to swap route into VELO
    ///         If a token address returns true, it cannot be swept from an AutoCompounder
    /// @param _token Address of token to query
    /// @return True if token is registered as a high liquidity token, else false
    function isHighLiquidityToken(address _token) external view returns (bool);

    /// @notice View for all registered high liquidity tokens
    /// @return Array of high liquidity tokens
    function highLiquidityTokens() external view returns (address[] memory);

    /// @notice Get the count of registered high liquidity tokens
    /// @return Count of registered high liquidity tokens
    function highLiquidityTokensLength() external view returns (uint256);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

interface IAutoCompounder {
    error AmountInTooHigh();
    error AmountInZero();
    error HighLiquidityToken();
    error InvalidPath();
    error NotHighLiquidityToken();
    error NoRouteFound();
    error SlippageTooHigh();
    error TooLate();
    error TooSoon();
    error UnequalLengths();
    error ZeroAddress();

    event Reward(address indexed sender, uint256 balanceRewarded);
    event Compound(uint256 balanceCompounded);
    event SetName(string oldName, string newName);
    event SwapTokenToVELO(
        address indexed claimer,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        IRouter.Route[] routes
    );
    event Sweep(address indexed token, address indexed claimer, address indexed recipient, uint256 amount);

    // -------------------------------------------------
    // Public functions
    // -------------------------------------------------

    /// @notice Swap token held by the autoCompounder into VELO using the optimal route determined by
    ///         the CompoundOptimizer unless the user-provided swap route has a better rate
    ///         Publicly callable in the final 24 hours before the epoch flip or by an authorized keeper starting the 2nd hour of an epoch or an admin
    /// @dev Optional routes are provided when the optional amountOut exceeds the amountOut calculated by CompoundOptimizer
    function swapTokenToVELOWithOptionalRoute(
        address _tokenToSwap,
        uint256 _slippage,
        IRouter.Route[] memory _optionalRoutes
    ) external;

    /// @notice Claim any rebase by the RewardsDistributor, reward the caller if publicly called, and deposit VELO
    ///          into the managed veNFT.
    ///         Publicly callable in the final 24 hours before the epoch flip
    function rewardAndCompound() external;

    /// @notice Claim any rebase by the RewardsDistributor, and deposit VELO into the managed veNFT
    function compound() external;

    // -------------------------------------------------
    // DEFAULT_ADMIN_ROLE functions
    // -------------------------------------------------

    /// @notice Set the name of the autoCompounder
    ///         Only callable by DEFAULT_ADMIN_ROLE
    /// @param _name New name for autoCompounder
    function setName(string calldata _name) external;

    /// @notice Sweep tokens within AutoCompounder to recipients
    ///         Only callable by DEFAULT_ADMIN_ROLE
    ///         Only callable within the first 24 hours after an epoch flip
    ///         Can only sweep tokens that do not exist within AutoCompounderFactory.isHighLiquidityToken()
    ///         Can only sweep to EOA
    /// @param _tokensToSweep   Addresses of tokens to sweep
    /// @param _recipients      Addresses of recipients to receive the swept tokens
    function sweep(address[] calldata _tokensToSweep, address[] calldata _recipients) external;
}

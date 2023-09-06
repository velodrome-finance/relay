// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

interface IAutoCompounder {
    error AlreadyInitialized();
    error AmountInTooHigh();
    error AmountInZero();
    error HighLiquidityToken();
    error InvalidPath();
    error NotFactory();
    error NotHighLiquidityToken();
    error NotKeeper();
    error NoRouteFound();
    error SlippageTooHigh();
    error TokenIdAlreadySet();
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
    event SwapTokenToVELOKeeper(
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
    ///             the CompoundOptimizer
    ///         Publicly callable in the final 24 hours before the epoch flip
    /// @param _tokenToSwap .
    /// @param _slippage .
    function swapTokenToVELO(address _tokenToSwap, uint256 _slippage) external;

    /// @notice Same as swapTokensToVELO with an additional argument of a user-provided swap route
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

    // -------------------------------------------------
    // Keeper functions
    // -------------------------------------------------

    /// @notice Swap a token into VELO as called by an authorized keeper
    ///         Only callable by keepers added by FactoryRegistry.owner() within AutoCompounderFactory.
    ///         Only callable 24 hours after the epoch flip
    ///         Swapping is done with routes and amount swapped determined by the keeper.
    /// @dev _amountIn and _amountOutMin cannot be 0.
    /// @param _routes          Array for which swap routes to execute
    /// @param _amountIn        Amount of token in for each swap route
    /// @param _amountOutMin    Minimum amount of token received for each swap route
    function swapTokenToVELOKeeper(IRouter.Route[] calldata _routes, uint256 _amountIn, uint256 _amountOutMin) external;
}

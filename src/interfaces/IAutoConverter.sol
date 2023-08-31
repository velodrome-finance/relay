// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

interface IAutoConverter {
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

    event SwapTokenToTokenKeeper(
        address indexed claimer,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        IRouter.Route[] routes
    );

    /// @notice Unique managed veNFT identifier
    function tokenId() external view returns (uint256);

    /// @notice Address of token used to convert into
    function token() external view returns (address);

    // -------------------------------------------------
    // DEFAULT_ADMIN_ROLE functions
    // -------------------------------------------------

    /// @notice Withdraw an amount of a token held by the autoConverter to a recipient
    ///         Only callable by DEFAULT_ADMIN_ROLE
    /// @param _token Address of token to withdraw
    /// @param _recipient Address to receive the withdrawn token
    /// @param _amount Amount of token to withdraw to _recipient
    function sweep(address _token, address _recipient, uint256 _amount) external;

    // -------------------------------------------------
    // ALLOWED_CALLER functions
    // -------------------------------------------------

    /// @notice Additional functionality for ALLOWED_CALLER to deposit more VELO into the managed tokenId.
    ///         This is effectively a bribe bonus for users that deposited into the autoConverter.
    function increaseAmount(uint256 _value) external;

    /// @notice Vote for Velodrome pools with the given weights.
    ///         Only callable by ALLOWED_CALLER.
    /// @dev Refer to IVoter.vote()
    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external;

    // -------------------------------------------------
    // Keeper functions
    // -------------------------------------------------

    /// @notice Claim rebases by the RewardsDistributor and voting rewards earned by the managed tokenId and
    ///             convert by swapping to VELO and then converting into USDC
    ///         Only callable by keepers added by FactoryRegistry.owner() within AutoConverterFactory.
    ///         Only callable 24 hours after the epoch flip
    ///         Swapping is done with routes and amounts swapped determined by the keeper.
    /// @dev _amountsIn and _amountsOutMin cannot be 0.
    /// @param _bribes          Addresses of BribeVotingRewards contracts
    /// @param _bribesTokens    Array of arrays for which tokens to claim for each BribeVotingRewards contract
    /// @param _fees            Addresses of FeesVotingRewards contracts
    /// @param _feesTokens      Array of arrays for which tokens to claim for each FeesVotingRewards contract
    /// @param _allRoutes       Array of arrays for which swap routes to execute
    /// @param _amountsIn       Amount of token in for each swap route
    /// @param _amountsOutMin   Minimum amount of token received for each swap route
    function claimAndConvertKeeper(
        address[] calldata _bribes,
        address[][] calldata _bribesTokens,
        address[] calldata _fees,
        address[][] calldata _feesTokens,
        IRouter.Route[][] calldata _allRoutes,
        uint256[] calldata _amountsIn,
        uint256[] calldata _amountsOutMin
    ) external;
}

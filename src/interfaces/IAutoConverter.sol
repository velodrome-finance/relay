// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

interface IAutoConverter {
    error AmountInTooHigh();
    error AmountInZero();
    error InvalidPath();
    error NotKeeper();
    error SlippageTooHigh();
    error ZeroAddress();

    event SwapTokenToToken(
        address indexed claimer,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        IRouter.Route[] routes
    );

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
    // Keeper functions
    // -------------------------------------------------

    /// @notice Swap one token into the target token stored by the autoConverter
    ///         Only callable by keepers added by FactoryRegistry.owner() within AutoConverterFactory.
    ///         Swapping is done with routes and amounts swapped determined by the keeper.
    /// @dev _amountIn and _amountOutMin cannot be 0.
    /// @param _routes          Arrays for which swap routes to execute
    /// @param _amountIn        Amount of token in
    /// @param _amountOutMin    Minimum amount of token received
    function swapTokenToToken(IRouter.Route[] calldata _routes, uint256 _amountIn, uint256 _amountOutMin) external;
}

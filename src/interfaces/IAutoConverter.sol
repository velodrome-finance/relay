// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

interface IAutoConverter {
    error AmountInZero();
    error InvalidPath();
    error NotHighLiquidityToken();
    error NoRouteFound();
    error SlippageTooHigh();
    error TooLate();
    error TooSoon();
    error UnequalLengths();
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
    // Public functions
    // -------------------------------------------------

    /// @notice Swap token held by the autoConverter into token using the optimal route determined by
    ///         the ConverterOptimizer unless the user-provided swap route has a better rate
    ///         Publicly callable in the final 24 hours before the epoch flip or by an authorized keeper starting on the 2nd hour of an epoch flip or admin
    /// @dev Optional routes are provided when the optional amountOut exceeds the amountOut calculated by ConverterOptimizer
    function swapTokenToTokenWithOptionalRoute(
        address _tokenToSwap,
        uint256 _slippage,
        IRouter.Route[] memory _optionalRoutes
    ) external;
}

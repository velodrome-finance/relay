// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

interface IOptimizer {
    error NotEnoughPoints();

    function usdc() external view returns (address);

    function weth() external view returns (address);

    function op() external view returns (address);

    function velo() external view returns (address);

    function factory() external view returns (address);

    /// @notice Given a token and the amountIn, return the route to return the most token1 given 7 potential routes
    ///             of v2 Velodrome pools
    ///         If all potential routes return an amountOut of 0, returns 0
    /// @dev The potential routes are stored in the Optimizer
    /// @param token0    Address of token to swap from
    /// @param token1    Address of token to swap to
    /// @param amountIn Amount of token to swap
    /// @return IRouter.Route[] Array of optimal route path to swap
    function getOptimalTokenToTokenRoute(
        address token0,
        address token1,
        uint256 amountIn
    ) external view returns (IRouter.Route[] memory);

    /// @notice Get the minimum amount out allowed in a swap given the TWAP for each swap path
    ///         Returns 0 if the route path does not exist
    /// @param routes Swap route path
    /// @param amountIn amount of token swapped in
    /// @param points Number of points used in TWAP
    /// @param slippage Percent of allowed slippage in the swap, in basis points
    /// @return amountOutMin Minimum amount allowed of token received
    function getOptimalAmountOutMin(
        IRouter.Route[] calldata routes,
        uint256 amountIn,
        uint256 points,
        uint256 slippage
    ) external view returns (uint256 amountOutMin);
}

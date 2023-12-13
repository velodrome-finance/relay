// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IOptimizer} from "../interfaces/IOptimizer.sol";
import {IAutoConverter} from "../interfaces/IAutoConverter.sol";
import {IRelayFactory} from "../interfaces/IRelayFactory.sol";

import {VelodromeTimeLibrary} from "@velodrome/contracts/libraries/VelodromeTimeLibrary.sol";

import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

import {Relay} from "../Relay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Velodrome AutoConverter for Managed veNFTs
/// @author velodrome.finance, @figs999, @pegahcarter, @pedrovalido
/// @notice Auto-Convert voting rewards earned from a Managed veNFT into an erc20 token
/// @dev Only intended to be used by the DEFAULT_ADMIN and ALLOWED_CALLER- no public incentivization
contract AutoConverter is IAutoConverter, Relay {
    using SafeERC20 for IERC20;

    uint256 internal constant WEEK = 7 days;
    uint256 public constant MAX_SLIPPAGE = 500;
    uint256 public constant POINTS = 3;

    IRelayFactory public immutable autoConverterFactory;
    IRouter public immutable router;

    address public token;
    mapping(uint256 epoch => uint256 amount) public amountTokenEarned;

    constructor(
        address _voter,
        address _admin,
        string memory _name,
        address _router,
        address _token,
        address _optimizer,
        address _relayFactory
    ) Relay(_voter, _admin, _relayFactory, _optimizer, _name) {
        autoConverterFactory = IRelayFactory(msg.sender);
        router = IRouter(_router);
        token = _token;

        // Default admin can grant/revoke ALLOWED_CALLER roles
        // See `ALLOWED_CALLER functions` section for permissions
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ALLOWED_CALLER, _admin);
    }

    /// @dev Keep amountTokenEarned for the epoch synced based on the balance before and after operations
    modifier syncAmountTokenEarned() {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        _;
        uint256 delta = IERC20(token).balanceOf(address(this)) - balanceBefore;
        if (delta > 0) {
            amountTokenEarned[VelodromeTimeLibrary.epochStart(block.timestamp)] += delta;
        }
    }

    function _checkSwapPermissions(address _caller) internal view {
        if (hasRole(DEFAULT_ADMIN_ROLE, _caller)) return;

        uint256 timestamp = block.timestamp;
        uint256 secondHourStart = timestamp - (timestamp % WEEK) + 1 hours;
        if (relayFactory.isKeeper(_caller)) {
            if (timestamp >= secondHourStart) {
                return;
            } else {
                revert TooSoon();
            }
        }
        uint256 lastDayStart = timestamp - (timestamp % WEEK) + WEEK - 1 days;
        if (timestamp < lastDayStart) revert TooSoon();
    }

    // -------------------------------------------------
    // Public functions
    // -------------------------------------------------

    /// @inheritdoc IAutoConverter
    function swapTokenToTokenWithOptionalRoute(
        address _token,
        uint256 _slippage,
        IRouter.Route[] memory _optionalRoute
    ) external syncAmountTokenEarned nonReentrant {
        _checkSwapPermissions(msg.sender);
        if (_slippage > MAX_SLIPPAGE) revert SlippageTooHigh();
        if (_token == token) revert InvalidPath();
        if (_token == address(0)) revert ZeroAddress();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) revert AmountInZero();

        IRouter.Route[] memory routes = optimizer.getOptimalTokenToTokenRoute(_token, token, balance);
        uint256 amountOutMin = optimizer.getOptimalAmountOutMin(routes, balance, POINTS, _slippage);

        // If an optional route was provided, compare the amountOut with the hardcoded optimizer amountOut to determine which
        // route has a better rate
        // Used if optional route is not direct _token => token as this route is already calculated by Optimizer
        uint256 optionalRouteLen = _optionalRoute.length;
        if (optionalRouteLen > 1) {
            if (_optionalRoute[0].from != _token) revert InvalidPath();
            if (_optionalRoute[optionalRouteLen - 1].to != token) revert InvalidPath();
            // Ensure route only uses high liquidity tokens
            for (uint256 x = 1; x < optionalRouteLen; x++) {
                if (!autoConverterFactory.isHighLiquidityToken(_optionalRoute[x].from)) revert NotHighLiquidityToken();
            }

            uint256 optionalAmountOutMin = optimizer.getOptimalAmountOutMin(_optionalRoute, balance, POINTS, _slippage);
            if (optionalAmountOutMin > amountOutMin) {
                routes = _optionalRoute;
                amountOutMin = optionalAmountOutMin;
            }
        }
        if (amountOutMin == 0) revert NoRouteFound();

        // swap
        _handleApproval(IERC20(_token), address(router), balance);
        uint256[] memory amountsOut = router.swapExactTokensForTokens(
            balance,
            amountOutMin,
            routes,
            address(this),
            block.timestamp
        );

        if (relayFactory.isKeeper(msg.sender)) {
            keeperLastRun = block.timestamp;
        }

        emit SwapTokenToToken(msg.sender, _token, balance, amountsOut[amountsOut.length - 1], routes);
    }

    // -------------------------------------------------
    // DEFAULT_ADMIN_ROLE functions
    // -------------------------------------------------

    /// @inheritdoc IAutoConverter
    function sweep(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        IERC20(_token).safeTransfer(_recipient, _amount);
    }
}

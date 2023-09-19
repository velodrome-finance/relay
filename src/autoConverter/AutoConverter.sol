// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IAutoConverter} from "../interfaces/IAutoConverter.sol";
import {IRelayFactory} from "../interfaces/IRelayFactory.sol";

import {VelodromeTimeLibrary} from "@velodrome/contracts/libraries/VelodromeTimeLibrary.sol";

import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

import {Relay} from "../Relay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Velodrome AutoConverter for Managed veNFTs
/// @author velodrome.finance, @figs999, @pegahcarter
/// @notice Auto-Convert voting rewards earned from a Managed veNFT into an erc20 token
/// @dev Only intended to be used by the DEFAULT_ADMIN and ALLOWED_CALLER- no public incentivization
contract AutoConverter is IAutoConverter, Relay {
    using SafeERC20 for IERC20;

    IRelayFactory public immutable autoConverterFactory;
    IRouter public immutable router;

    address public token;
    mapping(uint256 epoch => uint256 amount) public amountTokenEarned;

    constructor(
        address _forwarder,
        address _voter,
        address _admin,
        string memory _name,
        address _router,
        address _token,
        address _relayFactory
    ) Relay(_forwarder, _voter, _admin, _relayFactory, _name) {
        autoConverterFactory = IRelayFactory(_msgSender());
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

    // -------------------------------------------------
    // Keeper functions
    // -------------------------------------------------

    /// @inheritdoc IAutoConverter
    function swapTokenToToken(
        IRouter.Route[] memory routes,
        uint256 amountIn,
        uint256 amountOutMin
    ) external onlyKeeper(msg.sender) syncAmountTokenEarned nonReentrant {
        if (amountIn == 0) revert AmountInZero();
        if (amountOutMin == 0) revert SlippageTooHigh();

        address from = routes[0].from;
        if (from == address(0)) revert InvalidPath();
        if (routes[routes.length - 1].to != address(token)) revert InvalidPath();
        if (from == token) revert InvalidPath();
        uint256 balance = IERC20(from).balanceOf(address(this));
        if (amountIn > balance) revert AmountInTooHigh();

        _handleApproval(IERC20(from), address(router), amountIn);
        uint256[] memory amountsOut = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            routes,
            address(this),
            block.timestamp
        );
        keeperLastRun = block.timestamp;

        emit SwapTokenToToken(_msgSender(), from, amountIn, amountsOut[amountsOut.length - 1], routes);
    }
}

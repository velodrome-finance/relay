// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ICompoundOptimizer} from "../interfaces/ICompoundOptimizer.sol";
import {IAutoCompounder} from "../interfaces/IAutoCompounder.sol";
import {IAutoCompounderFactory} from "../interfaces/IAutoCompounderFactory.sol";

import {VelodromeTimeLibrary} from "@velodrome/contracts/libraries/VelodromeTimeLibrary.sol";
import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

import {Relay} from "../Relay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Velodrome AutoCompounder for Managed veNFTs
/// @author velodrome.finance, @figs999, @pegahcarter, @pedrovalido
/// @notice Auto-Compound voting rewards earned from a Managed veNFT back into the veNFT through call incentivization
contract AutoCompounder is IAutoCompounder, Relay {
    using SafeERC20 for IERC20;

    uint256 internal constant WEEK = 7 days;
    uint256 public constant MAX_SLIPPAGE = 500;
    uint256 public constant POINTS = 3;

    IAutoCompounderFactory public immutable autoCompounderFactory;
    IRouter public immutable router;
    ICompoundOptimizer public immutable optimizer;

    mapping(uint256 epoch => uint256 amount) public amountTokenEarned;

    constructor(
        address _forwarder,
        address _voter,
        address _admin,
        string memory _name,
        address _router,
        address _optimizer,
        address _relayFactory
    ) Relay(_forwarder, _voter, _admin, _relayFactory, _name) {
        autoCompounderFactory = IAutoCompounderFactory(_msgSender());
        router = IRouter(_router);
        optimizer = ICompoundOptimizer(_optimizer);

        _grantRole(ALLOWED_CALLER, _admin);
    }

    /// @dev Validate timestamp is within the final 24 hours before the epoch flip
    modifier onlyLastDayOfEpoch() {
        uint256 timestamp = block.timestamp;
        uint256 lastDayStart = timestamp - (timestamp % WEEK) + WEEK - 1 days;
        if (timestamp < lastDayStart) revert TooSoon();
        _;
    }

    modifier onlyFirstDayOfEpoch() {
        uint256 timestamp = block.timestamp;
        uint256 firstDayEnd = timestamp - (timestamp % WEEK) + 1 days;
        if (timestamp >= firstDayEnd) revert TooLate();
        _;
    }

    /// @dev Keep amountTokenEarned for the epoch synced based on the balance before and after operations
    modifier syncAmountEarned() {
        uint256 balBefore = ve.balanceOfNFT(mTokenId);
        _;
        uint256 balAfter = ve.balanceOfNFT(mTokenId);
        if (balBefore < balAfter) {
            amountTokenEarned[VelodromeTimeLibrary.epochStart(block.timestamp)] += balAfter - balBefore;
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

    /// @inheritdoc IAutoCompounder
    function swapTokenToVELOWithOptionalRoute(
        address _token,
        uint256 _slippage,
        IRouter.Route[] memory _optionalRoute
    ) external nonReentrant {
        _checkSwapPermissions(msg.sender);
        if (_slippage > MAX_SLIPPAGE) revert SlippageTooHigh();
        if (_token == address(velo)) revert InvalidPath();
        if (_token == address(0)) revert ZeroAddress();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) revert AmountInZero();

        IRouter.Route[] memory routes = optimizer.getOptimalTokenToVeloRoute(_token, balance);
        uint256 amountOutMin = optimizer.getOptimalAmountOutMin(routes, balance, POINTS, _slippage);

        // If an optional route was provided, compare the amountOut with the hardcoded optimizer amountOut to determine which
        // route has a better rate
        // Used if optional route is not direct _token => VELO as this route is already calculated by CompoundOptimizer
        uint256 optionalRouteLen = _optionalRoute.length;
        if (optionalRouteLen > 1) {
            if (_optionalRoute[0].from != _token) revert InvalidPath();
            if (_optionalRoute[optionalRouteLen - 1].to != address(velo)) revert InvalidPath();
            // Ensure route only uses high liquidity tokens
            for (uint256 x = 1; x < optionalRouteLen; x++) {
                if (!autoCompounderFactory.isHighLiquidityToken(_optionalRoute[x].from)) revert NotHighLiquidityToken();
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

        emit SwapTokenToVELO(_msgSender(), _token, balance, amountsOut[amountsOut.length - 1], routes);
    }

    /// @inheritdoc IAutoCompounder
    function rewardAndCompound() external onlyLastDayOfEpoch {
        address sender = _msgSender();
        uint256 balance = velo.balanceOf(address(this));
        uint256 reward;

        if (balance > 0) {
            // reward the caller the minimum of:
            // - 1% of the VELO designated for compounding (Rounds down)
            // - The constant VELO reward set by team in AutoCompounderFactory
            uint256 compoundRewardAmount = balance / 100;
            uint256 factoryRewardAmount = autoCompounderFactory.rewardAmount();
            reward = compoundRewardAmount < factoryRewardAmount ? compoundRewardAmount : factoryRewardAmount;

            if (reward > 0) {
                velo.transfer(sender, reward);
            }
            emit Reward(sender, reward);
        }
        compound();
    }

    /// @inheritdoc IAutoCompounder
    function compound() public syncAmountEarned {
        _handleRebase();

        uint256 balance = velo.balanceOf(address(this));
        if (balance > 0) {
            // Deposit the remaining balance into the nft
            _handleApproval(velo, address(ve), balance);
            ve.increaseAmount(mTokenId, balance);
            emit Compound(balance);
        }
    }

    function token() external view override returns (address) {
        return address(velo);
    }

    // -------------------------------------------------
    // DEFAULT_ADMIN_ROLE functions
    // -------------------------------------------------

    /// @inheritdoc IAutoCompounder
    function setName(string calldata _name) external onlyRole(DEFAULT_ADMIN_ROLE) {
        string memory oldName = name;
        name = _name;
        emit SetName(oldName, _name);
    }

    /// @inheritdoc IAutoCompounder
    function sweep(
        address[] calldata _tokensToSweep,
        address[] calldata _recipients
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyFirstDayOfEpoch nonReentrant {
        uint256 length = _tokensToSweep.length;
        if (length != _recipients.length) revert UnequalLengths();
        for (uint256 i = 0; i < length; i++) {
            address tokenToSweep = _tokensToSweep[i];
            if (autoCompounderFactory.isHighLiquidityToken(tokenToSweep)) revert HighLiquidityToken();
            address recipient = _recipients[i];
            if (recipient == address(0)) revert ZeroAddress();
            uint256 balance = IERC20(tokenToSweep).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokenToSweep).safeTransfer(recipient, balance);
                emit Sweep(tokenToSweep, msg.sender, recipient, balance);
            }
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IAutoConverter} from "../interfaces/IAutoConverter.sol";
import {IAutoConverterFactory} from "../interfaces/IAutoConverterFactory.sol";

import {VelodromeTimeLibrary} from "@velodrome/contracts/libraries/VelodromeTimeLibrary.sol";

import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";
import {IVelo} from "@velodrome/contracts/interfaces/IVelo.sol";
import {IVoter} from "@velodrome/contracts/interfaces/IVoter.sol";
import {IVotingEscrow} from "@velodrome/contracts/interfaces/IVotingEscrow.sol";
import {IRewardsDistributor} from "@velodrome/contracts/interfaces/IRewardsDistributor.sol";
import {IRouter} from "@velodrome/contracts/interfaces/IRouter.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/// @title Velodrome AutoConverter for Managed veNFTs
/// @author velodrome.finance, @figs999, @pegahcarter
/// @notice Auto-Convert voting rewards earned from a Managed veNFT into an erc20 token
/// @dev Only intended to be used by the DEFAULT_ADMIN and ALLOWED_CALLER- no public incentivization
contract AutoConverter is IAutoConverter, ERC721Holder, ERC2771Context, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    bytes32 public constant ALLOWED_CALLER = keccak256("ALLOWED_CALLER");

    IAutoConverterFactory public immutable autoConverterFactory;
    IRouter public immutable router;
    IVoter public immutable voter;
    IVotingEscrow public immutable ve;
    IVelo public immutable velo;
    IRewardsDistributor public immutable distributor;

    uint256 public tokenId;
    address public token;
    mapping(uint256 epoch => uint256 amount) public amountTokenEarned;

    constructor(
        address _forwarder,
        address _router,
        address _voter,
        address _token,
        address _admin
    ) ERC2771Context(_forwarder) {
        autoConverterFactory = IAutoConverterFactory(_msgSender());
        router = IRouter(_router);
        voter = IVoter(_voter);
        token = _token;

        ve = IVotingEscrow(voter.ve());
        velo = IVelo(ve.token());
        distributor = IRewardsDistributor(ve.distributor());

        // max approval is safe because of the immutability of ve.
        // This approval is only ever utilized from ve.increaseAmount() calls.
        velo.approve(address(ve), type(uint256).max);

        // Default admin can grant/revoke ALLOWED_CALLER roles
        // See `ALLOWED_CALLER functions` section for permissions
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ALLOWED_CALLER, _admin);
    }

    /// @dev Called within the creation transaction
    function initialize(uint256 _tokenId) external {
        if (_msgSender() != address(autoConverterFactory)) revert NotFactory();
        if (tokenId != 0) revert AlreadyInitialized();

        tokenId = _tokenId;
    }

    /// @dev Validate msg.sender is a keeper added by Velodrome team.
    modifier onlyKeeper(address _sender) {
        if (!autoConverterFactory.isKeeper(_sender)) revert NotKeeper();
        _;
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
    // ALLOWED_CALLER functions
    // -------------------------------------------------

    /// @inheritdoc IAutoConverter
    function increaseAmount(uint256 _value) external onlyRole(ALLOWED_CALLER) {
        velo.transferFrom(_msgSender(), address(this), _value);
        ve.increaseAmount(tokenId, _value);
    }

    /// @inheritdoc IAutoConverter
    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external onlyRole(ALLOWED_CALLER) {
        voter.vote(tokenId, _poolVote, _weights);
    }

    // -------------------------------------------------
    // Keeper functions
    // -------------------------------------------------

    /// @inheritdoc IAutoConverter
    function claimAndConvertKeeper(
        address[] memory _bribes,
        address[][] memory _bribesTokens,
        address[] memory _fees,
        address[][] memory _feesTokens,
        IRouter.Route[][] calldata _allRoutes,
        uint256[] calldata _amountsIn,
        uint256[] calldata _amountsOutMin
    ) external onlyKeeper(msg.sender) syncAmountTokenEarned nonReentrant {
        if (_allRoutes.length != _amountsIn.length || _allRoutes.length != _amountsOutMin.length)
            revert UnequalLengths();

        uint256 _tokenId = tokenId;
        voter.claimBribes(_bribes, _bribesTokens, _tokenId);
        voter.claimFees(_fees, _feesTokens, _tokenId);
        for (uint256 i = 0; i < _allRoutes.length; i++) {
            _swapTokenToTokenKeeper(_allRoutes[i], _amountsIn[i], _amountsOutMin[i]);
        }

        // claim rebase if possible
        if (distributor.claimable(_tokenId) > 0) {
            distributor.claim(_tokenId);
        }
    }

    function _swapTokenToTokenKeeper(IRouter.Route[] memory routes, uint256 amountIn, uint256 amountOutMin) internal {
        if (amountIn == 0) revert AmountInZero();
        if (amountOutMin == 0) revert SlippageTooHigh();

        address from = routes[0].from;
        if (from == address(0)) revert InvalidPath();
        if (routes[routes.length - 1].to != address(token)) revert InvalidPath();
        if (from == token) revert InvalidPath();
        uint256 balance = IERC20(from).balanceOf(address(this));
        if (amountIn > balance) revert AmountInTooHigh();

        _handleRouterApproval(IERC20(from), amountIn);
        uint256[] memory amountsOut = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            routes,
            address(this),
            block.timestamp
        );

        emit SwapTokenToTokenKeeper(_msgSender(), from, amountIn, amountsOut[amountsOut.length - 1], routes);
    }

    // -------------------------------------------------
    // Helpers
    // -------------------------------------------------

    /// @dev resets approval if needed then approves transfer of tokens to router
    function _handleRouterApproval(IERC20 _erc20, uint256 _amount) internal {
        uint256 allowance = _erc20.allowance(address(this), address(router));
        if (allowance > 0) _erc20.safeDecreaseAllowance(address(router), allowance);
        _erc20.safeIncreaseAllowance(address(router), _amount);
    }

    // -------------------------------------------------
    // Overrides
    // -------------------------------------------------

    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function _msgSender() internal view override(ERC2771Context, Context) returns (address) {
        return ERC2771Context._msgSender();
    }
}

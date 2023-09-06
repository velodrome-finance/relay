// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "src/Relay.sol";
import "src/AutoCompounder.sol";
import "src/CompoundOptimizer.sol";
import "src/AutoCompounderFactory.sol";

import "@velodrome/test/BaseTest.sol";

contract AutoCompounderTest is BaseTest {
    uint256 tokenId;
    uint256 mTokenId;

    AutoCompounderFactory autoCompounderFactory;
    AutoCompounder autoCompounder;
    CompoundOptimizer optimizer;
    LockedManagedReward lockedManagedReward;
    FreeManagedReward freeManagedReward;

    address[] bribes;
    address[] fees;
    address[][] tokensToClaim;
    address[] tokensToSweep;
    address[] recipients;

    constructor() {
        deploymentType = Deployment.FORK;
    }

    function _setUp() public override {
        // create managed veNFT
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));

        vm.startPrank(address(owner));

        // Create normal veNFT and deposit into managed
        deal(address(VELO), address(owner), TOKEN_1);
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        skipToNextEpoch(1 hours + 1);
        voter.depositManaged(tokenId, mTokenId);

        // Create auto compounder
        optimizer = new CompoundOptimizer(
            address(USDC),
            address(WETH),
            address(FRAX), // OP
            address(VELO),
            address(factory),
            address(router)
        );
        autoCompounderFactory = new AutoCompounderFactory(
            address(forwarder),
            address(voter),
            address(router),
            address(optimizer),
            address(factoryRegistry),
            new address[](0)
        );
        escrow.approve(address(autoCompounderFactory), mTokenId);
        autoCompounder = AutoCompounder(autoCompounderFactory.createAutoCompounder(address(owner), mTokenId, ""));

        skipToNextEpoch(1 hours + 1);

        vm.stopPrank();

        // Add the owner as a keeper
        vm.prank(escrow.team());
        autoCompounderFactory.addKeeper(address(owner));

        // Create a VELO pool for USDC, WETH, and FRAX (seen as OP in CompoundOptimizer)
        deal(address(VELO), address(owner), TOKEN_100K * 3);
        deal(address(WETH), address(owner), TOKEN_1 * 3);

        // @dev these pools have a higher VELO price value than v1 pools
        _createPoolAndSimulateSwaps(address(USDC), address(VELO), USDC_1, TOKEN_1, address(USDC), 10, 3);
        _createPoolAndSimulateSwaps(address(WETH), address(VELO), TOKEN_1, TOKEN_100K, address(VELO), 1e6, 3);
        _createPoolAndSimulateSwaps(address(FRAX), address(VELO), TOKEN_1, TOKEN_1, address(VELO), 1e6, 3);
        _createPoolAndSimulateSwaps(address(FRAX), address(DAI), TOKEN_1, TOKEN_1, address(FRAX), 1e6, 3);

        // skip to last day where claiming becomes public
        skipToNextEpoch(6 days + 1);
    }

    function _createPoolAndSimulateSwaps(
        address token1,
        address token2,
        uint256 liquidity1,
        uint256 liquidity2,
        address tokenIn,
        uint256 amountSwapped,
        uint256 numSwapped
    ) internal {
        address tokenOut = tokenIn == token1 ? token2 : token1;
        _addLiquidityToPool(address(owner), address(router), token1, token2, false, liquidity1, liquidity2);

        IRouter.Route[] memory routes = new IRouter.Route[](1);

        // for every hour, simulate a swap to add an observation
        for (uint256 i = 0; i < numSwapped; i++) {
            skipAndRoll(1 hours);
            routes[0] = IRouter.Route(tokenIn, tokenOut, false, address(0));

            IERC20(tokenIn).approve(address(router), amountSwapped);
            router.swapExactTokensForTokens(amountSwapped, 0, routes, address(owner), block.timestamp);
        }
    }

    function testCannotSwapIfNoRouteFound() public {
        // Create a new pool with liquidity that doesn't swap into VELO
        IERC20 tokenA = IERC20(new MockERC20("Token A", "A", 18));
        IERC20 tokenB = IERC20(new MockERC20("Token B", "B", 18));
        deal(address(tokenA), address(owner), TOKEN_1 * 2, true);
        deal(address(tokenB), address(owner), TOKEN_1 * 2, true);
        _createPoolAndSimulateSwaps(address(tokenA), address(tokenB), TOKEN_1, TOKEN_1, address(tokenA), 1e6, 3);

        // give rewards to the autoCompounder
        deal(address(tokenA), address(autoCompounder), 1e6);

        // Attempt swapping into VELO - should revert
        address tokenToSwap = address(tokenA);
        uint256 slippage = 0;
        vm.expectRevert(IAutoCompounder.NoRouteFound.selector);
        autoCompounder.swapTokenToVELO(tokenToSwap, slippage);

        // Cannot swap for a token that doesn't have a pool
        IERC20 tokenC = IERC20(new MockERC20("Token C", "C", 18));
        deal(address(tokenC), address(autoCompounder), 1e6);

        tokenToSwap = address(tokenC);

        // Attempt swapping into VELO - should revert
        vm.expectRevert(IAutoCompounder.NoRouteFound.selector);
        autoCompounder.swapTokenToVELO(tokenToSwap, slippage);
    }

    function testSwapToVELOAndCompoundIfCompoundRewardAmount() public {
        // Deal USDC, FRAX, and DAI to autocompounder to simulate earning bribes
        // NOTE: the low amount of bribe rewards leads to receiving 1% of the reward amount
        deal(address(USDC), address(autoCompounder), 1e2);
        deal(address(FRAX), address(autoCompounder), 1e6);
        deal(address(DAI), address(autoCompounder), 1e6);

        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);
        uint256 balanceVELOBefore = VELO.balanceOf(address(owner4));

        // Random user calls swapToVELO() for each token and then claims reward
        vm.startPrank(address(owner4));
        uint256 slippage = 500;
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeCall(autoCompounder.swapTokenToVELO, (address(USDC), slippage));
        calls[1] = abi.encodeCall(autoCompounder.swapTokenToVELO, (address(FRAX), slippage));
        calls[2] = abi.encodeCall(autoCompounder.swapTokenToVELO, (address(DAI), slippage));
        calls[3] = abi.encodeWithSelector(autoCompounder.rewardAndCompound.selector);
        autoCompounder.multicall(calls);

        // USDC and FRAX converted even though they already have a direct pair to VELO
        // DAI converted without a direct pair to VELO
        assertEq(USDC.balanceOf(address(autoCompounder)), 0);
        assertEq(FRAX.balanceOf(address(autoCompounder)), 0);
        assertEq(DAI.balanceOf(address(autoCompounder)), 0);
        assertEq(VELO.balanceOf(address(autoCompounder)), 0);

        uint256 rewardAmountToNFT = escrow.balanceOfNFT(mTokenId) - balanceNFTBefore;
        uint256 rewardAmountToCaller = VELO.balanceOf(address(owner4)) - balanceVELOBefore;

        assertGt(rewardAmountToNFT, 0);
        assertGt(rewardAmountToCaller, 0);
        assertLt(rewardAmountToCaller, autoCompounderFactory.rewardAmount());

        // total reward is 100x what caller received - as caller received 1% the total reward
        assertEq((rewardAmountToNFT + rewardAmountToCaller) / 100, rewardAmountToCaller);
    }

    function testSwapToVELOAndCompoundIfFactoryRewardAmount() public {
        // Adjust the factory reward rate to a lower VELO to trigger the rewardAmount.
        // NOTE: this will not be needed in prod as more than 0.00000001 DAI etc. will
        // be compounded at one time
        vm.prank(escrow.team());
        autoCompounderFactory.setRewardAmount(1e17);

        // Deal USDC, WETH, and DAI to autocompounder to simulate earning bribe rewards
        // NOTE; the difference here is WETH for a higher amount of VELO swapped
        deal(address(USDC), address(autoCompounder), 1e3);
        deal(address(WETH), address(autoCompounder), 1e15);
        deal(address(DAI), address(autoCompounder), 1e6);

        uint256 balanceVELOCallerBefore = VELO.balanceOf(address(owner4));
        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);

        // Random user calls swapToVELO() for each token and then claims reward
        vm.startPrank(address(owner4));
        uint256 slippage = 500;
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeCall(autoCompounder.swapTokenToVELO, (address(USDC), slippage));
        calls[1] = abi.encodeCall(autoCompounder.swapTokenToVELO, (address(WETH), slippage));
        calls[2] = abi.encodeCall(autoCompounder.swapTokenToVELO, (address(DAI), slippage));
        calls[3] = abi.encodeWithSelector(autoCompounder.rewardAndCompound.selector);
        autoCompounder.multicall(calls);

        // USDC and FRAX converted even though they already have a direct pair to VELO
        // DAI converted without a direct pair to VELO
        assertEq(USDC.balanceOf(address(autoCompounder)), 0);
        assertEq(WETH.balanceOf(address(autoCompounder)), 0);
        assertEq(DAI.balanceOf(address(autoCompounder)), 0);
        assertEq(VELO.balanceOf(address(autoCompounder)), 0);

        // Compounded into the mTokenId and caller has received a refund equal to the factory rewardAmount
        assertEq(VELO.balanceOf(address(owner4)), balanceVELOCallerBefore + autoCompounderFactory.rewardAmount());
        assertGt(escrow.balanceOfNFT(mTokenId), balanceNFTBefore);
    }

    function testClaimAndMulticallClaimRebaseOnly() public {
        address[] memory pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        autoCompounder.vote(pools, weights);

        skipToNextEpoch(6 days + 1);
        minter.updatePeriod();

        uint256 claimable = distributor.claimable(mTokenId);
        assertGt(distributor.claimable(mTokenId), 0);

        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(autoCompounder.claimBribes, (bribes, tokensToClaim));
        autoCompounder.multicall(calls);
        assertEq(escrow.balanceOfNFT(mTokenId), balanceNFTBefore + claimable);
    }

    function testRewardAndCompoundOnlyExistingVELOBalance() public {
        deal(address(VELO), address(autoCompounder), 1e18);

        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);

        vm.prank(address(owner2));
        autoCompounder.rewardAndCompound();

        // mTokenId has received the full VELO balance from the autoCompounder - meaning
        // the VELO has been directly compounded without a swap (minus fee)
        assertEq(escrow.balanceOfNFT(mTokenId), balanceNFTBefore + 1e18 - 1e16);
        assertEq(VELO.balanceOf(address(autoCompounder)), 0);
    }

    function testSwapTokenToVELOWithOptionalRouteAndCompoundIfBetterRate() public {
        // create a new pool with
        //  - liquidity of the token swapped to the mock token
        //  - liquidity of the mock token to VELO to return a lot of VELO
        // And add mock token as a high liquidity token
        MockERC20 mockToken = new MockERC20("Mock Token", "MOCK", 18);
        autoCompounderFactory.addHighLiquidityToken(address(mockToken));
        deal(address(mockToken), address(owner), TOKEN_1 * 3);
        deal(address(VELO), address(owner), TOKEN_100M + TOKEN_1 * 3);

        _createPoolAndSimulateSwaps(address(mockToken), address(FRAX), TOKEN_1, TOKEN_1, address(FRAX), 1e6, 3);
        _createPoolAndSimulateSwaps(address(mockToken), address(VELO), TOKEN_1, TOKEN_100M, address(VELO), TOKEN_1, 3);

        // simulate reward
        deal(address(FRAX), address(autoCompounder), 1e6);

        IRouter.Route[] memory optionalRoute = new IRouter.Route[](2);
        optionalRoute[0] = IRouter.Route(address(FRAX), address(mockToken), false, address(0));
        optionalRoute[1] = IRouter.Route(address(mockToken), address(VELO), false, address(0));

        address tokenToSwap = address(FRAX);
        uint256 slippage = 500;

        uint256[] memory amountsOut = router.getAmountsOut(1e6, optionalRoute);
        uint256 amountOut = amountsOut[amountsOut.length - 1];
        uint256 balanceOwnerBefore = VELO.balanceOf(address(owner));
        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            autoCompounder.swapTokenToVELOWithOptionalRoute,
            (tokenToSwap, slippage, optionalRoute)
        );
        calls[1] = abi.encodeWithSelector(autoCompounder.rewardAndCompound.selector);
        autoCompounder.multicall(calls);

        // validate the amount received by caller and balance increased to (m)veNFT equal
        // the amount out of the optionalRoute over the CompoundOptimizer suggested route
        uint256 balanceOwnerDelta = VELO.balanceOf(address(owner)) - balanceOwnerBefore;
        uint256 balanceNFTDelta = escrow.balanceOfNFT(mTokenId) - balanceNFTBefore;
        assertEq(balanceOwnerDelta + balanceNFTDelta, amountOut);
    }

    function testSwapTokenToVELOWithOptionalRouteAndCompoundIfBetterRateFromHighLiquidityToken() public {
        // create a new pool with
        //  - liquidity of the token swapped to the mock token
        //  - liquidity of the mock token to VELO to return a lot of VELO
        // Add mock token and token swapping from as high liquidity tokens
        MockERC20 mockToken = new MockERC20("Mock Token", "MOCK", 18);
        autoCompounderFactory.addHighLiquidityToken(address(mockToken));
        autoCompounderFactory.addHighLiquidityToken(address(FRAX));
        deal(address(mockToken), address(owner), TOKEN_1 * 3);
        deal(address(VELO), address(owner), TOKEN_100M + TOKEN_1 * 3);

        _createPoolAndSimulateSwaps(address(mockToken), address(FRAX), TOKEN_1, TOKEN_1, address(FRAX), 1e6, 3);
        _createPoolAndSimulateSwaps(address(mockToken), address(VELO), TOKEN_1, TOKEN_100M, address(VELO), TOKEN_1, 3);

        // simulate reward
        deal(address(FRAX), address(autoCompounder), 1e6);

        address tokenToSwap = address(FRAX);
        uint256 slippage = 500;
        IRouter.Route[] memory optionalRoute = new IRouter.Route[](2);
        optionalRoute[0] = IRouter.Route(address(FRAX), address(mockToken), false, address(0));
        optionalRoute[1] = IRouter.Route(address(mockToken), address(VELO), false, address(0));

        uint256[] memory amountsOut = router.getAmountsOut(1e6, optionalRoute);
        uint256 amountOut = amountsOut[amountsOut.length - 1];
        uint256 balanceOwnerBefore = VELO.balanceOf(address(owner));
        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            autoCompounder.swapTokenToVELOWithOptionalRoute,
            (tokenToSwap, slippage, optionalRoute)
        );
        calls[1] = abi.encodeWithSelector(autoCompounder.rewardAndCompound.selector);
        autoCompounder.multicall(calls);

        // validate the amount received by caller and balance increased to (m)veNFT equal
        // the amount out of the optionalRoute over the CompoundOptimizer suggested route
        uint256 balanceOwnerDelta = VELO.balanceOf(address(owner)) - balanceOwnerBefore;
        uint256 balanceNFTDelta = escrow.balanceOfNFT(mTokenId) - balanceNFTBefore;
        assertEq(balanceOwnerDelta + balanceNFTDelta, amountOut);
    }

    function testCannotSwapTokenToVELOWithOptionalRouteIfDoesNotUseHighLiquidityToken() public {
        // create a new pool with
        //  - liquidity of the token swapped to the mock token
        //  - liquidity of the mock token to VELO to return a lot of VELO
        // Mock Token is not added as a high liquidity token, so will revert
        MockERC20 mockToken = new MockERC20("Mock Token", "MOCK", 18);
        deal(address(mockToken), address(owner), TOKEN_1 * 3);
        deal(address(VELO), address(owner), TOKEN_100M + TOKEN_1 * 3);

        _createPoolAndSimulateSwaps(address(mockToken), address(FRAX), TOKEN_1, TOKEN_1, address(FRAX), 1e6, 3);
        _createPoolAndSimulateSwaps(address(mockToken), address(VELO), TOKEN_1, TOKEN_100M, address(VELO), TOKEN_1, 3);

        // simulate reward
        deal(address(FRAX), address(autoCompounder), 1e6);

        address tokenToSwap = address(FRAX);
        uint256 slippage = 500;
        IRouter.Route[] memory optionalRoute = new IRouter.Route[](2);
        optionalRoute[0] = IRouter.Route(address(FRAX), address(mockToken), false, address(0));
        optionalRoute[1] = IRouter.Route(address(mockToken), address(VELO), false, address(0));

        vm.expectRevert(IAutoCompounder.NotHighLiquidityToken.selector);
        autoCompounder.swapTokenToVELOWithOptionalRoute(tokenToSwap, slippage, optionalRoute);
    }

    function testSwapTokenToVELOWithOptionalRouteAndCompoundIfOnlyRoute() public {
        // create a new pool with
        //  - liquidity of the mock token to VELO
        // For a token that does NOT have a route supported by CompoundOptimizer
        MockERC20 mockToken = new MockERC20("Mock Token", "MOCK", 18);
        deal(address(mockToken), address(owner), TOKEN_1 * 3);
        deal(address(VELO), address(owner), TOKEN_100M + TOKEN_1 * 3);

        _createPoolAndSimulateSwaps(address(mockToken), address(VELO), TOKEN_1, TOKEN_100M, address(VELO), TOKEN_1, 3);

        // simulate reward
        deal(address(mockToken), address(autoCompounder), 1e6);

        address tokenToSwap = address(mockToken);
        uint256 slippage = 500;
        IRouter.Route[] memory optionalRoute = new IRouter.Route[](1);
        optionalRoute[0] = IRouter.Route(address(mockToken), address(VELO), false, address(0));

        uint256[] memory amountsOut = router.getAmountsOut(1e6, optionalRoute);
        uint256 amountOut = amountsOut[amountsOut.length - 1];
        uint256 balanceOwnerBefore = VELO.balanceOf(address(owner));
        uint256 balanceNFTBefore = escrow.balanceOfNFT(mTokenId);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            autoCompounder.swapTokenToVELOWithOptionalRoute,
            (tokenToSwap, slippage, optionalRoute)
        );
        calls[1] = abi.encodeWithSelector(autoCompounder.rewardAndCompound.selector);
        autoCompounder.multicall(calls);

        // validate the amount received by caller and balance increased to (m)veNFT equal
        // the amount out of the optionalRoute
        uint256 balanceOwnerDelta = VELO.balanceOf(address(owner)) - balanceOwnerBefore;
        uint256 balanceNFTDelta = escrow.balanceOfNFT(mTokenId) - balanceNFTBefore;
        assertEq(balanceOwnerDelta + balanceNFTDelta, amountOut);
    }

    function testIncreaseAmount() public {
        uint256 amount = TOKEN_1;
        deal(address(VELO), address(owner), amount);
        VELO.approve(address(autoCompounder), amount);

        uint256 balanceBefore = escrow.balanceOfNFT(mTokenId);
        uint256 supplyBefore = escrow.totalSupply();

        autoCompounder.increaseAmount(amount);

        assertEq(escrow.balanceOfNFT(mTokenId), balanceBefore + amount);
        assertEq(escrow.totalSupply(), supplyBefore + amount);
    }

    function testVote() public {
        address[] memory poolVote = new address[](1);
        uint256[] memory weights = new uint256[](1);
        poolVote[0] = address(pool2);
        weights[0] = 1;

        assertFalse(escrow.voted(mTokenId));

        autoCompounder.vote(poolVote, weights);

        assertTrue(escrow.voted(mTokenId));
        assertEq(voter.weights(address(pool2)), escrow.balanceOfNFT(mTokenId));
        assertEq(voter.votes(mTokenId, address(pool2)), escrow.balanceOfNFT(mTokenId));
        assertEq(voter.poolVote(mTokenId, 0), address(pool2));
    }

    function testSwapTokenToVELOAndCompoundKeeper() public {
        uint256 amount = TOKEN_1 / 100;
        deal(address(WETH), address(autoCompounder), amount);

        uint256 balanceBefore = escrow.balanceOfNFT(mTokenId);
        uint256 veloBalanceBefore = VELO.balanceOf(address(owner));

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(WETH), address(VELO), false, address(0));
        uint256[] memory amountsOut = router.getAmountsOut(amount, routes);
        uint256 amountOut = amountsOut[amountsOut.length - 1];
        assertGt(amountOut, 0);

        uint256 amountIn = amount;
        uint256 amountOutMin = 1;
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(autoCompounder.swapTokenToVELOKeeper, (routes, amountIn, amountOutMin));
        calls[1] = abi.encodeWithSelector(autoCompounder.compound.selector);
        autoCompounder.multicall(calls);

        // no reward given to caller this time- full amount deposited into mTokenId
        assertEq(VELO.balanceOf(address(owner)), veloBalanceBefore);
        assertEq(escrow.balanceOfNFT(mTokenId), balanceBefore + amountOut);
        assertEq(autoCompounder.amountTokenEarned(VelodromeTimeLibrary.epochStart(block.timestamp)), amountOut);
    }

    function testCannotInitializeIfAlreadyInitialized() external {
        vm.prank(address(autoCompounder.autoCompounderFactory()));
        vm.expectRevert("Initializable: contract is already initialized");
        autoCompounder.initialize(1);
    }

    function testCannotSwapTokenToVELOIfNotOnLastDayOfEpoch() external {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(autoCompounder.swapTokenToVELO, (address(0), 0));
        skipToNextEpoch(0);
        vm.expectRevert(IAutoCompounder.TooSoon.selector);
        autoCompounder.swapTokenToVELO(address(0), 0);
        vm.expectRevert(IRelay.MulticallFailed.selector);
        autoCompounder.multicall(calls);

        skipToNextEpoch(6 days - 1);
        vm.expectRevert(IAutoCompounder.TooSoon.selector);
        autoCompounder.swapTokenToVELO(address(0), 0);
        vm.expectRevert(IRelay.MulticallFailed.selector);
        autoCompounder.multicall(calls);
    }

    function testCannotRewardAndCompoundIfNotOnLastDayOfEpoch() external {
        skipToNextEpoch(0);
        vm.expectRevert(IAutoCompounder.TooSoon.selector);
        autoCompounder.rewardAndCompound();

        skipToNextEpoch(6 days - 1);
        vm.expectRevert(IAutoCompounder.TooSoon.selector);
        autoCompounder.rewardAndCompound();
    }

    function testCannotSwapIfSlippageTooHigh() public {
        address tokenToSwap = address(USDC);
        uint256 slippage = 501;
        vm.expectRevert(IAutoCompounder.SlippageTooHigh.selector);
        autoCompounder.swapTokenToVELO(tokenToSwap, slippage);
    }

    function testCannotSwapIfAmountInZero() public {
        vm.expectRevert(IAutoCompounder.AmountInZero.selector);
        autoCompounder.swapTokenToVELO(address(USDC), 500);
    }

    function testHandleRouterApproval() public {
        deal(address(FRAX), address(autoCompounder), TOKEN_1 / 1000, true);

        // give a fake approval to impersonate a dangling approved amount
        vm.prank(address(autoCompounder));
        FRAX.approve(address(router), 100);

        // resets and properly approves swap amount
        address tokenToSwap = address(FRAX);
        uint256 slippage = 500;

        autoCompounder.swapTokenToVELO(tokenToSwap, slippage);
        assertEq(FRAX.allowance(address(autoCompounder), address(router)), 0);
    }

    // TODO: order tests similar to AutoCompounder with section titles
    function testCannotSweepAfterFirstDayOfEpoch() public {
        skipToNextEpoch(1 days + 1);
        vm.expectRevert(IAutoCompounder.TooLate.selector);
        autoCompounder.sweep(tokensToSweep, recipients);
    }

    function testCannotSweepIfNotAdmin() public {
        skipToNextEpoch(1 days - 1);
        bytes memory revertString = bytes(
            "AccessControl: account 0x7d28001937fe8e131f76dae9e9947adedbd0abde is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        vm.startPrank(address(owner2));
        vm.expectRevert(revertString);
        autoCompounder.sweep(tokensToSweep, recipients);
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(autoCompounder.sweep, (tokensToSweep, recipients));
        vm.expectRevert(IRelay.MulticallFailed.selector);
        autoCompounder.multicall(calls);
    }

    function testCannotSweepUnequalLengths() public {
        skipToNextEpoch(1 days - 1);
        recipients.push(address(owner2));
        assertTrue(tokensToSweep.length != recipients.length);
        vm.prank(escrow.team());
        vm.expectRevert(IAutoCompounder.UnequalLengths.selector);
        autoCompounder.sweep(tokensToSweep, recipients);
    }

    function testCannotSweepHighLiquidityToken() public {
        skipToNextEpoch(1 days - 1);
        tokensToSweep.push(address(USDC));
        recipients.push(address(owner2));
        vm.prank(escrow.team());
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
        vm.expectRevert(IAutoCompounder.HighLiquidityToken.selector);
        autoCompounder.sweep(tokensToSweep, recipients);
    }

    function testCannotSweepZeroAddressRecipient() public {
        skipToNextEpoch(1 days - 1);
        tokensToSweep.push(address(USDC));
        recipients.push(address(0));
        vm.prank(escrow.team());
        vm.expectRevert(IAutoCompounder.ZeroAddress.selector);
        autoCompounder.sweep(tokensToSweep, recipients);
    }

    function testSweep() public {
        skipToNextEpoch(1 days - 1);
        tokensToSweep.push(address(USDC));
        recipients.push(address(owner2));
        deal(address(USDC), address(autoCompounder), USDC_1);
        uint256 balanceBefore = USDC.balanceOf(address(owner2));
        vm.prank(escrow.team());
        autoCompounder.sweep(tokensToSweep, recipients);
        assertEq(USDC.balanceOf(address(owner2)), balanceBefore + USDC_1);
    }

    function testCannotSwapKeeperIfWithinFirstDayOfEpoch() public {
        skipToNextEpoch(1 days - 1);

        vm.expectRevert(IAutoCompounder.TooSoon.selector);
        autoCompounder.swapTokenToVELOKeeper(new IRouter.Route[](0), 0, 0);
    }

    function testCannotSwapKeeperIfNotKeeper() public {
        vm.startPrank(address(owner2));
        vm.expectRevert(IAutoCompounder.NotKeeper.selector);
        autoCompounder.swapTokenToVELOKeeper(new IRouter.Route[](0), 0, 0);
    }

    function testCannotSwapKeeperIfAmountInZero() public {
        vm.expectRevert(IAutoCompounder.AmountInZero.selector);
        autoCompounder.swapTokenToVELOKeeper(new IRouter.Route[](0), 0, 0);
    }

    function testCannotSwapKeeperIfSlippageTooHigh() public {
        vm.expectRevert(IAutoCompounder.SlippageTooHigh.selector);
        autoCompounder.swapTokenToVELOKeeper(new IRouter.Route[](0), 1, 0);
    }

    function testCannotSwapKeeperIfInvalidPath() public {
        vm.expectRevert(IAutoCompounder.InvalidPath.selector);
        autoCompounder.swapTokenToVELOKeeper(new IRouter.Route[](0), 1, 1);
    }

    function testCannotSwapKeeperIfAmountInTooHigh() public {
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(WETH), address(VELO), false, address(0));
        vm.expectRevert(IAutoCompounder.AmountInTooHigh.selector);
        autoCompounder.swapTokenToVELOKeeper(routes, 1, 1);
    }

    function testName() public {
        // Create autoCompounder with a name
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        vm.startPrank(address(owner));
        escrow.approve(address(autoCompounderFactory), mTokenId);
        escrow.setApprovalForAll(address(owner2), true);
        vm.stopPrank();
        vm.prank(address(owner2));
        autoCompounder = AutoCompounder(autoCompounderFactory.createAutoCompounder(address(owner), mTokenId, "Test"));

        assertEq(autoCompounder.name(), "Test");

        // Create an autoCompounder without a name
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        vm.startPrank(address(owner));
        escrow.approve(address(autoCompounderFactory), mTokenId);
        escrow.setApprovalForAll(address(owner2), true);
        vm.stopPrank();
        vm.prank(address(owner2));
        autoCompounder = AutoCompounder(autoCompounderFactory.createAutoCompounder(address(owner), mTokenId, ""));

        assertEq(autoCompounder.name(), "");
    }

    function testSetName() public {
        assertEq(autoCompounder.name(), "");
        vm.startPrank(address(owner));
        autoCompounder.setName("New name");
        assertEq(autoCompounder.name(), "New name");
        autoCompounder.setName("Second new name");
        assertEq(autoCompounder.name(), "Second new name");
    }

    function testCannotSetNameIfNotAdmin() public {
        bytes memory revertString = bytes(
            "AccessControl: account 0x7d28001937fe8e131f76dae9e9947adedbd0abde is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        vm.startPrank(address(owner2));
        vm.expectRevert(revertString);
        autoCompounder.setName("Some totally new name");
    }
}

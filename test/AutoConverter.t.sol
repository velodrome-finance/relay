// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "src/Relay.sol";
import "src/Registry.sol";
import "src/autoConverter/AutoConverter.sol";
import "src/autoConverter/ConverterOptimizer.sol";
import "src/autoConverter/AutoConverterFactory.sol";

import "@velodrome/test/BaseTest.sol";

contract AutoConverterTest is BaseTest {
    uint256 tokenId;
    uint256 mTokenId;

    AutoConverterFactory autoConverterFactory;
    AutoConverter autoConverter;
    ConverterOptimizer optimizer;
    Registry keeperRegistry;
    LockedManagedReward lockedManagedReward;
    FreeManagedReward freeManagedReward;

    address[] bribes;
    address[] fees;
    address[][] tokensToClaim;
    address[] tokensToSwap;
    address[] tokensToSweep;
    uint256[] slippages;
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

        keeperRegistry = new Registry(new address[](0));
        // Create auto converter
        optimizer = new ConverterOptimizer(
            address(USDC),
            address(WETH),
            address(FRAX), // OP
            address(VELO),
            address(factory),
            address(router)
        );
        autoConverterFactory = new AutoConverterFactory(
            address(forwarder),
            address(voter),
            address(router),
            address(optimizer),
            address(keeperRegistry),
            new address[](0)
        );
        escrow.approve(address(autoConverterFactory), mTokenId);
        autoConverter = AutoConverter(
            autoConverterFactory.createRelay(address(owner), mTokenId, "AutoConverter", abi.encode(address(USDC)))
        );

        skipToNextEpoch(1 hours + 1);

        vm.stopPrank();

        // Add the owner as a keeper
        vm.prank(escrow.team());
        keeperRegistry.approve(address(owner));

        // Create a USDC pool for VELO, WETH, and FRAX (seen as OP in ConverterOptimizer)
        deal(address(USDC), address(owner), TOKEN_100K * 3);
        deal(address(WETH), address(owner), TOKEN_1 * 3);
        deal(address(VELO), address(owner), TOKEN_1 * 3);

        // @dev these pools have a higher VELO price value than v1 pools
        _createPoolAndSimulateSwaps(address(VELO), address(USDC), USDC_1, TOKEN_1, address(VELO), 10, 3);
        _createPoolAndSimulateSwaps(address(WETH), address(USDC), TOKEN_1, TOKEN_100K, address(USDC), 1e6, 3);
        _createPoolAndSimulateSwaps(address(FRAX), address(USDC), TOKEN_1, TOKEN_1, address(USDC), 1e6, 3);
        _createPoolAndSimulateSwaps(address(FRAX), address(DAI), TOKEN_1, TOKEN_1, address(FRAX), 1e6, 3);

        tokensToSwap.push(address(USDC));
        tokensToSwap.push(address(FRAX));
        tokensToSwap.push(address(DAI));

        // 5% slippage
        slippages.push(500);
        slippages.push(500);
        slippages.push(500);

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

    function testKeeperLastRunSetup() public {
        assertEq(autoConverter.keeperLastRun(), 0);
    }

    function testManagedTokenID() public {
        assertEq(autoConverter.mTokenId(), mTokenId);
        assertEq(escrow.ownerOf(mTokenId), address(autoConverter));
        assertTrue(escrow.escrowType(mTokenId) == IVotingEscrow.EscrowType.MANAGED);
    }

    function testCannotInitializeIfAlreadyInitialized() external {
        vm.expectRevert("Initializable: contract is already initialized");
        autoConverter.initialize(1);
    }

    function testCannotInitializeTokenNotOwned() external {
        AutoConverter comp = new AutoConverter(
            address(forwarder),
            address(voter),
            address(owner),
            "",
            address(router),
            address(USDC),
            address(optimizer),
            address(autoConverterFactory)
        );
        uint256 _mTokenId = escrow.createManagedLockFor(address(owner));
        vm.prank(escrow.allowedManager());
        vm.expectRevert(IRelay.ManagedTokenNotOwned.selector);
        comp.initialize(_mTokenId);
    }

    function testCannotInitializeTokenNotManaged() external {
        AutoConverter comp = new AutoConverter(
            address(forwarder),
            address(voter),
            address(owner),
            "",
            address(router),
            address(USDC),
            address(optimizer),
            address(autoConverterFactory)
        );
        vm.prank(escrow.allowedManager());
        vm.expectRevert(IRelay.TokenIdNotManaged.selector);
        comp.initialize(2);
    }

    function testCannotSwapIfNoRouteFound() public {
        // Create a new pool with liquidity that doesn't swap into USDC
        IERC20 tokenA = IERC20(new MockERC20("Token A", "A", 18));
        IERC20 tokenB = IERC20(new MockERC20("Token B", "B", 18));
        deal(address(tokenA), address(owner), TOKEN_1 * 2, true);
        deal(address(tokenB), address(owner), TOKEN_1 * 2, true);
        _createPoolAndSimulateSwaps(address(tokenA), address(tokenB), TOKEN_1, TOKEN_1, address(tokenA), 1e6, 3);

        // give rewards to the autoConverter
        deal(address(tokenA), address(autoConverter), 1e6);

        // Attempt swapping into USDC - should revert
        address tokenToSwap = address(tokenA);
        uint256 slippage = 0;
        IRouter.Route[] memory optionalRoute = new IRouter.Route[](0);
        vm.expectRevert(IAutoConverter.NoRouteFound.selector);
        autoConverter.swapTokenToTokenWithOptionalRoute(tokenToSwap, slippage, optionalRoute);

        // Cannot swap for a token that doesn't have a pool
        IERC20 tokenC = IERC20(new MockERC20("Token C", "C", 18));
        deal(address(tokenC), address(autoConverter), 1e6);

        tokenToSwap = address(tokenC);

        // Attempt swapping into USDC - should revert
        vm.expectRevert(IAutoConverter.NoRouteFound.selector);
        autoConverter.swapTokenToTokenWithOptionalRoute(tokenToSwap, slippage, optionalRoute);
    }

    function testClaimAndConvertClaimRebaseOnly() public {
        address[] memory pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        autoConverter.vote(pools, weights);

        skipToNextEpoch(6 days + 1);
        minter.updatePeriod();

        uint256 claimable = distributor.claimable(mTokenId);
        assertGt(distributor.claimable(mTokenId), 0);

        uint256 balanceBefore = escrow.balanceOfNFT(mTokenId);
        autoConverter.claimFees(fees, tokensToClaim);
        autoConverter.claimBribes(bribes, tokensToClaim);
        assertEq(escrow.balanceOfNFT(mTokenId), balanceBefore + claimable);
    }

    function testCannotSwapTokenToTokenWithOptionalRouteIfDoesNotUseHighLiquidityToken() public {
        // create a new pool with
        //  - liquidity of the token swapped to the mock token
        //  - liquidity of the mock token to USDC to return a lot of USDC
        // Mock Token is not added as a high liquidity token, so will revert
        MockERC20 mockToken = new MockERC20("Mock Token", "MOCK", 18);
        deal(address(mockToken), address(owner), TOKEN_1 * 3);
        deal(address(USDC), address(owner), TOKEN_100M + TOKEN_1 * 3);

        _createPoolAndSimulateSwaps(address(mockToken), address(FRAX), TOKEN_1, TOKEN_1, address(FRAX), 1e6, 3);
        _createPoolAndSimulateSwaps(address(mockToken), address(USDC), TOKEN_1, TOKEN_100M, address(USDC), TOKEN_1, 3);

        // simulate reward
        deal(address(FRAX), address(autoConverter), 1e6);

        address tokenToSwap = address(FRAX);
        uint256 slippage = 500;
        IRouter.Route[] memory optionalRoute = new IRouter.Route[](2);
        optionalRoute[0] = IRouter.Route(address(FRAX), address(mockToken), false, address(0));
        optionalRoute[1] = IRouter.Route(address(mockToken), address(USDC), false, address(0));

        vm.expectRevert(IAutoConverter.NotHighLiquidityToken.selector);
        autoConverter.swapTokenToTokenWithOptionalRoute(tokenToSwap, slippage, optionalRoute);
    }

    function testIncreaseAmount() public {
        uint256 amount = TOKEN_1;
        deal(address(VELO), address(owner), amount);
        VELO.approve(address(autoConverter), amount);

        uint256 balanceBefore = escrow.balanceOfNFT(mTokenId);
        uint256 supplyBefore = escrow.totalSupply();

        autoConverter.increaseAmount(amount);

        assertEq(escrow.balanceOfNFT(mTokenId), balanceBefore + amount);
        assertEq(escrow.totalSupply(), supplyBefore + amount);
    }

    function testVote() public {
        address[] memory poolVote = new address[](1);
        uint256[] memory weights = new uint256[](1);
        poolVote[0] = address(pool2);
        weights[0] = 1;

        assertFalse(escrow.voted(mTokenId));

        autoConverter.vote(poolVote, weights);

        assertEq(autoConverter.keeperLastRun(), block.timestamp);
        assertTrue(escrow.voted(mTokenId));
        assertEq(voter.weights(address(pool2)), escrow.balanceOfNFT(mTokenId));
        assertEq(voter.votes(mTokenId, address(pool2)), escrow.balanceOfNFT(mTokenId));
        assertEq(voter.poolVote(mTokenId, 0), address(pool2));
    }

    function testSwapTokenToToken() public {
        deal(address(FRAX), address(autoConverter), TOKEN_1 / 1000, true);

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(USDC), false, address(0));
        uint256 slippage = 500;

        uint256 balanceBefore = USDC.balanceOf(address(autoConverter));
        autoConverter.swapTokenToTokenWithOptionalRoute(address(FRAX), slippage, routes);
        assertEq(autoConverter.keeperLastRun(), block.timestamp);
        assertGt(USDC.balanceOf(address(autoConverter)), balanceBefore);
        assertEq(
            autoConverter.amountTokenEarned(VelodromeTimeLibrary.epochStart(block.timestamp)),
            USDC.balanceOf(address(autoConverter))
        );
    }

    function testHandleRouterApproval() public {
        deal(address(FRAX), address(autoConverter), TOKEN_1 / 1000, true);

        // give a fake approval to impersonate a dangling approved amount
        vm.prank(address(autoConverter));
        FRAX.approve(address(router), 100);

        // resets and properly approves swap amount
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(USDC), false, address(0));
        uint256 slippage = 500;

        autoConverter.swapTokenToTokenWithOptionalRoute(address(FRAX), slippage, routes);
        assertEq(FRAX.allowance(address(autoConverter), address(router)), 0);
    }

    function testCannotSwapIfSlippageTooHigh() public {
        address tokenToSwap = address(FRAX);
        uint256 slippage = 501;
        IRouter.Route[] memory optionalRoute = new IRouter.Route[](0);
        vm.expectRevert(IAutoConverter.SlippageTooHigh.selector);
        autoConverter.swapTokenToTokenWithOptionalRoute(tokenToSwap, slippage, optionalRoute);
    }

    function testCannotSwapIfAmountInZero() public {
        IRouter.Route[] memory optionalRoute = new IRouter.Route[](0);
        vm.expectRevert(IAutoConverter.AmountInZero.selector);
        autoConverter.swapTokenToTokenWithOptionalRoute(address(FRAX), 500, optionalRoute);
    }

    function testCannotSwapFromUSDC() public {
        address tokenToSwap = address(USDC);
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(0), false, address(0));
        uint256 slippage = 500;
        vm.expectRevert(IAutoConverter.InvalidPath.selector);
        autoConverter.swapTokenToTokenWithOptionalRoute(tokenToSwap, slippage, routes);
    }

    function testCannotSweepIfNotAdmin() public {
        deal(address(USDC), address(autoConverter), TOKEN_1);
        bytes memory revertString = bytes(
            "AccessControl: account 0x7d28001937fe8e131f76dae9e9947adedbd0abde is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        vm.startPrank(address(owner2));
        vm.expectRevert(revertString);
        autoConverter.sweep(address(0), address(owner2), TOKEN_1);
    }

    function testSweep() public {
        // partial withdraw
        deal(address(USDC), address(autoConverter), TOKEN_1);
        uint256 amount = TOKEN_1 / 4;
        uint256 balanceBefore = USDC.balanceOf(address(owner3));
        autoConverter.sweep(address(USDC), address(owner3), amount);
        assertEq(balanceBefore + amount, USDC.balanceOf(address(owner3)));
        assertEq(TOKEN_1 - amount, USDC.balanceOf(address(autoConverter)));

        // full withdraw
        deal(address(WETH), address(autoConverter), TOKEN_1);
        amount = TOKEN_1;
        balanceBefore = WETH.balanceOf(address(owner3));
        autoConverter.sweep(address(WETH), address(owner3), amount);
        assertEq(balanceBefore + amount, WETH.balanceOf(address(owner3)));
        assertEq(WETH.balanceOf(address(autoConverter)), 0);
    }
}

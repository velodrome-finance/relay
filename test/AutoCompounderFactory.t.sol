// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "test/RelayFactory.t.sol";

import "src/autoCompounder/AutoCompounder.sol";
import "src/autoCompounder/CompoundOptimizer.sol";
import "src/autoCompounder/AutoCompounderFactory.sol";

contract AutoCompounderFactoryTest is RelayFactoryTest {
    AutoCompounderFactory autoCompounderFactory;
    AutoCompounder autoCompounder;
    CompoundOptimizer optimizer;

    constructor() {
        deploymentType = Deployment.FORK;
    }

    // @dev: refer to velodrome-finance/test/BaseTest.sol
    function _setUp() public override {
        escrow.setTeam(address(owner4));
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
        relayFactory = RelayFactory(autoCompounderFactory);
    }

    function testCreateAutoCompounderFactoryWithHighLiquidityTokens() public {
        address[] memory highLiquidityTokens = new address[](2);
        highLiquidityTokens[0] = address(FRAX);
        highLiquidityTokens[1] = address(USDC);
        autoCompounderFactory = new AutoCompounderFactory(
            address(forwarder),
            address(voter),
            address(router),
            address(optimizer),
            address(factoryRegistry),
            highLiquidityTokens
        );
        assertTrue(autoCompounderFactory.isHighLiquidityToken(address(FRAX)));
        assertTrue(autoCompounderFactory.isHighLiquidityToken(address(USDC)));
    }

    function testCannotCreateAutoCompounderWithNoAdmin() public {
        vm.expectRevert(IRelayFactory.ZeroAddress.selector);
        autoCompounderFactory.createRelay(address(0), 1, "", new bytes(0));
    }

    function testCannotCreateAutoCompounderWithZeroTokenId() public {
        vm.expectRevert(IRelayFactory.TokenIdZero.selector);
        autoCompounderFactory.createRelay(address(1), 0, "", new bytes(0));
    }

    function testCannotCreateAutoCompounderIfNotApprovedSender() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        vm.startPrank(address(owner));
        escrow.approve(address(autoCompounderFactory), mTokenId);
        escrow.setApprovalForAll(address(autoCompounderFactory), true);
        vm.stopPrank();
        vm.expectRevert(IRelayFactory.TokenIdNotApproved.selector);
        vm.prank(address(owner2));
        autoCompounderFactory.createRelay(address(1), mTokenId, "", new bytes(0));
    }

    function testCannotCreateAutoCompounderIfTokenNotManaged() public {
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.expectRevert(IRelayFactory.TokenIdNotManaged.selector);
        autoCompounderFactory.createRelay(address(1), tokenId, "", new bytes(0)); // normal

        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);
        vm.expectRevert(IRelayFactory.TokenIdNotManaged.selector);
        autoCompounderFactory.createRelay(address(1), tokenId, "", new bytes(0)); // locked
    }

    function testCreateAutoCompounder() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoCompounderFactory.relaysLength(), 0);

        vm.startPrank(address(owner));
        escrow.approve(address(autoCompounderFactory), mTokenId);
        autoCompounder = AutoCompounder(autoCompounderFactory.createRelay(address(owner), mTokenId, "", new bytes(0)));

        assertFalse(address(autoCompounder) == address(0));
        assertEq(autoCompounderFactory.relaysLength(), 1);
        address[] memory autoCompounders = autoCompounderFactory.relays();
        assertEq(address(autoCompounder), autoCompounders[0]);
        assertEq(escrow.balanceOf(address(autoCompounder)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoCompounder));

        assertEq(address(autoCompounder.autoCompounderFactory()), address(autoCompounderFactory));
        assertEq(address(autoCompounder.router()), address(router));
        assertEq(address(autoCompounder.voter()), address(voter));
        assertEq(address(autoCompounder.optimizer()), address(optimizer));
        assertEq(address(autoCompounder.ve()), voter.ve());
        assertEq(address(autoCompounder.velo()), address(VELO));
        assertEq(address(autoCompounder.distributor()), escrow.distributor());

        assertTrue(autoCompounder.hasRole(0x00, address(owner))); // DEFAULT_ADMIN_ROLE
        assertTrue(autoCompounder.hasRole(keccak256("ALLOWED_CALLER"), address(owner)));

        assertEq(autoCompounder.mTokenId(), mTokenId);
    }

    function testCreateAutoCompounderByApproved() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoCompounderFactory.relaysLength(), 0);

        vm.startPrank(address(owner));
        escrow.setApprovalForAll(address(autoCompounderFactory), true);
        escrow.approve(address(owner2), mTokenId);
        vm.stopPrank();
        vm.prank(address(owner2));
        autoCompounder = AutoCompounder(autoCompounderFactory.createRelay(address(owner), mTokenId, "", new bytes(0)));

        assertFalse(address(autoCompounder) == address(0));
        assertEq(autoCompounderFactory.relaysLength(), 1);
        address[] memory autoCompounders = autoCompounderFactory.relays();
        assertEq(address(autoCompounder), autoCompounders[0]);
        assertEq(escrow.balanceOf(address(autoCompounder)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoCompounder));
        assertEq(autoCompounder.mTokenId(), mTokenId);
    }

    function testCreateAutoCompounderByApprovedForAll() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoCompounderFactory.relaysLength(), 0);

        vm.startPrank(address(owner));
        escrow.approve(address(autoCompounderFactory), mTokenId);
        escrow.setApprovalForAll(address(owner2), true);
        vm.stopPrank();
        vm.prank(address(owner2));
        autoCompounder = AutoCompounder(autoCompounderFactory.createRelay(address(owner), mTokenId, "", new bytes(0)));

        assertFalse(address(autoCompounder) == address(0));
        assertEq(autoCompounderFactory.relaysLength(), 1);
        address[] memory autoCompounders = autoCompounderFactory.relays();
        assertEq(address(autoCompounder), autoCompounders[0]);
        assertEq(escrow.balanceOf(address(autoCompounder)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoCompounder));
        assertEq(autoCompounder.mTokenId(), mTokenId);
    }

    function testCannotAddHighLiquidityTokenIfNotTeam() public {
        vm.startPrank(address(owner2));
        assertTrue(msg.sender != factoryRegistry.owner());
        vm.expectRevert(IRelayFactory.NotTeam.selector);
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
    }

    function testCannotAddHighLiquidityTokenIfZeroAddress() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IRelayFactory.ZeroAddress.selector);
        autoCompounderFactory.addHighLiquidityToken(address(0));
    }

    function testCannotAddHighLiquidityTokenIfAlreadyExists() public {
        vm.startPrank(factoryRegistry.owner());
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
        vm.expectRevert(IAutoCompounderFactory.HighLiquidityTokenAlreadyExists.selector);
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
    }

    function testAddHighLiquidityToken() public {
        assertFalse(autoCompounderFactory.isHighLiquidityToken(address(USDC)));
        assertEq(autoCompounderFactory.highLiquidityTokens(), new address[](0));
        assertEq(autoCompounderFactory.highLiquidityTokensLength(), 0);
        vm.prank(factoryRegistry.owner());
        autoCompounderFactory.addHighLiquidityToken(address(USDC));
        assertTrue(autoCompounderFactory.isHighLiquidityToken(address(USDC)));
        address[] memory highLiquidityTokens = new address[](1);
        highLiquidityTokens[0] = address(USDC);
        assertEq(autoCompounderFactory.highLiquidityTokens(), highLiquidityTokens);
        assertEq(autoCompounderFactory.highLiquidityTokensLength(), 1);
    }
}

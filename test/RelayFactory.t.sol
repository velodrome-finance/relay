// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "src/RelayFactory.sol";
import "src/Registry.sol";

import "@velodrome/test/BaseTest.sol";

abstract contract RelayFactoryTest is BaseTest {
    event SetKeeperRegistry(address indexed _keeperRegistry);
    event SetOptimizerRegistry(address indexed _optimizerRegistry);

    uint256 tokenId;
    uint256 mTokenId;

    RelayFactory relayFactory;
    Registry keeperRegistry;
    Registry optimizerRegistry;

    function testCannotCreateAutoConverterWithNoAdmin() public {
        vm.expectRevert(IRelayFactory.ZeroAddress.selector);
        relayFactory.createRelay(address(0), 1, "", abi.encode(address(USDC)));
    }

    function testCannotCreateAutoConverterWithZeroTokenId() public {
        vm.expectRevert(IRelayFactory.TokenIdZero.selector);
        relayFactory.createRelay(address(1), 0, "", abi.encode(address(USDC)));
    }

    function testCannotCreateAutoConverterIfNotApprovedSender() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        vm.startPrank(address(owner));
        escrow.approve(address(relayFactory), mTokenId);
        escrow.setApprovalForAll(address(relayFactory), true);
        vm.stopPrank();
        vm.expectRevert(IRelayFactory.TokenIdNotApproved.selector);
        vm.prank(address(owner2));
        relayFactory.createRelay(address(1), mTokenId, "", abi.encode(address(USDC)));
    }

    function testCannotCreateAutoCompounderIfTokenNotManaged() public {
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.expectRevert(IRelayFactory.TokenIdNotManaged.selector);
        relayFactory.createRelay(address(1), tokenId, "", new bytes(0)); // normal

        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);
        vm.expectRevert(IRelayFactory.TokenIdNotManaged.selector);
        relayFactory.createRelay(address(1), tokenId, "", new bytes(0)); // locked
    }

    function testSetKeeperRegistry() public {
        assertEq(address(relayFactory.keeperRegistry()), address(keeperRegistry));
        vm.startPrank(relayFactory.owner());
        address newRegistry = vm.addr(2);
        vm.expectEmit(true, false, false, true, address(relayFactory));
        emit SetKeeperRegistry(newRegistry);
        relayFactory.setKeeperRegistry(newRegistry);
        assertEq(address(relayFactory.keeperRegistry()), newRegistry);

        newRegistry = vm.addr(3);
        vm.expectEmit(true, false, false, true, address(relayFactory));
        emit SetKeeperRegistry(newRegistry);
        relayFactory.setKeeperRegistry(newRegistry);
        assertEq(address(relayFactory.keeperRegistry()), newRegistry);
    }

    function testCannotSetKeeperRegistryIfNotOwner() public {
        assertEq(address(relayFactory.keeperRegistry()), address(keeperRegistry));
        vm.startPrank(vm.addr(1));
        vm.expectRevert("Ownable: caller is not the owner");
        relayFactory.setKeeperRegistry(vm.addr(2));
        assertEq(address(relayFactory.keeperRegistry()), address(keeperRegistry));
    }

    function testCannotSetKeeperRegistryIfZeroAddress() public {
        assertEq(address(relayFactory.keeperRegistry()), address(keeperRegistry));
        vm.startPrank(relayFactory.owner());
        vm.expectRevert(IRelayFactory.ZeroAddress.selector);
        relayFactory.setKeeperRegistry(address(0));
        assertEq(address(relayFactory.keeperRegistry()), address(keeperRegistry));
    }

    function testCannotSetKeeperRegistryIfSameRegistry() public {
        assertEq(address(relayFactory.keeperRegistry()), address(keeperRegistry));
        vm.startPrank(relayFactory.owner());
        vm.expectRevert(IRelayFactory.SameRegistry.selector);
        relayFactory.setKeeperRegistry(address(keeperRegistry));
        assertEq(address(relayFactory.keeperRegistry()), address(keeperRegistry));
    }

    function testSetOptimizerRegistry() public {
        assertEq(address(relayFactory.optimizerRegistry()), address(optimizerRegistry));
        vm.startPrank(relayFactory.owner());
        address newRegistry = vm.addr(2);
        vm.expectEmit(true, false, false, true, address(relayFactory));
        emit SetOptimizerRegistry(newRegistry);
        relayFactory.setOptimizerRegistry(newRegistry);
        assertEq(address(relayFactory.optimizerRegistry()), newRegistry);

        newRegistry = vm.addr(3);
        vm.expectEmit(true, false, false, true, address(relayFactory));
        emit SetOptimizerRegistry(newRegistry);
        relayFactory.setOptimizerRegistry(newRegistry);
        assertEq(address(relayFactory.optimizerRegistry()), newRegistry);
    }

    function testCannotSetOptimizerRegistryIfNotOwner() public {
        assertEq(address(relayFactory.optimizerRegistry()), address(optimizerRegistry));
        vm.startPrank(vm.addr(1));
        vm.expectRevert("Ownable: caller is not the owner");
        relayFactory.setOptimizerRegistry(vm.addr(2));
        assertEq(address(relayFactory.optimizerRegistry()), address(optimizerRegistry));
    }

    function testCannotSetOptimizerRegistryIfZeroAddress() public {
        assertEq(address(relayFactory.optimizerRegistry()), address(optimizerRegistry));
        vm.startPrank(relayFactory.owner());
        vm.expectRevert(IRelayFactory.ZeroAddress.selector);
        relayFactory.setOptimizerRegistry(address(0));
        assertEq(address(relayFactory.optimizerRegistry()), address(optimizerRegistry));
    }

    function testCannotSetOptimizerRegistryIfSameRegistry() public {
        assertEq(address(relayFactory.optimizerRegistry()), address(optimizerRegistry));
        vm.startPrank(relayFactory.owner());
        vm.expectRevert(IRelayFactory.SameRegistry.selector);
        relayFactory.setOptimizerRegistry(address(optimizerRegistry));
        assertEq(address(relayFactory.optimizerRegistry()), address(optimizerRegistry));
    }
}

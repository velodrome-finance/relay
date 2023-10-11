// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "src/Registry.sol";
import "src/Registry.sol";
import "src/interfaces/IRegistry.sol";
import "src/autoConverter/AutoConverterFactory.sol";
import "src/autoCompounder/AutoCompounderFactory.sol";

import "@velodrome/test/BaseTest.sol";

contract RegistryTest is BaseTest {
    event Approve(address indexed element);
    event Unapprove(address indexed element);

    IRegistry public relayFactoryRegistry;
    IRegistry public keeperRegistry;
    address public convFactory;
    address public compFactory;
    address public testKeeper;
    address public testKeeper2;

    constructor() {
        deploymentType = Deployment.FORK;
    }

    // @dev: refer to velodrome-finance/test/BaseTest.sol
    function _setUp() public override {
        address[] memory approved = new address[](0);
        keeperRegistry = new Registry(approved);
        compFactory = address(
            new AutoCompounderFactory(
                address(forwarder),
                address(voter),
                address(router),
                address(0),
                address(keeperRegistry),
                new address[](0)
            )
        );
        convFactory = address(
            new AutoConverterFactory(
                address(forwarder),
                address(voter),
                address(router),
                address(0),
                address(keeperRegistry),
                new address[](0)
            )
        );
        relayFactoryRegistry = new Registry(approved);
        testKeeper = vm.addr(1);
        testKeeper2 = vm.addr(2);
    }

    function testInitialState() public {
        assertEq(keeperRegistry.length(), 0);
        assertEq(keeperRegistry.length(), 0);
    }

    function testApproveFactory() public {
        assertEq(relayFactoryRegistry.length(), 0);
        assertFalse(relayFactoryRegistry.isApproved(compFactory));
        assertFalse(relayFactoryRegistry.isApproved(convFactory));

        vm.expectEmit(true, false, false, true, address(relayFactoryRegistry));
        emit Approve(compFactory);
        relayFactoryRegistry.approve(compFactory);
        assertTrue(relayFactoryRegistry.isApproved(compFactory));

        assertEq(relayFactoryRegistry.length(), 1);
        assertEq(relayFactoryRegistry.getAll()[0], compFactory);

        vm.expectEmit(true, false, false, true, address(relayFactoryRegistry));
        emit Approve(convFactory);
        relayFactoryRegistry.approve(convFactory);
        assertTrue(relayFactoryRegistry.isApproved(convFactory));

        assertEq(relayFactoryRegistry.length(), 2);
        address[] memory relayFactories = relayFactoryRegistry.getAll();
        assertEq(relayFactories[0], compFactory);
        assertEq(relayFactories[1], convFactory);
    }

    function testCannotApproveFactoryIfNotOwner() public {
        assertFalse(relayFactoryRegistry.isApproved(compFactory));
        vm.prank(testKeeper);
        vm.expectRevert("Ownable: caller is not the owner");
        relayFactoryRegistry.approve(compFactory);
        assertEq(relayFactoryRegistry.length(), 0);
        assertFalse(relayFactoryRegistry.isApproved(compFactory));
    }

    function testCannotApproveFactoryIfZeroAddress() public {
        assertFalse(relayFactoryRegistry.isApproved(compFactory));
        vm.expectRevert(IRegistry.ZeroAddress.selector);
        relayFactoryRegistry.approve(address(0));
        assertEq(relayFactoryRegistry.length(), 0);
        assertFalse(relayFactoryRegistry.isApproved(compFactory));
    }

    function testCannotApproveFactoryIfAlreadyApproved() public {
        assertFalse(relayFactoryRegistry.isApproved(compFactory));
        vm.expectEmit(true, false, false, true, address(relayFactoryRegistry));
        emit Approve(compFactory);
        relayFactoryRegistry.approve(compFactory);
        assertEq(relayFactoryRegistry.length(), 1);
        assertTrue(relayFactoryRegistry.isApproved(compFactory));

        vm.expectRevert(IRegistry.AlreadyApproved.selector);
        relayFactoryRegistry.approve(compFactory);
        assertEq(relayFactoryRegistry.length(), 1);
        assertTrue(relayFactoryRegistry.isApproved(compFactory));
    }

    function testUnapproveFactory() public {
        relayFactoryRegistry.approve(compFactory);
        relayFactoryRegistry.approve(convFactory);
        assertTrue(relayFactoryRegistry.isApproved(compFactory));
        assertTrue(relayFactoryRegistry.isApproved(convFactory));

        assertEq(relayFactoryRegistry.length(), 2);
        address[] memory relayFactories = relayFactoryRegistry.getAll();
        assertEq(relayFactories[0], compFactory);
        assertEq(relayFactories[1], convFactory);

        vm.expectEmit(true, false, false, true, address(relayFactoryRegistry));
        emit Unapprove(compFactory);
        relayFactoryRegistry.unapprove(compFactory);
        assertFalse(relayFactoryRegistry.isApproved(compFactory));

        relayFactories = relayFactoryRegistry.getAll();
        assertEq(relayFactories[0], convFactory);
        assertEq(relayFactoryRegistry.length(), 1);

        vm.expectEmit(true, false, false, true, address(relayFactoryRegistry));
        emit Unapprove(convFactory);
        relayFactoryRegistry.unapprove(convFactory);
        assertFalse(relayFactoryRegistry.isApproved(convFactory));

        assertEq(relayFactoryRegistry.length(), 0);
        relayFactories = relayFactoryRegistry.getAll();
        assertEq(relayFactories.length, 0);
    }

    function testCannotUnapproveFactoryIfNotApproved() public {
        assertFalse(relayFactoryRegistry.isApproved(address(governor)));
        assertEq(relayFactoryRegistry.length(), 0);

        vm.expectRevert(IRegistry.NotApproved.selector);
        relayFactoryRegistry.unapprove(address(governor));
        assertFalse(relayFactoryRegistry.isApproved(address(governor)));
        assertEq(relayFactoryRegistry.length(), 0);
    }

    function testApproveKeeper() public {
        assertEq(keeperRegistry.length(), 0);
        assertFalse(keeperRegistry.isApproved(testKeeper));
        assertFalse(keeperRegistry.isApproved(testKeeper2));

        vm.expectEmit(true, false, false, true, address(keeperRegistry));
        emit Approve(testKeeper);
        keeperRegistry.approve(testKeeper);
        assertTrue(keeperRegistry.isApproved(testKeeper));

        assertEq(keeperRegistry.length(), 1);
        assertEq(keeperRegistry.getAll()[0], testKeeper);

        vm.expectEmit(true, false, false, true, address(keeperRegistry));
        emit Approve(testKeeper2);
        keeperRegistry.approve(testKeeper2);
        assertTrue(keeperRegistry.isApproved(testKeeper2));

        assertEq(keeperRegistry.length(), 2);
        address[] memory relayKeepers = keeperRegistry.getAll();
        assertEq(relayKeepers[0], testKeeper);
        assertEq(relayKeepers[1], testKeeper2);
    }

    function testCannotApproveKeeperIfNotOwner() public {
        assertFalse(keeperRegistry.isApproved(testKeeper));
        vm.prank(vm.addr(2));
        vm.expectRevert("Ownable: caller is not the owner");
        keeperRegistry.approve(testKeeper);
        assertEq(keeperRegistry.length(), 0);
        assertFalse(keeperRegistry.isApproved(testKeeper));
    }

    function testCannotApproveKeeperIfZeroAddress() public {
        assertFalse(keeperRegistry.isApproved(testKeeper));
        vm.expectRevert(IRegistry.ZeroAddress.selector);
        keeperRegistry.approve(address(0));
        assertEq(keeperRegistry.length(), 0);
        assertFalse(keeperRegistry.isApproved(testKeeper));
    }

    function testCannotApproveKeeperIfAlreadyApproved() public {
        assertFalse(keeperRegistry.isApproved(testKeeper));
        vm.expectEmit(true, false, false, true, address(keeperRegistry));
        emit Approve(testKeeper);
        keeperRegistry.approve(testKeeper);
        assertEq(keeperRegistry.length(), 1);
        assertTrue(keeperRegistry.isApproved(testKeeper));

        vm.expectRevert(IRegistry.AlreadyApproved.selector);
        keeperRegistry.approve(testKeeper);
        assertEq(keeperRegistry.length(), 1);
        assertTrue(keeperRegistry.isApproved(testKeeper));
    }

    function testUnapproveKeepers() public {
        keeperRegistry.approve(testKeeper);
        keeperRegistry.approve(testKeeper2);
        assertTrue(keeperRegistry.isApproved(testKeeper));
        assertTrue(keeperRegistry.isApproved(testKeeper2));

        assertEq(keeperRegistry.length(), 2);
        address[] memory relayKeepers = keeperRegistry.getAll();
        assertEq(relayKeepers[0], testKeeper);
        assertEq(relayKeepers[1], testKeeper2);

        vm.expectEmit(true, false, false, true, address(keeperRegistry));
        emit Unapprove(testKeeper);
        keeperRegistry.unapprove(testKeeper);
        assertFalse(keeperRegistry.isApproved(testKeeper));

        relayKeepers = keeperRegistry.getAll();
        assertEq(relayKeepers[0], testKeeper2);
        assertEq(keeperRegistry.length(), 1);

        vm.expectEmit(true, false, false, true, address(keeperRegistry));
        emit Unapprove(testKeeper2);
        keeperRegistry.unapprove(testKeeper2);
        assertFalse(keeperRegistry.isApproved(testKeeper2));

        assertEq(keeperRegistry.length(), 0);
        relayKeepers = keeperRegistry.getAll();
        assertEq(relayKeepers.length, 0);
    }

    function testCannotUnapproveKeeperIfNotApproved() public {
        assertEq(keeperRegistry.length(), 0);
        assertFalse(keeperRegistry.isApproved(address(governor)));

        vm.expectRevert(IRegistry.NotApproved.selector);
        keeperRegistry.unapprove(address(governor));
        assertFalse(keeperRegistry.isApproved(address(governor)));
        assertEq(keeperRegistry.length(), 0);
    }

    function testCannotUnapproveKeeperIfNotOwner() public {
        vm.prank(address(owner2));
        vm.expectRevert("Ownable: caller is not the owner");
        keeperRegistry.unapprove(address(owner));
    }
}

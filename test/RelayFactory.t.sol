// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "src/RelayFactory.sol";

import "@velodrome/test/BaseTest.sol";

abstract contract RelayFactoryTest is BaseTest {
    uint256 tokenId;
    uint256 mTokenId;

    RelayFactory relayFactory;

    function testCannotAddKeeperIfNotTeam() public {
        vm.startPrank(address(owner2));
        assertTrue(msg.sender != factoryRegistry.owner());
        vm.expectRevert(IRelayFactory.NotTeam.selector);
        relayFactory.addKeeper(address(owner2));
    }

    function testCannotAddKeeperIfZeroAddress() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IRelayFactory.ZeroAddress.selector);
        relayFactory.addKeeper(address(0));
    }

    function testCannotAddKeeperIfKeeperAlreadyExists() public {
        vm.startPrank(factoryRegistry.owner());
        relayFactory.addKeeper(address(owner));
        vm.expectRevert(IRelayFactory.KeeperAlreadyExists.selector);
        relayFactory.addKeeper(address(owner));
    }

    function testAddKeeper() public {
        assertEq(relayFactory.keepersLength(), 0);
        assertEq(relayFactory.keepers(), new address[](0));
        assertFalse(relayFactory.isKeeper(address(owner)));

        vm.prank(factoryRegistry.owner());
        relayFactory.addKeeper(address(owner));

        assertEq(relayFactory.keepersLength(), 1);
        address[] memory keepers = relayFactory.keepers();
        assertEq(keepers.length, 1);
        assertEq(keepers[0], address(owner));
        assertTrue(relayFactory.isKeeper(address(owner)));
    }

    function testCannotRemoveKeeperIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(IRelayFactory.NotTeam.selector);
        relayFactory.removeKeeper(address(owner));
    }

    function testCannotRemoveKeeperIfZeroAddress() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IRelayFactory.ZeroAddress.selector);
        relayFactory.removeKeeper(address(0));
    }

    function testCannotRemoveKeeperIfKeeperDoesntExist() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IRelayFactory.KeeperDoesNotExist.selector);
        relayFactory.removeKeeper(address(owner));
    }

    function testRemoveKeeper() public {
        vm.startPrank(factoryRegistry.owner());

        relayFactory.addKeeper(address(owner));
        relayFactory.removeKeeper(address(owner));

        assertEq(relayFactory.keepersLength(), 0);
        assertEq(relayFactory.keepers(), new address[](0));
        assertFalse(relayFactory.isKeeper(address(owner)));
    }
}

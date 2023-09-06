// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "src/autoConverter/AutoConverter.sol";
import "src/autoConverter/AutoConverterFactory.sol";

import "@velodrome/test/BaseTest.sol";

contract AutoConverterFactoryTest is BaseTest {
    uint256 tokenId;
    uint256 mTokenId;

    AutoConverterFactory autoConverterFactory;
    AutoConverter autoConverter;

    constructor() {
        deploymentType = Deployment.FORK;
    }

    // @dev: refer to velodrome-finance/test/BaseTest.sol
    function _setUp() public override {
        escrow.setTeam(address(owner4));
        autoConverterFactory = new AutoConverterFactory(
            address(forwarder),
            address(voter),
            address(router),
            address(factoryRegistry)
        );
    }

    function testCannotCreateAutoConverterWithNoAdmin() public {
        vm.expectRevert(IAutoConverterFactory.ZeroAddress.selector);
        autoConverterFactory.createAutoConverter(address(0), 1, "", address(USDC));
    }

    function testCannotCreateAutoConverterWithZeroTokenId() public {
        vm.expectRevert(IAutoConverterFactory.TokenIdZero.selector);
        autoConverterFactory.createAutoConverter(address(1), 0, "", address(USDC));
    }

    function testCannotCreateAutoConverterIfNotApprovedSender() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        vm.startPrank(address(owner));
        escrow.approve(address(autoConverterFactory), mTokenId);
        escrow.setApprovalForAll(address(autoConverterFactory), true);
        vm.stopPrank();
        vm.expectRevert(IAutoConverterFactory.TokenIdNotApproved.selector);
        vm.prank(address(owner2));
        autoConverterFactory.createAutoConverter(address(1), mTokenId, "", address(USDC));
    }

    function testCannotCreateAutoConverterIfTokenNotManaged() public {
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.expectRevert(IAutoConverterFactory.TokenIdNotManaged.selector);
        autoConverterFactory.createAutoConverter(address(1), tokenId, "", address(USDC)); // normal

        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);
        vm.expectRevert(IAutoConverterFactory.TokenIdNotManaged.selector);
        autoConverterFactory.createAutoConverter(address(1), tokenId, "", address(USDC)); // locked
    }

    function testCreateAutoConverter() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoConverterFactory.autoConvertersLength(), 0);

        vm.startPrank(address(owner));
        escrow.approve(address(autoConverterFactory), mTokenId);
        autoConverter = AutoConverter(
            autoConverterFactory.createAutoConverter(address(owner), mTokenId, "", address(USDC))
        );

        assertFalse(address(autoConverter) == address(0));
        assertEq(autoConverterFactory.autoConvertersLength(), 1);
        address[] memory autoConverters = autoConverterFactory.autoConverters();
        assertEq(address(autoConverter), autoConverters[0]);
        assertEq(escrow.balanceOf(address(autoConverter)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoConverter));

        assertEq(address(autoConverter.autoConverterFactory()), address(autoConverterFactory));
        assertEq(address(autoConverter.router()), address(router));
        assertEq(address(autoConverter.voter()), address(voter));
        assertEq(address(autoConverter.ve()), voter.ve());
        assertEq(address(autoConverter.velo()), address(VELO));
        assertEq(address(autoConverter.distributor()), escrow.distributor());

        assertTrue(autoConverter.hasRole(0x00, address(owner))); // DEFAULT_ADMIN_ROLE
        assertTrue(autoConverter.hasRole(keccak256("ALLOWED_CALLER"), address(owner)));

        assertEq(autoConverter.mTokenId(), mTokenId);
    }

    function testCreateAutoConverterByApproved() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoConverterFactory.autoConvertersLength(), 0);

        vm.startPrank(address(owner));
        escrow.setApprovalForAll(address(autoConverterFactory), true);
        escrow.approve(address(owner2), mTokenId);
        vm.stopPrank();
        vm.prank(address(owner2));
        autoConverter = AutoConverter(
            autoConverterFactory.createAutoConverter(address(owner), mTokenId, "", address(USDC))
        );

        assertFalse(address(autoConverter) == address(0));
        assertEq(autoConverterFactory.autoConvertersLength(), 1);
        address[] memory autoConverters = autoConverterFactory.autoConverters();
        assertEq(address(autoConverter), autoConverters[0]);
        assertEq(escrow.balanceOf(address(autoConverter)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoConverter));
        assertEq(autoConverter.mTokenId(), mTokenId);
    }

    function testCreateAutoConverterByApprovedForAll() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoConverterFactory.autoConvertersLength(), 0);

        vm.startPrank(address(owner));
        escrow.approve(address(autoConverterFactory), mTokenId);
        escrow.setApprovalForAll(address(owner2), true);
        vm.stopPrank();
        vm.prank(address(owner2));
        autoConverter = AutoConverter(
            autoConverterFactory.createAutoConverter(address(owner), mTokenId, "", address(USDC))
        );

        assertFalse(address(autoConverter) == address(0));
        assertEq(autoConverterFactory.autoConvertersLength(), 1);
        address[] memory autoConverters = autoConverterFactory.autoConverters();
        assertEq(address(autoConverter), autoConverters[0]);
        assertEq(escrow.balanceOf(address(autoConverter)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoConverter));
        assertEq(autoConverter.mTokenId(), mTokenId);
    }

    function testCannotAddKeeperIfNotTeam() public {
        vm.startPrank(address(owner2));
        assertTrue(msg.sender != factoryRegistry.owner());
        vm.expectRevert(IAutoConverterFactory.NotTeam.selector);
        autoConverterFactory.addKeeper(address(owner2));
    }

    function testCannotAddKeeperIfZeroAddress() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IAutoConverter.ZeroAddress.selector);
        autoConverterFactory.addKeeper(address(0));
    }

    function testCannotAddKeeperIfKeeperAlreadyExists() public {
        vm.startPrank(factoryRegistry.owner());
        autoConverterFactory.addKeeper(address(owner));
        vm.expectRevert(IAutoConverterFactory.KeeperAlreadyExists.selector);
        autoConverterFactory.addKeeper(address(owner));
    }

    function testAddKeeper() public {
        assertEq(autoConverterFactory.keepersLength(), 0);
        assertEq(autoConverterFactory.keepers(), new address[](0));
        assertFalse(autoConverterFactory.isKeeper(address(owner)));

        vm.prank(factoryRegistry.owner());
        autoConverterFactory.addKeeper(address(owner));

        assertEq(autoConverterFactory.keepersLength(), 1);
        address[] memory keepers = autoConverterFactory.keepers();
        assertEq(keepers.length, 1);
        assertEq(keepers[0], address(owner));
        assertTrue(autoConverterFactory.isKeeper(address(owner)));
    }

    function testCannotRemoveKeeperIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(IAutoConverterFactory.NotTeam.selector);
        autoConverterFactory.removeKeeper(address(owner));
    }

    function testCannotRemoveKeeperIfZeroAddress() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IAutoConverterFactory.ZeroAddress.selector);
        autoConverterFactory.removeKeeper(address(0));
    }

    function testCannotRemoveKeeperIfKeeperDoesntExist() public {
        vm.prank(factoryRegistry.owner());
        vm.expectRevert(IAutoConverterFactory.KeeperDoesNotExist.selector);
        autoConverterFactory.removeKeeper(address(owner));
    }

    function testRemoveKeeper() public {
        vm.startPrank(factoryRegistry.owner());

        autoConverterFactory.addKeeper(address(owner));
        autoConverterFactory.removeKeeper(address(owner));

        assertEq(autoConverterFactory.keepersLength(), 0);
        assertEq(autoConverterFactory.keepers(), new address[](0));
        assertFalse(autoConverterFactory.isKeeper(address(owner)));
    }
}

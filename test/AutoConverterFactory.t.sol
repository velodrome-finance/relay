// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "test/RelayFactory.t.sol";

import "src/autoConverter/AutoConverter.sol";
import "src/autoConverter/AutoConverterFactory.sol";

contract AutoConverterFactoryTest is RelayFactoryTest {
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
        relayFactory = RelayFactory(autoConverterFactory);
    }

    function testCannotCreateAutoConverterWithNoAdmin() public {
        vm.expectRevert(IRelayFactory.ZeroAddress.selector);
        autoConverterFactory.createRelay(address(0), 1, "", abi.encode(address(USDC)));
    }

    function testCannotCreateAutoConverterWithZeroTokenId() public {
        vm.expectRevert(IRelayFactory.TokenIdZero.selector);
        autoConverterFactory.createRelay(address(1), 0, "", abi.encode(address(USDC)));
    }

    function testCannotCreateAutoConverterIfNotApprovedSender() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        vm.startPrank(address(owner));
        escrow.approve(address(autoConverterFactory), mTokenId);
        escrow.setApprovalForAll(address(autoConverterFactory), true);
        vm.stopPrank();
        vm.expectRevert(IRelayFactory.TokenIdNotApproved.selector);
        vm.prank(address(owner2));
        autoConverterFactory.createRelay(address(1), mTokenId, "", abi.encode(address(USDC)));
    }

    function testCannotCreateAutoConverterIfTokenNotManaged() public {
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.expectRevert(IRelayFactory.TokenIdNotManaged.selector);
        bytes memory data = abi.encode(address(USDC));
        autoConverterFactory.createRelay(address(1), tokenId, "", data); // normal

        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);
        vm.expectRevert(IRelayFactory.TokenIdNotManaged.selector);
        autoConverterFactory.createRelay(address(1), tokenId, "", data); // locked
    }

    function testCreateAutoConverter() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoConverterFactory.relaysLength(), 0);

        vm.startPrank(address(owner));
        escrow.approve(address(autoConverterFactory), mTokenId);
        bytes memory data = abi.encode(address(USDC));
        autoConverter = AutoConverter(autoConverterFactory.createRelay(address(owner), mTokenId, "", data));

        assertFalse(address(autoConverter) == address(0));
        assertEq(autoConverterFactory.relaysLength(), 1);
        address[] memory autoConverters = autoConverterFactory.relays();
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

        assertEq(autoConverterFactory.relaysLength(), 0);

        vm.startPrank(address(owner));
        escrow.setApprovalForAll(address(autoConverterFactory), true);
        escrow.approve(address(owner2), mTokenId);
        vm.stopPrank();
        vm.prank(address(owner2));
        bytes memory data = abi.encode(address(USDC));
        autoConverter = AutoConverter(autoConverterFactory.createRelay(address(owner), mTokenId, "", data));

        assertFalse(address(autoConverter) == address(0));
        assertEq(autoConverterFactory.relaysLength(), 1);
        address[] memory autoConverters = autoConverterFactory.relays();
        assertEq(address(autoConverter), autoConverters[0]);
        assertEq(escrow.balanceOf(address(autoConverter)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoConverter));
        assertEq(autoConverter.mTokenId(), mTokenId);
    }

    function testCreateAutoConverterByApprovedForAll() public {
        vm.prank(escrow.allowedManager());
        mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(autoConverterFactory.relaysLength(), 0);

        vm.startPrank(address(owner));
        escrow.approve(address(autoConverterFactory), mTokenId);
        escrow.setApprovalForAll(address(owner2), true);
        vm.stopPrank();
        vm.prank(address(owner2));
        bytes memory data = abi.encode(address(USDC));
        autoConverter = AutoConverter(autoConverterFactory.createRelay(address(owner), mTokenId, "", data));

        assertFalse(address(autoConverter) == address(0));
        assertEq(autoConverterFactory.relaysLength(), 1);
        address[] memory autoConverters = autoConverterFactory.relays();
        assertEq(address(autoConverter), autoConverters[0]);
        assertEq(escrow.balanceOf(address(autoConverter)), 1);
        assertEq(escrow.ownerOf(mTokenId), address(autoConverter));
        assertEq(autoConverter.mTokenId(), mTokenId);
    }
}

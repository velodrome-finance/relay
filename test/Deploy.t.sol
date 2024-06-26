// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "../script/Deploy.s.sol";

contract TestDeploy is Script, Test {
    using stdJson for string;
    using stdStorage for StdStorage;

    uint256 optimismFork;
    /// @dev set OPTIMISM_RPC_URL in .env to run mainnet tests
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    /// @dev optionally set FORK_BLOCK_NUMBER in .env / test set up for faster tests / fixed tests
    uint256 BLOCK_NUMBER = vm.envOr("FORK_BLOCK_NUMBER", uint256(0));
    string public CONSTANTS_FILENAME = vm.envString("CONSTANTS_FILENAME");
    string public jsonConstants;
    address public constant testDeployer = address(1);

    address router;
    address USDC;
    address WETH;
    address OP;
    address VELO;
    address poolFactory;
    address voter;
    address[] highLiquidityTokens;

    Deploy deploy;

    constructor() {}

    function setUp() public {
        if (BLOCK_NUMBER != 0) {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL, BLOCK_NUMBER);
        } else {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL);
        }
        vm.selectFork(optimismFork);

        deploy = new Deploy();

        // load in variables
        string memory root = vm.projectRoot();
        string memory basePath = string.concat(root, "/script/constants/");
        string memory path = string.concat(basePath, CONSTANTS_FILENAME);
        jsonConstants = vm.readFile(path);
        router = abi.decode(jsonConstants.parseRaw(".v2.Router"), (address));
        // CompoundOptimizer-specific
        USDC = abi.decode(jsonConstants.parseRaw(".USDC"), (address));
        WETH = abi.decode(jsonConstants.parseRaw(".WETH"), (address));
        OP = abi.decode(jsonConstants.parseRaw(".OP"), (address));
        VELO = abi.decode(jsonConstants.parseRaw(".v2.VELO"), (address));
        poolFactory = abi.decode(jsonConstants.parseRaw(".v2.PoolFactory"), (address));
        // AutoCompounderFactory-specific
        voter = abi.decode(jsonConstants.parseRaw(".v2.Voter"), (address));
        address[] memory _highLiquidityTokens = abi.decode(jsonConstants.parseRaw(".highLiquidityTokens"), (address[]));
        highLiquidityTokens = new address[](_highLiquidityTokens.length);
        for (uint256 i = 0; i < _highLiquidityTokens.length; i++) {
            highLiquidityTokens[i] = _highLiquidityTokens[i];
        }

        // use test account for deployment
        stdstore.target(address(deploy)).sig("deployerAddress()").checked_write(testDeployer);
    }

    function testLoadedState() public {
        assertTrue(router != address(0));
        assertTrue(USDC != address(0));
        assertTrue(WETH != address(0));
        assertTrue(OP != address(0));
        assertTrue(VELO != address(0));
        assertTrue(poolFactory != address(0));
        assertTrue(voter != address(0));
        assertTrue(highLiquidityTokens.length > 0);
    }

    function testDeployScript() public {
        deploy.run();

        assertTrue(address(deploy.autoCompounderFactory()) != address(0));
        assertTrue(address(deploy.optimizer()) != address(0));

        // AutoCompounderFactory state checks
        assertEq(deploy.autoCompounderFactory().rewardAmount(), 10 * 1e18);
        assertEq(deploy.autoCompounderFactory().MAX_REWARD_AMOUNT(), 1_000 * 1e18);
        assertEq(deploy.autoCompounderFactory().MIN_REWARD_AMOUNT(), 1e17);
        assertEq(deploy.autoCompounderFactory().voter(), voter);
        assertEq(deploy.autoCompounderFactory().router(), router);
        assertEq(deploy.autoCompounderFactory().defaultOptimizer(), address(deploy.optimizer()));
        assertEq(deploy.autoCompounderFactory().highLiquidityTokensLength(), highLiquidityTokens.length);
        address[] memory deployedHighLiquidityTokens = deploy.autoCompounderFactory().highLiquidityTokens();
        for (uint256 i = 0; i < highLiquidityTokens.length; i++) {
            assertEq(deployedHighLiquidityTokens[i], highLiquidityTokens[i]);
        }

        // CompoundOptimizer state checks
        assertEq(deploy.optimizer().weth(), WETH);
        assertEq(deploy.optimizer().usdc(), USDC);
        assertEq(deploy.optimizer().op(), OP);
        assertEq(deploy.optimizer().velo(), VELO);
        assertEq(deploy.optimizer().factory(), poolFactory);
        assertEq(address(deploy.optimizer().router()), router);

        assertEq(address(deploy.keeperRegistry().owner()), testDeployer);
        assertTrue(deploy.relayFactoryRegistry().isApproved(address(deploy.autoCompounderFactory())));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {AutoCompounder} from "src/AutoCompounder.sol";
import {AutoCompounderFactory} from "src/AutoCompounderFactory.sol";
import {CompoundOptimizer} from "src/CompoundOptimizer.sol";

contract Deploy is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.addr(deployPrivateKey);
    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public outputFilename = vm.envString("OUTPUT_FILENAME");

    AutoCompounder public autoCompounder;
    AutoCompounderFactory public autoCompounderFactory;
    CompoundOptimizer public optimizer;
    string public jsonConstants;
    string public jsonOutput;

    function run() public {
        string memory root = vm.projectRoot();
        string memory basePath = string.concat(root, "/script/constants/");
        string memory path = string.concat(basePath, constantsFilename);

        // load in variables
        jsonConstants = vm.readFile(path);
        address router = abi.decode(jsonConstants.parseRaw(".v2.Router"), (address));
        // CompoundOptimizer-specific
        address USDC = abi.decode(jsonConstants.parseRaw(".USDC"), (address));
        address WETH = abi.decode(jsonConstants.parseRaw(".WETH"), (address));
        address OP = abi.decode(jsonConstants.parseRaw(".OP"), (address));
        address VELO = abi.decode(jsonConstants.parseRaw(".v2.VELO"), (address));
        address poolFactory = abi.decode(jsonConstants.parseRaw(".v2.PoolFactory"), (address));
        // AutoCompounderFactory-specific
        address forwarder = abi.decode(jsonConstants.parseRaw(".v2.Forwarder"), (address));
        address voter = abi.decode(jsonConstants.parseRaw(".v2.Voter"), (address));
        address factoryRegistry = abi.decode(jsonConstants.parseRaw(".v2.FactoryRegistry"), (address));
        address[] memory highLiquidityTokens = abi.decode(jsonConstants.parseRaw(".highLiquidityTokens"), (address[]));

        vm.startBroadcast(deployerAddress);

        // first deploy optimizer to pass into AutoCompounderFactory
        optimizer = new CompoundOptimizer(USDC, WETH, OP, VELO, poolFactory, router);
        autoCompounderFactory = new AutoCompounderFactory(
            forwarder,
            voter,
            router,
            address(optimizer),
            factoryRegistry,
            highLiquidityTokens
        );

        vm.stopBroadcast();

        path = string.concat(basePath, "output/");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("v2", "CompoundOptimizer", address(optimizer)), path);
        vm.writeJson(vm.serializeAddress("v2", "AutoCompounderFactory", address(autoCompounderFactory)), path);
    }
}
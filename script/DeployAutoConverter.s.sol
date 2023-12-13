// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {Registry} from "src/Registry.sol";
import {AutoConverter} from "src/autoConverter/AutoConverter.sol";
import {AutoConverterFactory} from "src/autoConverter/AutoConverterFactory.sol";
import {Optimizer} from "src/Optimizer.sol";

contract DeployAutoConverter is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public outputFilename = vm.envString("OUTPUT_FILENAME");

    AutoConverter public autoConverter;
    AutoConverterFactory public autoConverterFactory;
    Registry public keeperRegistry;
    Registry public optimizerRegistry;
    Registry public relayFactoryRegistry;
    Optimizer public optimizer;
    string public jsonConstants;
    string public jsonOutput;

    function run() public {
        string memory root = vm.projectRoot();
        string memory basePath = string.concat(root, "/script/constants/");
        string memory path = string.concat(basePath, constantsFilename);

        // load in variables
        jsonConstants = vm.readFile(path);
        address router = abi.decode(jsonConstants.parseRaw(".v2.Router"), (address));
        // AutoConverterFactory-specific
        address voter = abi.decode(jsonConstants.parseRaw(".v2.Voter"), (address));
        address[] memory highLiquidityTokens = abi.decode(jsonConstants.parseRaw(".highLiquidityTokens"), (address[]));

        path = string.concat(basePath, "output/");
        path = string.concat(path, outputFilename);
        jsonOutput = vm.readFile(path);
        relayFactoryRegistry = Registry(abi.decode(jsonOutput.parseRaw(".RelayFactoryRegistry"), (address)));
        keeperRegistry = Registry(abi.decode(jsonOutput.parseRaw(".KeeperRegistry"), (address)));
        optimizerRegistry = Registry(abi.decode(jsonOutput.parseRaw(".OptimizerRegistry"), (address)));
        optimizer = Optimizer(abi.decode(jsonOutput.parseRaw(".Optimizer"), (address)));

        vm.startBroadcast(deployerAddress);

        autoConverterFactory = new AutoConverterFactory(
            voter,
            router,
            address(keeperRegistry),
            address(optimizerRegistry),
            address(optimizer),
            highLiquidityTokens
        );
        relayFactoryRegistry.approve(address(autoConverterFactory));

        vm.stopBroadcast();

        path = string.concat(basePath, "output/DeployAutoConverter-");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("v2", "AutoConverterFactory", address(autoConverterFactory)), path);
    }
}

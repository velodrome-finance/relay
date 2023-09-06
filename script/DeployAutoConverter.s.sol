// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {AutoConverter} from "src/autoConverter/AutoConverter.sol";
import {AutoConverterFactory} from "src/autoConverter/AutoConverterFactory.sol";

contract DeployAutoConverter is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public outputFilename = vm.envString("OUTPUT_FILENAME");

    AutoConverter public autoConverter;
    AutoConverterFactory public autoConverterFactory;
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
        address forwarder = abi.decode(jsonConstants.parseRaw(".v2.Forwarder"), (address));
        address voter = abi.decode(jsonConstants.parseRaw(".v2.Voter"), (address));
        address factoryRegistry = abi.decode(jsonConstants.parseRaw(".v2.FactoryRegistry"), (address));

        vm.startBroadcast(deployerAddress);

        autoConverterFactory = new AutoConverterFactory(forwarder, voter, router, factoryRegistry);

        vm.stopBroadcast();

        path = string.concat(basePath, "output/");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("v2", "AutoConverterFactory", address(autoConverterFactory)), path);
    }
}

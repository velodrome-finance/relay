import { Contract } from "@ethersproject/contracts";
import { ethers } from "hardhat";
import { Libraries } from "hardhat/types";
import jsonOutput from "../constants/output/Tenderly.json";
import jsonConstants from "../constants/Optimism.json";
import { join } from "path";
import { writeFile } from "fs/promises";
import {
  Registry,
  AutoConverterFactory,
  ConverterOptimizer,
} from "../../artifacts/types";

export async function deploy<Type>(
  typeName: string,
  libraries?: Libraries,
  ...args: any[]
): Promise<Type> {
  const ctrFactory = await ethers.getContractFactory(typeName, { libraries });

  const ctr = (await ctrFactory.deploy(...args)) as unknown as Type;
  await (ctr as unknown as Contract).deployed();
  return ctr;
}

export async function getContractAt<Type>(
  typeName: string,
  address: string
): Promise<Type> {
  const ctr = (await ethers.getContractAt(
    typeName,
    address
  )) as unknown as Type;
  return ctr;
}

async function main() {
  const keeperRegistry = jsonOutput.KeeperRegistry;
  const relayFactoryRegistry = await getContractAt<Registry>(
    "Registry",
    jsonOutput.Registry
  );

  const optimizer = await deploy<ConverterOptimizer>(
    "CompoundOptimizer",
    undefined,
    jsonConstants.USDC,
    jsonConstants.WETH,
    jsonConstants.OP,
    jsonConstants.v2.VELO,
    jsonConstants.v2.PoolFactory,
    jsonConstants.v2.Router
  );
  console.log(`ConverterOptimizer deployed to: ${optimizer.address}`);
  const acFactory = await deploy<AutoConverterFactory>(
    "AutoConverterFactory",
    undefined,
    jsonConstants.v2.Forwarder,
    jsonConstants.v2.Voter,
    jsonConstants.v2.Router,
    optimizer.address,
    keeperRegistry.address,
    jsonConstants.highLiquidityTokens
  );
  console.log(`AutoConverterFactory deployed to ${acFactory.address}`);
  await relayFactoryRegistry.approve(acFactory.address);

  interface DeployOutput {
    ConverterOptimizer: string;
    AutoConverterFactory: string;
  }
  const output: DeployOutput = {
    ConverterOptimizer: optimizer.address,
    AutoConverterFactory: acFactory.address,
  };

  const outputDirectory = "script/constants/output";
  const outputFile = join(
    process.cwd(),
    outputDirectory,
    "TenderlyAutoConverter.json"
  );

  try {
    await writeFile(outputFile, JSON.stringify(output, null, 2));
  } catch (err) {
    console.error(`Error writing output file: ${err}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

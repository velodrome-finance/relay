import { Contract } from "@ethersproject/contracts";
import { ethers } from "hardhat";
import { Libraries } from "hardhat/types";
import jsonConstants from "../constants/Base.json";
import { join } from "path";
import { writeFile } from "fs/promises";
import {
  Registry,
  OptimizerBase,
  AutoCompounderFactory,
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

async function main() {
  const relayFactoryRegistry = await deploy<Registry>(
    "Registry",
    undefined,
    []
  );
  console.log(`Registry deployed to ${relayFactoryRegistry.address}`);
  const keeperRegistry = await deploy<Registry>("Registry", undefined, []);
  console.log(`KeeperRegistry deployed to ${keeperRegistry.address}`);

  const optimizerBase = await deploy<OptimizerBase>(
    "OptimizerBase",
    undefined,
    jsonConstants.USDC,
    jsonConstants.WETH,
    jsonConstants.v2.VELO,
    jsonConstants.v2.PoolFactory,
    jsonConstants.v2.Router
  );
  console.log(`OptimizerBase deployed to: ${optimizerBase.address}`);

  const optimizerRegistry = await deploy<Registry>("Registry", undefined, []);
  await optimizerRegistry.approve(optimizerBase.address);
  const acFactory = await deploy<AutoCompounderFactory>(
    "AutoCompounderFactory",
    undefined,
    jsonConstants.v2.Voter,
    jsonConstants.v2.Router,
    keeperRegistry.address,
    optimizerRegistry.address,
    optimizerBase.address,
    jsonConstants.highLiquidityTokens
  );
  console.log(`AutoCompounderFactory deployed to ${acFactory.address}`);
  await relayFactoryRegistry.approve(acFactory.address);

  interface DeployOutput {
    OptimizerBase: string;
    OptimizerRegistry: string;
    AutoCompounderFactory: string;
    RelayFactoryRegistry: string;
    KeeperRegistry: string;
  }

  const output: DeployOutput = {
    OptimizerBase: optimizerBase.address,
    OptimizerRegistry: optimizerRegistry.address,
    AutoCompounderFactory: acFactory.address,
    RelayFactoryRegistry: relayFactoryRegistry.address,
    KeeperRegistry: keeperRegistry.address,
  };

  const outputDirectory = "script/constants/output";
  const outputFile = join(process.cwd(), outputDirectory, "Tenderly.json");

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

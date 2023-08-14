import { Contract } from "@ethersproject/contracts";
import { ethers } from "hardhat";
import { Libraries } from "hardhat/types";
import jsonConstants from "../constants/Optimism.json";
import { join } from "path";
import { writeFile } from "fs/promises";
import {
  CompoundOptimizer,
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
  const optimizer = await deploy<CompoundOptimizer>(
    "CompoundOptimizer",
    undefined,
    jsonConstants.USDC,
    jsonConstants.WETH,
    jsonConstants.OP,
    jsonConstants.v2.VELO,
    jsonConstants.v2.PoolFactory,
    jsonConstants.v2.Router
  );
  console.log(`CompoundOptimizer deployed to: ${optimizer.address}`);
  const acFactory = await deploy<AutoCompounderFactory>(
    "AutoCompounderFactory",
    undefined,
    jsonConstants.v2.Forwarder,
    jsonConstants.v2.Voter,
    jsonConstants.v2.Router,
    optimizer.address,
    jsonConstants.v2.FactoryRegistry,
    jsonConstants.highLiquidityTokens
  );
  console.log(`AutoCompounderFactory deployed to ${acFactory.address}`);

  interface DeployOutput {
    CompoundOptimizer: string;
    AutoCompounderFactory: string;
  }
  const output: DeployOutput = {
    CompoundOptimizer: optimizer.address,
    AutoCompounderFactory: acFactory.address,
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

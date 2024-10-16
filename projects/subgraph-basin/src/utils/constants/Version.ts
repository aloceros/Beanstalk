import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";
import { Version } from "../../../generated/schema";
import { VersionDto } from "../../../../subgraph-core/constants/RuntimeConstants";
import { toAddress } from "../../../../subgraph-core/utils/Bytes";
import * as BeanstalkEth from "../../../../subgraph-core/constants/raw/BeanstalkEthConstants";
import * as BeanstalkArb from "../../../../subgraph-core/constants/raw/BeanstalkArbConstants";

export function handleInitVersion(block: ethereum.Block): void {
  const versionEntity = new Version("subgraph");
  versionEntity.versionNumber = "3.1.1";
  versionEntity.subgraphName = subgraphNameForBlockNumber(block.number);
  versionEntity.protocolAddress = protocolForBlockNumber(block.number);
  versionEntity.chain = chainForBlockNumber(block.number);
  versionEntity.save();
}

function subgraphNameForBlockNumber(blockNumber: BigInt): string {
  if (blockNumber == BeanstalkEth.BASIN_BLOCK) {
    return "basin";
  } else if (blockNumber == BeanstalkArb.BASIN_BLOCK) {
    return "basin";
  }
  throw new Error("Unable to initialize subgraph name for this block number");
}

function protocolForBlockNumber(blockNumber: BigInt): Address {
  if (blockNumber == BeanstalkEth.BASIN_BLOCK) {
    return BeanstalkEth.BEANSTALK;
  } else if (blockNumber == BeanstalkArb.BASIN_BLOCK) {
    return BeanstalkArb.BEANSTALK;
  }
  throw new Error("Unable to initialize protocol address for this block number");
}

function chainForBlockNumber(blockNumber: BigInt): string {
  if (blockNumber == BeanstalkEth.BASIN_BLOCK) {
    return "ethereum";
  } else if (blockNumber == BeanstalkArb.BASIN_BLOCK) {
    return "arbitrum";
  }
  throw new Error("Unable to initialize chain for this block number");
}

export function v(): VersionDto {
  const versionEntity = Version.load("subgraph")!;
  return {
    subgraphName: versionEntity.subgraphName,
    versionNumber: versionEntity.versionNumber,
    protocolAddress: toAddress(versionEntity.protocolAddress),
    chain: versionEntity.chain
  };
}

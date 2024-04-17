import { BigInt, Address, log } from "@graphprotocol/graph-ts";
import { TwaOracle } from "../../../generated/schema";
import { BI_10, emptyBigIntArray, ONE_BI, ZERO_BI } from "../../../../subgraph-core/utils/Decimals";
import { uniswapCumulativePrice } from "./UniswapPrice";
import { WETH_USDC_PAIR } from "../../../../subgraph-core/utils/Constants";
import { curveCumulativePrices } from "./CurvePrice";
import { TWAType } from "./Types";

export function loadOrCreateTwaOracle(poolAddress: string): TwaOracle {
  let twaOracle = TwaOracle.load(poolAddress);
  if (twaOracle == null) {
    twaOracle = new TwaOracle(poolAddress);
    twaOracle.pool = poolAddress;
    twaOracle.priceCumulativeSun = emptyBigIntArray(2);
    twaOracle.lastSun = ZERO_BI;
    twaOracle.priceCumulativeLast = emptyBigIntArray(2);
    twaOracle.lastBalances = emptyBigIntArray(2);
    twaOracle.lastUpdated = ZERO_BI;
    twaOracle.save();
  }
  return twaOracle as TwaOracle;
}

export function manualTwa(poolAddress: string, newReserves: BigInt[], timestamp: BigInt): void {
  let twaOracle = loadOrCreateTwaOracle(poolAddress);
  const elapsedTime = timestamp.minus(twaOracle.lastUpdated);
  const newPriceCumulative = [
    twaOracle.priceCumulativeLast[0].plus(twaOracle.lastBalances[0].times(elapsedTime)),
    twaOracle.priceCumulativeLast[1].plus(twaOracle.lastBalances[1].times(elapsedTime))
  ];
  twaOracle.priceCumulativeLast = newPriceCumulative;
  twaOracle.lastBalances = newReserves;
  twaOracle.lastUpdated = timestamp;
  twaOracle.save();
}

// Returns the current TWA prices since the previous TwaOracle update
export function getTWAPrices(poolAddress: string, type: TWAType, timestamp: BigInt): BigInt[] {
  let twaOracle = loadOrCreateTwaOracle(poolAddress);
  const initialized = twaOracle.lastSun != ZERO_BI;

  let newPriceCumulative: BigInt[] = [];
  let twaPrices: BigInt[] = [];

  const timeElapsed = timestamp.minus(twaOracle.lastSun);
  if (type == TWAType.UNISWAP) {
    const beanPrice = uniswapCumulativePrice(Address.fromString(poolAddress), 1, timestamp);
    const pegPrice = uniswapCumulativePrice(WETH_USDC_PAIR, 0, timestamp);
    newPriceCumulative = [beanPrice, pegPrice];

    twaPrices = [
      // (priceCumulative - s.o.cumulative) / timeElapsed / 1e12 -> Decimal.ratio() which does * 1e18 / (1 << 112).
      newPriceCumulative[0].minus(twaOracle.priceCumulativeSun[0]).div(timeElapsed).times(BI_10.pow(6)).div(ONE_BI.leftShift(112)),
      newPriceCumulative[1].minus(twaOracle.priceCumulativeSun[1]).div(timeElapsed).times(BI_10.pow(6)).div(ONE_BI.leftShift(112))
    ];
  } else {
    // Curve
    newPriceCumulative = curveCumulativePrices(Address.fromString(poolAddress), timestamp);
    twaPrices = [
      newPriceCumulative[0].minus(twaOracle.priceCumulativeSun[0]).div(timeElapsed),
      newPriceCumulative[1].minus(twaOracle.priceCumulativeSun[1]).div(timeElapsed)
    ];
  }

  // log.debug("twa prices {} | {}", [twaPrices[0].toString(), twaPrices[1].toString()]);

  twaOracle.priceCumulativeSun = newPriceCumulative;
  twaOracle.lastSun = timestamp;
  twaOracle.save();
  return initialized ? twaPrices : [BI_10.pow(18), BI_10.pow(18)];
}

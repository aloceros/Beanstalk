import { BigInt, Bytes, ethereum, log } from "@graphprotocol/graph-ts";
import { assert } from "matchstick-as/assembly/index";
import { handlePlotTransfer, handleSow } from "../../src/FieldHandler";
import {
  handlePodListingCreated_v2,
  handlePodListingFilled_v2,
  handlePodOrderCreated_v2,
  handlePodOrderFilled_v2
} from "../../src/MarketplaceHandler";
import { createPlotTransferEvent, createSowEvent } from "../event-mocking/Field";
import {
  createPodListingCreatedEvent_v2,
  createPodListingFilledEvent_v2,
  createPodOrderCreatedEvent_v2,
  createPodOrderFilledEvent_v2
} from "../event-mocking/Marketplace";
import { ONE_BI, ZERO_BI } from "../../../subgraph-core/utils/Decimals";
import {
  PodListingCreated as PodListingCreated_v2,
  PodListingFilled as PodListingFilled_v2,
  PodOrderCreated as PodOrderCreated_v2,
  PodOrderFilled as PodOrderFilled_v2
} from "../../generated/BIP29-PodMarketplace/Beanstalk";
import { BEANSTALK } from "../../../subgraph-core/utils/Constants";
import { Sow } from "../../generated/Field/Beanstalk";

const pricingFunction = Bytes.fromHexString(
  "0x0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000000000000000000000000000000000000000c8000000000000000000000000000000000000000000000000000000000000012c000000000000000000000000000000000000000000000000000000000000019000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010101010101010101010101010000"
);

export function sow(account: string, index: BigInt, beans: BigInt, pods: BigInt): Sow {
  const event = createSowEvent(account, index, beans, pods);
  handleSow(event);
  return event;
}

export function getPodFillId(index: BigInt, event: ethereum.Event): string {
  return BEANSTALK.toHexString() + "-" + index.toString() + "-" + event.transaction.hash.toHexString();
}

export function fillListing_v2(
  from: string,
  to: string,
  listingIndex: BigInt,
  listingStart: BigInt,
  podAmount: BigInt,
  costInBeans: BigInt
): PodListingFilled_v2 {
  const event = createPodListingFilledEvent_v2(from, to, listingIndex, listingStart, podAmount, costInBeans);
  handlePodListingFilled_v2(event);

  // Perform plot transfer (necessary for market - assumption is this is tested/working via PlotTransfer.test.ts)
  handlePlotTransfer(createPlotTransferEvent(from, to, listingIndex.plus(listingStart), podAmount));

  // Assert PodFill
  const podFillId = getPodFillId(event.params.index, event);
  assert.fieldEquals("PodFill", podFillId, "listing", event.params.from.toHexString() + "-" + event.params.index.toString());
  assert.fieldEquals("PodFill", podFillId, "from", event.params.from.toHexString());
  assert.fieldEquals("PodFill", podFillId, "to", event.params.to.toHexString());
  assert.fieldEquals("PodFill", podFillId, "amount", event.params.amount.toString());
  assert.fieldEquals("PodFill", podFillId, "index", event.params.index.toString());
  assert.fieldEquals("PodFill", podFillId, "start", event.params.start.toString());
  assert.fieldEquals("PodFill", podFillId, "costInBeans", event.params.costInBeans.toString());

  return event;
}

export function fillOrder_v2(
  from: string,
  to: string,
  orderId: Bytes,
  index: BigInt,
  start: BigInt,
  podAmount: BigInt,
  costInBeans: BigInt
): PodOrderFilled_v2 {
  const event = createPodOrderFilledEvent_v2(from, to, orderId, index, start, podAmount, costInBeans);
  handlePodOrderFilled_v2(event);

  // Assert PodFill
  const podFillId = getPodFillId(index, event);
  assert.fieldEquals("PodFill", podFillId, "order", event.params.id.toHexString());
  assert.fieldEquals("PodFill", podFillId, "from", event.params.from.toHexString());
  assert.fieldEquals("PodFill", podFillId, "to", event.params.to.toHexString());
  assert.fieldEquals("PodFill", podFillId, "amount", event.params.amount.toString());
  assert.fieldEquals("PodFill", podFillId, "index", event.params.index.toString());
  assert.fieldEquals("PodFill", podFillId, "start", event.params.start.toString());
  assert.fieldEquals("PodFill", podFillId, "costInBeans", event.params.costInBeans.toString());

  return event;
}

export function assertListingCreated_v2(event: PodListingCreated_v2): void {
  let listingID = event.params.account.toHexString() + "-" + event.params.index.toString();
  assert.fieldEquals("PodListing", listingID, "plot", event.params.index.toString());
  assert.fieldEquals("PodListing", listingID, "farmer", event.params.account.toHexString());
  assert.fieldEquals("PodListing", listingID, "status", "ACTIVE");
  assert.fieldEquals("PodListing", listingID, "originalIndex", event.params.index.toString());
  assert.fieldEquals("PodListing", listingID, "originalAmount", event.params.amount.toString());
  assert.fieldEquals("PodListing", listingID, "index", event.params.index.toString());
  assert.fieldEquals("PodListing", listingID, "start", event.params.start.toString());
  assert.fieldEquals("PodListing", listingID, "amount", event.params.amount.toString());
  assert.fieldEquals("PodListing", listingID, "remainingAmount", event.params.amount.toString());
  assert.fieldEquals("PodListing", listingID, "pricePerPod", event.params.pricePerPod.toString());
  assert.fieldEquals("PodListing", listingID, "maxHarvestableIndex", event.params.maxHarvestableIndex.toString());
  assert.fieldEquals("PodListing", listingID, "minFillAmount", event.params.minFillAmount.toString());
  assert.fieldEquals("PodListing", listingID, "pricingFunction", event.params.pricingFunction.toHexString());
  assert.fieldEquals("PodListing", listingID, "mode", event.params.mode.toString());
  assert.fieldEquals("PodListing", listingID, "pricingType", event.params.pricingType.toString());
}

export function assertOrderCreated_v2(account: string, event: PodOrderCreated_v2): void {
  let orderID = event.params.id.toHexString();
  assert.fieldEquals("PodOrder", orderID, "historyID", orderID + "-" + event.block.timestamp.toString());
  assert.fieldEquals("PodOrder", orderID, "farmer", account);
  assert.fieldEquals("PodOrder", orderID, "status", "ACTIVE");
  assert.fieldEquals("PodOrder", orderID, "beanAmount", event.params.amount.toString());
  assert.fieldEquals("PodOrder", orderID, "beanAmountFilled", "0");
  assert.fieldEquals("PodOrder", orderID, "minFillAmount", event.params.minFillAmount.toString());
  assert.fieldEquals("PodOrder", orderID, "maxPlaceInLine", event.params.maxPlaceInLine.toString());
  assert.fieldEquals("PodOrder", orderID, "pricePerPod", event.params.pricePerPod.toString());
  assert.fieldEquals("PodOrder", orderID, "pricingFunction", event.params.pricingFunction.toHexString());
  assert.fieldEquals("PodOrder", orderID, "pricingType", event.params.priceType.toString());
}

export function createListing_v2(
  account: string,
  index: BigInt,
  plotTotalPods: BigInt,
  start: BigInt,
  maxHarvestableIndex: BigInt
): PodListingCreated_v2 {
  const event = createPodListingCreatedEvent_v2(
    account,
    index,
    start,
    plotTotalPods.minus(start),
    BigInt.fromString("250000"),
    maxHarvestableIndex,
    BigInt.fromString("10000000"),
    pricingFunction,
    BigInt.fromI32(0),
    BigInt.fromI32(1)
  );
  handlePodListingCreated_v2(event);
  assertListingCreated_v2(event);
  return event;
}

export function createOrder_v2(
  account: string,
  id: Bytes,
  beans: BigInt,
  pricePerPod: BigInt,
  maxHarvestableIndex: BigInt
): PodOrderCreated_v2 {
  const event = createPodOrderCreatedEvent_v2(account, id, beans, pricePerPod, maxHarvestableIndex, ONE_BI, pricingFunction, ZERO_BI);
  handlePodOrderCreated_v2(event);
  assertOrderCreated_v2(account, event);
  return event;
}

export function assertMarketListingsState(
  address: string,
  listings: BigInt[],
  listedPods: BigInt,
  availableListedPods: BigInt,
  cancelledListedPods: BigInt,
  filledListedPods: BigInt,
  podVolume: BigInt,
  beanVolume: BigInt
): void {
  assert.fieldEquals("PodMarketplace", address, "listingIndexes", "[" + listings.join(", ") + "]");
  assert.fieldEquals("PodMarketplace", address, "listedPods", listedPods.toString());
  assert.fieldEquals("PodMarketplace", address, "availableListedPods", availableListedPods.toString());
  assert.fieldEquals("PodMarketplace", address, "cancelledListedPods", cancelledListedPods.toString());
  assert.fieldEquals("PodMarketplace", address, "filledListedPods", filledListedPods.toString());
  assert.fieldEquals("PodMarketplace", address, "podVolume", podVolume.toString());
  assert.fieldEquals("PodMarketplace", address, "beanVolume", beanVolume.toString());
}

export function assertMarketOrdersState(
  address: string,
  orders: string[],
  orderBeans: BigInt,
  filledOrderBeans: BigInt,
  filledOrderedPods: BigInt,
  cancelledOrderBeans: BigInt,
  podVolume: BigInt,
  beanVolume: BigInt
): void {
  assert.fieldEquals("PodMarketplace", address, "orders", "[" + orders.join(", ") + "]");
  assert.fieldEquals("PodMarketplace", address, "orderBeans", orderBeans.toString());
  assert.fieldEquals("PodMarketplace", address, "filledOrderBeans", filledOrderBeans.toString());
  assert.fieldEquals("PodMarketplace", address, "filledOrderedPods", filledOrderedPods.toString());
  assert.fieldEquals("PodMarketplace", address, "cancelledOrderBeans", cancelledOrderBeans.toString());
  assert.fieldEquals("PodMarketplace", address, "podVolume", podVolume.toString());
  assert.fieldEquals("PodMarketplace", address, "beanVolume", beanVolume.toString());
}

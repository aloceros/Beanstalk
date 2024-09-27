import { Address, Bytes } from "@graphprotocol/graph-ts";
import { BoreWell } from "../../generated/Basin-ABIs/Aquifer";
import { Well } from "../../generated/templates";
import { loadOrCreatePump } from "../entities/Pump";
import { loadOrCreateAquifer } from "../entities/Aquifer";
import { createWell, loadOrCreateWellFunction } from "../entities/Well";
import { loadOrCreateToken } from "../entities/Token";

export function handleBoreWell(event: BoreWell): void {
  let aquifer = loadOrCreateAquifer(event.address);

  Well.create(event.params.well);

  let well = createWell(event.params.well, event.params.tokens);
  well.aquifer = event.address;

  const tokens: Bytes[] = [];
  for (let i = 0; i < event.params.tokens.length; i++) {
    tokens.push(loadOrCreateToken(event.params.tokens[i]).id);
  }
  well.tokens = tokens;
  well.tokenOrder = tokens;

  for (let i = 0; i < event.params.pumps.length; i++) {
    loadOrCreatePump(event.params.pumps[i], event.params.well);
  }

  const wellFn = loadOrCreateWellFunction(event.params.wellFunction.target);
  wellFn.data = event.params.wellFunction.data;
  wellFn.save();

  well.wellFunction = event.params.wellFunction.target;
  well.implementation = event.params.implementation;
  well.createdTimestamp = event.block.timestamp;
  well.createdBlockNumber = event.block.number;
  well.save();

  let wells = aquifer.wells;
  wells.push(event.params.well);
  aquifer.wells = wells;
  aquifer.save();
}

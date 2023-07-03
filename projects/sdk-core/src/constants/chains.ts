/**
 * List of supported chains
 */
export enum ChainId {
  MAINNET = 1,
  LOCALHOST = 1337,
  ANVIL1 = 1007
}

/**
 * These chains are forks of mainnet,
 * therefore they use the same token addresses as mainnet.
 */
export const TESTNET_CHAINS = new Set([ChainId.LOCALHOST, ChainId.ANVIL1]);
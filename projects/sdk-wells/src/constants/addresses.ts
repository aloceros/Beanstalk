import { Address, ChainId } from "@beanstalk/sdk-core";

export const addresses = {
  // Tokens
  BEAN: Address.make({
    [ChainId.MAINNET]: "0xBEA0000029AD1c77D3d5D23Ba2D8893dB9d1Efab",
    [ChainId.ARBITRUM]: "0xBEA0005B8599265D41256905A9B3073D397812E4"
  }),
  WETH: Address.make({
    [ChainId.MAINNET]: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    [ChainId.ARBITRUM]: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
  }),
  WSTETH: Address.make({
    [ChainId.MAINNET]: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
    [ChainId.ARBITRUM]: "0x5979D7b546E38E414F7E9822514be443A4800529"
  }),
  WEETH: Address.make({
    [ChainId.MAINNET]: "0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee",
    [ChainId.ARBITRUM]: "0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe"
  }),
  DAI: Address.make({
    [ChainId.MAINNET]: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    [ChainId.ARBITRUM]: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1"
  }),
  WBTC: Address.make({
    [ChainId.MAINNET]: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
    [ChainId.ARBITRUM]: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f"
  }),
  USDC: Address.make({
    [ChainId.MAINNET]: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    [ChainId.ARBITRUM]: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
  }),
  USDT: Address.make({
    [ChainId.MAINNET]: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
    [ChainId.ARBITRUM]: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"
  }),
  STETH: Address.make({
    [ChainId.MAINNET]: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
  }),

  // Contracts
  DEPOT: Address.make({
    [ChainId.MAINNET]: "0xDEb0f00071497a5cc9b4A6B96068277e57A82Ae2",
    [ChainId.ARBITRUM]: "0xDEb0f0dEEc1A29ab97ABf65E537452D1B00A619c"
  }),
  PIPELINE: Address.make({
    [ChainId.MAINNET]: "0xb1bE0000C6B3C62749b5F0c92480146452D15423",
    [ChainId.ARBITRUM]: "0xb1bE000644bD25996b0d9C2F7a6D6BA3954c91B0"
  }),
  WETH9: Address.make({
    [ChainId.MAINNET]: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
    [ChainId.ARBITRUM]: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
  }),
  UNWRAP_AND_SEND_JUNCTION: Address.make({
    [ChainId.MAINNET]: "0x737cad465b75cdc4c11b3e312eb3fe5bef793d96"
    // [ChainId.ARBITRUM]: ""
  })
};

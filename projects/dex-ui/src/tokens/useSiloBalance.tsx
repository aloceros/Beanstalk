import { useAccount } from "wagmi";

import { DataSource, Token, TokenValue } from "@beanstalk/sdk";

import { getIsValidEthereumAddress } from "src/utils/addresses";
import { queryKeys } from "src/utils/query/queryKeys";
import { useScopedQuery, useSetScopedQueryData } from "src/utils/query/useScopedQuery";
import useSdk from "src/utils/sdk/useSdk";

export const useSiloBalance = (token: Token) => {
  const { address } = useAccount();
  const sdk = useSdk();

  const { data, isLoading, error, refetch, isFetching } = useScopedQuery({
    queryKey: queryKeys.siloBalance(token.address),

    queryFn: async (): Promise<TokenValue> => {
      let balance: TokenValue;
      if (!address) {
        balance = TokenValue.ZERO;
      } else {
        const sdkLPToken = sdk.tokens.findByAddress(token.address);
        const result = await sdk.silo.getBalance(sdkLPToken!, address);
        balance = result.amount;
      }
      return balance;
    },

    staleTime: 1000 * 30,
    refetchInterval: 1000 * 30,
    refetchIntervalInBackground: false,
    refetchOnWindowFocus: "always"
  });

  return { data, isLoading, error, refetch, isFetching };
};

export const useFarmerWellsSiloBalances = () => {
  const { address } = useAccount();
  const sdk = useSdk();
  const setQueryData = useSetScopedQueryData();
  const wellTokens = Array.from(sdk.tokens.wellLP);
  const addresses = wellTokens.map((token) => token.address);

  const { data, isLoading, error, refetch, isFetching } = useScopedQuery({
    queryKey: queryKeys.siloBalancesAll(addresses),
    queryFn: async () => {
      const resultMap: Record<string, TokenValue> = {};
      if (!address) return resultMap;

      const results = await Promise.all(
        wellTokens.map((token) => sdk.silo.getBalance(token, address))
      );

      results.forEach((val, i) => {
        const token = wellTokens[i];
        resultMap[token.address] = val.amount;
        setQueryData(queryKeys.siloBalance(token.address), () => {
          return val.amount;
        });
      });

      return resultMap;
    },
    enabled: getIsValidEthereumAddress(address) && !!wellTokens.length,
    retry: false
  });

  return { data, isLoading, error, refetch, isFetching };
};

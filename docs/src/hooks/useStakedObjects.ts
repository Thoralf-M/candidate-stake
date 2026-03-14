import { useQuery } from "@tanstack/react-query";
import { useIotaClient } from "@iota/dapp-kit";

export interface StakedIotaInfo {
  objectId: string;
  principal: string;
  validatorAddress: string;
}

export function useStakedObjects(address: string | undefined) {
  const client = useIotaClient();
  return useQuery({
    queryKey: ["staked-objects", address],
    queryFn: async () => {
      if (!address) return [];
      const stakes = await client.getStakes({ owner: address });
      const result: StakedIotaInfo[] = [];
      for (const group of stakes) {
        for (const stake of group.stakes) {
          result.push({
            objectId: stake.stakedIotaId,
            principal: stake.principal,
            validatorAddress: group.validatorAddress,
          });
        }
      }
      return result;
    },
    enabled: !!address,
    refetchInterval: 15_000,
  });
}

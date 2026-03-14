import { useQuery } from "@tanstack/react-query";
import { useIotaClient } from "@iota/dapp-kit";

export interface ValidatorSummary {
  iotaAddress: string;
  name: string;
  description: string;
  imageUrl: string;
  projectUrl: string;
  stakingPoolIotaBalance: string;
  commissionRate: string;
  nextEpochCommissionRate: string;
}

export function useValidators() {
  const client = useIotaClient();
  return useQuery({
    queryKey: ["validators"],
    queryFn: async () => {
      const state = await client.getLatestIotaSystemState();
      const map = new Map<string, ValidatorSummary>();
      for (const v of state.activeValidators) {
        map.set(v.iotaAddress, v as unknown as ValidatorSummary);
      }
      return map;
    },
    staleTime: 60_000,
  });
}

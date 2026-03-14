import { useCurrentAccount } from "@iota/dapp-kit";
import type { PoolData } from "../hooks/usePools";
import { useValidators } from "../hooks/useValidators";
import { useCandidateValidators } from "../hooks/useCandidateValidators";
import { useStakedObjects } from "../hooks/useStakedObjects";
import { PoolCard } from "./PoolCard";

type Account = ReturnType<typeof useCurrentAccount>;

interface Props {
  pools: PoolData[];
  packageId: string;
  network: string;
  account: Account;
  onChanged: () => void;
}

export function PoolList({ pools, packageId, network, account, onChanged }: Props) {
  const { data: validators } = useValidators();
  const { data: candidates } = useCandidateValidators();
  const { data: stakedObjects } = useStakedObjects(account?.address);

  // Merge active validators and candidates into one lookup
  const allValidators = new Map(validators ?? []);
  if (candidates) {
    for (const c of candidates) {
      if (!allValidators.has(c.iotaAddress)) {
        allValidators.set(c.iotaAddress, {
          ...c,
          nextEpochCommissionRate: c.commissionRate,
        });
      }
    }
  }

  if (!pools.length)
    return <p className="empty">No pools found for this package.</p>;

  return (
    <div className="section">
      <h2>Pools ({pools.length})</h2>
      {pools.map((pool) => (
        <PoolCard
          key={pool.objectId}
          pool={pool}
          packageId={packageId}
          network={network}
          validator={allValidators.get(pool.fields.target_validator)}
          account={account}
          stakedObjects={stakedObjects ?? []}
          onChanged={onChanged}
        />
      ))}
    </div>
  );
}

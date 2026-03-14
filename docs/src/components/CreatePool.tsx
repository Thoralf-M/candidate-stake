import { useState } from "react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
} from "@iota/dapp-kit";
import { Transaction } from "@iota/iota-sdk/transactions";
import { useCandidateValidators } from "../hooks/useCandidateValidators";

type Account = ReturnType<typeof useCurrentAccount>;

interface Props {
  packageId: string;
  account: Account;
  existingTargets: Set<string>;
  onCreated: () => void;
}

function shortAddr(addr: string): string {
  return addr.slice(0, 8) + "..." + addr.slice(-6);
}

export function CreatePool({
  packageId,
  account,
  existingTargets,
  onCreated,
}: Props) {
  const [validator, setValidator] = useState("");
  const [error, setError] = useState("");
  const { data: candidates } = useCandidateValidators();
  const { mutate: signAndExecute, isPending } =
    useSignAndExecuteTransaction();

  const create = () => {
    setError("");
    const tx = new Transaction();
    tx.moveCall({
      target: `${packageId}::candidate_stake::create`,
      arguments: [tx.pure.address(validator)],
    });
    signAndExecute(
      { transaction: tx },
      {
        onSuccess: () => {
          setValidator("");
          onCreated();
        },
        onError: (e) => setError(e.message),
      },
    );
  };

  const available =
    candidates?.filter((c) => !existingTargets.has(c.iotaAddress)) ?? [];

  return (
    <div className="section">
      <h2>Create Pool</h2>
      {!account ? (
        <p style={{ color: "var(--muted)", fontSize: "0.85rem" }}>
          Connect a wallet to create a pool.
        </p>
      ) : available.length > 0 ? (
        <div className="form-row">
          <select
            value={validator}
            onChange={(e) => setValidator(e.target.value)}
          >
            <option value="">Select candidate validator...</option>
            {available.map((v) => (
              <option key={v.iotaAddress} value={v.iotaAddress}>
                {v.name} ({shortAddr(v.iotaAddress)})
              </option>
            ))}
          </select>
          <button onClick={create} disabled={!validator || isPending}>
            {isPending ? "Creating..." : "Create"}
          </button>
        </div>
      ) : candidates && candidates.length > 0 ? (
        <p style={{ color: "var(--muted)", fontSize: "0.85rem" }}>
          All candidate validators already have a pool.
        </p>
      ) : candidates ? (
        <p style={{ color: "var(--muted)", fontSize: "0.85rem" }}>
          No candidate validators found on this network.
        </p>
      ) : (
        <p className="loading">Loading candidates...</p>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  );
}

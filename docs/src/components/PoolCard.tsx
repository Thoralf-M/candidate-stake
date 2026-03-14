import { useState } from "react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
} from "@iota/dapp-kit";
import { Transaction } from "@iota/iota-sdk/transactions";
import type { PoolData } from "../hooks/usePools";
import type { ValidatorSummary } from "../hooks/useValidators";
import type { StakedIotaInfo } from "../hooks/useStakedObjects";

const THRESHOLD = 2_000_000;
const NANOS_PER_IOTA = 1_000_000_000;

function formatIota(nanos: string | number): string {
  const n = typeof nanos === "string" ? Number(nanos) : nanos;
  return (n / NANOS_PER_IOTA).toLocaleString(undefined, {
    maximumFractionDigits: 2,
  });
}

function shortAddr(addr: string): string {
  return addr.slice(0, 8) + "..." + addr.slice(-6);
}

function explorerObjectUrl(id: string, network: string): string {
  return `https://explorer.iota.org/object/${id}?network=${network}`;
}

function explorerAddrUrl(addr: string, network: string): string {
  return `https://explorer.iota.org/address/${addr}?network=${network}`;
}

function ExplorerObjectLink({
  id,
  network,
  short,
}: {
  id: string;
  network: string;
  short?: boolean;
}) {
  return (
    <a
      className="explorer-link"
      href={explorerObjectUrl(id, network)}
      target="_blank"
      rel="noreferrer"
      title={id}
    >
      {short ? shortAddr(id) : id}
    </a>
  );
}

function ExplorerAddrLink({
  addr,
  network,
  label,
}: {
  addr: string;
  network: string;
  label?: string;
}) {
  return (
    <a
      className="explorer-link"
      href={explorerAddrUrl(addr, network)}
      target="_blank"
      rel="noreferrer"
      title={addr}
    >
      {label ?? shortAddr(addr)}
    </a>
  );
}

interface Props {
  pool: PoolData;
  packageId: string;
  network: string;
  validator: ValidatorSummary | undefined;
  account: ReturnType<typeof useCurrentAccount>;
  stakedObjects: StakedIotaInfo[];
  onChanged: () => void;
}

export function PoolCard({
  pool,
  packageId,
  network,
  validator,
  account,
  stakedObjects,
  onChanged,
}: Props) {
  const { fields } = pool;
  const totalPrincipal = Number(fields.total_principal);
  const thresholdNanos = THRESHOLD * NANOS_PER_IOTA;
  const progress = Math.min(100, (totalPrincipal / thresholdNanos) * 100);
  const isReady = totalPrincipal >= thresholdNanos;
  const isCreator = account?.address === fields.creator;

  const myDeposits = fields.deposits.filter(
    (d) => d.depositor === account?.address,
  );
  const myTotal = myDeposits.reduce(
    (sum, d) => sum + Number(d.principal_amount),
    0,
  );

  const [selectedStake, setSelectedStake] = useState("");
  const [error, setError] = useState("");
  const { mutate: signAndExecute, isPending } =
    useSignAndExecuteTransaction();

  const exec = (buildTx: (tx: Transaction) => void) => {
    setError("");
    const tx = new Transaction();
    buildTx(tx);
    signAndExecute(
      { transaction: tx },
      { onSuccess: onChanged, onError: (e) => setError(e.message) },
    );
  };

  const deposit = () => {
    if (!selectedStake) return;
    exec((tx) => {
      tx.moveCall({
        target: `${packageId}::candidate_stake::deposit`,
        arguments: [tx.object(pool.objectId), tx.object(selectedStake)],
      });
    });
    setSelectedStake("");
  };

  const withdraw = () =>
    exec((tx) => {
      tx.moveCall({
        target: `${packageId}::candidate_stake::withdraw`,
        arguments: [tx.object(pool.objectId)],
      });
    });

  const execute = () =>
    exec((tx) => {
      tx.moveCall({
        target: `${packageId}::candidate_stake::execute`,
        arguments: [tx.object(pool.objectId), tx.object("0x5")],
      });
    });

  const cancel = () =>
    exec((tx) => {
      tx.moveCall({
        target: `${packageId}::candidate_stake::cancel`,
        arguments: [tx.object(pool.objectId)],
      });
    });

  const destroyEmpty = () =>
    exec((tx) => {
      tx.moveCall({
        target: `${packageId}::candidate_stake::destroy_empty`,
        arguments: [tx.object(pool.objectId)],
      });
    });

  return (
    <div className="pool-card">
      <div className="pool-header">
        <div className="pool-id">
          <ExplorerObjectLink id={pool.objectId} network={network} />
        </div>
        <span className={`badge ${isReady ? "ready" : "pending"}`}>
          {isReady ? "Ready" : `${progress.toFixed(1)}%`}
        </span>
      </div>

      <div className="progress-bar">
        <div
          className={`fill ${isReady ? "complete" : ""}`}
          style={{ width: `${progress}%` }}
        />
      </div>

      <div className="pool-details">
        <div className="detail-row">
          <span className="detail-label">Total staked</span>
          <span className="detail-value">
            {formatIota(fields.total_principal)} / {THRESHOLD.toLocaleString()} IOTA
          </span>
        </div>
        <div className="detail-row">
          <span className="detail-label">Deposits</span>
          <span className="detail-value">{fields.deposits.length}</span>
        </div>
        <div className="detail-row">
          <span className="detail-label">Creator</span>
          <span className="detail-value">
            <ExplorerAddrLink addr={fields.creator} network={network} />
            {isCreator && <span className="you-badge">you</span>}
          </span>
        </div>
      </div>

      <div className="validator-section">
        <div className="detail-label" style={{ marginBottom: "0.35rem" }}>
          Target validator
        </div>
        <div className="validator-card">
          <div className="validator-header">
            <strong>{validator?.name ?? "Unknown"}</strong>
            <ExplorerAddrLink addr={fields.target_validator} network={network} />
          </div>
          {validator && (
            <div className="validator-meta">
              {validator.description && (
                <div className="validator-desc">{validator.description}</div>
              )}
              <div className="validator-stats">
                <span>
                  Commission <strong>{Number(validator.commissionRate) / 100}%</strong>
                </span>
                <span>
                  Pool balance <strong>{formatIota(validator.stakingPoolIotaBalance)} IOTA</strong>
                </span>
                {validator.projectUrl && (
                  <a
                    href={validator.projectUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="explorer-link"
                  >
                    Website
                  </a>
                )}
              </div>
            </div>
          )}
        </div>
      </div>

      {account && (
        <>
          {myDeposits.length > 0 && (
            <div className="my-deposits">
              Your deposits: <strong>{formatIota(myTotal)} IOTA</strong> (
              {myDeposits.length} deposit
              {myDeposits.length > 1 ? "s" : ""})
            </div>
          )}

          <div className="card-actions">
            <div className="action-row">
              {stakedObjects.length > 0 ? (
                <>
                  <select
                    value={selectedStake}
                    onChange={(e) => setSelectedStake(e.target.value)}
                  >
                    <option value="">Select StakedIota to deposit...</option>
                    {stakedObjects.map((s) => (
                      <option key={s.objectId} value={s.objectId}>
                        {shortAddr(s.objectId)} — {formatIota(s.principal)} IOTA
                      </option>
                    ))}
                  </select>
                  <button
                    onClick={deposit}
                    disabled={!selectedStake || isPending}
                    title="Add your StakedIota to this pool"
                  >
                    Deposit
                  </button>
                </>
              ) : (
                <span className="action-hint">
                  No StakedIota in wallet — stake IOTA to a validator first
                </span>
              )}
              {myDeposits.length > 0 && (
                <button
                  className="secondary"
                  onClick={withdraw}
                  disabled={isPending}
                  title="Returns all your deposited StakedIota back to your wallet"
                >
                  Withdraw All ({formatIota(myTotal)} IOTA)
                </button>
              )}
            </div>

            <div className="action-row">
              <button
                onClick={execute}
                disabled={!isReady || isPending}
                title={
                  isReady
                    ? "Unstake all deposits and restake to the target validator. Each depositor gets their new StakedIota back."
                    : `${formatIota(thresholdNanos - totalPrincipal)} IOTA still needed to reach threshold`
                }
              >
                {isReady
                  ? "Restake to Target Validator"
                  : `Restake (${formatIota(thresholdNanos - totalPrincipal)} IOTA remaining)`}
              </button>

              <button
                className="danger"
                onClick={cancel}
                disabled={!isCreator || isPending}
                title={
                  isCreator
                    ? "Return all deposits to their owners and destroy this pool"
                    : "Only the pool creator can cancel"
                }
              >
                Cancel Pool
              </button>

              {fields.deposits.length === 0 && (
                <button
                  className="secondary"
                  onClick={destroyEmpty}
                  disabled={isPending}
                  title="Clean up this empty pool object"
                >
                  Destroy Empty
                </button>
              )}
            </div>
          </div>
        </>
      )}

      {error && <p className="error">{error}</p>}
    </div>
  );
}

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ConnectButton,
  useCurrentAccount,
  useIotaClientContext,
} from "@iota/dapp-kit";
import { NETWORKS } from "./networkConfig";
import { usePools } from "./hooks/usePools";
import { PoolList } from "./components/PoolList";
import { CreatePool } from "./components/CreatePool";
import contractSource from "../../sources/candidate_stake.move?raw";

const GITHUB_REPO = "https://github.com/Thoralf-M/candidate-stake";
const GITHUB_CONTRACT = `${GITHUB_REPO}/blob/main/sources/candidate_stake.move`;

function explorerPackageUrl(packageId: string, network: string): string {
  return `https://explorer.iota.org/object/${packageId}?network=${network}`;
}

type NetworkKey = keyof typeof NETWORKS;

export function App() {
  const account = useCurrentAccount();
  const ctx = useIotaClientContext();
  const network = ctx.network as NetworkKey;
  const defaultPkg = NETWORKS[network]?.packageId ?? "";
  const graphqlUrl = NETWORKS[network]?.graphql ?? "";
  const [customPkg, setCustomPkg] = useState(
    () => localStorage.getItem(`customPkg:${network}`) ?? "",
  );
  const [useCustom, setUseCustom] = useState(
    () => localStorage.getItem(`useCustom:${network}`) === "true",
  );
  // Restore per-network custom state when switching networks
  useEffect(() => {
    setCustomPkg(localStorage.getItem(`customPkg:${network}`) ?? "");
    setUseCustom(localStorage.getItem(`useCustom:${network}`) === "true");
  }, [network]);

  const packageId = useCustom || !defaultPkg ? customPkg : defaultPkg;
  const [refreshKey, setRefreshKey] = useState(0);
  const refresh = () => setRefreshKey((k) => k + 1);
  const [lightbox, setLightbox] = useState(false);
  const closeLightbox = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setLightbox(false);
  }, []);

  const { data: pools } = usePools(packageId, graphqlUrl, refreshKey);

  const existingTargets = useMemo(
    () => new Set(pools?.map((p) => p.fields.target_validator) ?? []),
    [pools],
  );

  return (
    <div className="app">
      <header>
        <h1>CandidateStake</h1>
        <div className="header-controls">
          <select
            value={network}
            onChange={(e) => ctx.selectNetwork(e.target.value)}
          >
            {Object.keys(NETWORKS).map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
          {defaultPkg && (
            <label className="custom-toggle">
              <input
                type="checkbox"
                checked={useCustom}
                onChange={(e) => {
                  setUseCustom(e.target.checked);
                  localStorage.setItem(`useCustom:${network}`, String(e.target.checked));
                }}
              />{" "}
              Custom package ID
            </label>
          )}
          <ConnectButton />
        </div>
      </header>

      {(useCustom || !defaultPkg) && (
        <div className="custom-bar">
          <input
            type="text"
            placeholder="Package ID (0x...)"
            value={customPkg}
            onChange={(e) => {
              setCustomPkg(e.target.value);
              localStorage.setItem(`customPkg:${network}`, e.target.value);
            }}
          />
        </div>
      )}

      <div className="intro">
        <p>
          Pool your staked IOTA to help a candidate validator reach the
          2,000,000 IOTA minimum required to join the active validator set.
          Deposit your existing <code>StakedIota</code> objects into a pool —
          you stay in full control and can withdraw at any time.
          Once the threshold is reached, the pool creator can trigger the restaking
          — all deposits are unstaked and restaked to the target validator,
          with each depositor receiving their new <code>StakedIota</code> back
          (including any accrued rewards). Since deposits stay staked to their
          original validator until execution, you only miss out on a single
          epoch of staking rewards during the restaking transition — assuming
          the target validator successfully joins the committee (the committee
          size is limited, so a slot must be available).
          Only the pool creator can trigger execution, so they can sync it
          with the target validator
          calling <code>0x3::iota_system::request_add_validator</code> in the same epoch.
          If this is not called in the same epoch as the restaking,
          an additional epoch of rewards is lost. Depositors should not unstake
          before the validator has joined, as this could cause the join to fail.
        </p>
        <picture onClick={() => setLightbox(true)}>
          <source media="(max-width: 768px)" srcSet="./flow-mobile.svg" />
          <img className="flow-diagram" src="./flow.svg" alt="CandidateStake flow diagram" />
        </picture>
        {lightbox && (
          <div className="lightbox" onClick={closeLightbox}>
            <img
              src={window.innerWidth <= 768 ? "./flow-mobile.svg" : "./flow.svg"}
              alt="CandidateStake flow diagram"
            />
          </div>
        )}
      </div>

      {packageId && (
        <>
          <CreatePool
            packageId={packageId}
            network={network}
            account={account}
            existingTargets={existingTargets}
            onCreated={refresh}
          />
          <PoolList
            pools={pools ?? []}
            account={account}
            packageId={packageId}
            network={network}
            onChanged={refresh}
          />
        </>
      )}

      {!packageId && (
        <p className="empty">Enter a package ID above to get started.</p>
      )}

      <div className="links-bar">
        <a href={GITHUB_REPO} target="_blank" rel="noreferrer">GitHub</a>
        {packageId && (
          <a href={explorerPackageUrl(packageId, network)} target="_blank" rel="noreferrer">
            Package on Explorer: {packageId.slice(0, 8)}...{packageId.slice(-6)}
          </a>
        )}
      </div>

      <details className="faq">
        <summary>FAQ</summary>
        <dl>
          <dt>What do I need to deposit?</dt>
          <dd>
            You need existing <code>StakedIota</code> objects in your wallet. These are
            obtained by staking IOTA to any validator. You deposit these objects into a
            pool — they stay staked to their original validator until the pool executes.
            You remain in full control of your deposit at all times and can withdraw it
            back to your wallet whenever you want.
          </dd>

          <dt>Can I withdraw my deposit?</dt>
          <dd>
            Yes, at any time before the pool is executed. Your{" "}
            <code>StakedIota</code> objects are returned directly to your wallet — no
            approval needed from anyone. Withdrawal is all-or-nothing: all your deposits
            in that pool are returned at once.
          </dd>

          <dt>What happens when the threshold is reached?</dt>
          <dd>
            Once total deposits reach 2,000,000 IOTA, the pool creator can trigger the
            restaking. Only the creator can execute, so they can coordinate the timing
            with the target validator. All deposits are unstaked from their original
            validators and restaked to the target candidate validator. Each depositor
            receives their new <code>StakedIota</code> back (including any accrued
            rewards). The pool is then destroyed.
          </dd>

          <dt>How much staking reward do I miss?</dt>
          <dd>
            Your deposits remain staked to their original validator until execution, so
            you keep earning rewards the whole time. During the restaking transition you
            miss one epoch of rewards. Only the pool creator can trigger execution,
            so they can sync it with the target validator
            calling <code>0x3::iota_system::request_add_validator</code> in the same epoch.
            If this is not called in the same epoch as the restaking, an additional epoch
            of rewards is lost. If any depositor unstakes before the validator has joined,
            the validator may fail to join entirely.
          </dd>

          <dt>What happens if the pool is full (1,000 deposits)?</dt>
          <dd>
            A pool holds up to 1,000 deposits. If the pool is full, you can still deposit
            — but only if your deposit is strictly larger than the current smallest deposit.
            The smallest deposit gets evicted and returned to its original depositor.
          </dd>

          <dt>Who can cancel a pool?</dt>
          <dd>
            Only the pool creator can cancel. Cancelling returns all deposits to their
            original depositors and destroys the pool. This can be done at any time before
            execution, regardless of the current pool balance.
          </dd>

          <dt>What does "Destroy Empty" do?</dt>
          <dd>
            It cleans up a pool object that has no deposits left (e.g. after everyone has
            withdrawn). It does not move any funds — it simply deletes the empty on-chain
            object.
          </dd>

          <dt>Is the contract permissionless?</dt>
          <dd>
            Anyone can create a pool, deposit, and withdraw their own deposits at any time.
            Execution and cancellation are restricted to the pool creator, so the creator
            can coordinate the restaking timing with the target validator.
          </dd>
        </dl>
      </details>

      <details className="contract-source">
        <summary>Smart Contract Source</summary>
        <div className="contract-header">
          <a href={GITHUB_CONTRACT} target="_blank" rel="noreferrer">
            sources/candidate_stake.move
          </a>
          {packageId && (
            <a href={explorerPackageUrl(packageId, network)} target="_blank" rel="noreferrer">
              View package on IOTA Explorer
            </a>
          )}
        </div>
        <pre><code>{contractSource}</code></pre>
      </details>
    </div>
  );
}

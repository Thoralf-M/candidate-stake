import { useCallback, useMemo, useState } from "react";
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
  const [customPkg, setCustomPkg] = useState("");
  const [customGraphql, setCustomGraphql] = useState("");
  const [useCustom, setUseCustom] = useState(false);
  const packageId = useCustom ? customPkg : defaultPkg;
  const gqlUrl = useCustom ? customGraphql : graphqlUrl;
  const [refreshKey, setRefreshKey] = useState(0);
  const refresh = () => setRefreshKey((k) => k + 1);
  const [lightbox, setLightbox] = useState(false);
  const closeLightbox = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setLightbox(false);
  }, []);

  const { data: pools } = usePools(packageId, gqlUrl, refreshKey);

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
                onChange={(e) => setUseCustom(e.target.checked)}
              />{" "}
              Custom
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
            onChange={(e) => setCustomPkg(e.target.value)}
          />
          <input
            type="text"
            placeholder="GraphQL URL"
            value={customGraphql}
            onChange={(e) => setCustomGraphql(e.target.value)}
          />
        </div>
      )}

      <div className="intro">
        <p>
          Pool your staked IOTA to help a candidate validator reach the
          2,000,000 IOTA minimum required to join the active validator set.
          Deposit your existing <code>StakedIota</code> objects into a pool.
          Once the threshold is reached, anyone can trigger the restaking
          — all deposits are unstaked and restaked to the target validator,
          with each depositor receiving their new <code>StakedIota</code> back
          (including any accrued rewards). Since deposits stay staked to their
          original validator until execution, you only miss out on a single
          epoch of staking rewards during the restaking transition — assuming
          the target validator joins the committee and starts earning rewards
          the following epoch.
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

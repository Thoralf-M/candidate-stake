import { createNetworkConfig } from "@iota/dapp-kit";

export const NETWORKS = {
  devnet: {
    url: "https://api.devnet.iota.cafe",
    graphql: "https://graphql.devnet.iota.cafe",
    packageId:
      "0x5b8e73954c18a0d743e967de27e588ddcae6b7d060098e7a2e55c5d269cf76c1",
  },
  testnet: {
    url: "https://api.testnet.iota.cafe",
    graphql: "https://graphql.testnet.iota.cafe",
    packageId: "",
  },
  mainnet: {
    url: "https://api.mainnet.iota.cafe",
    graphql: "https://graphql.mainnet.iota.cafe",
    packageId: "",
  },
  localnet: {
    url: "http://127.0.0.1:9000",
    graphql: "http://127.0.0.1:9125",
    packageId: "",
  },
} as const;

const { networkConfig } = createNetworkConfig({
  devnet: { url: NETWORKS.devnet.url },
  testnet: { url: NETWORKS.testnet.url },
  mainnet: { url: NETWORKS.mainnet.url },
  localnet: { url: NETWORKS.localnet.url },
});

export { networkConfig };

import { useQuery } from "@tanstack/react-query";
import { useIotaClient } from "@iota/dapp-kit";

export interface DepositFields {
  depositor: string;
  principal_amount: string;
}

export interface PoolFields {
  creator: string;
  target_validator: string;
  deposits: DepositFields[];
  total_principal: string;
  max_deposits: string;
}

export interface PoolData {
  objectId: string;
  fields: PoolFields;
}

const POOL_QUERY = `
  query ($type: String!, $after: String) {
    objects(filter: { type: $type }, first: 50, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes {
        address
        asMoveObject {
          contents { json }
        }
      }
    }
  }
`;

interface GqlNode {
  address: string;
  asMoveObject?: {
    contents?: {
      json?: Record<string, unknown>;
    };
  };
}

interface GqlResponse {
  data?: {
    objects?: {
      pageInfo: { hasNextPage: boolean; endCursor: string | null };
      nodes: GqlNode[];
    };
  };
  errors?: { message: string }[];
}

async function fetchPools(
  graphqlUrl: string,
  packageId: string,
): Promise<PoolData[]> {
  const type = `${packageId}::candidate_stake::CandidateStake`;
  const result: PoolData[] = [];
  let after: string | null = null;
  let hasNext = true;

  while (hasNext) {
    const resp = await fetch(graphqlUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        query: POOL_QUERY,
        variables: { type, after },
      }),
    });
    const json = (await resp.json()) as GqlResponse;
    if (json.errors?.length) throw new Error(json.errors[0]!.message);
    const objects = json.data?.objects;
    if (!objects) break;

    for (const node of objects.nodes) {
      const fields = node.asMoveObject?.contents?.json;
      if (!fields) continue;
      result.push({
        objectId: node.address,
        fields: parseFields(fields),
      });
    }

    hasNext = objects.pageInfo.hasNextPage;
    after = objects.pageInfo.endCursor;
  }
  return result;
}

function parseFields(json: Record<string, unknown>): PoolFields {
  const deposits = (json["deposits"] as Array<Record<string, unknown>> | undefined) ?? [];
  return {
    creator: String(json["creator"] ?? ""),
    target_validator: String(json["target_validator"] ?? ""),
    total_principal: String(json["total_principal"] ?? "0"),
    max_deposits: String(json["max_deposits"] ?? "1000"),
    deposits: deposits.map((d) => ({
      depositor: String(d["depositor"] ?? ""),
      principal_amount: String(d["principal_amount"] ?? "0"),
    })),
  };
}

export function usePools(packageId: string, graphqlUrl: string, refreshKey?: number) {
  const client = useIotaClient();
  return useQuery({
    queryKey: ["pools", packageId, graphqlUrl, refreshKey],
    queryFn: async () => {
      if (graphqlUrl) {
        return fetchPools(graphqlUrl, packageId);
      }
      // Fallback: no GraphQL URL, try to find pools via events
      const events = await client.queryEvents({
        query: { MoveEventModule: { package: packageId, module: "candidate_stake" } },
        limit: 50,
      });
      const objectIds = new Set<string>();
      for (const ev of events.data) {
        const parsed = ev.parsedJson as Record<string, string> | undefined;
        if (parsed?.["pool_id"]) objectIds.add(parsed["pool_id"]);
      }
      if (objectIds.size === 0) return [];
      const objects = await client.multiGetObjects({
        ids: [...objectIds],
        options: { showContent: true },
      });
      const result: PoolData[] = [];
      for (const obj of objects) {
        const content = obj.data?.content;
        if (!content || content.dataType !== "moveObject") continue;
        result.push({
          objectId: obj.data!.objectId,
          fields: content.fields as unknown as PoolFields,
        });
      }
      return result;
    },
    enabled: !!packageId,
    refetchInterval: 15_000,
  });
}

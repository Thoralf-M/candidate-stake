import { useQuery } from "@tanstack/react-query";
import { useIotaClient } from "@iota/dapp-kit";
import type { IotaClient } from "@iota/iota-sdk/client";

export interface CandidateValidator {
  iotaAddress: string;
  name: string;
  description: string;
  imageUrl: string;
  projectUrl: string;
  stakingPoolIotaBalance: string;
  commissionRate: string;
}

/**
 * Candidate validators are stored as:
 *   Table<address, ValidatorWrapper>
 *     ValidatorWrapper { inner: Versioned }
 *       Versioned stores the actual ValidatorV1 as a dynamic field keyed by version (u64).
 *
 * So fetching one candidate requires:
 *   1. getDynamicFields on the table → entry with name = validator address
 *   2. getDynamicFieldObject on the table → gives ValidatorWrapper with inner.id
 *   3. getDynamicFields on inner.id → entry with name = version (u64 "1")
 *   4. getDynamicFieldObject on inner.id → ValidatorV1 with metadata
 */
async function fetchCandidate(
  client: IotaClient,
  tableId: string,
  name: { type: string; value: unknown },
): Promise<CandidateValidator | null> {
  // Step 1: Get the ValidatorWrapper from the table
  const wrapperObj = await client.getDynamicFieldObject({
    parentObjectId: tableId,
    name,
    options: { showContent: true },
  });
  const wrapperContent = wrapperObj.data?.content;
  if (!wrapperContent || wrapperContent.dataType !== "moveObject") return null;
  const wrapperFields = wrapperContent.fields as Record<string, unknown>;

  // Step 2: Navigate to inner Versioned object ID
  const value = wrapperFields["value"] as Record<string, unknown> | undefined;
  const inner = (value?.["fields"] as Record<string, unknown>)?.["inner"] ??
    value?.["inner"];
  const innerFields = (inner as Record<string, unknown>)?.["fields"] ??
    inner;
  const innerId = ((innerFields as Record<string, unknown>)?.["id"] as Record<string, unknown>)?.["id"];
  if (typeof innerId !== "string") return null;

  // Step 3: Get the version key from the Versioned dynamic fields
  const versionedFields = await client.getDynamicFields({
    parentId: innerId,
  });
  if (!versionedFields.data.length) return null;
  const versionEntry = versionedFields.data[0]!;

  // Step 4: Fetch the actual ValidatorV1
  const validatorObj = await client.getDynamicFieldObject({
    parentObjectId: innerId,
    name: versionEntry.name,
    options: { showContent: true },
  });
  const validatorContent = validatorObj.data?.content;
  if (!validatorContent || validatorContent.dataType !== "moveObject") return null;
  const vFields = validatorContent.fields as Record<string, unknown>;

  // The ValidatorV1 is inside value.fields
  const v1 = (vFields["value"] as Record<string, unknown>)?.["fields"] as
    | Record<string, unknown>
    | undefined;
  if (!v1) return null;

  const meta = ((v1["metadata"] as Record<string, unknown>)?.["fields"] ??
    v1["metadata"]) as Record<string, unknown> | undefined;
  if (!meta) return null;

  return {
    iotaAddress: String(meta["iota_address"] ?? String(name.value)),
    name: String(meta["name"] ?? "Unknown"),
    description: String(meta["description"] ?? ""),
    imageUrl: String(meta["image_url"] ?? ""),
    projectUrl: String(meta["project_url"] ?? ""),
    stakingPoolIotaBalance: String(
      ((v1["staking_pool"] as Record<string, unknown>)?.["fields"] as Record<string, unknown>)?.["iota_balance"] ??
        "0",
    ),
    commissionRate: String(v1["commission_rate"] ?? "0"),
  };
}

export function useCandidateValidators() {
  const client = useIotaClient();
  return useQuery({
    queryKey: ["candidate-validators"],
    queryFn: async () => {
      const state = await client.getLatestIotaSystemState();
      const tableId = state.validatorCandidatesId;
      const size = Number(state.validatorCandidatesSize);
      if (size === 0) return [];

      const candidates: CandidateValidator[] = [];
      let cursor: string | null | undefined = null;
      let hasNext = true;

      while (hasNext) {
        const page = await client.getDynamicFields({
          parentId: tableId,
          cursor: cursor ?? undefined,
        });

        for (const field of page.data) {
          try {
            const candidate = await fetchCandidate(client, tableId, field.name);
            if (candidate) candidates.push(candidate);
          } catch {
            continue;
          }
        }

        cursor = page.nextCursor;
        hasNext = page.hasNextPage;
      }

      return candidates;
    },
    staleTime: 60_000,
  });
}

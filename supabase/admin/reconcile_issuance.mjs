// Explicit local operator tool. Keys stay in memory; output contains only counts.
import { api, localStatus } from "../scripts/local_supabase.mjs";
import { pathToFileURL } from "node:url";

export async function reconcile(local, operation, options = {}) {
  if (!/^http:\/\/(127\.0\.0\.1|localhost):54321$/.test(local.API_URL)) {
    throw new Error("Reconciliation requires local Supabase");
  }
  if (operation && !/^[0-9a-f-]{36}$/.test(operation)) {
    throw new Error("Invalid operation UUID");
  }
  const counts = { cleaned: 0, protected: 0, busy: 0, pending: 0 };
  async function rpc(args) {
    const r = await api(
      local,
      "/rest/v1/rpc/advance_certificate_issuance",
      local.SERVICE_ROLE_KEY,
      "POST",
      JSON.stringify(args),
      { "Content-Type": "application/json" },
    );
    if (!r.ok) throw new Error("Reconciliation transaction failed");
    return r.json();
  }
  // Stable IDs; operations are retained, never deleted. Pages include failed
  // tombstones, catching objects from uploads that arrived after an earlier delete.
  for (let offset = 0;; offset += 100) {
    const query = operation ? `id=eq.${operation}` : "status=neq.completed";
    const r = await api(
      local,
      `/rest/v1/certificate_issuance_operations?${query}&select=id,institution_id&order=id&limit=100&offset=${offset}`,
      local.SERVICE_ROLE_KEY,
    );
    if (!r.ok) throw new Error("Cannot read local reconciliation queue");
    const operations = await r.json();
    for (const op of operations) {
      const base = {
        p_institution: op.institution_id,
        p_operation: op.id,
        p_lease: null,
      };
      const claim = await rpc({ ...base, p_action: "cleanup_claim" });
      if (claim.status === "protected") {
        counts.protected++;
        continue;
      }
      if (claim.status === "in_progress") {
        counts.busy++;
        continue;
      }
      const owned = { ...base, p_lease: claim.lease_token };
      // Recheck DB immediately before touching Storage. Terminal cleanup states
      // forbid publication even after this transaction ends or its lease expires.
      const check = await rpc({ ...owned, p_action: "cleanup_check" });
      if (check.status !== "cleanup_pending") {
        counts.protected++;
        continue;
      }
      const path = `${op.institution_id}/${claim.target_certificate_id}.pdf`;
      try {
        if (options.failDelete) {
          throw new Error("Injected local delete failure");
        }
        const deletion = await api(
          local,
          "/storage/v1/object/certificates",
          local.SERVICE_ROLE_KEY,
          "DELETE",
          JSON.stringify({ prefixes: [path] }),
          { "Content-Type": "application/json" },
        );
        if (!deletion.ok) throw new Error("Storage cleanup failed");
        const absent = await api(
          local,
          `/storage/v1/object/authenticated/certificates/${path}`,
          local.SERVICE_ROLE_KEY,
        );
        const absentBody = await absent.json().catch(() => ({}));
        // Storage may report a missing object as HTTP 400 with statusCode 404.
        if (absent.status !== 404 && String(absentBody.statusCode) !== "404") {
          throw new Error("Deletion not confirmed");
        }
        await rpc({ ...owned, p_action: "cleanup_done" });
        counts.cleaned++;
      } catch {
        counts.pending++;
      }
    }
    if (operations.length < 100 || operation) break;
  }
  return counts;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  if (process.argv[2] !== "--local") {
    throw new Error(
      "Usage: node supabase/admin/reconcile_issuance.mjs --local [operation UUID]",
    );
  }
  const counts = await reconcile(localStatus(), process.argv[3]);
  console.log(JSON.stringify(counts));
  if (counts.pending) process.exitCode = 1;
}

import { authenticatedActor, Backend } from "./backend.ts";
import {
  fingerprint,
  IssuanceError,
  requestInput,
  sha256,
} from "./contract.ts";
import { validatePdf } from "./pdf.ts";
import { cors } from "../_shared/http.ts";

export interface Config {
  url: string;
  anonKey: string;
  serviceKey: string;
  testFaultToken?: string;
}
export function handler(
  config: Config,
): (request: Request) => Promise<Response> {
  return async (request) => {
    const respond = (body: unknown, status: number) =>
      new Response(JSON.stringify(body), {
        status,
        headers: {
          ...cors,
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
          ...(status === 409 || status === 503 ? { "Retry-After": "120" } : {}),
        },
      });
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      return respond({ error: "method_not_allowed" }, 405);
    }
    const backend = new Backend(config.url, config.serviceKey);
    let lease: Record<string, unknown> | undefined;
    let institution: string | undefined;
    const fault = (stage: string) => {
      if (
        config.testFaultToken &&
        request.headers.get("x-local-fault-token") === config.testFaultToken &&
        request.headers.get("x-local-fault") === stage
      ) {
        // Only wired by index.ts in a local CLI runtime with an explicit test token.
        throw new IssuanceError("temporary_failure", 503);
      }
    };
    const advance = (action: string, extra: Record<string, unknown> = {}) =>
      backend.rpc("advance_certificate_issuance", {
        p_institution: institution,
        p_operation: lease!.operation_id,
        p_lease: lease!.lease_token,
        p_action: action,
        ...extra,
      });
    try {
      const actor = await authenticatedActor(
        request,
        config.url,
        config.anonKey,
      );
      const { input, pdf } = await requestInput(request);
      await validatePdf(pdf);
      const pdfHash = await sha256(pdf);
      institution = input.institution_id;
      lease = await backend.rpc("reserve_certificate_issuance", {
        p_institution: institution,
        p_actor: actor,
        p_holder: input.holder_id,
        p_key: input.idempotency_key,
        p_title: input.title,
        p_description: input.description,
        p_expires: input.expires_at,
        p_pdf_hash: pdfHash,
        p_fingerprint: await fingerprint(input, actor, pdfHash),
      });
      if (lease.status === "completed") {
        return respond({
          status: "completed",
          certificate_id: lease.certificate_id,
        }, 200);
      }
      if (lease.status !== "uploading") {
        return respond({
          error: lease.status === "in_progress"
            ? "operation_in_progress"
            : "attempt_failed",
          status: lease.status,
        }, 409);
      }
      await fault("after_reserve");
      const path = `${institution}/${lease.target_certificate_id}.pdf`;
      // A lost upload response is resolved by reading the immutable reserved path.
      try {
        await backend.upload(path, pdf);
      } catch (error) {
        if (
          !(error instanceof IssuanceError) ||
          error.code !== "temporary_failure"
        ) throw error;
      }
      await fault("after_upload");
      const stored = await backend.download(path);
      if (stored.length !== pdf.length || await sha256(stored) !== pdfHash) {
        throw new IssuanceError("stored_object_invalid", 503);
      }
      try {
        await validatePdf(stored);
      } catch {
        throw new IssuanceError("stored_object_invalid", 503);
      }
      await fault("after_read");
      await advance("validate", { p_stored_hash: await sha256(stored) });
      await fault("after_validate");
      await fault("before_publish");
      const result = await advance("publish");
      await fault("after_publish");
      if (result.status !== "completed") {
        throw new IssuanceError("internal_failure", 500);
      }
      return respond({
        status: "completed",
        certificate_id: result.certificate_id,
      }, 201);
    } catch (error) {
      const safe = error instanceof IssuanceError
        ? error
        : new IssuanceError("internal_failure", 500);
      if (
        lease?.status === "uploading" &&
        ["forbidden", "invalid_input", "stored_object_invalid"].includes(
          safe.code,
        )
      ) {
        // If this RPC fails the durable uploading/finalizing row remains available
        // for operator reconciliation. Never delete Storage from this catch.
        try {
          await advance("abandon");
        } catch { /* retain durable recovery state */ }
      }
      // No request/error logging: upstream details can contain private values.
      return respond({ error: safe.code }, safe.status);
    }
  };
}

import { handler } from "../revoke-certificate/handler.ts";
Deno.serve(
  handler({
    url: Deno.env.get("SUPABASE_URL")!,
    anonKey: Deno.env.get("SUPABASE_ANON_KEY")!,
    serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  }, "progress"),
);

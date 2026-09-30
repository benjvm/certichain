import { handler } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const localRuntime = !Deno.env.get("DENO_DEPLOYMENT_ID") &&
  /^http:\/\/(kong|127\.0\.0\.1|localhost)(:\d+)?$/.test(url);
Deno.serve(handler({
  url,
  anonKey: Deno.env.get("SUPABASE_ANON_KEY")!,
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  testFaultToken: localRuntime
    ? Deno.env.get("CERTICHAIN_LOCAL_FAULT_TOKEN")
    : undefined,
}));

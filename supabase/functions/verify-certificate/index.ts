import { handler } from "./handler.ts";

Deno.serve(handler({
  url: Deno.env.get("SUPABASE_URL")!,
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
}));

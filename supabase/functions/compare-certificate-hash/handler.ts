import { publicHandler } from "../_shared/public_handler.ts";
export const handler = (config: { url: string; serviceKey: string }) =>
  publicHandler(config, true);

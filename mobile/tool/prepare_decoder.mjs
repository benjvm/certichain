import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Reproducible local assets, no CDN requests from a scanner session.
const here = dirname(fileURLToPath(import.meta.url));
const source = resolve(here, "node_modules/@zxing/library");
const target = resolve(here, "../web/decoder");
const bytes = readFileSync(resolve(source, "umd/index.min.js"));
const license = readFileSync(resolve(source, "LICENSE"));
const version =
  JSON.parse(readFileSync(resolve(source, "package.json"))).version;
if (version !== "0.23.0") throw new Error("Unexpected decoder version");
mkdirSync(target, { recursive: true });
// Strip only the optional source-map lookup; decoder behavior is untouched.
const script = bytes.toString().replace(/\/\/# sourceMappingURL=.*$/m, "");
writeFileSync(resolve(target, "zxing-0.23.0.min.js"), script);
writeFileSync(resolve(target, "LICENSE"), license);
writeFileSync(
  resolve(target, "manifest.json"),
  JSON.stringify(
    {
      package: "@zxing/library",
      version,
      sha256: createHash("sha256").update(script).digest("hex"),
      source: "npm lockfile; UMD; Apache-2.0; no external runtime imports",
    },
    null,
    2,
  ) + "\n",
);
console.log("Prepared pinned local QR decoder and license");

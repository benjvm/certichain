// Standard library only. Installs verified archives, never nested Git repositories.
import assert from "node:assert/strict";
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { basename, join, resolve } from "node:path";
import { lock, root, run, sha256, suffix, verifyVersions } from "./common.mjs";

const platform = `${process.platform}-${process.arch}`;
assert(
  lock.foundry.platforms[platform],
  `Unsupported platform: ${platform}; use documented Linux x64 environment`,
);
const downloadDir = resolve(root, ".tools/downloads");
mkdirSync(downloadDir, { recursive: true });
mkdirSync(resolve(root, ".tools/bin"), { recursive: true });
mkdirSync(resolve(root, "lib"), { recursive: true });
async function fetchChecked(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(120_000) });
  assert(response.ok, `Download failed: ${response.status} ${url}`);
  return Buffer.from(await response.arrayBuffer());
}
async function download(entry) {
  const destination = join(downloadDir, basename(new URL(entry.url).pathname));
  if (!existsSync(destination)) {
    writeFileSync(destination, await fetchChecked(entry.url));
  }
  assert.equal(
    sha256(readFileSync(destination)),
    entry.sha256,
    `Checksum mismatch: ${entry.url}`,
  );
  return destination;
}
function verifyTag(entry) {
  const lines = run("git", [
    "ls-remote",
    entry.repository,
    `refs/tags/${entry.tag}`,
    `refs/tags/${entry.tag}^{}`,
  ]).split("\n");
  const peeled = lines.find((line) => line.trim().endsWith("^{}"));
  const selected = peeled ??
    lines.find((line) => line.includes(`refs/tags/${entry.tag}`));
  assert(selected, `Missing tag: ${entry.tag}`);
  assert.equal(
    selected.split(/\s+/)[0],
    entry.commit,
    `Tag commit changed: ${entry.tag}`,
  );
}
function tree(directory) {
  const entries = [];
  function walk(path, relative = "") {
    for (
      const item of readdirSync(path, { withFileTypes: true }).sort((a, b) =>
        a.name.localeCompare(b.name, "en")
      )
    ) {
      const key = relative + item.name;
      assert(!item.isSymbolicLink(), `Unexpected symlink: ${key}`);
      if (item.isDirectory()) walk(join(path, item.name), key + "/");
      else entries.push([key, sha256(readFileSync(join(path, item.name)))]);
    }
  }
  walk(directory);
  return entries;
}
function removeOwnedTemporary(directory) {
  const absolute = resolve(directory);
  assert(
    absolute.startsWith(
      resolve(root, ".tools") + (process.platform === "win32" ? "\\" : "/"),
    ),
  );
  assert(/^(foundry|dependency)-/.test(basename(absolute)));
  if (existsSync(absolute)) rmSync(absolute, { recursive: true });
}
for (const entry of [lock.foundry, lock.solidity, ...lock.dependencies]) {
  verifyTag(entry);
}
const foundry = lock.foundry.platforms[platform];
const official =
  (await fetchChecked(foundry.checksumUrl)).toString("utf8").split(/\s+/)[0];
assert.equal(
  official,
  foundry.sha256,
  "Official Foundry checksum differs from lock",
);
const solidity = lock.solidity.platforms[platform];
const release = JSON.parse(
  (await fetchChecked(lock.solidity.checksumSource)).toString("utf8"),
);
const asset = release.assets.find((a) =>
  a.browser_download_url === solidity.url
);
assert.equal(
  asset?.digest,
  `sha256:${solidity.sha256}`,
  "Official solc checksum differs from lock",
);
const archive = await download(foundry);
const extracted = mkdtempSync(resolve(root, ".tools/foundry-"));
try {
  run("tar", ["-xf", archive, "-C", extracted]);
  for (const name of ["forge", "cast", "anvil"]) {
    const source = join(extracted, name + suffix);
    const destination = resolve(root, ".tools/bin", name + suffix);
    if (existsSync(destination)) {
      assert.equal(
        sha256(readFileSync(destination)),
        sha256(readFileSync(source)),
        `Installed ${name} modified`,
      );
    } else copyFileSync(source, destination);
    chmodSync(destination, 0o755);
  }
} finally {
  removeOwnedTemporary(extracted);
}
const compiler = await download(solidity);
const compilerTarget = resolve(root, ".tools/bin", "solc" + suffix);
if (existsSync(compilerTarget)) {
  assert.equal(sha256(readFileSync(compilerTarget)), solidity.sha256);
} else copyFileSync(compiler, compilerTarget);
chmodSync(compilerTarget, 0o755);
for (const entry of lock.dependencies) {
  const file = await download(entry);
  const temporary = mkdtempSync(resolve(root, ".tools/dependency-"));
  try {
    run("tar", ["-xf", file, "--strip-components=1", "-C", temporary]);
    const destination = resolve(root, "lib", entry.name);
    if (existsSync(destination)) {
      assert.deepEqual(
        tree(destination),
        tree(temporary),
        `Dependency modified: ${entry.name}`,
      );
    } else renameSync(temporary, destination);
  } finally {
    removeOwnedTemporary(temporary);
  }
}
verifyVersions();
console.log(
  `Verified Foundry ${lock.foundry.version}, solc ${lock.solidity.version}, OZ 5.7.0, forge-std 1.17.0 (${platform})`,
);

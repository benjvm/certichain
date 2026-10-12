import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { pdfFixture } from "../../supabase/tests/pdf_fixture.mjs";
import { root, sha256 } from "./common.mjs";

const pdf = pdfFixture();
const vector = {
  synthetic: true,
  credential_code: "00112233-4455-6677-8899-aabbccddeeff",
  uuid_bytes: "0x00112233445566778899aabbccddeeff",
  issuer_id:
    "0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
  salt: "0x202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
  document_sha256:
    "0x598c50f845d76f4fe6125df9906750584668e526be96e78ca43548eb60f20b1f",
  certificate_key:
    "0xca2b59a1b252b8233c8966af500b93f84873c2c3ca7642dab5f4470597c49638",
  commitment:
    "0x9b81a31ebdcfdb3b0fa0d60c557485c6b5d55e0e77e7730a2cf202c9a66155f4",
  pdf_bytes: 330,
  key_preimage_bytes: 46,
  commitment_preimage_bytes: 162,
};
const bytes = (value) => Buffer.from(value.slice(2), "hex");
const keyPreimage = Buffer.concat([
  Buffer.from("certichain:certificate-key:v1\0", "utf8"),
  bytes(vector.uuid_bytes),
]);
const commitmentPreimage = Buffer.concat([
  Buffer.from("certichain:document-commitment:v1\0", "utf8"),
  bytes(vector.certificate_key),
  bytes(vector.issuer_id),
  bytes(vector.document_sha256),
  bytes(vector.salt),
]);
assert.equal(pdf.length, vector.pdf_bytes);
assert.equal("0x" + sha256(pdf), vector.document_sha256);
assert.equal(keyPreimage.length, vector.key_preimage_bytes);
assert.equal(commitmentPreimage.length, vector.commitment_preimage_bytes);
assert.equal("0x" + sha256(keyPreimage), vector.certificate_key);
assert.equal("0x" + sha256(commitmentPreimage), vector.commitment);
const directory = resolve(root, "fixtures");
const json = JSON.stringify(vector, null, 2) + "\n";
if (process.argv.includes("--check")) {
  assert.equal(
    readFileSync(resolve(directory, "protocol-v1.json"), "utf8"),
    json,
  );
  assert.deepEqual(readFileSync(resolve(directory, "synthetic.pdf")), pdf);
} else {
  mkdirSync(directory, { recursive: true });
  writeFileSync(resolve(directory, "protocol-v1.json"), json);
  writeFileSync(resolve(directory, "synthetic.pdf"), pdf);
}
console.log(
  "9A synthetic SHA-256 vector verified with Node crypto (H/K/C, binary preimages)",
);

import {
  expiration,
  fingerprint,
  fingerprintBytes,
  IssuanceError,
  MAX_PDF,
  normalize,
  readLimited,
  requestInput,
  sha256,
} from "./contract.ts";
import { validatePdf } from "./pdf.ts";
import { pdfFixture } from "../../tests/pdf_fixture.mjs";
import { PDFDocument } from "pdf-lib";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}
async function rejects(action: () => unknown, code?: string) {
  try {
    await action();
  } catch (error) {
    if (code && (!(error instanceof IssuanceError) || error.code !== code)) {
      throw error;
    }
    return;
  }
  throw new Error("Expected rejection");
}
const values = {
  institution_id: "ABCDEFAB-1234-5678-90AB-ABCDEFABCDEF",
  holder_id: "99999999-AAAA-BBBB-CCCC-DDDDDDDDDDDD",
  idempotency_key: "01234567-89ab-cdef-0123-456789abcdef",
  title: "  Ti\u0301tulo 🎓  ",
  description: " e\u0301 ",
  expires_at: "2030-01-02T03:04:05.123456+01:00",
};
const actor = "11111111-2222-3333-4444-555555555555";
const knownHash =
  "598c50f845d76f4fe6125df9906750584668e526be96e78ca43548eb60f20b1f";

Deno.test("fingerprint v1: exact UTF-8 bytes, order, UUID, NFC, microseconds and known PDF", async () => {
  const input = normalize(values);
  equal(input.title, "Título 🎓");
  equal(input.description, "é");
  equal(input.expires_at, "2030-01-02T02:04:05.123456Z");
  equal(await sha256(pdfFixture()), knownHash);
  equal(
    await fingerprint(input, actor, knownHash),
    "2e6d33776958d6fcb51ec56e238fc347cca05327df127100e2c82925a7d78162",
  );
  const bytes = fingerprintBytes([
    input.institution_id,
    actor,
    input.holder_id,
    input.title,
    input.description,
    input.expires_at,
    knownHash,
  ]);
  equal(
    Array.from(bytes, (x) => x.toString(16).padStart(2, "0")).join(""),
    "6365727469636861696e2d69737375616e63652d7631000000002461626364656661622d313233342d353637382d393061622d6162636465666162636465660000002431313131313131312d323232322d333333332d343434342d3535353535353535353535350000002439393939393939392d616161612d626262622d636363632d6464646464646464646464640000000c54c3ad74756c6f20f09f8e9300000002c3a90000001b323033302d30312d30325430323a30343a30352e3132333435365a0000004035393863353066383435643736663466653631323564663939303637353035383436363865353236626539366537386361343335343865623630663230623166",
  );
});
Deno.test("fingerprint v1: NULL sentinel differs from zero bytes; empty description normalizes to NULL", async () => {
  const input = normalize({ ...values, description: "   " });
  equal(input.description, null);
  equal(
    await fingerprint(input, actor, knownHash),
    "e89ac9981fae04fc2fd3f7dbd6a12773e2e82b95a69aa2b427dce0edbad69d04",
  );
  equal(
    await sha256(
      fingerprintBytes([
        input.institution_id,
        actor,
        input.holder_id,
        input.title,
        "",
        input.expires_at,
        knownHash,
      ]),
    ),
    "6b95264a1c4e673a725a07b0f4edbc0669c07439af6a3d9380edc66d4533b182",
  );
  equal(Array.from(fingerprintBytes([null]).slice(-4)), [255, 255, 255, 255]);
  equal(Array.from(fingerprintBytes([""]).slice(-4)), [0, 0, 0, 0]);
});
Deno.test("calendar validation and UTC normalization preserve fractions", async () => {
  equal(
    expiration("2030-01-01T00:00:00.1+14:00"),
    "2029-12-31T10:00:00.100000Z",
  );
  equal(expiration("2030-01-01T00:00:00-01:30"), "2030-01-01T01:30:00.000000Z");
  equal(expiration(null), null);
  for (
    const value of [
      "2030-02-30T00:00:00Z",
      "2030-01-01",
      "2030-01-01T24:00:00Z",
      "2030-01-01T00:00:00.1234567Z",
      "2030-01-01T00:00:00+14:01",
    ]
  ) await rejects(() => expiration(value), "invalid_input");
});
Deno.test("closed contract, UUID, blank title, controls and length bounds", async () => {
  for (
    const field of [
      "actor_id",
      "issued_by",
      "status",
      "credential_code",
      "id",
      "issued_at",
      "document_path",
      "document_hash",
      "request_fingerprint",
    ]
  ) {
    await rejects(
      () => normalize({ ...values, [field]: "injected" }),
      "invalid_input",
    );
  }
  for (const title of ["", " ", "a\u0000b", "a".repeat(201)]) {
    await rejects(() => normalize({ ...values, title }), "invalid_input");
  }
  await rejects(
    () => normalize({ ...values, holder_id: "invalid" }),
    "invalid_input",
  );
  equal(normalize({ ...values, title: "🎓".repeat(200) }).title.length, 400);
  await rejects(
    () => normalize({ ...values, description: "a".repeat(4001) }),
    "invalid_input",
  );
});
Deno.test("streamed read enforces real size with absent or dishonest Content-Length", async () => {
  for (const length of [undefined, "1", "999999"]) {
    const request = new Request("http://localhost", {
      method: "POST",
      body: new ReadableStream({
        start(c) {
          c.enqueue(new Uint8Array(6));
          c.close();
        },
      }),
      headers: length ? { "Content-Length": length } : {},
    });
    await rejects(() => readLimited(request.body, 5), "payload_too_large");
  }
});
Deno.test("multipart requires one file, exact MIME/extension, no duplicate fields", async () => {
  const form = new FormData();
  for (const [key, value] of Object.entries(values)) form.append(key, value);
  form.append(
    "pdf",
    new Blob([pdfFixture()], { type: "application/pdf" }),
    "a.pdf",
  );
  const request = () =>
    new Request("http://localhost", { method: "POST", body: form });
  equal((await requestInput(request())).pdf.length, 330);
  form.append("title", "duplicate");
  await rejects(() => requestInput(request()), "invalid_input");
});
Deno.test("parser accepts real classic-xref PDF and rejects empty/fake/corrupt/truncated/xref mismatch", async () => {
  const valid = pdfFixture();
  await validatePdf(valid);
  for (
    const bytes of [
      new Uint8Array(),
      new TextEncoder().encode("%PDF-1.4\nnot a document\n%%EOF\n"),
      valid.subarray(0, valid.length - 15),
      new TextEncoder().encode(
        valid.toString().replace("0000000009", "0000000010"),
      ),
      new TextEncoder().encode("text"),
    ]
  ) await rejects(() => validatePdf(bytes), "invalid_pdf");
  for (
    const replacement of [
      valid.toString().replace("endobj", "      "),
      valid.toString().replace("/Root 1 0 R", "/Root 9 0 R"),
    ]
  ) {
    await rejects(
      () => validatePdf(new TextEncoder().encode(replacement)),
      "invalid_pdf",
    );
  }
});
Deno.test("parser rejects encrypted, active and attached documents, including escaped PDF names", async () => {
  for (
    const extra of [
      "/OpenAction << /S /JavaScript /JS (evil) >>",
      "/AA << >>",
      "/A << /S /Rendition >>",
      "/AcroForm << >>",
      "/Open#41ction << >>",
      "/Names << /EmbeddedFiles << >> >>",
      "/XFA (payload)",
    ]
  ) {
    await rejects(
      () => validatePdf(pdfFixture(undefined, extra)),
      "invalid_pdf",
    );
  }
  const encrypted = pdfFixture().toString().replace(
    "/Size 4 /Root 1 0 R",
    "/Size 4 /Root 1 0 R /Encrypt 1 0 R",
  );
  await rejects(
    () => validatePdf(new TextEncoder().encode(encrypted)),
    "invalid_pdf",
  );
  const document = await PDFDocument.create();
  document.addPage();
  await document.attach(new Uint8Array([1]), "file.bin");
  await rejects(
    async () => validatePdf(await document.save({ useObjectStreams: false })),
    "invalid_pdf",
  );
  document.addJavaScript("test", "app.alert('x')");
  await rejects(
    async () => validatePdf(await document.save({ useObjectStreams: false })),
    "invalid_pdf",
  );
});
Deno.test("parser rejects uninspectable codecs/object streams and caps inflated content", async () => {
  const document = await PDFDocument.create();
  document.addPage();
  await rejects(async () => validatePdf(await document.save()), "invalid_pdf");
  // Valid Flate stream from pdf-lib is inspectable and does not transform input.
  document.getPage(0).drawText("Certificate");
  const bytes = await document.save({ useObjectStreams: false });
  await validatePdf(bytes);
  const { PDFName } = await import("pdf-lib");
  document.context.register(
    document.context.flateStream(new Uint8Array(16_777_217)),
  );
  await rejects(
    async () => validatePdf(await document.save({ useObjectStreams: false })),
    "invalid_pdf",
  );
  document.context.register(
    document.context.stream(new Uint8Array([1]), {
      Filter: PDFName.of("Unsupported"),
    }),
  );
  await rejects(
    async () => validatePdf(await document.save({ useObjectStreams: false })),
    "invalid_pdf",
  );
});
Deno.test("8 MiB boundary passes parser without transformation; one excess byte rejected", async () => {
  const bytes = pdfFixture(MAX_PDF), before = await sha256(bytes);
  equal(bytes.length, MAX_PDF);
  await validatePdf(bytes);
  equal(await sha256(bytes), before);
  await rejects(() => validatePdf(pdfFixture(MAX_PDF + 1)), "invalid_pdf");
});

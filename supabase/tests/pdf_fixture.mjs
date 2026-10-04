// Deterministic classic-xref PDF, one page, exact byte offsets, no external data.
import { Buffer } from "node:buffer";
import { deflateSync } from "node:zlib";
export function pdfFixture(size, catalogExtra = "") {
  let body = "%PDF-1.4\n";
  const objects = [
    `<< /Type /Catalog /Pages 2 0 R ${catalogExtra} >>`,
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>",
  ];
  const offsets = [0];
  for (let i = 0; i < objects.length; i++) {
    offsets.push(Buffer.byteLength(body));
    body += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`;
  }
  const tail = (offset) =>
    `xref\n0 4\n0000000000 65535 f \n${
      offsets.slice(1).map((n) => `${String(n).padStart(10, "0")} 00000 n \n`)
        .join("")
    }trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n${offset}\n%%EOF\n`;
  if (size) {
    // Comment padding before xref changes only the xref pointer, never object offsets.
    let padding = size -
      Buffer.byteLength(body + tail(Buffer.byteLength(body)));
    for (let i = 0; i < 5; i++) {
      padding = size -
        Buffer.byteLength(body + tail(Buffer.byteLength(body) + padding));
    }
    if (padding < 2) throw new Error("Fixture size too small");
    body += `%${" ".repeat(padding - 2)}\n`;
  }
  return Buffer.from(body + tail(Buffer.byteLength(body)));
}

export function flatePdfFixture(corrupt = false) {
  const data = deflateSync(Buffer.from("q Q\n"));
  if (corrupt) data[0] = 0;
  let body = "%PDF-1.4\n";
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R >>",
    `<< /Length ${data.length} /Filter /FlateDecode >>\nstream\n${
      data.toString("latin1")
    }\nendstream`,
  ];
  const offsets = [];
  for (let i = 0; i < objects.length; i++) {
    offsets.push(body.length);
    body += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`;
  }
  const start = body.length;
  body += `xref\n0 5\n0000000000 65535 f \n${
    offsets.map((n) => `${String(n).padStart(10, "0")} 00000 n \n`).join("")
  }trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n${start}\n%%EOF\n`;
  return Buffer.from(body, "latin1");
}

// Compatibility/resource corpus: classic xref, actual text/font/page streams,
// Unicode Info string and optional bounded Flate input. No external documents.
export function compatibilityPdf(
  { pages = 1, version = "1.7", inflated } = {},
) {
  const data = inflated == null
    ? Buffer.from("BT /F1 12 Tf 10 50 Td (CertiChain synthetic) Tj ET\n")
    : deflateSync(Buffer.alloc(inflated, 32));
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    `<< /Type /Pages /Count ${pages} /Kids [${
      Array.from({ length: pages }, (_, i) => `${6 + i} 0 R`).join(" ")
    }] >>`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${data.length} ${
      inflated == null ? "" : "/Filter /FlateDecode"
    } >>\nstream\n${data.toString("latin1")}\nendstream`,
    "<< /Title <FEFF0043006500720074006900660069006300610064006F002000E1> /Producer (Synthetic 7D classic writer) >>",
    ...Array.from(
      { length: pages },
      () =>
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /Font << /F1 3 0 R >> >> /Contents 4 0 R >>",
    ),
  ];
  let body = `%PDF-${version}\n%\xE2\xE3\xCF\xD3\n`;
  const offsets = [];
  for (const [i, object] of objects.entries()) {
    offsets.push(body.length);
    body += `${i + 1} 0 obj\n${object}\nendobj\n`;
  }
  const start = body.length;
  body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${
    offsets.map((n) => `${String(n).padStart(10, "0")} 00000 n \n`).join("")
  }trailer\n<< /Size ${
    objects.length + 1
  } /Root 1 0 R /Info 5 0 R >>\nstartxref\n${start}\n%%EOF\n`;
  return Buffer.from(body, "latin1");
}

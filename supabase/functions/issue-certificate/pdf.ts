import {
  PDFArray,
  PDFContext,
  PDFDict,
  PDFDocument,
  PDFInvalidObject,
  PDFName,
  PDFNumber,
  PDFObjectParser,
  PDFRawStream,
  PDFRef,
} from "pdf-lib";
import { IssuanceError, MAX_PDF, readLimited } from "./contract.ts";

// pdf-lib deliberately tolerates missing endobj. Its exported object parser
// exposes the consumed offset through a protected ByteStream; confine that
// version-specific integration here, and regression-test it against the lock.
class StrictObjectParser extends PDFObjectParser {
  static consumed(bytes: Uint8Array, context: PDFContext): number {
    const parser = PDFObjectParser.forBytes(
      bytes,
      context,
    ) as StrictObjectParser;
    parser.parseObject();
    return parser.bytes.offset();
  }
}

// Conservative MVP: single classic xref revision, no object/xref streams.
// pdf-lib is permissive about repaired/truncated documents; enforce envelope,
// xref offsets and stream lengths ourselves, then inspect its parsed graph.
export async function validatePdf(bytes: Uint8Array): Promise<void> {
  try {
    if (!bytes.length || bytes.length > MAX_PDF) throw new Error();
    const source = new TextDecoder("latin1").decode(bytes);
    if (!/^%PDF-1\.[0-7][\r\n]/.test(source)) throw new Error();
    // Reject compressed object streams BEFORE pdf-lib can inflate them. Decode
    // name escapes too; false positives inside streams are deliberately denied.
    let nameCount = 0, objectCount = 0;
    for (
      const match of source.matchAll(/\/(?:[^\s<>\[\]()/%]|#[0-9a-fA-F]{2})+/g)
    ) {
      if (++nameCount > 100_000 || match[0].length > 1024) throw new Error();
      const name = match[0].slice(1).replace(
        /#([0-9a-fA-F]{2})/g,
        (_, hex) => String.fromCharCode(parseInt(hex, 16)),
      );
      if (["ObjStm", "XRef"].includes(name)) throw new Error();
    }
    for (const _ of source.matchAll(/\b\d+\s+\d+\s+obj\b/g)) {
      if (++objectCount > 20_000) throw new Error();
    }
    const end = /startxref\s+(\d+)\s+%%EOF\s*$/.exec(source);
    if (!end) throw new Error();
    const start = Number(end[1]);
    if (start >= bytes.length || source.slice(start, start + 4) !== "xref") {
      throw new Error();
    }
    const xref = source.slice(start, end.index);
    const trailerAt = xref.indexOf("trailer");
    if (trailerAt < 0 || /\/Prev\b|\/XRefStm\b/.test(xref)) throw new Error();
    const lines = xref.slice(4, trailerAt).trim().split(/\r\n|\r|\n/);
    const indexed = new Map<string, number>();
    let entries = 0;
    for (let i = 0; i < lines.length;) {
      const section = /^(\d+)\s+(\d+)\s*$/.exec(lines[i++]);
      if (!section) throw new Error();
      const first = Number(section[1]), count = Number(section[2]);
      entries += count;
      if (entries > 20_000 || count > lines.length - i) throw new Error();
      for (let j = 0; j < count; j++) {
        const entry = /^(\d{10}) (\d{5}) ([nf])\s*$/.exec(lines[i++]);
        if (!entry) throw new Error();
        if (entry[3] === "n") {
          const offset = Number(entry[1]);
          if (
            offset >= start ||
            !source.slice(offset, offset + 40).startsWith(
              `${first + j} ${Number(entry[2])} obj`,
            )
          ) throw new Error();
          const ref = `${first + j} ${Number(entry[2])} R`;
          if (first + j === 0 || indexed.has(ref)) throw new Error();
          indexed.set(ref, offset);
        }
      }
    }
    const doc = await PDFDocument.load(bytes, {
      ignoreEncryption: false,
      throwOnInvalidObject: true,
      updateMetadata: false,
    });
    const root = /\/Root\s+(\d+)\s+(\d+)\s+R\b/.exec(xref.slice(trailerAt));
    if (
      !root ||
      doc.context.trailerInfo.Root?.toString() !== `${root[1]} ${root[2]} R`
    ) throw new Error();
    const objects = doc.context.enumerateIndirectObjects();
    if (
      objects.length !== indexed.size ||
      objects.some(([ref]) => !indexed.has(ref.toString()))
    ) throw new Error();
    const offsets = [...indexed.values()].sort((a, b) => a - b);
    const whitespace =
      "(?:[\\x00\\t\\n\\f\\r ]|%[^\\r\\n]*(?:\\r\\n|\\r|\\n))*";
    for (let i = 0; i < offsets.length; i++) {
      const offset = offsets[i], next = offsets[i + 1] ?? start;
      const header = /^\d+ \d+ obj\b/.exec(source.slice(offset, offset + 40));
      if (!header) throw new Error();
      const bodyStart = offset + header[0].length;
      const consumed = StrictObjectParser.consumed(
        bytes.subarray(bodyStart, next),
        doc.context,
      );
      if (
        !new RegExp(`^${whitespace}endobj${whitespace}$`).test(
          source.slice(bodyStart + consumed, next),
        )
      ) throw new Error();
    }
    if (doc.isEncrypted || doc.getPageCount() < 1 || doc.getPageCount() > 100) {
      throw new Error();
    }
    const forbidden = new Set([
      "JavaScript",
      "JS",
      "AA",
      "A",
      "Action",
      "OpenAction",
      "Launch",
      "RichMedia",
      "EmbeddedFiles",
      "EmbeddedFile",
      "Filespec",
      "EF",
      "AF",
      "AcroForm",
      "Rendition",
      "Movie",
      "Sound",
      "3D",
      "XFA",
      "SubmitForm",
      "ImportData",
      "GoToR",
      "GoToE",
      "URI",
      "ObjStm",
      "XRef",
      "Encrypt",
    ]);
    const seen = new Set<unknown>();
    let nodes = 0, decoded = 0;
    const visit = async (obj: unknown, depth = 0): Promise<void> => {
      if (++nodes > 100_000 || depth > 64) throw new Error();
      if (obj instanceof PDFRef) {
        const target = doc.context.lookup(obj);
        if (!target) throw new Error();
        return visit(target, depth + 1);
      }
      if (seen.has(obj)) return;
      seen.add(obj);
      if (obj instanceof PDFInvalidObject) throw new Error();
      if (obj instanceof PDFName && forbidden.has(obj.decodeText())) {
        throw new Error();
      }
      if (obj instanceof PDFRawStream) {
        const length = doc.context.lookup(obj.dict.get(PDFName.of("Length")));
        if (
          !(length instanceof PDFNumber) ||
          length.asNumber() !== obj.contents.length
        ) throw new Error();
        const filter = obj.dict.get(PDFName.of("Filter"));
        if (filter) {
          // Unknown codecs and custom decode parameters are outside the MVP.
          if (
            !(filter instanceof PDFName) ||
            filter.decodeText() !== "FlateDecode" ||
            obj.dict.has(PDFName.of("DecodeParms"))
          ) throw new Error();
          const stream = new Blob([obj.contents]).stream().pipeThrough(
            new DecompressionStream("deflate"),
          );
          decoded += (await readLimited(stream, 16_777_216 - decoded)).length;
          if (decoded > 16_777_216) throw new Error();
        }
        await visit(obj.dict, depth + 1);
      } else if (obj instanceof PDFDict) {
        for (const [key, value] of obj.entries()) {
          await visit(key, depth + 1);
          await visit(value, depth + 1);
        }
      } else if (obj instanceof PDFArray) {
        for (let i = 0; i < obj.size(); i++) await visit(obj.get(i), depth + 1);
      }
    };
    for (const [, obj] of objects) await visit(obj);
    for (const page of doc.getPages()) {
      const size = page.getSize();
      if (
        !Number.isFinite(size.width) || !Number.isFinite(size.height) ||
        size.width <= 0 || size.height <= 0
      ) throw new Error();
    }
  } catch {
    throw new IssuanceError("invalid_pdf", 422);
  }
}

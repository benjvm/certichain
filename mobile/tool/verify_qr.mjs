import { readFileSync } from "node:fs";
import { PNG } from "pngjs";
import jsQR from "jsqr";

// Independent decoder, test tool only. The app has no scanner dependency.
export function decodeQr(pngBytes, expected) {
  const png = PNG.sync.read(pngBytes);
  const decoded = jsQR(new Uint8ClampedArray(png.data), png.width, png.height);
  if (!decoded || decoded.data !== expected) {
    throw new Error("Rendered QR did not recover the exact configured link");
  }
  return decoded.data;
}
if (process.argv[1]?.endsWith("verify_qr.mjs")) {
  decodeQr(readFileSync(process.argv[2]), process.argv[3]);
  console.log("PASS: independently decoded the rendered QR to the exact link");
}

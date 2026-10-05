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
// Extract the actual painted QR from a production screenshot. Semantics bounds
// can differ from page screenshot coordinates after browser/Flutter scrolling.
export function cropRenderedQr(pngBytes, expected) {
  const png = PNG.sync.read(pngBytes);
  const decoded = jsQR(new Uint8ClampedArray(png.data), png.width, png.height);
  if (!decoded || decoded.data !== expected) {
    throw new Error("Production screenshot QR decode failed");
  }
  const points = [
    decoded.location.topLeftCorner,
    decoded.location.topRightCorner,
    decoded.location.bottomLeftCorner,
    decoded.location.bottomRightCorner,
  ];
  const left = Math.min(...points.map((p) => p.x)),
    top = Math.min(...points.map((p) => p.y));
  const right = Math.max(...points.map((p) => p.x)),
    bottom = Math.max(...points.map((p) => p.y));
  const margin = Math.ceil(Math.max(right - left, bottom - top) * 0.12);
  const x = Math.max(0, Math.floor(left) - margin),
    y = Math.max(0, Math.floor(top) - margin);
  const size = Math.min(
    png.width - x,
    png.height - y,
    Math.ceil(Math.max(right - left, bottom - top)) + margin * 2,
  );
  const crop = new PNG({ width: size, height: size });
  PNG.bitblt(png, crop, x, y, size, size, 0, 0);
  const bytes = PNG.sync.write(crop);
  decodeQr(bytes, expected);
  return bytes;
}
if (process.argv[1]?.endsWith("verify_qr.mjs")) {
  decodeQr(readFileSync(process.argv[2]), process.argv[3]);
  console.log("PASS: independently decoded the rendered QR to the exact link");
}

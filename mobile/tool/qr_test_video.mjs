import { PNG } from "pngjs";
import { writeFileSync } from "node:fs";

// The video frames contain the QR painted by the actual 8B widget. Chrome's
// emulated getUserMedia device feeds them to the production scanner/decoder.
export function qrTestVideo(pngBytes, path) {
  const png = PNG.sync.read(pngBytes);
  const width = 640, height = 480, size = 384;
  const frame = Buffer.alloc(width * height * 3 / 2, 128);
  frame.fill(235, 0, width * height);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const source = (Math.floor(y * png.height / size) * png.width +
        Math.floor(x * png.width / size)) * 4;
      frame[(y + 48) * width + x + 128] = png.data[source] < 128 ? 16 : 235;
    }
  }
  const chunks = [
    Buffer.from(`YUV4MPEG2 W${width} H${height} F15:1 Ip A1:1 C420jpeg\n`),
  ];
  for (let i = 0; i < 30; i++) chunks.push(Buffer.from("FRAME\n"), frame);
  writeFileSync(path, Buffer.concat(chunks));
}

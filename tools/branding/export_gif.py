"""Render the final Lottie with Chrome, then encode those frames as GIF/WebP."""

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageSequence

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/branding/.render"
OUT = ROOT / "docs/assets"
FINAL_PAUSE_MS = 1200  # Additional to the Lottie's own 500 ms final hold.
BACKGROUND = (8, 11, 28)


def export(skip_render=False):
    if not skip_render:
        subprocess.run(
            ["node", str(ROOT / "tools/branding/render_lottie.mjs")],
            cwd=ROOT,
            check=True,
            env={**os.environ, "CERTICHAIN_TEST_CAMERA": "0"},
        )
    report = json.loads((WORK / "render-report.json").read_text(encoding="utf-8"))
    source = ROOT / "mobile/assets/animations/certichain_intro.json"
    if hashlib.sha256(source.read_bytes()).hexdigest() != report["sha256"]:
        raise SystemExit("Rendered frames are stale. Run without --skip-render.")
    frames = [
        Image.open(WORK / f"alpha-{n}.png").convert("RGBA")
        for n in range(report["frames"])
    ]
    # A single palette for the whole sequence avoids flickering gradients. Sample
    # all phases, including low-opacity colors, not just the final logo.
    samples = frames[::3]
    atlas = Image.new("RGB", (200 * len(samples), 200), BACKGROUND)
    for index, image in enumerate(samples):
        atlas.paste(
            image.resize((200, 200), Image.Resampling.LANCZOS), (200 * index, 0)
        )
    palette = atlas.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    # Reserve index 255 for binary GIF transparency; quantize straight RGB,
    # without compositing edges onto a matte that would create dark halos.
    entries = palette.getpalette()
    entries[765:768] = [0, 0, 0]
    palette.putpalette(entries)
    indexed = []
    for image in frames:
        quantized = image.convert("RGB").quantize(
            palette=palette, dither=Image.Dither.NONE
        )
        transparent = image.getchannel("A").point(lambda n: 255 if n < 128 else 0)
        quantized.paste(255, mask=transparent)
        indexed.append(quantized)
    # GIF uses centiseconds: distribute 30/40 ms, preserving the 2.8 s duration.
    ticks = [round(n * 100 / report["fps"]) for n in range(len(frames) + 1)]
    durations = [(ticks[n + 1] - ticks[n]) * 10 for n in range(len(frames))]
    durations[-1] += FINAL_PAUSE_MS
    gif_path = OUT / "certichain_intro.gif"
    indexed[0].save(
        gif_path,
        save_all=True,
        append_images=indexed[1:],
        duration=durations,
        loop=0,
        optimize=False,
        transparency=255,
        disposal=2,
    )
    frames[0].save(
        OUT / "certichain_intro.webp",
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        lossless=True,
        method=6,
    )
    # Evidence uses actual rendered frames, with labels outside the canvas.
    moments = [
        (0, "0,00 s · Inicio"),
        (18, "0,60 s · Red"),
        (36, "1,20 s · Certificado"),
        (42, "1,40 s · Verificación"),
        (53, "1,77 s · Nombre"),
        (83, "2,77 s · Estado final"),
    ]
    sheet = Image.new("RGB", (1080, 792), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(str(ROOT / "mobile/assets/fonts/Inter-Regular.ttf"), 15)
    for index, (frame, label) in enumerate(moments):
        frame = round(frame / 83 * (len(frames) - 1))
        label = f"{frame / report['fps']:.2f} s · {label.split(' · ', 1)[1]}"
        x, y = (index % 3) * 360, (index // 3) * 396
        tile = frames[frame].resize((360, 360), Image.Resampling.LANCZOS)
        sheet.paste(tile, (x, y), tile)
        draw.text((x + 20, y + 366), label, font=font, fill=(165, 181, 208))
    sheet.save(OUT / "certichain_intro_keyframes.png", optimize=True)
    # Verify the encoded file, including Pillow's coalesced final hold.
    with Image.open(gif_path) as gif:
        delays = [frame.info["duration"] for frame in ImageSequence.Iterator(gif)]
        assert gif.size == (600, 600) and gif.n_frames > 30
        assert gif.info["loop"] == 0
        assert sum(delays) == round(len(frames) * 1000 / report["fps"]) + FINAL_PAUSE_MS
        assert delays[-1] >= FINAL_PAUSE_MS
        summary = {
            "frames": gif.n_frames,
            "duration_ms": sum(delays),
            "final_hold_ms": delays[-1],
            "bytes": gif_path.stat().st_size,
        }
    print(
        json.dumps(
            {
                "gif": summary,
                "webp_bytes": (OUT / "certichain_intro.webp").stat().st_size,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-render",
        action="store_true",
        help="Use existing captures only if their Lottie SHA-256 matches",
    )
    export(parser.parse_args().skip_render)

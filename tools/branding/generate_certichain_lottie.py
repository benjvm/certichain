"""Original CertiChain vector artwork and motion. Python 3 standard library only.

The measured design space is the official 916 px PNG. These few, hand-authored
Bezier paths preserve its silhouette, without tracing raster noise or loading
fonts. Both Lottie and the static SVG come from the same geometry.
"""

import argparse
import json
import math
import re
from itertools import pairwise
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[2]
DURATION = 2.8
FPS = 30
CANVAS = 512
# Layout in the reference PNG coordinate system, fitted with safe margins.
ART_SCALE = 0.50
ART_OFFSET = (26, 32)
POSITIONS = {"left": (225, 367), "right": (700, 374), "bottom": (462, 507)}
COLORS = {
    "cyan": "#00DEED",
    "blue": "#168FFF",
    "violet": "#6924F5",
    "indigo": "#3520E8",
    "check": "#65EDFA",
    "white": "#FFFFFF",
    "background": "#080B1C",
}
# Seconds; each phase scales proportionally when DURATION changes.
TIMING = {
    "network": (0.0, 0.60),
    "left": (0.12, 0.40),
    "right": (0.22, 0.50),
    "bottom": (0.32, 0.60),
    "document": (0.45, 1.05),
    "line1": (0.80, 1.08),
    "line2": (0.92, 1.20),
    "check": (1.05, 1.60),
    "pulse": (1.60, 1.675, 1.75),
    "wordmark": (1.70, 2.30),
    "hold": (2.30, 2.80),
}
EASE_OUT = (0.26, 0.0)
EASE_IN = (0.22, 1.0)
NODE_START_SCALE = 91
DOCUMENT_START_SCALE = 97
DOCUMENT_RISE = 9
WORDMARK_RISE = 5
CHECK_PULSE_SCALE = 102.5


def frame(seconds):
    return round(seconds * DURATION / 2.8 * FPS, 4)


def point(x, y, offset=(0, 0)):
    ratio = CANVAS / 512
    return [
        round(((x + offset[0]) * ART_SCALE + ART_OFFSET[0]) * ratio, 4),
        round(((y + offset[1]) * ART_SCALE + ART_OFFSET[1]) * ratio, 4),
    ]


def rgb(color):
    value = COLORS.get(color, color).lstrip("#")
    return [round(int(value[n : n + 2], 16) / 255, 6) for n in (0, 2, 4)]


def fixed(value):
    return {"a": 0, "k": value}


def animated(times, values):
    keys = []
    for index, (time, value) in enumerate(zip(times, values, strict=True)):
        key = {"t": frame(time), "s": value if isinstance(value, list) else [value]}
        if index < len(times) - 1:
            key.update(
                o={"x": [EASE_OUT[0]], "y": [EASE_OUT[1]]},
                i={"x": [EASE_IN[0]], "y": [EASE_IN[1]]},
            )
        keys.append(key)
    return {"a": 1, "k": keys}


def paths(data, offset=(0, 0)):
    """Convert the explicit M/L/C/Q/Z source subset to cubic Lottie paths.

    Handles are relative to each vertex, as required by Lottie. Q is converted
    analytically to cubic; no polygon sampling and no third-party SVG parser.
    """
    tokens = re.findall(r"[MLCQZ]|-?\d+(?:\.\d+)?", data)
    if re.sub(r"[MLCQZ\s,\-\d.]", "", data):
        raise ValueError("Unsupported source path syntax")
    result, current = [], None
    index = 0
    sizes = {"M": 2, "L": 2, "C": 6, "Q": 4, "Z": 0}
    while index < len(tokens):
        command = tokens[index]
        count = sizes[command]
        coords = [float(n) for n in tokens[index + 1 : index + count + 1]]
        index += count + 1
        if command == "Z":
            current["c"] = True
            continue
        end = point(*coords[-2:], offset)
        if command == "M":
            current = {"v": [end], "i": [[0, 0]], "o": [[0, 0]], "c": False}
            result.append(current)
            continue
        start = current["v"][-1]
        control1, control2 = start, end
        if command == "C":
            control1 = point(*coords[:2], offset)
            control2 = point(*coords[2:4], offset)
        elif command == "Q":
            q = point(*coords[:2], offset)
            control1 = [start[k] + 2 / 3 * (q[k] - start[k]) for k in (0, 1)]
            control2 = [end[k] + 2 / 3 * (q[k] - end[k]) for k in (0, 1)]
        current["o"][-1] = [round(control1[k] - start[k], 4) for k in (0, 1)]
        current["v"].append(end)
        current["i"].append([round(control2[k] - end[k], 4) for k in (0, 1)])
        current["o"].append([0, 0])
    # Merge an explicit closing endpoint with the initial vertex. This preserves
    # its incoming tangent and avoids a zero-length segment for trim paths.
    for item in result:
        if item["c"] and item["v"][0] == item["v"][-1]:
            item["i"][0] = item["i"].pop()
            item["v"].pop()
            item["o"].pop()
    return result


def transform():
    return {
        "ty": "tr",
        "p": fixed([0, 0]),
        "a": fixed([0, 0]),
        "s": fixed([100, 100]),
        "r": fixed(0),
        "o": fixed(100),
        "sk": fixed(0),
        "sa": fixed(0),
    }


def paint(colors, start, end, width=0):
    common = {"o": fixed(100)}
    if len(colors) == 1:
        common.update(ty="st" if width else "fl", c=fixed(rgb(colors[0])))
    else:
        stops = []
        for index, color in enumerate(colors):
            stops.extend([index / (len(colors) - 1), *rgb(color)])
        common.update(
            ty="gs" if width else "gf",
            t=1,
            g={"p": len(colors), "k": fixed(stops)},
            s=fixed(point(*start)),
            e=fixed(point(*end)),
        )
    if width:
        common.update(w=fixed(width * ART_SCALE * CANVAS / 512), lc=2, lj=2, ml=4)
    else:
        common["r"] = 2  # even-odd, including the e/a counters
    return common


def group(
    name, data, colors, start=(0, 0), end=(916, 916), width=0, trim=None, offset=(0, 0)
):
    items = [{"ty": "sh", "nm": name, "ks": fixed(p)} for p in paths(data, offset)]
    items.append(paint(colors, start, end, width))
    if trim:
        items.append(
            {
                "ty": "tm",
                "s": fixed(0),
                "e": animated(trim, [0, 100]),
                "o": fixed(0),
                "m": 1,
            }
        )
    return {"ty": "gr", "nm": name, "it": [*items, transform()]}


def layer(name, shapes, reveal=None, center=(458, 430), scale=100, rise=0, pulse=None):
    pivot = [*point(*center), 0]
    ks = {
        "o": fixed(100),
        "r": fixed(0),
        "p": fixed(pivot),
        "a": fixed(pivot),
        "s": fixed([100, 100, 100]),
    }
    if reveal:
        ks["o"] = animated(reveal, [0, 100])
        if scale != 100:
            ks["s"] = animated(reveal, [[scale, scale, 100], [100, 100, 100]])
        if rise:
            ks["p"] = animated(
                reveal, [[pivot[0], pivot[1] + rise * CANVAS / 512, 0], pivot]
            )
    if pulse:
        ks["s"] = animated(
            pulse,
            [
                [100, 100, 100],
                [CHECK_PULSE_SCALE, CHECK_PULSE_SCALE, 100],
                [100, 100, 100],
            ],
        )
    return {
        "ddd": 0,
        "ty": 4,
        "nm": name,
        "sr": 1,
        "ks": ks,
        "ao": 0,
        "shapes": shapes,
        "ip": 0,
        "op": frame(2.8),
        "st": 0,
        "bm": 0,
    }


# Lettering reconstructed from the supplied logo, not a substituted system font.
# Uppercase C is reused in both halves; i includes the dot as another contour.
LETTER_C = """M137 687 L115 709 C105 698 94 692 80 692
 C56 692 42 710 42 733 C42 757 57 774 80 774 C94 774 106 768 116 758
 L138 780 C123 797 105 805 80 805 C40 805 11 775 11 733
 C11 693 39 661 80 661 C104 661 122 669 137 687 Z"""
LETTER_I = """M396 702 L426 702 L426 801 L396 801 Z
 M410 660 C420 660 427 667 427 677 C427 687 420 694 410 694
 C400 694 393 687 393 677 C393 667 400 660 410 660 Z"""
WORDMARK = [
    ("C", LETTER_C, (0, 0)),
    (
        "e",
        """M242 761 L173 761 C176 775 185 781 198 781
      C209 781 219 777 227 769 L242 786 C230 799 215 805 197 805
      C163 805 140 784 140 753 C140 722 161 700 193 700
      C226 700 244 723 244 751 L244 758 Q244 761 242 761 Z
      M173 740 L214 740 C211 728 205 722 194 722 C183 722 176 728 173 740 Z""",
        (0, 0),
    ),
    (
        "r",
        """M255 801 L255 746 C255 716 279 698 314 700 L314 728
      C294 726 285 734 285 751 L285 801 Z""",
        (0, 0),
    ),
    (
        "t",
        """M326 671 L355 671 L355 702 L382 702 L382 728 L355 728
      L355 762 Q355 777 368 777 Q376 777 382 774 L382 800
      Q372 805 359 805 C336 805 326 790 326 766 Z""",
        (0, 0),
    ),
    ("i", LETTER_I, (0, 0)),
    ("C", LETTER_C, (424, 0)),
    (
        "h",
        """M568 664 L598 664 L598 714 C606 704 616 700 629 700
      C651 700 665 717 665 742 L665 801 L635 801 L635 748
      C635 734 629 726 617 726 C605 726 598 734 598 748 L598 801 L568 801 Z""",
        (0, 0),
    ),
    (
        "a",
        """M677 718 C690 706 705 700 723 700 C752 700 767 715 767 744
      L767 801 L739 801 L739 790 C731 800 720 805 706 805
      C685 805 671 791 671 773 C671 749 692 738 737 739
      C736 728 730 722 718 722 C707 722 698 726 691 733 Z
      M737 759 C712 758 700 761 700 771 C700 778 705 783 714 783
      C728 783 737 775 737 764 Z""",
        (0, 0),
    ),
    ("i", LETTER_I, (383, 0)),
    (
        "n",
        """M818 702 L848 702 L848 715 C857 704 868 700 881 700
      C903 700 914 717 914 742 L914 801 L884 801 L884 748
      C884 733 878 726 867 726 C855 726 848 734 848 748 L848 801 L818 801 Z""",
        (0, 0),
    ),
]


def cube(name, center, size=1):
    # Three planar faces with common edges: scale affects the whole node only.
    face_data = [
        (
            "left",
            "M-70 -37 L-12 -3 Q-6 0.5 0 0.5 L0 78 Q-6 78 -12 74 L-61 46 Q-70 41 -70 30 Z",
            ["cyan", "blue"],
        ),
        (
            "right",
            "M0 0.5 Q6 0.5 12 -3 L70 -37 L70 30 Q70 41 61 46 L12 74 Q6 78 0 78 Z",
            ["indigo", "violet"],
        ),
        (
            "top",
            "M-70 -37 Q-70 -44 -60 -49 L-12 -77 Q0 -84 12 -77 L60 -49 Q70 -44 70 -37 L12 -3 Q0 4 -12 -3 Z",
            ["cyan", "blue"],
        ),
    ]
    shapes = []
    for face, data, colors in face_data:
        start, end = {
            "top": ((-65, -65), (65, -25)),
            "left": ((-65, -30), (0, 75)),
            "right": ((0, 0), (70, 65)),
        }[face]
        shape = group(
            f"{name} / {face}",
            data,
            colors,
            (center[0] + start[0] * size, center[1] + start[1] * size),
            (center[0] + end[0] * size, center[1] + end[1] * size),
            offset=center,
        )
        if size != 1:
            pivot = point(*center)
            for item in shape["it"]:
                if item["ty"] == "sh":
                    p = item["ks"]["k"]
                    p["v"] = [
                        [round(pivot[k] + (v[k] - pivot[k]) * size, 4) for k in (0, 1)]
                        for v in p["v"]
                    ]
                    for key in ("i", "o"):
                        p[key] = [[round(v * size, 4) for v in pair] for pair in p[key]]
        shapes.append(shape)
    return layer(f"Cube / {name}", shapes, TIMING[name], center, NODE_START_SCALE)


def build_animation():
    layers = [
        layer(
            "Network / rear",
            [
                group(
                    "Link to left cube",
                    "M333 211 L244 264 Q219 279 219 310 L225 367",
                    ["cyan", "blue"],
                    (215, 310),
                    (333, 211),
                    42,
                    TIMING["network"],
                ),
                group(
                    "Link to right cube",
                    "M628 234 L675 265 Q701 280 701 310 L700 374",
                    ["violet", "blue"],
                    (614, 226),
                    (701, 374),
                    42,
                    TIMING["network"],
                ),
            ],
        ),
        layer(
            "Network / front",
            [
                group(
                    "Left to lower cube",
                    "M225 392 L462 535",
                    ["cyan", "blue"],
                    (225, 392),
                    (462, 535),
                    43,
                    (0.14, 0.60),
                ),
                group(
                    "Right to lower cube",
                    "M700 397 L462 535",
                    ["blue", "cyan"],
                    (700, 397),
                    (462, 535),
                    43,
                    (0.20, 0.60),
                ),
            ],
        ),
        layer(
            "Certificate / outline and folded corner",
            [
                group(
                    "Left edge and sloped top",
                    # Closed silhouette: flush fold junction and diagonal foot.
                    # A round-capped stroke extends half its width past both.
                    "M313 423 L313 137 Q313 98 353 91 L538 61 "
                    "L538 100 L360 129 Q352 130 352 145 L352 447 Z",
                    ["cyan", "blue", "indigo"],
                    (333, 110),
                    (389, 840),
                ),
                group(
                    "Right edge",
                    "M600 160 L628 154 L628 415 L600 431 Z",
                    ["violet", "indigo", "blue"],
                    (614, 150),
                    (614, 421),
                ),
                group(
                    "Fold",
                    "M538 61 L627 146 Q637 156 621 162 L562 174 Q538 178 538 151 Z",
                    ["cyan", "blue", "violet"],
                    (538, 68),
                    (634, 175),
                ),
            ],
            TIMING["document"],
            (474, 265),
            DOCUMENT_START_SCALE,
            DOCUMENT_RISE,
        ),
        layer(
            "Certificate / line 1",
            [
                group(
                    "Content line 1",
                    "M393 182 L480 166",
                    ["cyan", "blue"],
                    (393, 182),
                    (480, 166),
                    28,
                    TIMING["line1"],
                )
            ],
        ),
        layer(
            "Certificate / line 2",
            [
                group(
                    "Content line 2",
                    "M392 232 L504 212",
                    ["blue", "violet"],
                    (392, 232),
                    (504, 212),
                    28,
                    TIMING["line2"],
                )
            ],
        ),
        layer(
            "Verification / check",
            [
                group(
                    "Two-segment verification stroke",
                    "M424 321 L466 361 L554 261",
                    ["check"],
                    width=42,
                    trim=TIMING["check"],
                )
            ],
            center=(483, 314),
            pulse=TIMING["pulse"],
        ),
        cube("left", POSITIONS["left"]),
        cube("right", POSITIONS["right"]),
        cube("bottom", POSITIONS["bottom"], 1.20),
    ]
    for name, letters, colors in [
        ("Certi", WORDMARK[:5], ["white"]),
        ("Chain", WORDMARK[5:], ["cyan", "blue", "violet"]),
    ]:
        shapes = [
            group(letter, data, colors, (435, 680), (914, 797), offset=offset)
            for letter, data, offset in letters
        ]
        layers.append(
            layer(f"Wordmark / {name}", shapes, TIMING["wordmark"], rise=WORDMARK_RISE)
        )
    layers.reverse()  # Lottie stacks the first layer on top.
    for index, item in enumerate(layers, 1):
        item["ind"] = index
    return {
        "v": "5.12.2",
        "fr": FPS,
        "ip": 0,
        "op": frame(2.8),
        "w": CANVAS,
        "h": CANVAS,
        "nm": "CertiChain / identity intro",
        "ddd": 0,
        "assets": [],
        "layers": layers,
        "markers": [
            {"tm": frame(times[0]), "cm": name, "dr": frame(times[-1] - times[0])}
            for name, times in TIMING.items()
            if name in ("network", "document", "check", "wordmark", "hold")
        ],
    }


def svg_path(path):
    vertices = path["v"]
    commands = [f"M{vertices[0][0]} {vertices[0][1]}"]
    count = len(vertices) if path["c"] else len(vertices) - 1
    for index in range(count):
        nxt = (index + 1) % len(vertices)
        a, b = vertices[index], vertices[nxt]
        out, inc = path["o"][index], path["i"][nxt]
        if any(out) or any(inc):
            numbers = [a[0] + out[0], a[1] + out[1], b[0] + inc[0], b[1] + inc[1], *b]
            commands.append(
                "C" + " ".join(f"{n:.4f}".rstrip("0").rstrip(".") for n in numbers)
            )
        else:
            commands.append(f"L{b[0]} {b[1]}")
    if path["c"]:
        commands.append("Z")
    return " ".join(commands)


def build_svg(animation):
    defs, body = [], []
    for item in reversed(animation["layers"]):
        body.append(f'<g id="layer-{item["ind"]}"><title>{escape(item["nm"])}</title>')
        for shape in item["shapes"]:
            geometry = " ".join(
                svg_path(s["ks"]["k"]) for s in shape["it"] if s["ty"] == "sh"
            )
            style = next(s for s in shape["it"] if s["ty"] in ("fl", "st", "gf", "gs"))
            if style["ty"] in ("gf", "gs"):
                ident = f"gradient-{len(defs)}"
                start, end = style["s"]["k"], style["e"]["k"]
                values = style["g"]["k"]["k"]
                stops = "".join(
                    f'<stop offset="{values[n]}" stop-color="rgb({",".join(str(round(v * 255)) for v in values[n + 1 : n + 4])})"/>'
                    for n in range(0, len(values), 4)
                )
                defs.append(
                    f'<linearGradient id="{ident}" gradientUnits="userSpaceOnUse" x1="{start[0]}" y1="{start[1]}" x2="{end[0]}" y2="{end[1]}">{stops}</linearGradient>'
                )
                color = f"url(#{ident})"
            else:
                color = (
                    "rgb("
                    + ",".join(str(round(v * 255)) for v in style["c"]["k"])
                    + ")"
                )
            attr = f'fill="{color}" fill-rule="evenodd"'
            if style["ty"] in ("st", "gs"):
                attr = f'fill="none" stroke="{color}" stroke-width="{style["w"]["k"]}" stroke-linecap="round" stroke-linejoin="round"'
            body.append(f'<path d="{geometry}" {attr}/>')
        body.append("</g>")
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}" role="img" aria-labelledby="title"><title id="title">CertiChain</title><defs>{"".join(defs)}</defs>{"".join(body)}</svg>\n'


def validate(animation):
    """Additional semantic invariants beyond the external Lottie JSON schema."""
    assert animation["w"] == animation["h"] == CANVAS
    assert animation["fr"] == FPS and animation["op"] == frame(2.8)
    assert animation["assets"] == []
    ids = [item["ind"] for item in animation["layers"]]
    assert len(ids) == len(set(ids)) == 11
    assert "".join(letter[0] for letter in WORDMARK) == "CertiChain"

    def walk(value):
        if isinstance(value, dict):
            assert not any(
                key in value for key in ("refId", "ef", "x", "fonts", "chars")
            )
            if "v" in value and isinstance(value["v"], list):
                assert len(value["v"]) == len(value["i"]) == len(value["o"])
            if value.get("a") == 1 and isinstance(value.get("k"), list):
                times = [key["t"] for key in value["k"]]
                assert all(a < b for a, b in pairwise(times))
                assert 0 <= times[0] <= times[-1] <= frame(2.30)
            for key, child in value.items():
                # Bezier easing x is data, not an expression.
                if key not in ("i", "o") or not isinstance(child, dict):
                    walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
        elif isinstance(value, float):
            assert math.isfinite(value)

    walk(animation)


def outputs():
    animation = build_animation()
    validate(animation)
    return {
        ROOT / "mobile/assets/animations/certichain_intro.json": json.dumps(
            animation, ensure_ascii=False, separators=(",", ":"), allow_nan=False
        )
        + "\n",
        ROOT / "assets/branding/certichain-logo.svg": build_svg(animation),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if committed outputs differ from the generator",
    )
    args = parser.parse_args()
    for path, content in outputs().items():
        if args.check:
            if not path.exists() or path.read_bytes() != content.encode("utf-8"):
                raise SystemExit(f"Stale generated asset: {path.relative_to(ROOT)}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content.encode("utf-8"))
        print(
            f"{'OK' if args.check else 'Wrote'} {path.relative_to(ROOT)} ({len(content.encode('utf-8')):,} bytes)"
        )


if __name__ == "__main__":
    main()

"""Lightweight geometry, format and render checks. Run after export_gif.py."""

import copy
import hashlib
import json
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

import generate_certichain_lottie as generator

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/branding/.render"


class GeneratorTests(unittest.TestCase):
    def test_document_junctions_have_no_protruding_stroke_caps(self):
        animation = generator.build_animation()
        document = next(
            layer
            for layer in animation["layers"]
            if layer["nm"] == "Certificate / outline and folded corner"
        )
        for group in document["shapes"][:2]:
            self.assertFalse(any(item["ty"] in ("st", "gs") for item in group["it"]))
            path = next(item["ks"]["k"] for item in group["it"] if item["ty"] == "sh")
            self.assertTrue(path["c"])
        top = document["shapes"][0]["it"][0]["ks"]["k"]
        self.assertLessEqual(max(p[0] for p in top["v"]), generator.point(538, 61)[0])

    def setUp(self):
        self.animation = generator.build_animation()

    def test_generated_files_are_deterministic_and_current(self):
        self.assertEqual(generator.outputs(), generator.outputs())
        for path, content in generator.outputs().items():
            self.assertEqual(path.read_bytes(), content.encode("utf-8"))

    def test_dimensions_timing_layers_and_no_external_resources(self):
        generator.validate(self.animation)
        self.assertEqual(
            (
                self.animation["w"],
                self.animation["h"],
                self.animation["fr"],
                self.animation["op"],
            ),
            (512, 512, 30, 84),
        )
        self.assertEqual(self.animation["assets"], [])
        self.assertTrue(all(item["ty"] == 4 for item in self.animation["layers"]))
        self.assertLess(len(json.dumps(self.animation).encode()), 200_000)

    def test_lettering_and_svg_are_outlined(self):
        self.assertEqual("".join(item[0] for item in generator.WORDMARK), "CertiChain")
        svg = ET.fromstring(generator.build_svg(self.animation))
        self.assertGreater(len(svg.findall(".//{*}path")), 20)
        self.assertEqual(svg.findall(".//{*}text"), [])
        self.assertEqual(svg.findall(".//{*}image"), [])
        self.assertEqual(svg.find("{*}title").text, "CertiChain")

    def test_quadratic_conversion_preserves_tangents(self):
        curve = generator.paths("M0 0 Q30 60 60 0")[0]
        self.assertEqual(curve["o"][0], [10, 20])
        self.assertEqual(curve["i"][1], [-10, 20])
        self.assertFalse(curve["c"])

    def test_closed_curve_keeps_incoming_tangent(self):
        curve = generator.paths("M0 0 L60 0 C60 30 0 30 0 0 Z")[0]
        self.assertTrue(curve["c"])
        self.assertEqual(len(curve["v"]), 2)
        self.assertEqual(curve["i"][0], [0, 15])

    def test_check_is_one_open_two_segment_trimmed_path(self):
        check = next(
            item
            for item in self.animation["layers"]
            if item["nm"] == "Verification / check"
        )
        items = check["shapes"][0]["it"]
        path = next(item for item in items if item["ty"] == "sh")["ks"]["k"]
        self.assertFalse(path["c"])
        self.assertEqual(len(path["v"]), 3)
        trim = next(item for item in items if item["ty"] == "tm")
        self.assertEqual(trim["e"]["k"][0]["s"], [0])
        self.assertEqual(trim["e"]["k"][-1]["s"], [100])

    def test_gradient_stops_and_geometry_inside_canvas(self):
        for layer in self.animation["layers"]:
            for group in layer["shapes"]:
                for item in group["it"]:
                    if item["ty"] in ("gf", "gs"):
                        stops = item["g"]["k"]["k"]
                        self.assertEqual(len(stops), item["g"]["p"] * 4)
                        self.assertEqual(stops[::4], sorted(stops[::4]))
                        self.assertTrue(all(0 <= n <= 1 for n in stops))
                    if item["ty"] == "sh":
                        self.assertTrue(
                            all(
                                15 < n < 497
                                for pair in item["ks"]["k"]["v"]
                                for n in pair
                            )
                        )

    def test_rejects_broken_references(self):
        broken = copy.deepcopy(self.animation)
        broken["layers"][0]["refId"] = "missing"
        with self.assertRaises(AssertionError):
            generator.validate(broken)

    def test_official_schema_1_0_1(self):
        import jsonschema

        schema = WORK / "lottie.schema.json"
        self.assertTrue(
            schema.exists(),
            "Download the versioned schema as documented before testing.",
        )
        self.assertEqual(
            hashlib.sha256(schema.read_bytes()).hexdigest(),
            "a6adf87565bfbc94c73b1a5310569fbe53dd7d54df0060dada00559c2a030296",
        )
        data = json.loads(schema.read_text(encoding="utf-8"))
        self.assertEqual(data["$version"], 10001)
        jsonschema.Draft202012Validator.check_schema(data)
        jsonschema.Draft202012Validator(data).validate(self.animation)


class RenderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PIL import Image, ImageChops, ImageStat

        cls.Image, cls.ImageChops, cls.ImageStat = Image, ImageChops, ImageStat
        cls.report = json.loads(
            (WORK / "render-report.json").read_text(encoding="utf-8")
        )

    def image(self, name):
        with self.Image.open(WORK / name) as image:
            return image.convert("RGBA")

    def test_rendered_source_matches_and_playback_succeeded(self):
        source = (ROOT / "mobile/assets/animations/certichain_intro.json").read_bytes()
        self.assertEqual(self.report["sha256"], hashlib.sha256(source).hexdigest())
        for key in ("playback", "controls", "offline"):
            self.assertEqual(self.report[key], "PASS")
        self.assertEqual(self.report["errors"], [])

    def test_first_frame_empty_and_all_frames_unclipped(self):
        self.assertIsNone(self.image("alpha-0.png").getbbox())
        blank = self.Image.new("RGB", (600, 600), (8, 11, 28))
        for n in range(self.report["frames"]):
            image = self.image(f"frame-{n:03}.png").convert("RGB")
            bounds = self.ImageChops.difference(image, blank).getbbox()
            if bounds:
                self.assertTrue(
                    bounds[0] > 10
                    and bounds[1] > 10
                    and bounds[2] < 590
                    and bounds[3] < 590,
                    (n, bounds),
                )

    def test_check_draws_progressively_and_wordmark_is_delayed(self):
        def colored_pixels(image, box, predicate):
            return sum(predicate(p) for p in image.crop(box).get_flattened_data())

        # Cyan check, separate from dark document strokes and network.
        cyan = lambda p: p[0] > 65 and p[1] > 195 and p[2] > 200 and p[3] > 180
        check_box = (260, 175, 375, 265)
        counts = [
            colored_pixels(self.image(f"alpha-{n}.png"), check_box, cyan)
            for n in (18, 36, 42, 53)
        ]
        self.assertEqual(counts[0], 0)
        self.assertLess(counts[1], counts[2])
        self.assertLess(counts[2], counts[3])
        self.assertIsNone(self.image("alpha-36.png").crop((0, 420, 600, 530)).getbbox())
        self.assertIsNotNone(
            self.image("alpha-83.png").crop((0, 420, 600, 530)).getbbox()
        )

    def test_final_hold_and_offline_are_pixel_identical(self):
        final = self.image("frame-083.png")
        for n in range(69, 84):
            self.assertEqual(final.tobytes(), self.image(f"frame-{n:03}.png").tobytes())
        self.assertEqual(final.tobytes(), self.image("offline.png").tobytes())

    def test_static_svg_and_canvas_renderer_match_final_lottie(self):
        final = self.image("frame-083.png").convert("RGB")
        for name in ("static.png", "canvas.png"):
            other = self.Image.new("RGBA", (600, 600), (8, 11, 28, 255))
            other.alpha_composite(self.image(name))
            delta = self.ImageChops.difference(final, other.convert("RGB"))
            self.assertLess(max(self.ImageStat.Stat(delta).mean), 0.2, name)

    def test_gif_is_transparent_looping_and_holds_final_logo(self):
        with self.Image.open(ROOT / "docs/assets/certichain_intro.gif") as gif:
            self.assertEqual(gif.size, (600, 600))
            self.assertEqual(gif.info["loop"], 0)
            self.assertIn("transparency", gif.info)
            self.assertGreater(gif.n_frames, 30)
            self.assertIsNone(gif.convert("RGBA").getbbox())
            durations = []
            for n in range(gif.n_frames):
                gif.seek(n)
                durations.append(gif.info["duration"])
                image = gif.convert("RGBA")
                self.assertEqual(image.getpixel((0, 0))[3], 0)
            self.assertEqual(sum(durations), 4000)
            self.assertGreaterEqual(durations[-1], 1500)
            final = gif.convert("RGBA")
            self.assertIsNotNone(final.getbbox())
            for color in ("#080B1C", "#FFFFFF"):
                actual = self.Image.new("RGBA", final.size, color)
                actual.alpha_composite(final)
                expected = self.Image.new("RGBA", final.size, color)
                expected.alpha_composite(self.image("alpha-83.png"))
                delta = self.ImageChops.difference(
                    actual.convert("RGB"), expected.convert("RGB")
                )
                self.assertLess(max(self.ImageStat.Stat(delta).mean), 1.5)


if __name__ == "__main__":
    unittest.main()

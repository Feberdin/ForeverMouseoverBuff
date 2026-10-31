"""Render the three source-derived 0.9.0 release artboards without a browser.

Inputs: launch-0.9.0.html frame snapshots, unchanged local artwork/brand assets,
Arial/Arial Narrow/Georgia fonts, fonttools 4.68.0 and CairoSVG 2.9.1.
Outputs: standalone 1600x900 SVG compositions and matching PNG renders.
Invariants: no network, new UI data, image retouching, external SVG references,
private paths, or modification of source artwork. Text is outlined for portability.
Debug: run this file with --debug; failures identify the missing input or view.
"""

from __future__ import annotations

import argparse
import base64
import json
import logging
import re
from pathlib import Path
from xml.etree import ElementTree as ET

import cairosvg
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

LOG = logging.getLogger("fmb.artwork")
NS = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
ET.register_namespace("", NS)
ET.register_namespace("xlink", XLINK)
ASSETS = Path(__file__).resolve().parent
COLORS = {
    "bg": "#09181c",
    "panel": "#10282d",
    "gold": "#e3c78d",
    "mint": "#8cd1b7",
    "text": "#ecf0e9",
    "muted": "#9bb4b3",
}


def element(parent, tag, **attrs):
    """Create explicit SVG elements, keeping all source text XML-escaped."""
    values = {key.replace("_", "-"): str(value) for key, value in attrs.items()}
    return ET.SubElement(parent, f"{{{NS}}}{tag}", values)


def read_asset(name):
    path = ASSETS / name
    if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
        raise ValueError(f"Required artwork missing, empty or linked: {name}")
    return path.read_bytes()


def data_uri(name):
    kind = "jpeg" if name.endswith(".jpg") else "png"
    return f"data:image/{kind};base64," + base64.b64encode(read_asset(name)).decode(
        "ascii"
    )


class Font:
    """Use only glyph outlines needed by this artwork; no font file is bundled."""

    def __init__(self, name, path):
        if not path.is_file():
            raise ValueError(
                f"Missing font {path.name}; pass its directory via --fonts-dir"
            )
        self.name, self.face = name, TTFont(path)
        self.glyphs = self.face.getGlyphSet()
        self.cmap = self.face.getBestCmap()
        self.units = self.face["head"].unitsPerEm
        self.metrics = self.face["hmtx"].metrics
        self.kern = {}
        if "kern" in self.face:
            for table in self.face["kern"].kernTables:
                self.kern.update(table.kernTable)

    def sequence(self, value):
        for char in value:
            glyph = self.cmap.get(ord(char))
            if not glyph:
                raise ValueError(f"Font {self.name} does not contain U+{ord(char):04X}")
            yield char, glyph

    def width(self, value, size, tracking=0):
        result, previous = 0, None
        for _, glyph in self.sequence(value):
            result += self.kern.get((previous, glyph), 0) + self.metrics[glyph][0]
            previous = glyph
        return result * size / self.units + max(0, len(value) - 1) * tracking


class Artboard:
    """Compose vector geometry and unchanged embedded assets on a fixed canvas."""

    def __init__(self, fonts, view):
        self.fonts, self.used = fonts, set()
        self.root = ET.Element(
            f"{{{NS}}}svg",
            {
                "width": "1600",
                "height": "900",
                "viewBox": "0 0 1600 900",
                "role": "img",
            },
        )
        element(self.root, "title").text = f"Forever Mouseover Buff 0.9.0 Beta — {view}"
        element(
            self.root, "desc"
        ).text = "Independent Feberdin addon. Source-derived interface preview, not an in-game screenshot."
        self.defs = element(self.root, "defs")
        gradient = element(
            self.defs, "radialGradient", id="backdrop", cx="77%", cy="40%", r="90%"
        )
        for offset, color in [
            ("0%", "#18383b"),
            ("41%", "#10272c"),
            ("100%", "#08191d"),
        ]:
            element(gradient, "stop", offset=offset, stop_color=color)
        self.rect(0, 0, 1600, 900, "url(#backdrop)")

    def rect(self, x, y, w, h, color, parent=None, **attrs):
        return element(
            parent if parent is not None else self.root,
            "rect",
            x=x,
            y=y,
            width=w,
            height=h,
            fill=color,
            **attrs,
        )

    def image(self, uri, x, y, w, h, parent=None, aspect="xMidYMid meet"):
        node = element(
            parent if parent is not None else self.root,
            "image",
            x=x,
            y=y,
            width=w,
            height=h,
            preserveAspectRatio=aspect,
        )
        node.set(f"{{{XLINK}}}href", uri)
        return node

    def text(
        self,
        value,
        x,
        y,
        size=14,
        color=None,
        font="sans",
        tracking=0,
        parent=None,
        anchor="start",
    ):
        face = self.fonts[font]
        group = element(
            parent if parent is not None else self.root,
            "g",
            fill=color or COLORS["text"],
            aria_label=value,
        )
        element(group, "title").text = value
        width = face.width(value, size, tracking)
        x -= width / 2 if anchor == "middle" else width if anchor == "end" else 0
        previous, cursor = None, 0
        for char, glyph in face.sequence(value):
            cursor += face.kern.get((previous, glyph), 0) * size / face.units
            ident = f"glyph-{font}-{ord(char)}"
            if ident not in self.used:
                pen = SVGPathPen(face.glyphs)
                face.glyphs[glyph].draw(pen)
                element(self.defs, "path", id=ident, d=pen.getCommands())
                self.used.add(ident)
            use = element(
                group,
                "use",
                transform=f"translate({x + cursor:.3f} {y:.3f}) scale({size / face.units:.6f} {-size / face.units:.6f})",
            )
            use.set(f"{{{XLINK}}}href", f"#{ident}")
            cursor += face.metrics[glyph][0] * size / face.units + tracking
            previous = glyph
        return group

    def lines(self, values, x, y, size=14, spacing=None, **attrs):
        for index, value in enumerate(values):
            self.text(value, x, y + index * (spacing or size * 1.4), size, **attrs)

    def common(self, hero=False):
        self.image(data_uri("project-icon.png"), 72, 63, 58, 58)
        self.text("FOREVER", 148, 85, 14, COLORS["gold"], tracking=3.5)
        self.text("MOUSEOVER BUFF", 148, 108, 12, "#dde9e4", tracking=1.7)
        self.image(data_uri("feberdin-knight.png"), 1426, 43, 110, 96)
        self.rect(22, 22, 1556, 856, "none", stroke="#d9bd7a", stroke_opacity=0.19)
        self.rect(72, 820, 1456, 1, "#b4c7bd", opacity=0.2)
        if hero:
            left, right = (
                "Every cast needs a keypress · WoW Forever · 0.9.0 Beta",
                "AI-assisted illustration · Independent addon by Feberdin",
            )
        else:
            left, right = (
                "UI preview from addon code · German interface",
                "WoW Forever · 0.9.0 Beta",
            )
        self.text(left, 72, 860, 12, "#b2c7c2")
        self.text(right, 1528, 860, 10 if hero else 12, "#9bb4b3", anchor="end")

    def save(self, name):
        path = ASSETS / f"{name}.svg"
        raw = ET.tostring(self.root, encoding="utf-8", xml_declaration=True)
        if len(raw) > 2 * 1024 * 1024:
            raise ValueError(f"SVG exceeds upload budget: {name}")
        path.write_bytes(raw)
        cairosvg.svg2png(
            bytestring=raw,
            write_to=str(ASSETS / f"{name}.png"),
            output_width=1600,
            output_height=900,
        )
        size = (ASSETS / f"{name}.png").stat().st_size
        LOG.info("Rendered %s: SVG=%d bytes, PNG=%d bytes", name, len(raw), size)
        if size > 2 * 1024 * 1024:
            raise ValueError(
                f"PNG exceeds upload budget; use a vector-composition JPEG export: {name}"
            )


def wrap(value, font, size, width):
    """Wrap only at existing spaces; preserve the source's explicit line breaks."""
    result = []
    for paragraph in value.split("\n"):
        current = ""
        for word in paragraph.split(" "):
            candidate = f"{current} {word}" if current else word
            if current and font.width(candidate, size) > width:
                result.append(current)
                current = word
            else:
                current = candidate
        result.append(current)
    return result


def native_preview(board, layout, textures):
    """Replay exported native geometry, text and texture order; invent no UI."""
    board.rect(560, 123, 958, 707, "none", stroke="#afc7bf", stroke_opacity=0.08, rx=11)
    board.rect(
        571, 134, 936, 685, "#071417", stroke="#e0c489", stroke_opacity=0.26, rx=5
    )
    board.text("THE ACTUAL ADDON LAYOUT", 586, 113, 10, "#8daca6", tracking=2)
    parent = element(board.root, "g", transform="translate(585 148) scale(1.08)")

    def color(values):
        rgb = [round(values.get(str(k), 0) * 255) for k in (1, 2, 3)]
        return "#" + "".join(f"{c:02x}" for c in rgb), values.get("4", 1)

    for index, item in enumerate(layout):
        x, y, w, h = [item[k] for k in ("x", "y", "w", "h")]
        if not all(isinstance(v, (int, float)) and abs(v) < 5000 for v in (x, y, w, h)):
            raise ValueError(f"Invalid native geometry at node {index}")
        if item.get("texture"):
            name = item["texture"].split("\\")[-1].removesuffix(".tga")
            board.image(textures[name], x, y, w, h, parent)
        elif item["kind"] == "FontString":
            size = item["size"]
            lines = wrap(item["text"], board.fonts["narrow"], size, w)
            spacing = size * 1.18
            first = y + size * 0.94
            if item["vertical"] == "MIDDLE":
                first = y + (h - len(lines) * spacing) / 2 + size * 0.94
            anchor = (
                "middle"
                if item["align"] == "CENTER"
                else "end"
                if item["align"] == "RIGHT"
                else "start"
            )
            at = x + w / 2 if anchor == "middle" else x + w if anchor == "end" else x
            clip = element(board.defs, "clipPath", id=f"native-clip-{index}")
            board.rect(x, y, w, h, "white", clip)
            group = element(parent, "g", clip_path=f"url(#native-clip-{index})")
            board.lines(
                lines,
                at,
                first,
                size,
                spacing,
                color=color(item["textColor"])[0],
                font="narrow",
                parent=group,
                anchor=anchor,
            )
        else:
            fill, opacity = color(item["color"])
            board.rect(x, y, w, h, fill, parent, opacity=opacity)


def hero(fonts):
    board = Artboard(fonts, "hero")
    board.image(
        data_uri("hero-art-0.9.0.jpg"), 0, 0, 1600, 900, aspect="xMaxYMid slice"
    )
    for ident, stops, vertical in [
        ("hero-shade", [(0, 0.92), (0.24, 0.88), (0.42, 0.53), (0.64, 0.03)], False),
        ("footer-shade", [(0, 0), (0.7, 0), (1, 0.92)], True),
    ]:
        gradient = element(
            board.defs,
            "linearGradient",
            id=ident,
            x1="0%",
            y1="0%",
            x2="0%" if vertical else "100%",
            y2="100%" if vertical else "0%",
        )
        for offset, opacity in stops:
            element(
                gradient,
                "stop",
                offset=f"{offset * 100}%",
                stop_color="#06161b",
                stop_opacity=opacity,
            )
        board.rect(0, 0, 1600, 900, f"url(#{ident})")
    board.text("Forever", 77, 309, 88, font="serif", tracking=-2.8)
    board.text("Mouseover Buff", 77, 399, 88, "#f1d597", font="serif", tracking=-2.8)
    board.lines(
        ["A blessing. A key.", "A better journey."],
        80,
        478,
        30,
        42,
        color="#e9eee4",
        font="serif",
    )
    board.rect(80, 550, 74, 2, COLORS["gold"])
    board.text("Mouseover blessings", 80, 595, 17, COLORS["mint"])
    board.text("· Guided setup · Your own key", 250, 595, 17, "#c5d6d2")
    board.text("A small kindness for the road ahead.", 80, 626, 17, "#c5d6d2")
    for x, width, label, tint in [
        (80, 145, "WOW FOREVER", COLORS["gold"]),
        (235, 115, "0.9.0 BETA", "#d2e4de"),
    ]:
        board.rect(
            x,
            696,
            width,
            33,
            "#10292b",
            fill_opacity=0.6,
            stroke=tint,
            stroke_opacity=0.45,
            rx=4,
        )
        board.text(label, x + width / 2, 718, 12, tint, tracking=1.1, anchor="middle")
    board.common(hero=True)
    board.save("launch-hero-0.9.0")


def setup_board(fonts, layouts, textures, keybinding=False):
    board = Artboard(fonts, "keybinding" if keybinding else "introduction")
    if keybinding:
        board.text(
            "YOUR SETUP. YOUR CHOICE.",
            72,
            190,
            12,
            COLORS["mint"],
            font="bold",
            tracking=3,
        )
        board.text("Your buff.", 68, 288, 69, font="serif", tracking=-1.6)
        board.text(
            "Your key.", 68, 362, 69, COLORS["gold"], font="serif", tracking=-1.6
        )
        benefits = [
            (
                "1",
                "Keyboard + modifiers",
                ["Use Alt, Ctrl, Shift or Cmd", "with a free keyboard key."],
            ),
            (
                "2",
                "Mouse buttons + wheel",
                [
                    "Choose a middle or extra mouse button,",
                    "or a direction of your mouse wheel.",
                ],
            ),
            (
                "3",
                "Other keys stay protected.",
                ["Occupied keys are rejected.", "Escape cancels without a change."],
            ),
        ]
        start = 430
    else:
        board.text("NEW IN 0.9.0", 72, 181, 12, COLORS["mint"], font="bold", tracking=3)
        board.text("Start in three", 68, 269, 61, font="serif", tracking=-1.6)
        board.text(
            "simple steps.", 68, 335, 61, COLORS["gold"], font="serif", tracking=-1.6
        )
        benefits = [
            (
                "1",
                "Choose your buff key.",
                ["Pick a free key inside the addon.", "No hidden default assignment."],
            ),
            (
                "2",
                "Hover. Press. Bless.",
                [
                    "Mouse over a friendly player.",
                    "Every blessing needs your keypress.",
                ],
            ),
            (
                "3",
                "Make greetings your own.",
                ["Control sending, receiving and", "the display of your own messages."],
            ),
        ]
        start = 411
    for index, (number, title, lines) in enumerate(benefits):
        y = start + index * 103
        element(
            board.root,
            "circle",
            cx=89,
            cy=y + 17,
            r=17,
            fill="none",
            stroke="#d4ba7e",
            stroke_opacity=0.4,
        )
        board.text(
            number, 89, y + 23, 17, COLORS["gold"], font="serif", anchor="middle"
        )
        board.text(title, 123, y + 22, 19)
        board.lines(lines, 123, y + 50, 14, 22, color=COLORS["muted"])
    if keybinding:
        board.text("Open Buffs & Taste → Taste wählen", 72, 752, 13, COLORS["mint"])
        board.text("or enter /fmb bind.", 72, 774, 13, "#a6c4bb")
    else:
        board.text("Always within reach.", 72, 742, 13, COLORS["mint"])
        board.text("Reopen the introduction with /fmb intro.", 72, 764, 13, "#a6c4bb")
    native_preview(board, layouts["capture" if keybinding else "intro"], textures)
    board.common()
    board.save("launch-keybinding-0.9.0" if keybinding else "launch-intro-0.9.0")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fonts-dir", type=Path, default=Path("/System/Library/Fonts/Supplemental")
    )
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(levelname)s: %(message)s",
    )
    html = read_asset("launch-0.9.0.html").decode("utf-8")
    values = {}
    for key in ("layouts", "textures"):
        match = re.search(r"const " + key + r"=(.*?);\n", html, re.DOTALL)
        if not match:
            raise ValueError(f"Required native export missing from HTML: {key}")
        values[key] = json.loads(match[1])
    fonts = {
        name: Font(name, args.fonts_dir / file)
        for name, file in {
            "sans": "Arial.ttf",
            "bold": "Arial Bold.ttf",
            "narrow": "Arial Narrow.ttf",
            "serif": "Georgia.ttf",
        }.items()
    }
    hero(fonts)
    setup_board(fonts, values["layouts"], values["textures"])
    setup_board(fonts, values["layouts"], values["textures"], keybinding=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as failure:
        LOG.error("Artwork generation failed: %s", failure)
        raise SystemExit(1) from failure

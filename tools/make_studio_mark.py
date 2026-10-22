#!/usr/bin/env python3
"""Draws the Clear Prop Games studio mark (a bold propeller over the wordmark) as SVG and writes it where it is used:
  assets/studio_mark.svg   the mark alone, the wordmark alone and both together (for docs and the app icon work)
  web/shell.html           the web loading page, from web/shell.template.html with <!--MARK--> replaced
The wordmark is Fredoka SemiBold turned into outlines (so it never depends on a font loading). Needs fonttools:
  pip install fonttools && python3 tools/make_studio_mark.py"""
import os, io
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
GOLD, GOLD_DARK, INK, BLUE = "#ffc933", "#c98a0b", "#0a1020", "#3d8bff"
NAME = "CLEAR PROP GAMES"

def wordmark(size=64):
    f = TTFont(os.path.join(ROOT, "assets/fonts/Fredoka.ttf"))
    f = instancer.instantiateVariableFont(f, {"wght": 600})
    gs = f.getGlyphSet(); cmap = f.getBestCmap(); upm = f["head"].unitsPerEm
    k = size / upm
    x = 0.0
    paths = []
    for ch in NAME:
        g = cmap[ord(ch)]
        pen = SVGPathPen(gs)
        tp = TransformPen(pen, (k, 0, 0, -k, x, 0))   # flip y: font units point up, SVG down
        gs[g].draw(tp)
        d = pen.getCommands()
        if d:
            paths.append(d)
        x += gs[g].width * k
    return " ".join(paths), x

def mark(cx=100, cy=100):
    blade = "M0 0 C-17 -22 -17 -62 0 -86 C17 -62 17 -22 0 0 Z"
    shine = "M-4 -26 C-8 -40 -8 -56 -3 -68"
    blades = "".join('<g transform="rotate(%d)"><path d="%s" fill="%s" stroke="%s" stroke-width="7" stroke-linejoin="round"/>'
                     '<path d="%s" fill="none" stroke="#fff" stroke-opacity=".55" stroke-width="5" stroke-linecap="round"/></g>' % (a, blade, GOLD, INK, shine) for a in (0, 120, 240))
    spin = '<animateTransform attributeName="transform" type="rotate" from="0" to="360" dur="2.4s" repeatCount="indefinite"/>'
    return ('<g transform="translate(%g %g)"><g class="spin">%s%s'
            '<circle r="17" fill="%s" stroke="%s" stroke-width="7"/><circle r="6" fill="%s"/></g></g>' % (cx, cy, spin, blades, BLUE, INK, GOLD))

def svg_all():
    d, w = wordmark(40)
    pad = 20
    W = w + 2 * pad
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %g %g" width="%g" height="%g">' % (W, 252, W * 1.5, 378)]
    out.append(mark(W / 2, 100))
    out.append('<path transform="translate(%g 234)" d="%s" fill="#fff" stroke="%s" stroke-width="7" stroke-linejoin="round" paint-order="stroke"/>' % (pad, d, INK))
    out.append("</svg>")
    return "".join(out), W

svg, W = svg_all()
open(os.path.join(ROOT, "assets/studio_mark.svg"), "w").write(svg)
tpl = open(os.path.join(ROOT, "web/shell.template.html")).read()
open(os.path.join(ROOT, "web/shell.html"), "w").write(tpl.replace("<!--MARK-->", svg))
print("studio mark written (%d bytes)" % len(svg))

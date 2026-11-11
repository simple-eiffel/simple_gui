# Makes simple_gui's test font: every letter and digit is one plain block, so the file is
# tiny, and its family name is one no system has installed.
import sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

FAMILY = "Simple Gui Test"
out = sys.argv[1]
chars = [chr(c) for c in range(0x30, 0x3A)] + [chr(c) for c in range(0x41, 0x5B)] + [chr(c) for c in range(0x61, 0x7B)]
names = [".notdef", "space", "block"]
fb = FontBuilder(1000, isTTF=True)
fb.setupGlyphOrder(names)
cmap = {0x20: "space"}
for ch in chars:
    cmap[ord(ch)] = "block"
fb.setupCharacterMap(cmap)

def box(x0, y0, x1, y1):
    pen = TTGlyphPen(None)
    pen.moveTo((x0, y0)); pen.lineTo((x0, y1)); pen.lineTo((x1, y1)); pen.lineTo((x1, y0)); pen.closePath()
    return pen.glyph()

empty = TTGlyphPen(None).glyph()
fb.setupGlyf({".notdef": box(100, 0, 500, 700), "space": empty, "block": box(80, 0, 520, 700)})
fb.setupHorizontalMetrics({".notdef": (600, 100), "space": (300, 0), "block": (600, 80)})
fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({"familyName": FAMILY, "styleName": "Regular", "uniqueFontIdentifier": "simple_gui test font 1.0",
                   "fullName": FAMILY, "psName": "SimpleGuiTest-Regular", "version": "Version 1.0",
                   "copyright": "Made for simple_gui's tests. Public domain (CC0)."})
fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200, usWeightClass=400)
fb.setupPost()
fb.save(out)

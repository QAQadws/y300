# /// script
# requires-python = ">=3.12"
# dependencies = ["fonttools==4.60.1"]
# ///
"""Original rectangle glyphs with explicit zero and nonzero font line gaps.

Run `uv run tool/generate_leading_test_fonts.py` from this package. These fonts
are loaded explicitly by tests and are not registered as production assets.
"""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def main():
    target = Path(__file__).resolve().parent.parent / "test/fixtures/fonts"
    target.mkdir(parents=True, exist_ok=True)
    for leading in (0, 400):
        family = f"ForumBodyLeading{leading}"
        widths = {".notdef": 500, "space": 250, "letter": 500}
        builder = FontBuilder(1000, isTTF=True)
        builder.setupGlyphOrder(list(widths))
        builder.setupCharacterMap({32: "space", **{c: "letter" for c in range(65, 91)}})
        glyphs = {}
        for name, width in widths.items():
            pen = TTGlyphPen(None)
            if name != "space":
                pen.moveTo((0, 0))
                pen.lineTo((width, 0))
                pen.lineTo((width, 800))
                pen.lineTo((0, 800))
                pen.closePath()
            glyphs[name] = pen.glyph()
        builder.setupGlyf(glyphs)
        builder.setupHorizontalMetrics({name: (width, 0) for name, width in widths.items()})
        builder.setupHorizontalHeader(ascent=800, descent=-200, lineGap=leading)
        builder.setupNameTable({
            "familyName": family, "styleName": "Regular",
            "uniqueFontIdentifier": family + "-1", "fullName": family,
            "psName": family, "version": "Version 1.0",
            "description": "Original Y300 native leading regression fixture.",
        })
        builder.setupOS2(version=4, sTypoAscender=800, sTypoDescender=-200,
                        sTypoLineGap=leading, usWinAscent=800, usWinDescent=200,
                        fsSelection=0xC0)
        builder.setupPost()
        builder.font["head"].created = builder.font["head"].modified = 2082844800
        builder.font.recalcTimestamp = False
        builder.save(target / f"leading_{leading}.ttf")


if __name__ == "__main__":
    main()

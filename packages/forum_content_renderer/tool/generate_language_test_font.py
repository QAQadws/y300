# /// script
# requires-python = ">=3.12"
# dependencies = ["fonttools==4.60.1"]
# ///
"""Original test-only glyphs with measurable OpenType language substitutions.

Run `uv run tool/generate_language_test_font.py` from this package. The fixture
is loaded explicitly by tests and is never registered as a production asset.
"""
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def rectangle(width):
    pen = TTGlyphPen(None)
    pen.moveTo((0, 0))
    pen.lineTo((width, 0))
    pen.lineTo((width, 800))
    pen.lineTo((0, 800))
    pen.closePath()
    return pen.glyph()


def main():
    family = "ForumBodyLanguageTest"
    widths = {".notdef": 500, "han": 500, "han.jp": 750, "han.kr": 1000,
              "han.ruby": 250, "han.jp.ruby": 375, "han.kr.ruby": 500}
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(list(widths))
    builder.setupCharacterMap({0x6F22: "han"})
    builder.setupGlyf({name: rectangle(width) for name, width in widths.items()})
    builder.setupHorizontalMetrics({name: (width, 0) for name, width in widths.items()})
    builder.setupHorizontalHeader(ascent=800, descent=-200, lineGap=0)
    builder.setupNameTable({
        "familyName": family, "styleName": "Regular",
        "uniqueFontIdentifier": family + "-1", "fullName": family,
        "psName": family, "version": "Version 1.0",
        "description": "Original Y300 native language regression fixture.",
    })
    builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, sTypoLineGap=0,
                    usWinAscent=800, usWinDescent=200)
    builder.setupPost()
    addOpenTypeFeaturesFromString(builder.font, """
        languagesystem DFLT dflt;
        languagesystem hani dflt;
        languagesystem hani JAN;
        languagesystem hani KOR;
        feature locl {
            script hani;
            language JAN;
            sub han by han.jp;
            language KOR;
            sub han by han.kr;
        } locl;
        feature ruby {
            sub han by han.ruby;
            sub han.jp by han.jp.ruby;
            sub han.kr by han.kr.ruby;
        } ruby;
    """)
    builder.font["head"].created = builder.font["head"].modified = 2082844800
    builder.font.recalcTimestamp = False
    target = Path(__file__).resolve().parent.parent / "test/fixtures/fonts/language.ttf"
    target.parent.mkdir(parents=True, exist_ok=True)
    builder.save(target)


if __name__ == "__main__":
    main()

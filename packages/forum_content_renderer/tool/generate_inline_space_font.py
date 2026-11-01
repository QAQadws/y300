# /// script
# requires-python = ">=3.12"
# dependencies = ["fonttools==4.60.1"]
# ///
"""Generate the renderer's original blank layout font (SPACE/NBSP plus WJ).

Run with `uv run tool/generate_inline_space_font.py` from this package.
No downloaded typeface or third-party glyph is included in the generated asset.
"""
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def main():
    family = "ForumBodyInlineSpace"
    # A larger em avoids Android's native font-size quantization changing tiny
    # system-font advances. The renderer uses fontSize = logicalWidth * 1024;
    # glyph/vertical bounds stay zero even for large logical whitespace.
    builder = FontBuilder(1024, isTTF=True)
    builder.setupGlyphOrder([".notdef", "space", "joiner"])
    builder.setupCharacterMap({32: "space", 0xA0: "space", 0x2060: "joiner"})
    builder.setupGlyf({name: TTGlyphPen(None).glyph() for name in [".notdef", "space", "joiner"]})
    builder.setupHorizontalMetrics({".notdef": (0, 0), "space": (1, 0), "joiner": (0, 0)})
    builder.setupHorizontalHeader(ascent=0, descent=0, lineGap=0)
    builder.setupNameTable({
        "familyName": family,
        "styleName": "Regular",
        "uniqueFontIdentifier": family + "-3",
        "fullName": family,
        "psName": family,
        "version": "Version 3.0",
        "description": "Y300 internal layout resource. Blank SPACE/NBSP and zero-advance WJ.",
    })
    builder.setupOS2(sTypoAscender=0, sTypoDescender=0, sTypoLineGap=0,
                    usWinAscent=0, usWinDescent=0)
    builder.setupPost()
    # Rebuilds must not introduce a new binary merely because time has passed.
    builder.font["head"].created = builder.font["head"].modified = 2082844800
    builder.font.recalcTimestamp = False
    target = Path(__file__).resolve().parent.parent / "assets/fonts/inline_space.ttf"
    target.parent.mkdir(parents=True, exist_ok=True)
    builder.save(target)


if __name__ == "__main__":
    main()

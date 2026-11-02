# Native font fixtures

`language.ttf` contains original rectangle glyphs and no third-party font data.
It is test-only, loaded explicitly with FontLoader, and is not a production asset.

Regenerate from this package with:

```powershell
uv run tool/generate_language_test_font.py
```

The generator pins fonttools and fixes timestamps. At 20 logical pixels U+6F22
has advance 10 by default, 15 for OpenType `hani/JAN`, and 20 for `hani/KOR`.
These distinct native `locl` results verify that inherited and overridden
TextStyle locales actually reach shaping, including band children and pagination.
Tests also verify an explicit unknown language clears an inherited Japanese
locale. Matching a Locale value alone would not prove the native behavior.

`leading_0.ttf` and `leading_400.ttf` contain original rectangle glyphs for ASCII
capitals and an empty SPACE. Regenerate with
`uv run tool/generate_leading_test_fonts.py`. They use identical 1000-unit em,
800 ascent, 200 descent and glyph advances, but zero versus 400 units of font
line gap. Hhea and OS/2 v4 typo metrics agree, with USE_TYPO_METRICS enabled.
These test-only inputs exercise native normal height, mixed sizes and stable
local baselines near a half-pixel threshold in long paragraphs.

`language.ttf`'s optional `ruby` feature halves its language glyph advances. Source-free
emphasis mark tests use it to prove that the actual native font feature and
locale both reach shaping at half the original font size. Ordinary language
tests retain their original widths while `ruby` is disabled.

# Native language fixture

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

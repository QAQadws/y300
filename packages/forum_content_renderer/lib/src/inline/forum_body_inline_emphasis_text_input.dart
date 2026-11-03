part of 'forum_body_emphasis_text_input.dart';

/// Parent-only targets in the exact original mixed projection. Ruby/base/RT
/// windows remain with their actual child formats, never parent marker units.
final class ForumBodyInlineEmphasisTextInput {
  ForumBodyInlineEmphasisTextInput._(
    this.glyphInput,
    List<ForumBodyEmphasisTextUnit> units,
  ) : units = UnmodifiableListView(units);
  static const revision = 1;
  final ForumBodyInlineEmphasisGlyphInput glyphInput;
  ForumBodyInlineSpanContent get content => glyphInput.original;
  final List<ForumBodyEmphasisTextUnit> units;

  /// Actual parent and marker font sizes only. A containing format must also
  /// include its real child fonts before freezing the shared nonlinear scaler.
  Iterable<double> get nativeFontSizes sync* {
    yield glyphInput.glyphs.style.textStyle.fontSize!;
    for (final run in glyphInput.glyphs.parentRuns) {
      yield run.style.textStyle.fontSize!;
    }
    for (final unit in units) {
      yield ForumBodyEmphasisMarkInput.resolveFontSize(
        content.runs[unit.runIndex].style.textStyle,
      );
    }
  }
}

/// Whole-projection Unicode targets over a qualified parent glyph derivation.
/// Every scan unit checks its current owner; results retain no callbacks/cache.
final class ForumBodyInlineEmphasisTextPreparation {
  ForumBodyInlineEmphasisTextPreparation({
    required ForumBodyInlineSpanContent content,
    required void Function() ensureOwner,
    int maxUnits = 512,
  }) : this._(content, null, ensureOwner, maxUnits);

  ForumBodyInlineEmphasisTextPreparation.fromGlyphInput({
    required ForumBodyInlineEmphasisGlyphInput glyphInput,
    required void Function() ensureOwner,
    int maxUnits = 512,
  }) : this._(glyphInput.original, glyphInput, ensureOwner, maxUnits);

  ForumBodyInlineEmphasisTextPreparation._(
    ForumBodyInlineSpanContent content,
    ForumBodyInlineEmphasisGlyphInput? glyphInput,
    void Function() ensureOwner,
    this.maxUnits,
  ) : _glyphInput = glyphInput,
      _ensureOwner = ensureOwner {
    if (maxUnits < 0) throw ArgumentError.value(maxUnits);
    _targets = _EmphasisTargetPreparation(
      projection: content.projection.display,
      runs: content.runs,
      path: content.path,
      maxUnits: maxUnits,
      inline: content.projection,
    );
    if (glyphInput == null) {
      _glyphPreparation = ForumBodyInlineEmphasisGlyphPreparation(
        content: content,
        ensureOwner: _guard,
      );
    }
  }
  final int maxUnits;
  ForumBodyInlineEmphasisGlyphPreparation? _glyphPreparation;
  ForumBodyInlineEmphasisGlyphInput? _glyphInput;
  _EmphasisTargetPreparation? _targets;
  void Function()? _ensureOwner;
  ForumBodyInlineEmphasisTextInput? _result;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline emphasis text is reentrant');
    _operating = true;
    try {
      _guard();
      var used = 0;
      while (!isReady && used < maxParts) {
        if (_glyphInput == null) {
          final glyphs = _glyphPreparation!;
          used += glyphs.advance(maxParts: maxParts - used);
          _guard();
          if (glyphs.isReady) {
            _glyphInput = glyphs.takeInput();
            _glyphPreparation = null;
          }
        } else {
          // The shared pure scanner has no callbacks. Advance one unit here so
          // owner retirement is checked around each scalar/part/interval.
          used += _targets!.advance(maxParts: 1);
          _guard();
          if (_targets!.isReady) {
            _result = ForumBodyInlineEmphasisTextInput._(
              _glyphInput!,
              _targets!.takeUnits(),
            );
            _targets = null;
            _glyphInput = null;
          }
        }
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyInlineEmphasisTextInput takeInput() {
    if (_operating) throw StateError('Inline emphasis text is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Inline emphasis text is incomplete');
      final result = _result!;
      close();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_closed) throw StateError('Inline emphasis text is retired');
    _ensureOwner!();
    if (_closed) throw StateError('Inline emphasis text owner is retired');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _glyphPreparation?.close();
    _glyphPreparation = null;
    _glyphInput = null;
    _targets?.close();
    _targets = null;
    _ensureOwner = null;
    _result = null;
  }
}

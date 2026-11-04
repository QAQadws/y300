part of 'forum_body_inline_span_content.dart';

/// Explicit original/glyph association for a mixed parent's ordinary text.
/// Child windows/inputs and all display/engine mappings keep original identity;
/// suppression is not a complete decoration, visible source or owner proof.
final class ForumBodyInlineEmphasisGlyphInput {
  const ForumBodyInlineEmphasisGlyphInput._(this.original, this.glyphs);
  static const revision = 1;
  final ForumBodyInlineSpanContent original, glyphs;
  int get extraRuns =>
      identical(original.runs, glyphs.runs) ? 0 : glyphs.runs.length;
}

/// One root style, parent piece, skipped source part or run per unit. No text
/// flattening, grapheme splitting, native layout or child request rewriting.
final class ForumBodyInlineEmphasisGlyphPreparation {
  ForumBodyInlineEmphasisGlyphPreparation({
    required ForumBodyInlineSpanContent content,
    required void Function() ensureOwner,
    int maxRuns = 512,
  }) : _original = content,
       _ensureOwner = ensureOwner,
       _cursor = _InlineParentCursor(content.projection) {
    if (maxRuns < 0) throw ArgumentError.value(maxRuns);
    if (content.paintLayer != ForumBodyParagraphPaintLayer.all) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.structure,
        content.path,
      );
    }
    if (content.runs.length > maxRuns) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.runLimit,
        content.path,
      );
    }
  }
  ForumBodyInlineSpanContent? _original;
  void Function()? _ensureOwner;
  _InlineParentCursor? _cursor;
  ForumBodyResolvedStyle? _style;
  Set<int>? _parentRuns = {};
  List<ForumBodyParagraphRun>? _runs = [];
  ForumBodyInlineEmphasisGlyphInput? _result;
  int _index = 0;
  bool _changed = false, _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline glyph preparation is reentrant');
    _operating = true;
    try {
      _guard();
      var used = 0;
      while (!isReady && used < maxParts) {
        final original = _original!;
        if (_style == null) {
          _style = _glyphStyle(original.style);
          _changed = !identical(original.style, _style);
        } else if (_cursor case final cursor?) {
          if (cursor.isComplete) {
            _cursor = null;
          } else if (cursor.advance()?.runIndex case final index?) {
            _parentRuns!.add(index);
          }
        } else if (_index < original.runs.length) {
          final index = _index++, run = original.runs[index];
          final style = _parentRuns!.contains(index)
              ? _glyphStyle(run.style)
              : run.style;
          final changed = !identical(run.style, style);
          _changed |= changed;
          _runs!.add(changed ? ForumBodyParagraphRun(run.path, style) : run);
        } else {
          _result = ForumBodyInlineEmphasisGlyphInput._(
            original,
            _changed
                ? ForumBodyInlineSpanContent._emphasisGlyphs(
                    original,
                    _style!,
                    _runs!,
                  )
                : original,
          );
          _runs = null;
          _original = null;
          _style = null;
          _parentRuns = null;
        }
        used++;
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

  ForumBodyResolvedStyle _glyphStyle(ForumBodyResolvedStyle style) =>
      style.textEmphasis.isEnabled
      ? style.withTextEmphasis(const ForumBodyTextEmphasis())
      : style;

  ForumBodyInlineEmphasisGlyphInput takeInput() {
    if (_operating) throw StateError('Inline glyph preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Inline glyph input is incomplete');
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
    if (_closed) throw StateError('Inline glyph preparation is retired');
    _ensureOwner!();
    if (_closed) throw StateError('Inline glyph owner is retired');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _original = null;
    _ensureOwner = null;
    _cursor = null;
    _style = null;
    _parentRuns = null;
    _runs = null;
    _result = null;
  }
}

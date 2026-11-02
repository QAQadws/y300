part of 'forum_body_paragraph_content.dart';

/// Explicit derivation for the decorated format's base glyphs. Original text,
/// projection and native font inputs remain intact; only active emphasis flags
/// are suppressed in [glyphs]. This is not a live source/owner qualification.
final class ForumBodyEmphasisGlyphInput {
  const ForumBodyEmphasisGlyphInput._(this.original, this.glyphs);
  static const revision = 1;
  final ForumBodyParagraphContent original;
  final ForumBodyParagraphContent glyphs;

  /// Derive both sides from the same legal display window. Source/run identity
  /// and the already suppressed glyph styles are retained without preparing
  /// the full style table again or shaping any row in isolation.
  ForumBodyEmphasisGlyphInput displayWindow({
    required int startUtf16,
    required int endUtf16,
    bool? appliesFirstLineIndent,
  }) {
    final source = original.displayWindow(
      startUtf16: startUtf16,
      endUtf16: endUtf16,
      appliesFirstLineIndent: appliesFirstLineIndent,
    );
    return ForumBodyEmphasisGlyphInput._(
      source,
      identical(original, glyphs)
          ? source
          : ForumBodyParagraphContent._emphasisGlyphs(
              source,
              glyphs.style,
              glyphs.runs,
            ),
    );
  }
}

/// One root or run style per work unit; no shaping, parsing, source splitting,
/// marker insertion or implicit draining of the entire style table.
final class ForumBodyEmphasisGlyphPreparation {
  ForumBodyEmphasisGlyphPreparation({
    required ForumBodyParagraphContent content,
    int maxRuns = 512,
  }) : _original = content {
    if (maxRuns < 0) throw ArgumentError.value(maxRuns);
    if (content.isSourceFree) {
      throw ArgumentError('Emphasis base requires actual source text');
    }
    if (content.runs.length > maxRuns) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.runLimit,
        content.path,
      );
    }
  }
  ForumBodyParagraphContent? _original;
  ForumBodyResolvedStyle? _style;
  List<ForumBodyParagraphRun>? _runs = [];
  ForumBodyEmphasisGlyphInput? _result;
  int _index = 0;
  bool _changed = false, _closed = false;
  bool get isReady => _result != null;

  ForumBodyResolvedStyle _glyphStyle(ForumBodyResolvedStyle style) =>
      style.textEmphasis.isEnabled
      ? style.withTextEmphasis(const ForumBodyTextEmphasis())
      : style;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_closed) throw StateError('Emphasis glyph input is retired');
    var used = 0;
    try {
      while (used < maxParts && !isReady) {
        final original = _original!;
        if (_style == null) {
          _style = _glyphStyle(original.style);
          _changed = !identical(_style, original.style);
        } else if (_index < original.runs.length) {
          final run = original.runs[_index++];
          final style = _glyphStyle(run.style);
          final changed = !identical(style, run.style);
          _changed |= changed;
          _runs!.add(changed ? ForumBodyParagraphRun(run.path, style) : run);
        } else {
          final runs = _runs!;
          _runs = null;
          _result = ForumBodyEmphasisGlyphInput._(
            original,
            _changed
                ? ForumBodyParagraphContent._emphasisGlyphs(
                    original,
                    _style!,
                    runs,
                  )
                : original,
          );
          _original = null;
          _style = null;
        }
        used++;
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    }
  }

  ForumBodyEmphasisGlyphInput takeInput() {
    if (_closed) throw StateError('Emphasis glyph input is retired');
    if (!isReady) throw StateError('Emphasis glyph input is incomplete');
    final result = _result!;
    close();
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _original = null;
    _style = null;
    _runs = null;
    _result = null;
  }
}

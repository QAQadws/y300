import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import 'forum_body_emphasis_text_input.dart';

/// Explicit original emphasis -> whole glyph parent -> actual row derivation.
/// Pure source and numeric metadata only; live source/font qualification still
/// requires the current row view, its exact metrics and actual parent handle.
final class ForumBodyEmphasisRowInput {
  const ForumBodyEmphasisRowInput._(this.parentGlyphInput, this.row, this.text);
  static const revision = 1;
  final ForumBodyEmphasisGlyphInput parentGlyphInput;
  final ForumBodyParagraphRowMetrics row;
  final ForumBodyEmphasisTextInput text;
  ForumBodyParagraphContent get content => text.content;
}

/// Prepares only the requested actual row's original complete graphemes. The
/// whole glyph style derivation is reused, not rebuilt or filtered from a
/// retained chapter-wide list of mark targets.
final class ForumBodyEmphasisRowInputPreparation {
  ForumBodyEmphasisRowInputPreparation({
    required ForumBodyEmphasisGlyphInput parentGlyphInput,
    required ForumBodyParagraphRowMetrics row,
    this.maxUnits = 512,
  }) : _parent = parentGlyphInput,
       _row = row {
    if (maxUnits < 0) throw ArgumentError.value(maxUnits);
    if (!identical(parentGlyphInput.glyphs, row.parentContent)) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        row.parentContent.path,
      );
    }
  }
  final int maxUnits;
  ForumBodyEmphasisGlyphInput? _parent;
  ForumBodyParagraphRowMetrics? _row;
  ForumBodyEmphasisTextPreparation? _text;
  ForumBodyEmphasisRowInput? _result;
  bool _closed = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_closed) throw StateError('Emphasis row source is retired');
    var used = 0;
    try {
      while (used < maxParts && !isReady) {
        final job = _text;
        if (job == null) {
          final row = _row!;
          final glyphs = _parent!.displayWindow(
            startUtf16: row.startUtf16,
            endUtf16: row.endUtf16,
            appliesFirstLineIndent: row.content.appliesFirstLineIndent,
          );
          _text = ForumBodyEmphasisTextPreparation.fromGlyphInput(
            glyphInput: glyphs,
            maxUnits: maxUnits,
          );
          used++;
        } else if (!job.isReady) {
          used += job.advance(maxParts: maxParts - used);
        } else {
          _result = ForumBodyEmphasisRowInput._(
            _parent!,
            _row!,
            job.takeInput(),
          );
          _text = null;
          used++;
        }
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    }
  }

  ForumBodyEmphasisRowInput takeInput() {
    if (_closed) throw StateError('Emphasis row source is retired');
    if (!isReady) throw StateError('Emphasis row source is incomplete');
    final result = _result!;
    close();
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _text?.close();
    _text = null;
    _parent = null;
    _row = null;
    _result = null;
  }
}

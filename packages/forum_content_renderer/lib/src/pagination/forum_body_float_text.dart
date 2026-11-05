part of 'forum_body_text_page_session.dart';

/// One source paragraph consuming native line groups across physical bands.
/// A band uses the full unconsumed projection so its last visible row has
/// the same native wrapping and justification as the rest of that layout.
final class _FloatTextAdmission {
  _FloatTextAdmission(
    this._session,
    this._content,
    this._window, {
    required this.left,
    required this.width,
  });

  final ForumBodyTextPageSession _session;
  ForumBodyParagraphContent _content;
  ForumBodyParagraphWindow _window;
  final double left, width;
  ForumBodyFloatLineBand? _band;
  ForumBodyEmphasisPageAdmission? _plan;
  int? _inputIndex;
  bool isComplete = false;

  ({bool waiting, int lines}) advance({
    required int maxLines,
    required int maxFormatParts,
  }) {
    final composer = _session._composer;
    final band = _band ??= composer.nextFloatTextBand(
      left: left,
      width: width,
      spaceBefore: _session._margin,
    );
    final reduced = band.bottom.isFinite;
    if (_inputIndex == null) {
      if (reduced && band.width <= 2 * _content.horizontalInset) {
        _skipBand(band);
        return (waiting: false, lines: 0);
      }
      final plan = _plan ??= _session._openParagraphPlan(_content, band.width);
      try {
        final step = plan.advance(maxParts: maxFormatParts);
        if (!plan.isReady) {
          return (waiting: step.waitingForLayoutBudget, lines: 0);
        }
      } on ForumBodyParagraphLayoutException catch (error) {
        if (!reduced ||
            (error.failure != ForumBodyParagraphLayoutFailure.width &&
                error.failure != ForumBodyParagraphLayoutFailure.indent)) {
          rethrow;
        }
        plan.close();
        _plan = null;
        _skipBand(band);
        return (waiting: false, lines: 0);
      }
      _inputIndex = _session._content.items.length;
      _session._appendParagraphPlan(
        plan,
        left: band.left,
        spaceBefore: band.spaceBefore,
        window: _window,
      );
      _session._margin = 0;
      _plan = null;
    }
    final step = composer.advance(
      maxLines: maxLines,
      floatBandBottom: reduced ? band.bottom : null,
    );
    if (step.paragraphCompleted) {
      isComplete = true;
    } else if (reduced) {
      final pageSealed = step.pagesPublished != 0;
      final end = composer.retireFloatTextBand(
        bottom: band.bottom,
        pageSealed: pageSealed,
      );
      if (end != null) {
        final cut = end.endUtf16;
        if (cut == null) {
          _session._content.retain(_inputIndex!);
        } else if (cut == _content.projection.text.length) {
          // A full layout can leave only the source-free row after its final
          // hard break. Preserve that row's actual native window.
          _window = ForumBodyParagraphWindow.terminalEmptyLine;
        } else {
          _content = _content.displayWindow(
            startUtf16: cut,
            endUtf16: _content.projection.text.length,
            appliesFirstLineIndent: false,
          );
        }
        _inputIndex = null;
        _band = null;
        if (end.blocked && !pageSealed) _skipBand(band);
      }
    }
    return (waiting: false, lines: step.linesInspected);
  }

  void _skipBand(ForumBodyFloatLineBand band) {
    _session._composer.moveBelowFloatTextBand(band.bottom);
    _session._margin = 0;
    _band = null;
  }

  void close() {
    _plan?.close();
    _plan = null;
  }
}

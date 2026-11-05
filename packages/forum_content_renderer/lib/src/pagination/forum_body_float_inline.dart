part of 'forum_body_text_page_session.dart';

/// A mixed inline run follows the same physical bands as ordinary text. The
/// prepared source plan can restart after an exact engine line edge without
/// reparsing ruby or resolving an image a second time.
final class _FloatInlineAdmission {
  _FloatInlineAdmission(
    this._session,
    this._flow,
    this._window, {
    required this.left,
    required this.width,
    _HeldFloatInline? prefix,
    this.holdLastLine = false,
  }) : _prefix = prefix;

  final ForumBodyTextPageSession _session;
  ForumBodyInlineFlowContent? _flow;
  ForumBodyParagraphWindow _window;
  final double left, width;
  final bool holdLastLine;
  _HeldFloatInline? _prefix;
  ForumBodyInlinePlanInput? _source;
  int? _engineCut;
  ForumBodyFloatLineBand? _band;
  ForumBodyInlinePageAdmission? _plan;
  ({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})?
  _ready;
  ForumBodyInlineNativeEntriesPreparation? _entries;
  int? _inputIndex;
  bool isComplete = false;
  _HeldFloatInline? held;

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
      if (reduced && band.width <= 0) {
        _skipBand(band);
        return (waiting: false, lines: 0);
      }
      if (_ready == null) {
        try {
          final plan = _plan ??= ForumBodyInlinePageAdmission(
            input: _flow,
            prefix: _prefix?.source.remainingAt(
              width: band.width,
              engineEndUtf16: _prefix?.engineCut,
            ),
            keepTrailingSpace: holdLastLine,
            continuation: _source?.remainingAt(
              width: band.width,
              engineEndUtf16: _engineCut,
            ),
            width: band.width,
            cache: _session._cache,
            textScaler: _session._textScaler,
            ensureOwner: _session._ensureActivePlan,
            validateCounts: _session._content.checkCounts,
          );
          final step = plan.advance(maxParts: maxFormatParts);
          if (!step.isReady) {
            return (waiting: step.waitingForLayoutBudget, lines: 0);
          }
          _source = plan.readySource;
          _engineCut = null;
          _flow = null;
          _prefix = null;
          final ready = _ready = plan.take();
          _plan = null;
          if (!identical(_source!.content, ready.content.content)) {
            throw StateError(
              'Inline continuation source does not match the native plan',
            );
          }
          if (composer.maxNativeEntriesPerPage != null ||
              composer.maxNativeEstimatedBytesPerPage != null) {
            _entries = ForumBodyInlineNativeEntriesPreparation(
              input: ready.content,
              parent: ready.lease,
              cache: _session._cache,
              textScaler: _session._textScaler,
              ensureOwner: _session._ensureActivePlan,
            );
            return (waiting: false, lines: 0);
          }
        } on ForumBodyParagraphLayoutException catch (error) {
          if (!reduced ||
              (error.failure != ForumBodyParagraphLayoutFailure.width &&
                  error.failure != ForumBodyParagraphLayoutFailure.indent)) {
            rethrow;
          }
          _plan?.close();
          _plan = null;
          _skipBand(band);
          return (waiting: false, lines: 0);
        }
      }
      ForumBodyInlineNativeEntries? entries;
      if (_entries case final work?) {
        work.advance(maxParts: maxFormatParts);
        if (!work.isReady) return (waiting: false, lines: 0);
        entries = work.take();
        _entries = null;
      }
      final ready = _ready!;
      _ready = null;
      _inputIndex = _session._content.items.length;
      _session._appendInlinePlan(
        ready,
        entries,
        left: band.left,
        spaceBefore: band.spaceBefore,
        window: _window,
      );
      _session._margin = 0;
    }

    final step = composer.advance(
      maxLines: maxLines,
      floatBandBottom: reduced ? band.bottom : null,
      holdFloatLineInset: holdLastLine
          ? _source!.content.horizontalInset
          : null,
    );
    if (step.paragraphCompleted) {
      isComplete = true;
    } else if (reduced || holdLastLine) {
      final sealed = step.pagesPublished != 0;
      final end = composer.retireFloatTextBand(
        bottom: band.bottom,
        pageSealed: reduced && sealed,
      );
      if (end != null) {
        final cut = end.engineEndUtf16;
        if (cut == null) {
          _session._content.retain(_inputIndex!);
        } else if (cut ==
            _source!.content
                .projectionForLayout(_source!.layoutMode)
                .engineText
                .length) {
          _engineCut = null;
          _window = ForumBodyParagraphWindow.terminalEmptyLine;
        } else {
          _engineCut = cut;
        }
        _inputIndex = null;
        _band = null;
        if (end.heldLine case final line?) {
          _session._margin = line.spaceBefore;
          held = _HeldFloatInline(_source!, _engineCut, _window, line);
          isComplete = true;
        }
        if (end.blocked && !sealed) _skipBand(band);
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
    _entries?.close();
    _entries = null;
    _ready?.lease.release();
    _ready = null;
  }
}

part of 'forum_body_text_page_session.dart';

typedef ForumBodySelectionChunk = ({
  String? path,
  int sourceStart,
  int sourceEnd,
  String text,
});

/// A bounded copy over a fixed prefix of one live layout. An unproved or
/// retired range has no result. No partial text is observable during copying.
final class ForumBodySelectionCopyCursor {
  ForumBodySelectionCopyCursor._(
    this._session,
    this._range,
    this._chunks,
    this._maxCodeUnits,
    this._remainingWork,
  );

  ForumBodyTextPageSession? _session;
  Iterator<ForumBodySelectionChunk?>? _chunks;
  final ForumBodySourceRange? _range;
  final int _maxCodeUnits;
  int _remainingWork;
  int _codeUnits = 0;
  final _accepted = <ForumBodySelectionChunk>[];
  String? _text;

  bool get isDone => _chunks == null;
  String? get text => _text;

  void advance({required int maxWork}) {
    if (maxWork <= 0) throw ArgumentError.value(maxWork);
    final chunks = _chunks;
    if (chunks == null) return;
    final session = _session!;
    if (session.isClosed || session.isLayoutOwnerRetired) {
      close();
      return;
    }
    for (var step = 0; step < maxWork; step++) {
      if (!chunks.moveNext()) {
        _finish();
        return;
      }
      if (--_remainingWork < 0) {
        close();
        return;
      }
      final chunk = chunks.current;
      if (chunk == null) continue;
      _codeUnits += chunk.text.length;
      if (_codeUnits > _maxCodeUnits) {
        close();
        return;
      }
      _accepted.add(chunk);
    }
  }

  void _finish() {
    // A float or table cell may be laid out independently of source order.
    _accepted.sort((a, b) => a.sourceStart.compareTo(b.sourceStart));
    final range = _range;
    if (_accepted.isEmpty ||
        (range != null &&
            (_accepted.first.sourceStart != range.startRune ||
                _accepted.last.sourceEnd != range.endRune))) {
      close();
      return;
    }
    final result = StringBuffer();
    ForumBodySelectionChunk? previous;
    for (final chunk in _accepted) {
      if (previous != null) {
        if (chunk.sourceStart < previous.sourceEnd) {
          close();
          return;
        }
        if (previous.path != chunk.path &&
            !previous.text.endsWith('\n') &&
            !chunk.text.startsWith('\n')) {
          _codeUnits++;
          result.writeln();
        }
      }
      result.write(chunk.text);
      previous = chunk;
    }
    close();
    if (_codeUnits <= _maxCodeUnits) _text = result.toString();
  }

  void close() {
    _session = null;
    _chunks = null;
    _accepted.clear();
    _text = null;
  }
}

// Kept internal to the renderer. Table areas delegate through this same walk
// so their retained cell projections use the outer copy's single work budget.
extension ForumBodySelectionChunkSource on ForumBodyTextPageSession {
  Iterable<ForumBodySelectionChunk?> selectionChunks(
    ForumBodyTextPageSnapshot prefix,
    ForumBodySourceRange range,
  ) sync* {
    bool intersects(int start, int end) =>
        start < range.endRune && range.startRune < end;

    for (final page in prefix) {
      yield null;
      for (final fragment in page.fragments) {
        yield null;
        final hint = fragment.sourceHint;
        if (hint == null || !intersects(hint.runeStart, hint.runeEnd)) continue;
        final body = _content.items[fragment.paragraphIndex].bodyContent;
        final text = switch (body) {
          ForumBodyParagraphPageContent(:final content) ||
          ForumBodyEmphasisPageContent(
            :final content,
          ) => (content.projection, content.runs),
          ForumBodyFittedEmphasisPageContent(:final plan) => (
            plan.content.projection,
            plan.content.runs,
          ),
          ForumBodyInlinePageContent(:final content) => (
            content.projection.display,
            content.runs,
          ),
          ForumBodyImagePageContent() || ForumBodyListItemPageContent() => null,
        };
        if (text == null) continue;
        final (projection, runs) = text;
        final visible = forumBodyVisibleTextRanges(
          projection,
          runs,
          fragment.coverageStartUtf16,
          fragment.coverageEndUtf16,
          includeAnnotations: false,
        )!;
        for (final window in visible) {
          yield null;
          for (final span in projection.displayRangesInSource(
            sourceStart: range.startRune,
            sourceEnd: range.endRune,
            startUtf16: window.start,
            endUtf16: window.end,
          )) {
            final source = projection.sourceEnvelope(
              startUtf16: span.startUtf16,
              endUtf16: span.endUtf16,
            )!;
            yield (
              path: fragment.path,
              sourceStart: source.runeStart,
              sourceEnd: source.runeEnd,
              text: projection.text.substring(span.startUtf16, span.endUtf16),
            );
          }
        }
      }
      for (final frame in page.tableFrames) {
        yield null;
        if (!intersects(
          frame.sourceRange.runeStart,
          frame.sourceRange.runeEnd,
        )) {
          continue;
        }
        final table = _tables[(page.index, frame.path)]!;
        for (final area in table.captions.followedBy(table.cells)) {
          yield null;
          final source = area.element.source;
          if (intersects(source.runeStart, source.runeEnd)) {
            yield* area.selectionChunks(range);
          }
        }
      }
    }
  }
}

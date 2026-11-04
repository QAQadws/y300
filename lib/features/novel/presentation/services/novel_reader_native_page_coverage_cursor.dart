import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../models/novel_reader_native_anchor_map.dart';
import '../models/novel_reader_native_page_coverage.dart';

enum NovelReaderNativeCoverageState { active, complete, failed, closed }

enum NovelReaderNativeCoverageFailure { identity, budget, retired }

final class NovelReaderNativeCoverageException implements Exception {
  const NovelReaderNativeCoverageException(this.failure);
  final NovelReaderNativeCoverageFailure failure;
  @override
  String toString() => 'NovelReaderNativeCoverageException(${failure.name})';
}

final class NovelReaderNativeCoverageLimits {
  const NovelReaderNativeCoverageLimits({
    this.maxFragments = 256,
    this.maxGraphemes = 16384,
    this.maxPoints = 8192,
  });
  final int maxFragments;
  final int maxGraphemes;
  final int maxPoints;
}

final class NovelReaderNativeCoverageStep {
  const NovelReaderNativeCoverageStep(
    this.graphemesChecked,
    this.fragmentsCompleted,
    this.isComplete,
  );
  final int graphemesChecked;
  final int fragmentsCompleted;
  final bool isComplete;
  bool get madeProgress =>
      graphemesChecked > 0 || fragmentsCompleted > 0 || isComplete;
}

/// Borrows a prepared page's live leases; never shapes, acquires or releases
/// them. Partial proof stays private. Terminal cursors drop all owner/native
/// references. The caller schedules advances outside Widget build.
final class NovelReaderNativePageCoverageCursor {
  factory NovelReaderNativePageCoverageCursor({
    required NovelReaderNativeAnchorMap anchors,
    required ForumBodyTextPageSnapshot snapshot,
    required int pageIndex,
    required String layoutId,
    required List<ForumBodyParagraphLease> leases,
    NovelReaderNativeCoverageLimits limits =
        const NovelReaderNativeCoverageLimits(),
  }) {
    validateForumBodyTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      leases: leases,
    );
    return NovelReaderNativePageCoverageCursor.prepared(
      anchors: anchors,
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      fragments: [
        for (final (index, lease) in leases.indexed)
          ForumBodyPreparedTextFragment.paragraph(
            lease: lease,
            startLine: snapshot[pageIndex].fragments[index].startLine,
            endLine: snapshot[pageIndex].fragments[index].endLine,
          ),
      ],
      limits: limits,
    );
  }

  factory NovelReaderNativePageCoverageCursor.prepared({
    required NovelReaderNativeAnchorMap anchors,
    required ForumBodyTextPageSnapshot snapshot,
    required int pageIndex,
    required String layoutId,
    required List<ForumBodyPreparedTextFragment> fragments,
    NovelReaderNativeCoverageLimits limits =
        const NovelReaderNativeCoverageLimits(),
  }) {
    if (limits.maxFragments < 0 ||
        limits.maxGraphemes < 0 ||
        limits.maxPoints < 0) {
      throw ArgumentError('Invalid native coverage limits');
    }
    if (anchors.identity != snapshot.identity) {
      _fail(NovelReaderNativeCoverageFailure.identity);
    }
    if (snapshot[pageIndex].itemCount > limits.maxFragments) {
      _fail(NovelReaderNativeCoverageFailure.budget);
    }
    validateForumBodyPreparedTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      fragments: fragments,
    );
    return NovelReaderNativePageCoverageCursor._(
      anchors,
      snapshot,
      pageIndex,
      layoutId,
      List.unmodifiable(fragments),
      limits,
    );
  }

  NovelReaderNativePageCoverageCursor._(
    this._anchors,
    this._snapshot,
    this.pageIndex,
    this.layoutId,
    this._fragments,
    this.limits,
  );

  NovelReaderNativeAnchorMap? _anchors;
  ForumBodyTextPageSnapshot? _snapshot;
  List<ForumBodyPreparedTextFragment> _fragments;
  final int pageIndex;
  final String layoutId;
  final NovelReaderNativeCoverageLimits limits;
  final _points = <NovelReaderNativeCoveragePoint>[];
  NovelReaderNativeCoverageState _state = NovelReaderNativeCoverageState.active;
  NovelReaderNativePageCoverage? _result;
  int _fragmentIndex = 0;
  int _graphemes = 0;
  bool _hasClippedGlyphs = false;
  Iterator<({int startUtf16, int endUtf16})>? _ranges;
  ForumBodyPreparedTextFragment? _fragment;
  HtmlDisplayTextProjection? _projection;
  List<ForumBodyParagraphRun> _runs = const [];
  Rect _clip = Rect.zero;

  NovelReaderNativeCoverageState get state => _state;
  int get checkedGraphemes => _graphemes;
  NovelReaderNativePageCoverage get result =>
      _state == NovelReaderNativeCoverageState.complete
      ? _result!
      : throw StateError('Native page coverage is not complete');

  NovelReaderNativeCoverageStep advance({
    required int maxGraphemes,
    required int maxFragments,
  }) {
    if (_state != NovelReaderNativeCoverageState.active) {
      throw StateError('Native coverage cursor is retired');
    }
    if (maxGraphemes <= 0 || maxFragments <= 0) {
      throw ArgumentError('Native coverage work budgets must be positive');
    }
    var checked = 0;
    var fragments = 0;
    try {
      _ensureLive();
      final page = _snapshot![pageIndex];
      while (checked < maxGraphemes && fragments < maxFragments) {
        if (_fragmentIndex == page.fragments.length) {
          _finish();
          break;
        }
        _ranges ??= _openFragment(page.fragments[_fragmentIndex]);
        if (!_ranges!.moveNext()) {
          _fragmentIndex++;
          fragments++;
          _ranges = null;
          _fragment = null;
          _projection = null;
          _runs = const [];
          continue;
        }
        if (_graphemes >= limits.maxGraphemes) {
          _fail(NovelReaderNativeCoverageFailure.budget);
        }
        _graphemes++;
        checked++;
        final range = _ranges!.current;
        _includeGrapheme(range.startUtf16, range.endUtf16);
      }
      if (_fragmentIndex == page.fragments.length &&
          _state == NovelReaderNativeCoverageState.active) {
        _finish();
      }
      return NovelReaderNativeCoverageStep(
        checked,
        fragments,
        _state == NovelReaderNativeCoverageState.complete,
      );
    } catch (_) {
      _state = NovelReaderNativeCoverageState.failed;
      _dropBorrowed();
      rethrow;
    }
  }

  Iterator<({int startUtf16, int endUtf16})> _openFragment(
    ForumBodyTextPageFragment fragment,
  ) {
    final prepared = _fragments[_fragmentIndex];
    _fragment = prepared;
    // These inputs are immutable for this delivery. Re-reading mixed fragment
    // getters per grapheme repeatedly scans every child lease. Native geometry
    // and the per-step lifetime guard still validate the current ownership.
    final projection = _projection = prepared.projection;
    _runs = prepared.runs;
    final snapshot = _snapshot!;
    _clip = Rect.fromLTWH(0, 0, fragment.width, fragment.height).intersect(
      Rect.fromLTWH(
        -fragment.left,
        -fragment.top,
        snapshot.width,
        snapshot.height,
      ),
    );
    if (_clip.isEmpty) {
      return const <({int startUtf16, int endUtf16})>[].iterator;
    }
    return projection
        .graphemeRanges(
          startUtf16: fragment.coverageStartUtf16,
          endUtf16: fragment.coverageEndUtf16,
        )
        .iterator;
  }

  void _includeGrapheme(int start, int end) {
    final prepared = _fragment!;
    final projection = _projection!;
    if (!_visibleStyles(projection, _runs, start, end)) return;
    final boxes = prepared.glyphBoxes(start, end);
    if (boxes.isEmpty) {
      // An explicit separator belongs to the preceding physical row, even
      // when the engine emits no selection box. Require that entire measured
      // row to fit; do not invent a caret or blank-line height.
      var coveredBreak = false;
      for (final line in prepared.lines) {
        if (line.endUtf16 == start &&
            line.coverageEndUtf16 == end &&
            _contains(
              Rect.fromLTRB(
                line.left,
                line.top,
                line.left + line.width,
                line.bottom,
              ),
            )) {
          coveredBreak = true;
          break;
        }
      }
      if (!coveredBreak) return;
    } else if (boxes.any((box) => !_contains(box.toRect()))) {
      _hasClippedGlyphs = true;
      return;
    }
    _addPoint(projection, start, HtmlProjectionAffinity.downstream);
    _addPoint(projection, end, HtmlProjectionAffinity.upstream);
  }

  bool _contains(Rect box) =>
      box.height > 0 &&
      box.left >= _clip.left - precisionErrorTolerance &&
      box.right <= _clip.right + precisionErrorTolerance &&
      box.top >= _clip.top - precisionErrorTolerance &&
      box.bottom <= _clip.bottom + precisionErrorTolerance;

  void _addPoint(
    HtmlDisplayTextProjection projection,
    int offset,
    HtmlProjectionAffinity affinity,
  ) {
    final source = projection.sourceAtUtf16(offset, affinity: affinity);
    final anchor = _anchors!.anchorAtSourceRune(
      source.sourceRune,
      affinity: affinity,
      requireAdjacentOrigin: true,
    );
    if (anchor == null) return;
    if (_points.length >= limits.maxPoints) {
      _fail(NovelReaderNativeCoverageFailure.budget);
    }
    _points.add(
      NovelReaderNativeCoveragePoint(
        anchor: anchor,
        fragmentIndex: _fragmentIndex,
        displayUtf16: offset,
        sourceRune: source.sourceRune,
        affinity: affinity,
      ),
    );
  }

  void _ensureLive() {
    if (_fragments.any((fragment) => !fragment.isActive)) {
      _fail(NovelReaderNativeCoverageFailure.retired);
    }
  }

  void _finish() {
    _ensureLive();
    _result = NovelReaderNativePageCoverage(
      identity: _snapshot!.identity,
      layoutId: layoutId,
      pageIndex: pageIndex,
      hasClippedGlyphs: _hasClippedGlyphs,
      points: _points,
    );
    _state = NovelReaderNativeCoverageState.complete;
    _dropBorrowed();
  }

  void _dropBorrowed() {
    _points.clear();
    _anchors = null;
    _snapshot = null;
    _fragments = const [];
    _ranges = null;
    _fragment = null;
    _projection = null;
    _runs = const [];
  }

  void close() {
    if (_state == NovelReaderNativeCoverageState.closed) return;
    _state = NovelReaderNativeCoverageState.closed;
    _result = null;
    _dropBorrowed();
  }
}

bool _visibleStyles(
  HtmlDisplayTextProjection projection,
  List<ForumBodyParagraphRun> runs,
  int start,
  int end,
) {
  final parts = projection.parts;
  var low = 0;
  var high = parts.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (parts[middle].utf16Start + parts[middle].text.length <= start) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  for (
    var index = low;
    index < parts.length && parts[index].utf16Start < end;
    index++
  ) {
    if (runs[parts[index].runIndex].style.visibilityHidden) {
      return false;
    }
  }
  return low < parts.length;
}

Never _fail(NovelReaderNativeCoverageFailure failure) =>
    throw NovelReaderNativeCoverageException(failure);

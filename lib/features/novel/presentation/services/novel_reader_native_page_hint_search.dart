import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

import '../models/novel_reader_native_anchor_map.dart';

enum NovelReaderNativePageHintKind { endpoint, preferred }

/// Candidate admission only. No hint is proof that an anchor is visible.
final class NovelReaderNativePageHint {
  const NovelReaderNativePageHint({
    required this.identity,
    required this.layoutId,
    required this.pageIndex,
    required this.kind,
  });
  final ForumBodyIdentity identity;
  final String layoutId;
  final int pageIndex;
  final NovelReaderNativePageHintKind kind;
}

final class NovelReaderNativeHintSearchStep {
  const NovelReaderNativeHintSearchStep(
    this.pagesRead,
    this.fragmentsRead,
    this.isComplete,
    this.bufferIsFull,
  );
  final int pagesRead;
  final int fragmentsRead;
  final bool isComplete;
  final bool bufferIsFull;
  bool get madeProgress => pagesRead > 0 || fragmentsRead > 0 || isComplete;
}

/// Bounded metadata scan over one fixed published prefix. Draining candidates
/// resumes the same cursor; a newer prefix starts at nextPageIndex. It neither
/// shapes/prepares earlier pages nor retains native leases or the anchor map.
final class NovelReaderNativePageHintSearch {
  factory NovelReaderNativePageHintSearch({
    required ForumBodyTextPageSnapshot snapshot,
    required String layoutId,
    required NovelReaderNativeAnchorMap anchors,
    required NovelReaderTextAnchor anchor,
    HtmlProjectionAffinity affinity = HtmlProjectionAffinity.downstream,
    int startPageIndex = 0,
    int maxBufferedCandidates = 32,
    bool allowNodeCompatibility = false,
  }) {
    if (maxBufferedCandidates <= 0) {
      throw ArgumentError.value(maxBufferedCandidates, 'maxBufferedCandidates');
    }
    RangeError.checkValueInInterval(
      startPageIndex,
      0,
      snapshot.length,
      'startPageIndex',
    );
    if (snapshot.identity != anchors.identity ||
        snapshot.layoutId != layoutId ||
        snapshot.backendRevision != ForumBodyParagraphLayout.backendRevision ||
        snapshot.composerRevision != ForumBodyTextPageComposer.revision) {
      throw StateError('Native page hint identity changed');
    }
    final ranges = anchors
        .sourceCandidates(
          anchor,
          allowNodeCompatibility: allowNodeCompatibility,
        )
        .toList(growable: false);
    return NovelReaderNativePageHintSearch._(
      snapshot,
      ranges,
      affinity,
      startPageIndex,
      maxBufferedCandidates,
    );
  }

  NovelReaderNativePageHintSearch._(
    ForumBodyTextPageSnapshot snapshot,
    this._ranges,
    this.affinity,
    this._pageIndex,
    this.maxBufferedCandidates,
  ) : pageCount = snapshot.length,
      identity = snapshot.identity,
      layoutId = snapshot.layoutId,
      _snapshot = snapshot {
    if (_ranges.isEmpty) _pageIndex = pageCount;
    _dropIfComplete();
  }
  ForumBodyTextPageSnapshot? _snapshot;
  List<NovelReaderNativeSourceCandidate> _ranges;
  final HtmlProjectionAffinity affinity;
  final int maxBufferedCandidates;
  final int pageCount;
  final ForumBodyIdentity identity;
  final String layoutId;
  final _buffer = <NovelReaderNativePageHint>[];
  int _pageIndex;
  int _fragmentIndex = 0;
  int _rank = 0;
  bool _closed = false;

  bool get isComplete => _pageIndex == pageCount;
  bool get bufferIsFull => _buffer.length == maxBufferedCandidates;
  int get nextPageIndex => _pageIndex;

  NovelReaderNativeHintSearchStep advance({
    required int maxPages,
    required int maxFragments,
  }) {
    if (_closed) throw StateError('Native page hint search is closed');
    if (maxPages <= 0 || maxFragments <= 0) {
      throw ArgumentError('Native page hint work budgets must be positive');
    }
    var pages = 0;
    var fragments = 0;
    while (!isComplete &&
        !bufferIsFull &&
        pages < maxPages &&
        fragments < maxFragments) {
      final page = _snapshot![_pageIndex];
      if (_fragmentIndex < page.fragments.length) {
        final hint = page.fragments[_fragmentIndex++].sourceHint;
        fragments++;
        if (hint != null) {
          final rank = _hintRank(hint.runeStart, hint.runeEnd);
          if (rank > _rank) _rank = rank;
          // No later fragment can improve the strongest candidate kind.
          if (_rank == 2) _fragmentIndex = page.fragments.length;
        }
      }
      if (_fragmentIndex == page.fragments.length) {
        if (_rank > 0) {
          _buffer.add(
            NovelReaderNativePageHint(
              identity: identity,
              layoutId: layoutId,
              pageIndex: _pageIndex,
              kind: _rank == 2
                  ? NovelReaderNativePageHintKind.preferred
                  : NovelReaderNativePageHintKind.endpoint,
            ),
          );
        }
        _pageIndex++;
        _fragmentIndex = 0;
        _rank = 0;
        pages++;
      }
    }
    _dropIfComplete();
    return NovelReaderNativeHintSearchStep(
      pages,
      fragments,
      isComplete,
      bufferIsFull,
    );
  }

  List<NovelReaderNativePageHint> takeCandidates() {
    if (_closed) throw StateError('Native page hint search is closed');
    final result = List<NovelReaderNativePageHint>.unmodifiable(_buffer);
    _buffer.clear();
    return result;
  }

  int _hintRank(int start, int end) {
    if (end <= start) return 0;
    final first = _firstRangeEnd(start, after: false);
    if (first == _ranges.length || _ranges[first].runeStart > end) return 0;
    if (affinity == HtmlProjectionAffinity.downstream) {
      return _ranges[first].runeStart < end ? 2 : 1;
    }
    final inside = _firstRangeEnd(start, after: true);
    return inside < _ranges.length && _ranges[inside].runeStart <= end ? 2 : 1;
  }

  int _firstRangeEnd(int point, {required bool after}) {
    var low = 0;
    var high = _ranges.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      final end = _ranges[middle].runeEnd;
      if (end < point || (after && end == point)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void _dropIfComplete() {
    if (!isComplete) return;
    _snapshot = null;
    _ranges = const [];
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _snapshot = null;
    _ranges = const [];
    _buffer.clear();
  }
}

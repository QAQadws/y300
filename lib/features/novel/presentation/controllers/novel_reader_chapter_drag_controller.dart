import '../models/novel_reader_chapter_turn.dart';

/// One boundary drag's presentation intent, never reading/completion proof.
/// The viewport freezes eligible chapter edges at drag start and rechecks authority
/// before using [edgeToCommit]. No source completion can add an eligible edge.
final class NovelReaderChapterDragController {
  NovelReaderChapterDragController({
    required String? previousChapterTitle,
    required String? nextChapterTitle,
    required this.viewportDimension,
    required this.policy,
  }) : _previousTitle = _title(previousChapterTitle),
       _nextTitle = _title(nextChapterTitle);

  final double viewportDimension;
  final NovelReaderChapterTurnPolicy policy;
  final String? _previousTitle;
  final String? _nextTitle;
  NovelReaderChapterEdge? _edge;
  double _distance = 0;

  void resetPull() {
    _edge = null;
    _distance = 0;
  }

  void observeOverscroll(double delta) {
    if (!delta.isFinite || delta == 0) return;
    final edge = delta < 0
        ? NovelReaderChapterEdge.start
        : NovelReaderChapterEdge.end;
    if (_titleFor(edge) == null) {
      _edge = null;
      _distance = 0;
      return;
    }
    // Reversing a one-page pull retires its old peak, rather than committing
    // whichever direction happened to accumulate the largest distance.
    if (_edge != edge) _distance = 0;
    _edge = edge;
    _distance += delta.abs();
  }

  NovelReaderChapterTurnHint? get hint {
    final edge = _edge;
    if (edge == null ||
        !policy.shouldRevealHint(
          overscrollDistance: _distance,
          viewportDimension: viewportDimension,
        )) {
      return null;
    }
    return NovelReaderChapterTurnHint(
      edge: edge,
      chapterTitle: _titleFor(edge)!,
      isReadyToCommit: edgeToCommit != null,
    );
  }

  NovelReaderChapterEdge? get edgeToCommit =>
      policy.shouldCommit(
        overscrollDistance: _distance,
        viewportDimension: viewportDimension,
      )
      ? _edge
      : null;

  String? _titleFor(NovelReaderChapterEdge edge) =>
      edge == NovelReaderChapterEdge.start ? _previousTitle : _nextTitle;

  static String? _title(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

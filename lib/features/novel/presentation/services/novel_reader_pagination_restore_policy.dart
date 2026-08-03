import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';

/// Resolves a persisted location without allowing a stale page index to jump
/// to the end of a newly reflowed chapter.
final class NovelReaderPaginationRestorePolicy {
  const NovelReaderPaginationRestorePolicy();

  /// Resolves a page only when an incremental plan already contains enough
  /// stable information to restore it without displaying a temporary page.
  /// A complete plan can use the existing percentage and legacy fallbacks.
  int? resolveAvailablePage({
    required NovelReaderPaginationPlan plan,
    required NovelReaderProgressSnapshot snapshot,
    required bool isPlanComplete,
  }) {
    final pageCount = plan.pageCount;
    if (pageCount <= 0) {
      return null;
    }
    if (snapshot.episodeId != plan.episodeId) {
      return 0;
    }
    // A newly prepared plan may have a different page count or layout key.
    // Once the complete plan is available, the persisted percentage is the
    // stable position contract and must win over stale page/anchor hints.
    if (isPlanComplete) {
      final percentPage = _pageFromProgressPercent(snapshot, pageCount);
      if (percentPage != null) {
        return percentPage;
      }
    }
    if (snapshot.paginationKey == plan.key.layoutFingerprint &&
        _isValidPage(snapshot.pageIndex, pageCount)) {
      return snapshot.pageIndex;
    }
    final anchor = _anchorFromSnapshot(snapshot);
    if (anchor != null) {
      final anchoredPage = plan.pageIndexForAnchor(anchor);
      if (anchoredPage != null && _isValidPage(anchoredPage, pageCount)) {
        return anchoredPage;
      }
    }
    if (!isPlanComplete && _hasMeaningfulResumeTarget(snapshot)) {
      return null;
    }
    return resolveInitialPage(plan: plan, snapshot: snapshot);
  }

  int resolveInitialPage({
    required NovelReaderPaginationPlan plan,
    required NovelReaderProgressSnapshot snapshot,
  }) {
    final pageCount = plan.pageCount;
    if (pageCount <= 0 || snapshot.episodeId != plan.episodeId) {
      return 0;
    }

    final percentPage = _pageFromProgressPercent(snapshot, pageCount);
    if (percentPage != null) {
      return percentPage;
    }

    if (snapshot.paginationKey == plan.key.layoutFingerprint &&
        _isValidPage(snapshot.pageIndex, pageCount)) {
      return snapshot.pageIndex;
    }

    final anchor = _anchorFromSnapshot(snapshot);
    if (anchor != null) {
      final anchoredPage = plan.pageIndexForAnchor(anchor);
      if (anchoredPage != null && _isValidPage(anchoredPage, pageCount)) {
        return anchoredPage;
      }
    }

    // This is only a compatibility fallback for old rows or rows whose
    // layout identity was invalidated. Never clamp an oversized old page to
    // the last page; an uncertain location is safer at the beginning.
    if (_isValidPage(snapshot.pageIndex, pageCount)) {
      return snapshot.pageIndex;
    }
    return 0;
  }

  int? _pageFromProgressPercent(
    NovelReaderProgressSnapshot snapshot,
    int pageCount,
  ) {
    if (!snapshot.progressPercent.isFinite || snapshot.progressPercent <= 0) {
      return null;
    }
    final scale =
        snapshot.flowMode == NovelReaderFlowMode.vertical ||
            snapshot.pageCount != null
        ? pageCount
        : pageCount - 1;
    return (snapshot.progressPercent.clamp(0.0, 1.0) * scale)
        .floor()
        .clamp(0, pageCount - 1)
        .toInt();
  }

  NovelReaderTextAnchor? _anchorFromSnapshot(
    NovelReaderProgressSnapshot snapshot,
  ) {
    final nodeId = snapshot.anchorNodeId?.trim();
    if (nodeId == null || nodeId.isEmpty) {
      return null;
    }
    return NovelReaderTextAnchor(
      episodeId: snapshot.episodeId,
      nodeId: nodeId,
      textOffset: snapshot.anchorTextOffset,
    );
  }

  bool _isValidPage(int index, int pageCount) {
    return index >= 0 && index < pageCount;
  }

  bool _hasMeaningfulResumeTarget(NovelReaderProgressSnapshot snapshot) {
    final anchorNodeId = snapshot.anchorNodeId?.trim();
    return snapshot.pageIndex > 0 ||
        snapshot.progressPercent > 0 ||
        (anchorNodeId != null && anchorNodeId.isNotEmpty);
  }
}

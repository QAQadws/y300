import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';

final class NovelReaderPaginationRestoreResolution {
  const NovelReaderPaginationRestoreResolution({
    required this.pageIndex,
    required this.isReadOnlyCompatibilityRestore,
  });

  final int pageIndex;

  /// Selecting a readable page does not establish the unit of an old offset.
  /// Only an exact canonical anchor or explicit reader navigation can do that.
  final bool isReadOnlyCompatibilityRestore;
}

/// Resolves a persisted location without allowing a stale page index to jump
/// to the end of a newly reflowed chapter.
final class NovelReaderPaginationRestorePolicy {
  const NovelReaderPaginationRestorePolicy();

  /// A nonzero percentage needs a final page count only until a readable
  /// restore target is found. A verified beginning is independent of totals.
  bool requiresCompletePageCount({
    required NovelReaderProgressSnapshot snapshot,
    required bool isRestoreTargetPending,
  }) =>
      isRestoreTargetPending &&
      _hasUsableProgressPercent(snapshot) &&
      snapshot.progressPercent > 0;

  /// Resolves a page only when an incremental plan already contains enough
  /// stable information to restore it without displaying a temporary page.
  /// A complete plan can use the existing percentage and legacy fallbacks.
  NovelReaderPaginationRestoreResolution? resolveAvailablePage({
    required NovelReaderPaginationPlan plan,
    required NovelReaderProgressSnapshot snapshot,
    required bool isPlanComplete,
  }) {
    final pageCount = plan.pageCount;
    if (pageCount <= 0) {
      return null;
    }
    if (snapshot.episodeId != plan.episodeId) {
      return const NovelReaderPaginationRestoreResolution(
        pageIndex: 0,
        isReadOnlyCompatibilityRestore: true,
      );
    }
    final anchor = _anchorFromSnapshot(snapshot);
    final exactPage = anchor == null
        ? null
        : plan.pageIndexForAnchor(anchor, isPlanComplete: isPlanComplete);
    NovelReaderPaginationRestoreResolution resolution(int pageIndex) =>
        NovelReaderPaginationRestoreResolution(
          pageIndex: pageIndex,
          isReadOnlyCompatibilityRestore: exactPage == null,
        );
    // Unlike a nonzero percentage, a verified 0% needs no final page count.
    // Conversion can invalidate its old node; retain compatibility read-only
    // status unless that node actually proves the displayed first page.
    if (_hasUsableProgressPercent(snapshot) && snapshot.progressPercent == 0) {
      return NovelReaderPaginationRestoreResolution(
        pageIndex: 0,
        isReadOnlyCompatibilityRestore: exactPage != 0,
      );
    }
    // A newly prepared plan may have a different page count or layout key.
    // Once the complete plan is available, the persisted percentage is the
    // stable position contract and must win over stale page/anchor hints.
    if (isPlanComplete) {
      final percentPage = _pageFromProgressPercent(snapshot, pageCount);
      if (percentPage != null) {
        return resolution(percentPage);
      }
    }
    if (snapshot.paginationKey == plan.key.layoutFingerprint &&
        _isValidPage(snapshot.pageIndex, pageCount)) {
      return resolution(snapshot.pageIndex);
    }
    if (anchor != null) {
      if (exactPage != null) return resolution(exactPage);
      // A matching canonical node may not yet contain the requested offset.
      // Do not downgrade that pending exact target to the node's first page.
      if (!plan.hasMatchingTextIdentity(anchor)) {
        final nodePage = plan.pageIndexForNode(anchor);
        if (nodePage != null) return resolution(nodePage);
      }
    }
    if (!isPlanComplete && _hasMeaningfulResumeTarget(snapshot)) {
      return null;
    }
    return resolveInitialPage(plan: plan, snapshot: snapshot);
  }

  NovelReaderPaginationRestoreResolution resolveInitialPage({
    required NovelReaderPaginationPlan plan,
    required NovelReaderProgressSnapshot snapshot,
  }) {
    final pageCount = plan.pageCount;
    if (pageCount <= 0 || snapshot.episodeId != plan.episodeId) {
      return const NovelReaderPaginationRestoreResolution(
        pageIndex: 0,
        isReadOnlyCompatibilityRestore: true,
      );
    }
    final anchor = _anchorFromSnapshot(snapshot);
    final exactPage = anchor == null
        ? null
        : plan.pageIndexForAnchor(anchor, isPlanComplete: true);
    NovelReaderPaginationRestoreResolution resolution(int pageIndex) =>
        NovelReaderPaginationRestoreResolution(
          pageIndex: pageIndex,
          isReadOnlyCompatibilityRestore: exactPage == null,
        );

    if (_hasUsableProgressPercent(snapshot) && snapshot.progressPercent == 0) {
      return NovelReaderPaginationRestoreResolution(
        pageIndex: 0,
        isReadOnlyCompatibilityRestore: exactPage != 0,
      );
    }
    final percentPage = _pageFromProgressPercent(snapshot, pageCount);
    if (percentPage != null) {
      return resolution(percentPage);
    }

    if (snapshot.paginationKey == plan.key.layoutFingerprint &&
        _isValidPage(snapshot.pageIndex, pageCount)) {
      return resolution(snapshot.pageIndex);
    }

    if (anchor != null) {
      if (exactPage != null) return resolution(exactPage);
      final nodePage = plan.pageIndexForNode(anchor);
      if (nodePage != null) return resolution(nodePage);
    }

    // This is only a compatibility fallback for old rows or rows whose
    // layout identity was invalidated. Never clamp an oversized old page to
    // the last page; an uncertain location is safer at the beginning.
    if (_isValidPage(snapshot.pageIndex, pageCount)) {
      return resolution(snapshot.pageIndex);
    }
    return resolution(0);
  }

  int? _pageFromProgressPercent(
    NovelReaderProgressSnapshot snapshot,
    int pageCount,
  ) {
    if (!_hasUsableProgressPercent(snapshot)) {
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

  bool _hasUsableProgressPercent(NovelReaderProgressSnapshot snapshot) =>
      snapshot.isProgressPercentValid != false &&
      snapshot.progressPercent.isFinite &&
      snapshot.progressPercent >= 0 &&
      (snapshot.progressPercent > 0 || snapshot.isProgressPercentValid == true);

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
      formatVersion: snapshot.anchorFormatVersion,
      textIdentity: snapshot.anchorTextIdentity,
      isProgressPercentValid: snapshot.isProgressPercentValid,
    );
  }

  bool _isValidPage(int index, int pageCount) {
    return index >= 0 && index < pageCount;
  }

  bool _hasMeaningfulResumeTarget(NovelReaderProgressSnapshot snapshot) {
    final anchorNodeId = snapshot.anchorNodeId?.trim();
    return snapshot.pageIndex > 0 ||
        (snapshot.isProgressPercentValid != false &&
            snapshot.progressPercent > 0) ||
        (anchorNodeId != null && anchorNodeId.isNotEmpty);
  }
}

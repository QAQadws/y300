import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';

import '../models/novel_reader_native_page_coverage.dart';
import '../models/novel_reader_pagination_restore_resolution.dart';

/// Pure, layout-scoped restore state. It retains at most three page indices,
/// never native layouts, coverage collections, a source session or page prefix.
/// Feed only complete native coverage; source envelopes are not accepted here.
/// Real navigation retires this cursor rather than upgrading its latched result.
final class NovelReaderNativeRestoreCursor {
  NovelReaderNativeRestoreCursor({
    required this.identity,
    required this.layoutId,
    required this.episodeId,
    required this.paginationKey,
    required NovelReaderProgressSnapshot position,
    NovelReaderTextAnchor? conversionAnchor,
    this.maxCoveragePoints = 8192,
  }) : isConversionRestore = conversionAnchor != null,
       isExplicitNavigation = false,
       _hasKnownPercentBasis = const {
         NovelProgressPercentBasis.legacyReaderLayout,
         NovelProgressPercentBasis.bodyGeometryV1,
         NovelProgressPercentBasis.pagedStartV1,
       }.contains(position.percentBasis),
       _position = position,
       _conversionAnchor = conversionAnchor {
    if (layoutId.isEmpty || paginationKey.isEmpty || maxCoveragePoints < 0) {
      throw ArgumentError('Invalid native restore scope');
    }
    final node = position.anchorNodeId?.trim();
    if (node != null && node.isNotEmpty) {
      _savedAnchor = NovelReaderTextAnchor(
        episodeId: position.episodeId,
        nodeId: node,
        textOffset: position.anchorTextOffset,
        formatVersion: position.anchorFormatVersion,
        textIdentity: position.anchorTextIdentity,
      );
    }
  }

  /// Explicit search/bookmark navigation has no percentage/page-key fallback.
  /// Only observed text coverage, or a recorded-node compatibility point, can
  /// resolve it. The caller must still confirm the real mounted navigation.
  NovelReaderNativeRestoreCursor.forNavigation({
    required this.identity,
    required this.layoutId,
    required this.paginationKey,
    required NovelReaderTextAnchor anchor,
    this.maxCoveragePoints = 8192,
  }) : episodeId = anchor.episodeId,
       isConversionRestore = false,
       isExplicitNavigation = true,
       _hasKnownPercentBasis = true,
       _savedAnchor = anchor {
    if (layoutId.isEmpty ||
        paginationKey.isEmpty ||
        maxCoveragePoints < 0 ||
        anchor.episodeId.isEmpty ||
        anchor.nodeId?.trim().isNotEmpty != true) {
      throw ArgumentError('Invalid native anchor navigation scope');
    }
  }

  final ForumBodyIdentity identity;
  final String layoutId;
  final String episodeId;

  /// Stable geometry/cache fingerprint, distinct from request-only layoutId.
  final String paginationKey;
  final bool isConversionRestore;
  final bool isExplicitNavigation;
  final bool _hasKnownPercentBasis;
  final int maxCoveragePoints;
  NovelReaderProgressSnapshot? _position;
  NovelReaderTextAnchor? _savedAnchor;
  NovelReaderTextAnchor? _conversionAnchor;
  NovelReaderPaginationRestoreResolution? _resolution;
  int? _exactPage;
  int? _convertedPage;
  int? _nodePage;
  NovelReaderTextAnchor? _nodeAnchor;
  NovelReaderTextAnchor? _resolvedNavigationAnchor;
  bool _hasMatchingTextIdentity = false;
  bool _closed = false;
  int _pageCountSeen = 0;
  bool _completed = false;

  NovelReaderTextAnchor? get targetAnchor => _conversionAnchor ?? _savedAnchor;
  bool get isResolved => _resolution != null;
  NovelReaderTextAnchor? get resolvedNavigationAnchor =>
      _resolvedNavigationAnchor;

  /// A resolved target must never keep old percent-driven foreground demand.
  bool get requiresCompletePageCount =>
      !_closed &&
      !isResolved &&
      !isExplicitNavigation &&
      !isConversionRestore &&
      _position!.episodeId == episodeId &&
      _hasUsablePercent &&
      _position!.progressPercent > 0;

  void observe({
    required ForumBodyTextPageSnapshot snapshot,
    required NovelReaderNativePageCoverage coverage,
  }) {
    _checkPrefix(snapshot);
    if (coverage.identity != identity ||
        coverage.layoutId != layoutId ||
        coverage.pageIndex < 0 ||
        coverage.pageIndex >= snapshot.length) {
      throw StateError('Native restore coverage scope changed');
    }
    if (coverage.points.length > maxCoveragePoints) {
      throw StateError('Native restore coverage budget exceeded');
    }
    if (isResolved ||
        (_position != null && _position!.episodeId != episodeId)) {
      return;
    }
    final saved = _savedAnchor;
    final converted = _conversionAnchor;
    if (converted != null &&
        converted.episodeId == episodeId &&
        coverage.locate(converted) != null) {
      _convertedPage ??= coverage.pageIndex;
    }
    if (saved == null) return;
    final exact = coverage.locate(saved);
    if (exact != null) {
      _exactPage ??= coverage.pageIndex;
      if (isExplicitNavigation) _resolvedNavigationAnchor ??= exact.anchor;
    }
    for (final point in coverage.points) {
      final anchor = point.anchor;
      if (anchor.episodeId != episodeId || anchor.nodeId != saved.nodeId) {
        continue;
      }
      if (_nodePage == null || coverage.pageIndex < _nodePage!) {
        _nodePage = coverage.pageIndex;
        _nodeAnchor = anchor;
      }
      if (saved.hasCanonicalTextOffset &&
          anchor.formatVersion == saved.formatVersion &&
          anchor.textIdentity == saved.textIdentity) {
        _hasMatchingTextIdentity = true;
      }
    }
  }

  NovelReaderPaginationRestoreResolution? resolve(
    ForumBodyTextPageSnapshot snapshot,
  ) {
    _checkPrefix(snapshot);
    if (isResolved) return _resolution;
    if (snapshot.isEmpty) return null;
    if (isExplicitNavigation) {
      if (_exactPage != null) return _latch(_exactPage!, exact: true);
      if (_nodePage != null && !_hasMatchingTextIdentity) {
        _resolvedNavigationAnchor = _nodeAnchor;
        return _latch(_nodePage!);
      }
      return null;
    }
    final position = _position!;
    if (position.episodeId != episodeId) return _latch(0);
    if (_conversionAnchor != null) {
      if (_convertedPage != null) return _latch(_convertedPage!);
      // A conversion hint can be before the current prefix. Its percentage
      // fallback is permitted only at actual EOF, never at a failed source.
      if (!snapshot.isComplete) return null;
    }
    if (_hasUsablePercent && position.progressPercent == 0) {
      return _latch(0, exact: _exactPage == 0);
    }
    // Canonical proof wins before percentage approximation at both partial
    // and complete prefixes. Proof on another page cannot make a fallback
    // writable. Once latched, later EOF/proofs cannot move or upgrade it.
    if (_exactPage != null) return _latch(_exactPage!, exact: true);
    if (snapshot.isComplete && _hasUsablePercent) {
      // Preserve the existing saved percentage convention, including paged
      // rows written before pageCount existed. No persisted fields change.
      final scale = position.isPaged && position.pageCount == null
          ? snapshot.length - 1
          : snapshot.length;
      final page = (position.progressPercent.clamp(0.0, 1.0) * scale)
          .floor()
          .clamp(0, snapshot.length - 1);
      return _latch(page);
    }
    bool validPage(int page) => page >= 0 && page < snapshot.length;
    if (position.paginationKey == paginationKey &&
        validPage(position.pageIndex)) {
      return _latch(position.pageIndex);
    }
    // A matching canonical node with an uncovered offset is still pending.
    // Unsupported/mismatched text may use an observed node only read-only.
    if (_nodePage != null && !_hasMatchingTextIdentity) {
      return _latch(_nodePage!);
    }
    final meaningfulTarget =
        position.pageIndex > 0 ||
        (_hasUsablePercent && position.progressPercent > 0) ||
        _savedAnchor != null;
    if (!snapshot.isComplete && meaningfulTarget) return null;
    return _latch(validPage(position.pageIndex) ? position.pageIndex : 0);
  }

  bool get _hasUsablePercent {
    final position = _position!;
    return position.isProgressPercentValid != false &&
        position.progressPercent.isFinite &&
        position.progressPercent >= 0 &&
        (position.progressPercent > 0 ||
            position.isProgressPercentValid == true);
  }

  NovelReaderPaginationRestoreResolution _latch(
    int page, {
    bool exact = false,
  }) {
    _resolution = NovelReaderPaginationRestoreResolution(
      pageIndex: page,
      isReadOnlyCompatibilityRestore:
          !isExplicitNavigation &&
          (!exact || isConversionRestore || !_hasKnownPercentBasis),
    );
    // The result and request scope are all that is needed after selection.
    _position = null;
    _savedAnchor = null;
    _conversionAnchor = null;
    return _resolution!;
  }

  void _checkPrefix(ForumBodyTextPageSnapshot snapshot) {
    if (_closed) throw StateError('Native restore cursor is closed');
    if (snapshot.identity != identity ||
        snapshot.layoutId != layoutId ||
        snapshot.backendRevision != ForumBodyParagraphLayout.backendRevision ||
        snapshot.composerRevision != ForumBodyTextPageComposer.revision ||
        snapshot.length < _pageCountSeen ||
        (_completed && !snapshot.isComplete)) {
      throw StateError('Native restore prefix changed');
    }
    _pageCountSeen = snapshot.length;
    _completed = snapshot.isComplete;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _position = null;
    _savedAnchor = null;
    _conversionAnchor = null;
    _resolution = null;
    _exactPage = null;
    _convertedPage = null;
    _nodePage = null;
    _nodeAnchor = null;
    _resolvedNavigationAnchor = null;
  }
}

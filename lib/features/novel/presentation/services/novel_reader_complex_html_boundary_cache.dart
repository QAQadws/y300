import 'dart:async';
import 'dart:collection';

import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_source_anchor_projection.dart';

/// Invalidates cached DOM boundary sessions when indexing semantics change.
abstract final class NovelReaderComplexHtmlBoundaryIndexRevision {
  static const int current = 2;
}

final class NovelReaderComplexHtmlBoundaryCacheRequest {
  const NovelReaderComplexHtmlBoundaryCacheRequest({
    required this.episodeId,
    required this.contentHash,
    required this.atomId,
    required this.html,
    required this.startAnchor,
    required this.normalizerRevision,
    this.sourceAnchorProjection,
    this.boundaryIndexerRevision =
        NovelReaderComplexHtmlBoundaryIndexRevision.current,
  });

  final String episodeId;
  final String contentHash;
  final String atomId;
  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderSourceAnchorProjection? sourceAnchorProjection;
  final int normalizerRevision;
  final int boundaryIndexerRevision;
}

final class NovelReaderComplexHtmlBoundaryCacheResult {
  const NovelReaderComplexHtmlBoundaryCacheResult({
    required this.session,
    required this.fromCache,
    required this.joinedInFlight,
  });

  final NovelReaderComplexHtmlSliceSession session;
  final bool fromCache;
  final bool joinedInFlight;
}

/// Bounded process-local cache for immutable DOM boundary sessions.
///
/// The exact HTML and source anchor are retained in the private key so a
/// stale content hash or reused atom id cannot return boundaries for another
/// fragment. DOM sessions are intentionally never persisted.
final class NovelReaderComplexHtmlBoundaryCache {
  NovelReaderComplexHtmlBoundaryCache({
    this.capacity = 32,
    this.maxEstimatedBytes = 16 * 1024 * 1024,
  }) : assert(capacity > 0),
       assert(maxEstimatedBytes >= 0);

  final int capacity;
  final int maxEstimatedBytes;
  final LinkedHashMap<
    _NovelReaderComplexHtmlBoundaryCacheKey,
    ({NovelReaderComplexHtmlSliceSession session, int bytes})
  >
  _entries =
      LinkedHashMap<
        _NovelReaderComplexHtmlBoundaryCacheKey,
        ({NovelReaderComplexHtmlSliceSession session, int bytes})
      >();
  final Map<
    _NovelReaderComplexHtmlBoundaryCacheKey,
    Future<NovelReaderComplexHtmlSliceSession>
  >
  _inFlight =
      <
        _NovelReaderComplexHtmlBoundaryCacheKey,
        Future<NovelReaderComplexHtmlSliceSession>
      >{};
  int _generation = 0;
  int _estimatedRetainedBytes = 0;
  bool _closed = false;

  int get length => _entries.length;
  bool get isClosed => _closed;

  /// Conservative fixed weights for HTML/DOM, graphemes, boundaries and
  /// projection arrays. Excludes in-flight work and is not a heap measurement.
  int get estimatedRetainedBytes => _estimatedRetainedBytes;

  Future<NovelReaderComplexHtmlBoundaryCacheResult> resolve({
    required NovelReaderComplexHtmlBoundaryCacheRequest request,
    required NovelReaderComplexHtmlSliceSession Function() build,
  }) {
    if (_closed) {
      return Future<NovelReaderComplexHtmlBoundaryCacheResult>.error(
        StateError('The boundary cache has been disposed.'),
      );
    }
    final key = _NovelReaderComplexHtmlBoundaryCacheKey.from(request);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return Future<NovelReaderComplexHtmlBoundaryCacheResult>.value(
        NovelReaderComplexHtmlBoundaryCacheResult(
          session: cached.session,
          fromCache: true,
          joinedInFlight: false,
        ),
      );
    }

    final existing = _inFlight[key];
    if (existing != null) {
      return existing.then(
        (session) => NovelReaderComplexHtmlBoundaryCacheResult(
          session: session,
          fromCache: false,
          joinedInFlight: true,
        ),
      );
    }

    final requestGeneration = _generation;
    final future = Future<NovelReaderComplexHtmlSliceSession>.sync(build).then((
      session,
    ) {
      if (!_closed && requestGeneration == _generation) {
        _put(key, session, _estimate(request, session));
      }
      return session;
    });
    _inFlight[key] = future;
    unawaited(
      future.then<void>(
        (_) => _removeInFlight(key, future),
        onError: (Object error, StackTrace stackTrace) =>
            _removeInFlight(key, future),
      ),
    );
    return future.then(
      (session) => NovelReaderComplexHtmlBoundaryCacheResult(
        session: session,
        fromCache: false,
        joinedInFlight: false,
      ),
    );
  }

  void clear() {
    _generation += 1;
    _entries.clear();
    _inFlight.clear();
    _estimatedRetainedBytes = 0;
  }

  void dispose() {
    _closed = true;
    clear();
  }

  void _put(
    _NovelReaderComplexHtmlBoundaryCacheKey key,
    NovelReaderComplexHtmlSliceSession session,
    int bytes,
  ) {
    _evict(key);
    if (bytes > maxEstimatedBytes) {
      return;
    }
    _entries[key] = (session: session, bytes: bytes);
    _estimatedRetainedBytes += bytes;
    while (_entries.length > capacity ||
        _estimatedRetainedBytes > maxEstimatedBytes) {
      _evict(_entries.keys.first);
    }
  }

  void _evict(_NovelReaderComplexHtmlBoundaryCacheKey key) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _estimatedRetainedBytes -= entry.bytes;
    }
  }

  int _estimate(
    NovelReaderComplexHtmlBoundaryCacheRequest request,
    NovelReaderComplexHtmlSliceSession session,
  ) =>
      256 +
      6 * request.html.length +
      32 * session.textLength +
      96 * session.boundaries.length +
      32 * session.protectedRanges.length +
      8 *
          (request
                  .sourceAnchorProjection
                  ?.semanticOffsetsBySourceRuneBoundary
                  .length ??
              0) +
      2 *
          (request.episodeId.length +
              request.contentHash.length +
              request.atomId.length +
              request.startAnchor.episodeId.length +
              (request.startAnchor.nodeId?.length ?? 0) +
              (request.startAnchor.textIdentity?.length ?? 0) +
              (request.sourceAnchorProjection?.cacheIdentity.length ?? 0));

  void _removeInFlight(
    _NovelReaderComplexHtmlBoundaryCacheKey key,
    Future<NovelReaderComplexHtmlSliceSession> future,
  ) {
    if (identical(_inFlight[key], future)) {
      _inFlight.remove(key);
    }
  }
}

final class _NovelReaderComplexHtmlBoundaryCacheKey {
  const _NovelReaderComplexHtmlBoundaryCacheKey({
    required this.episodeId,
    required this.contentHash,
    required this.atomId,
    required this.html,
    required this.anchorEpisodeId,
    required this.anchorNodeId,
    required this.anchorTextOffset,
    required this.anchorFormatVersion,
    required this.anchorTextIdentity,
    required this.anchorIsProgressPercentValid,
    required this.sourceProjectionIdentity,
    required this.normalizerRevision,
    required this.boundaryIndexerRevision,
  });

  factory _NovelReaderComplexHtmlBoundaryCacheKey.from(
    NovelReaderComplexHtmlBoundaryCacheRequest request,
  ) {
    return _NovelReaderComplexHtmlBoundaryCacheKey(
      episodeId: request.episodeId,
      contentHash: request.contentHash,
      atomId: request.atomId,
      html: request.html,
      anchorEpisodeId: request.startAnchor.episodeId,
      anchorNodeId: request.startAnchor.nodeId,
      anchorTextOffset: request.startAnchor.textOffset,
      anchorFormatVersion: request.startAnchor.formatVersion,
      anchorTextIdentity: request.startAnchor.textIdentity,
      anchorIsProgressPercentValid: request.startAnchor.isProgressPercentValid,
      sourceProjectionIdentity: request.sourceAnchorProjection?.cacheIdentity,
      normalizerRevision: request.normalizerRevision,
      boundaryIndexerRevision: request.boundaryIndexerRevision,
    );
  }

  final String episodeId;
  final String contentHash;
  final String atomId;
  final String html;
  final String anchorEpisodeId;
  final String? anchorNodeId;
  final int anchorTextOffset;
  final int anchorFormatVersion;
  final String? anchorTextIdentity;
  final bool? anchorIsProgressPercentValid;
  final String? sourceProjectionIdentity;
  final int normalizerRevision;
  final int boundaryIndexerRevision;

  @override
  bool operator ==(Object other) {
    return other is _NovelReaderComplexHtmlBoundaryCacheKey &&
        other.episodeId == episodeId &&
        other.contentHash == contentHash &&
        other.atomId == atomId &&
        other.html == html &&
        other.anchorEpisodeId == anchorEpisodeId &&
        other.anchorNodeId == anchorNodeId &&
        other.anchorTextOffset == anchorTextOffset &&
        other.anchorFormatVersion == anchorFormatVersion &&
        other.anchorTextIdentity == anchorTextIdentity &&
        other.anchorIsProgressPercentValid == anchorIsProgressPercentValid &&
        other.sourceProjectionIdentity == sourceProjectionIdentity &&
        other.normalizerRevision == normalizerRevision &&
        other.boundaryIndexerRevision == boundaryIndexerRevision;
  }

  @override
  int get hashCode => Object.hash(
    episodeId,
    contentHash,
    atomId,
    html,
    anchorEpisodeId,
    anchorNodeId,
    anchorTextOffset,
    anchorFormatVersion,
    anchorTextIdentity,
    anchorIsProgressPercentValid,
    sourceProjectionIdentity,
    normalizerRevision,
    boundaryIndexerRevision,
  );
}

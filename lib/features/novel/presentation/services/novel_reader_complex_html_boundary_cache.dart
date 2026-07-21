import 'dart:async';
import 'dart:collection';

import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';

/// Invalidates cached DOM boundary sessions when indexing semantics change.
abstract final class NovelReaderComplexHtmlBoundaryIndexRevision {
  static const int current = 1;
}

final class NovelReaderComplexHtmlBoundaryCacheRequest {
  const NovelReaderComplexHtmlBoundaryCacheRequest({
    required this.episodeId,
    required this.contentHash,
    required this.atomId,
    required this.html,
    required this.startAnchor,
    required this.normalizerRevision,
    this.boundaryIndexerRevision =
        NovelReaderComplexHtmlBoundaryIndexRevision.current,
  });

  final String episodeId;
  final String contentHash;
  final String atomId;
  final String html;
  final NovelReaderTextAnchor startAnchor;
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
  NovelReaderComplexHtmlBoundaryCache({this.capacity = 32})
    : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<
    _NovelReaderComplexHtmlBoundaryCacheKey,
    NovelReaderComplexHtmlSliceSession
  >
  _entries =
      LinkedHashMap<
        _NovelReaderComplexHtmlBoundaryCacheKey,
        NovelReaderComplexHtmlSliceSession
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

  int get length => _entries.length;

  Future<NovelReaderComplexHtmlBoundaryCacheResult> resolve({
    required NovelReaderComplexHtmlBoundaryCacheRequest request,
    required NovelReaderComplexHtmlSliceSession Function() build,
  }) {
    final key = _NovelReaderComplexHtmlBoundaryCacheKey.from(request);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return Future<NovelReaderComplexHtmlBoundaryCacheResult>.value(
        NovelReaderComplexHtmlBoundaryCacheResult(
          session: cached,
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
      if (requestGeneration == _generation) {
        _put(key, session);
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
  }

  void _put(
    _NovelReaderComplexHtmlBoundaryCacheKey key,
    NovelReaderComplexHtmlSliceSession session,
  ) {
    _entries.remove(key);
    _entries[key] = session;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

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
    normalizerRevision,
    boundaryIndexerRevision,
  );
}

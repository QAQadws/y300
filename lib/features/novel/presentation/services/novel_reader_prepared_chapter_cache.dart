import 'dart:collection';
import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// A bounded process-local cache for prepared HTML documents.
///
/// Prepared chapters are derived from the canonical SQLite正文 and reader
/// preferences. They are never an offline storage format and are safe to
/// discard whenever memory pressure or a new content identity requires it.
final class NovelReaderPreparedChapterCache {
  NovelReaderPreparedChapterCache({
    this.capacity = 4,
    this.maxEstimatedBytes = 8 * 1024 * 1024,
  }) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
    if (maxEstimatedBytes < 0) {
      throw ArgumentError.value(
        maxEstimatedBytes,
        'maxEstimatedBytes',
        'must be nonnegative',
      );
    }
  }

  final int capacity;
  final int maxEstimatedBytes;
  final LinkedHashMap<String, ({NovelReaderPreparedChapter chapter, int bytes})>
  _entries =
      LinkedHashMap<
        String,
        ({NovelReaderPreparedChapter chapter, int bytes})
      >();
  final Map<String, Future<NovelReaderPreparedChapter>> _inFlight = {};
  int _generation = 0;
  int _estimatedRetainedBytes = 0;
  bool _closed = false;

  int get length => _entries.length;
  bool get isClosed => _closed;

  /// Fixed-weight estimate of retained documents/projections and image metadata.
  /// Shared strings may be counted twice; in-flight work and real heap size are excluded.
  int get estimatedRetainedBytes => _estimatedRetainedBytes;

  NovelReaderPreparedChapter? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    _entries[key] = entry;
    return entry.chapter;
  }

  void put(String key, NovelReaderPreparedChapter chapter) {
    if (_closed) {
      return;
    }
    evict(key);
    final bytes = _estimate(key, chapter);
    if (bytes > maxEstimatedBytes) {
      return;
    }
    _entries[key] = (chapter: chapter, bytes: bytes);
    _estimatedRetainedBytes += bytes;
    while (_entries.length > capacity ||
        _estimatedRetainedBytes > maxEstimatedBytes) {
      evict(_entries.keys.first);
    }
  }

  Future<NovelReaderPreparedChapter> resolve({
    required String key,
    required Future<NovelReaderPreparedChapter> Function() prepare,
  }) {
    if (_closed) {
      return Future<NovelReaderPreparedChapter>.error(
        StateError('The prepared chapter cache has been disposed.'),
      );
    }
    final cached = get(key);
    if (cached != null) {
      return Future<NovelReaderPreparedChapter>.value(cached);
    }
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }
    final generation = _generation;
    late final Future<NovelReaderPreparedChapter> future;
    future = Future<NovelReaderPreparedChapter>.sync(prepare).then((chapter) {
      if (!_closed &&
          generation == _generation &&
          identical(_inFlight[key], future)) {
        put(key, chapter);
      }
      return chapter;
    });
    _inFlight[key] = future;
    unawaited(
      future.then<void>(
        (_) => _removeInFlight(key, future),
        onError: (Object error, StackTrace stack) =>
            _removeInFlight(key, future),
      ),
    );
    return future;
  }

  void evict(String key) {
    _inFlight.remove(key);
    final entry = _entries.remove(key);
    if (entry != null) {
      _estimatedRetainedBytes -= entry.bytes;
    }
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

  void _removeInFlight(String key, Future<NovelReaderPreparedChapter> future) {
    if (identical(_inFlight[key], future)) {
      _inFlight.remove(key);
    }
  }

  int _estimate(String key, NovelReaderPreparedChapter chapter) {
    final document = chapter.renderDocument;
    var bytes =
        256 +
        2 *
            (key.length +
                chapter.episodeId.length +
                chapter.contentHash.length +
                chapter.html.length +
                (chapter.scrollHtml?.length ?? 0) +
                chapter.themeSignature.length +
                document.preparedHtml.length +
                document.themeSignature.length +
                document.sequence.sourceId.length);
    for (final fragment in chapter.scrollFragments ?? const <String>[]) {
      bytes += 24 + 2 * fragment.length;
    }
    for (final unit in chapter.flowUnits) {
      bytes +=
          96 +
          2 * (unit.unitId.length + unit.html.length) +
          8 * unit.imageIndices.length +
          _anchorBytes(unit.startAnchor) +
          _anchorBytes(unit.endAnchor) +
          8 *
              (unit
                      .sourceAnchorProjection
                      ?.semanticOffsetsBySourceRuneBoundary
                      .length ??
                  0);
    }
    for (final entry in document.sequence.entries) {
      bytes +=
          128 +
          2 *
              (entry.url.length +
                  entry.rawSrc.length +
                  entry.cacheKey.length +
                  (entry.attachmentId?.length ?? 0) +
                  (entry.alt?.length ?? 0) +
                  (entry.title?.length ?? 0));
    }
    for (final entry in document.attachmentIdsByUrl.entries) {
      bytes += 32 + 2 * (entry.key.length + entry.value.length);
    }
    return bytes;
  }

  int _anchorBytes(NovelReaderTextAnchor anchor) =>
      64 +
      2 *
          (anchor.episodeId.length +
              (anchor.nodeId?.length ?? 0) +
              (anchor.textIdentity?.length ?? 0));
}

/// Adds bounded caching and same-request single-flight to preparation without
/// changing the existing HTML preparation contract.
final class NovelReaderCachingHtmlPreparationService
    implements NovelReaderHtmlPreparationService {
  NovelReaderCachingHtmlPreparationService({
    required NovelReaderHtmlPreparationService delegate,
    NovelReaderPreparedChapterCache? cache,
  }) : _delegate = delegate,
       cache = cache ?? NovelReaderPreparedChapterCache();

  final NovelReaderHtmlPreparationService _delegate;
  final NovelReaderPreparedChapterCache cache;

  @override
  int get legacyMarkupNormalizerRevision =>
      _delegate.legacyMarkupNormalizerRevision;

  @override
  Future<NovelReaderPreparedChapter> prepare({
    required String rawHtml,
    required NovelEpisodeItem episode,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
    NovelReaderDocument? semanticDocument,
    bool refresh = false,
  }) {
    final key = _PreparationCacheKey.from(
      rawHtml: rawHtml,
      episodeId: episode.episodeId,
      sourceTid: episode.sourceTid,
      preferences: preferences,
      themeSignature: theme.signature,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
      semanticDocumentHash: semanticDocument?.rawHtmlHash,
      semanticConversionIdentity: semanticDocument?.textConversionIdentity,
      legacyMarkupNormalizerRevision: legacyMarkupNormalizerRevision,
    ).value;
    // An explicit retry must not rejoin an unsettled, timed-out preparation.
    // Identity checks keep its late completion from replacing the new entry.
    if (refresh) cache.evict(key);
    return cache.resolve(
      key: key,
      prepare: () => _delegate.prepare(
        rawHtml: rawHtml,
        episode: episode,
        preferences: preferences,
        theme: theme,
        sourceId: sourceId,
        threadId: threadId,
        imageCacheOwnerId: imageCacheOwnerId,
        semanticDocument: semanticDocument,
      ),
    );
  }
}

final class _PreparationCacheKey {
  const _PreparationCacheKey(this.value);

  final String value;

  factory _PreparationCacheKey.from({
    required String rawHtml,
    required String episodeId,
    required String sourceTid,
    required ForumHtmlReaderPreferences preferences,
    required String themeSignature,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
    required String? semanticDocumentHash,
    required String? semanticConversionIdentity,
    required int legacyMarkupNormalizerRevision,
  }) {
    final source = <String?>[
      _hash(rawHtml),
      episodeId,
      sourceTid,
      preferences.hashCode.toString(),
      preferences.typography.hashCode.toString(),
      preferences.conversionMode.name,
      preferences.preserveAuthorFontSize.toString(),
      themeSignature,
      sourceId,
      threadId,
      imageCacheOwnerId,
      semanticDocumentHash,
      semanticConversionIdentity,
      legacyMarkupNormalizerRevision.toString(),
    ].join('\u001f');
    return _PreparationCacheKey(_hash(source));
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  @override
  bool operator ==(Object other) =>
      other is _PreparationCacheKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

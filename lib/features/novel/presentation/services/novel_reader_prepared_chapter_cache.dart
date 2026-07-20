import 'dart:collection';
import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

/// A bounded process-local cache for prepared HTML documents.
///
/// Prepared chapters are derived from the canonical SQLite正文 and reader
/// preferences. They are never an offline storage format and are safe to
/// discard whenever memory pressure or a new content identity requires it.
final class NovelReaderPreparedChapterCache {
  NovelReaderPreparedChapterCache({this.capacity = 4}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final int capacity;
  final LinkedHashMap<String, NovelReaderPreparedChapter> _entries =
      LinkedHashMap<String, NovelReaderPreparedChapter>();

  int get length => _entries.length;

  NovelReaderPreparedChapter? get(String key) {
    final chapter = _entries.remove(key);
    if (chapter == null) {
      return null;
    }
    _entries[key] = chapter;
    return chapter;
  }

  void put(String key, NovelReaderPreparedChapter chapter) {
    _entries.remove(key);
    _entries[key] = chapter;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void evict(String key) => _entries.remove(key);

  void clear() => _entries.clear();
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
  final Map<String, Future<NovelReaderPreparedChapter>> _inFlight =
      <String, Future<NovelReaderPreparedChapter>>{};

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
    ).value;
    final cached = cache.get(key);
    if (cached != null) {
      return Future<NovelReaderPreparedChapter>.value(cached);
    }
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }
    final future = _delegate
        .prepare(
          rawHtml: rawHtml,
          episode: episode,
          preferences: preferences,
          theme: theme,
          sourceId: sourceId,
          threadId: threadId,
          imageCacheOwnerId: imageCacheOwnerId,
          semanticDocument: semanticDocument,
        )
        .then((prepared) {
          cache.put(key, prepared);
          return prepared;
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

  void _removeInFlight(String key, Future<NovelReaderPreparedChapter> future) {
    if (identical(_inFlight[key], future)) {
      _inFlight.remove(key);
    }
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

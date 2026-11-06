import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html;
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/repositories/library_state_repository.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/preferences/novel_chapter_interactions_dock_preferences_provider.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_interactions_dock_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';

/// Only the I/O boundary is synthetic. Bootstrap, preparation, controllers,
/// layout, visibility and progress commits all use the production page.
final class NovelMainPageProfileData
    implements NovelRepository, NovelReadingStateRepository {
  final _chapters = <String, NovelChapterContent>{};
  final _progress = <String, NovelReadingProgress>{};
  final _states = <String, LibraryEpisodeState>{};
  final _bookmarks = <String, NovelReaderBookmark>{};
  final _preferences = _Preferences();
  int _serial = 0;

  int get retainedChapters => _chapters.length;

  ({String novelId, String episodeId}) add(
    String source, {
    List<String>? storedParagraphs,
  }) {
    final id = 'synthetic-profile:${++_serial}';
    final text =
        storedParagraphs?.join('\n') ?? html.parseFragment(source).text ?? '';
    _chapters[id] = NovelChapterContent(
      episodeId: id,
      rawHtml: source,
      plainText: text,
      paragraphs: storedParagraphs ?? [text],
    );
    // Every open starts without a persisted position or typography preview.
    _preferences.value = profileReaderPreferences;
    return (novelId: id, episodeId: id);
  }

  void release(String id) {
    _chapters.remove(id);
    _progress.remove(id);
    _states.remove(id);
    _bookmarks.removeWhere((_, bookmark) => bookmark.novelId == id);
  }

  Widget scope(
    Widget child, {
    NovelReaderPreferencesRepository? preferences,
  }) => ProviderScope(
    overrides: [
      novelRepositoryProvider.overrideWithValue(this),
      novelReaderPreferencesRepositoryProvider.overrideWithValue(
        preferences ?? _preferences,
      ),
      novelChapterInteractionsDockPreferencesRepositoryProvider
          .overrideWithValue(_DisabledDock()),
      libraryStateRepositoryProvider.overrideWithValue(_UnusedLibraryState()),
      forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      imageCacheServiceProvider.overrideWithValue(_UnusedImages()),
    ],
    child: child,
  );

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async => [
    NovelEpisodeItem(
      episodeId: novelId,
      novelId: novelId,
      sourceTid: '100',
      sourcePid: '5001',
      episodeTitle: 'Synthetic chapter',
      orderIndex: 0,
    ),
  ];

  @override
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async => _chapters[episodeId];

  @override
  Future<NovelItem?> getDetail({required String novelId}) async => NovelItem(
    novelId: novelId,
    sourceTid: '100',
    sourceFid: '49',
    title: 'Synthetic profile corpus',
    updatedAt: DateTime.utc(2026, 10, 1),
    episodeCount: 1,
  );

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async => [
    for (final bookmark in _bookmarks.values)
      if (bookmark.novelId == novelId) bookmark,
  ];

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {
    _bookmarks[bookmark.bookmarkId] = bookmark;
  }

  @override
  Future<NovelReadingStateSnapshot> loadWorkState({
    required String novelId,
  }) async => NovelReadingStateSnapshot(
    novelId: novelId,
    progressByEpisode: {novelId: ?_progress[novelId]},
    episodeStates: {novelId: ?_states[novelId]},
    recentEpisodeId: _progress.containsKey(novelId) ? novelId : null,
  );

  @override
  Future<NovelReadingProgress?> getChapterProgress({
    required String novelId,
    required String episodeId,
  }) async => _progress[episodeId];

  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) async {
    if (canCommit?.call() == false ||
        !_chapters.containsKey(progress.episodeId)) {
      return false;
    }
    _progress[progress.episodeId] = progress;
    if (markCompleted) {
      _states[progress.episodeId] = LibraryEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: progress.episodeId,
        workId: progress.novelId,
        isRead: true,
      );
    }
    return true;
  }

  // Unexpected I/O must fail, rather than quietly reaching the user's account.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected profile I/O: ${invocation.memberName}');
}

final profileReaderPreferences = NovelReaderPreferences.defaults().copyWith(
  flowMode: NovelReaderFlowMode.pagedLtr,
  fontSize: 18.5,
  lineHeight: 1.6,
  paragraphSpacing: 12,
  conversionMode: NovelReaderConversionMode.none,
);

final class _Preferences implements NovelReaderPreferencesRepository {
  NovelReaderPreferences value = profileReaderPreferences;
  @override
  Future<NovelReaderPreferences> load() async => value;
  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    value = preferences;
  }
}

final class _DisabledDock
    implements NovelChapterInteractionsDockPreferencesRepository {
  @override
  Future<NovelChapterInteractionsDockPreferences> load() async =>
      const NovelChapterInteractionsDockPreferences(enabled: false);
  @override
  Future<void> save(
    NovelChapterInteractionsDockPreferences preferences,
  ) async {}
}

final class _UnusedLibraryState implements LibraryStateRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected profile shared I/O: ${invocation.memberName}',
  );
}

final class _UnusedImages implements ImageCacheService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected profile image I/O: ${invocation.memberName}',
  );
}

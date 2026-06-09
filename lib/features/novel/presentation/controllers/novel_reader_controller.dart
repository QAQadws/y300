import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_reader_cache_service.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';

class NovelReaderArgs {
  const NovelReaderArgs({
    required this.novelId,
    required this.episodeId,
  });

  final String novelId;
  final String episodeId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is NovelReaderArgs &&
        other.novelId == novelId &&
        other.episodeId == episodeId;
  }

  @override
  int get hashCode => Object.hash(novelId, episodeId);
}

class NovelReaderViewState {
  const NovelReaderViewState({
    required this.novel,
    required this.episodes,
    required this.currentEpisode,
    required this.currentContent,
    required this.document,
    required this.preferences,
    required this.readingProgress,
    required this.progressSnapshot,
    required this.currentOffset,
    this.bookmarks = const <NovelReaderBookmark>[],
    this.currentEpisodeBookmarks = const <NovelReaderBookmark>[],
    this.searchResults = const <NovelReaderSearchResult>[],
    this.currentSearchIndex = -1,
    this.searchKeyword = '',
    this.downloadedEpisodeIds = const <String>{},
    this.isCachingEpisodes = false,
    this.cacheCurrent = 0,
    this.cacheTotal = 0,
    this.cacheError,
  });

  final NovelItem? novel;
  final List<NovelEpisodeItem> episodes;
  final NovelEpisodeItem currentEpisode;
  final NovelChapterContent currentContent;
  final NovelReaderDocument document;
  final NovelReaderPreferences preferences;
  final NovelReadingProgress? readingProgress;
  final NovelReaderProgressSnapshot progressSnapshot;
  final double currentOffset;
  final List<NovelReaderBookmark> bookmarks;
  final List<NovelReaderBookmark> currentEpisodeBookmarks;
  final List<NovelReaderSearchResult> searchResults;
  final int currentSearchIndex;
  final String searchKeyword;
  final Set<String> downloadedEpisodeIds;
  final bool isCachingEpisodes;
  final int cacheCurrent;
  final int cacheTotal;
  final String? cacheError;

  int get currentEpisodeIndex {
    return episodes.indexWhere(
      (episode) => episode.episodeId == currentEpisode.episodeId,
    );
  }

  NovelEpisodeItem? get previousEpisode {
    final index = currentEpisodeIndex;
    if (index <= 0) {
      return null;
    }
    return episodes[index - 1];
  }

  NovelEpisodeItem? get nextEpisode {
    final index = currentEpisodeIndex;
    if (index < 0 || index >= episodes.length - 1) {
      return null;
    }
    return episodes[index + 1];
  }

  bool get hasPreviousEpisode => previousEpisode != null;

  bool get hasNextEpisode => nextEpisode != null;

  bool get isCurrentEpisodeDownloaded {
    return downloadedEpisodeIds.contains(currentEpisode.episodeId);
  }

  bool get hasCurrentEpisodeBookmark {
    return currentEpisodeBookmarks.any(
      (bookmark) => bookmark.bookmarkId.startsWith('episode-bookmark:'),
    );
  }

  Set<String> get bookmarkEpisodeIds {
    return bookmarks.map((bookmark) => bookmark.episodeId).toSet();
  }

  NovelReaderSearchResult? get currentSearchResult {
    if (currentSearchIndex < 0 || currentSearchIndex >= searchResults.length) {
      return null;
    }
    return searchResults[currentSearchIndex];
  }

  NovelReaderViewState copyWith({
    NovelItem? novel,
    bool clearNovel = false,
    List<NovelEpisodeItem>? episodes,
    NovelEpisodeItem? currentEpisode,
    NovelChapterContent? currentContent,
    NovelReaderDocument? document,
    NovelReaderPreferences? preferences,
    NovelReadingProgress? readingProgress,
    bool clearReadingProgress = false,
    NovelReaderProgressSnapshot? progressSnapshot,
    double? currentOffset,
    List<NovelReaderBookmark>? bookmarks,
    List<NovelReaderBookmark>? currentEpisodeBookmarks,
    List<NovelReaderSearchResult>? searchResults,
    int? currentSearchIndex,
    String? searchKeyword,
    Set<String>? downloadedEpisodeIds,
    bool? isCachingEpisodes,
    int? cacheCurrent,
    int? cacheTotal,
    String? cacheError,
    bool clearCacheError = false,
  }) {
    return NovelReaderViewState(
      novel: clearNovel ? null : (novel ?? this.novel),
      episodes: episodes ?? this.episodes,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      currentContent: currentContent ?? this.currentContent,
      document: document ?? this.document,
      preferences: preferences ?? this.preferences,
      readingProgress:
          clearReadingProgress ? null : (readingProgress ?? this.readingProgress),
      progressSnapshot: progressSnapshot ?? this.progressSnapshot,
      currentOffset: currentOffset ?? this.currentOffset,
      bookmarks: bookmarks ?? this.bookmarks,
      currentEpisodeBookmarks:
          currentEpisodeBookmarks ?? this.currentEpisodeBookmarks,
      searchResults: searchResults ?? this.searchResults,
      currentSearchIndex: currentSearchIndex ?? this.currentSearchIndex,
      searchKeyword: searchKeyword ?? this.searchKeyword,
      downloadedEpisodeIds: downloadedEpisodeIds ?? this.downloadedEpisodeIds,
      isCachingEpisodes: isCachingEpisodes ?? this.isCachingEpisodes,
      cacheCurrent: cacheCurrent ?? this.cacheCurrent,
      cacheTotal: cacheTotal ?? this.cacheTotal,
      cacheError: clearCacheError ? null : (cacheError ?? this.cacheError),
    );
  }
}

final novelReaderControllerProvider = AsyncNotifierProvider.autoDispose
    .family<NovelReaderController, NovelReaderViewState, NovelReaderArgs>(
  (args) => NovelReaderController(args),
);

class NovelReaderController extends AsyncNotifier<NovelReaderViewState> {
  NovelReaderController(this._args);

  final NovelReaderArgs _args;
  final NovelReaderProgressPolicy _progressPolicy = const NovelReaderProgressPolicy();
  Timer? _saveDebounce;

  @override
  FutureOr<NovelReaderViewState> build() async {
    ref.onDispose(() => _saveDebounce?.cancel());
    return _load(_args.episodeId);
  }

  Future<void> updatePreferences(NovelReaderPreferences preferences) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    await ref.read(novelRepositoryProvider).upsertReaderPreferences(preferences);
    state = AsyncData(
      current.copyWith(
        preferences: preferences,
        progressSnapshot: current.progressSnapshot.copyWith(
          flowMode: preferences.flowMode,
        ),
      ),
    );
  }

  Future<void> openEpisode(String episodeId) async {
    final current = state.value;
    if (current == null || current.currentEpisode.episodeId == episodeId) {
      return;
    }
    final preservedProgress = current.readingProgress;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _load(episodeId, preservedProgress: preservedProgress),
    );
  }

  Future<void> openEpisodeFromCatalog(String episodeId) {
    return openEpisode(episodeId);
  }

  Future<void> goToPreviousEpisode() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final previous = current.previousEpisode;
    if (previous == null) {
      return;
    }
    await openEpisode(previous.episodeId);
  }

  Future<void> goToNextEpisode() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final next = current.nextEpisode;
    if (next == null) {
      return;
    }
    await openEpisode(next.episodeId);
  }

  Future<void> onScrollOffsetChanged(
    double offset, {
    double maxScrollExtent = 0,
  }) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final snapshot = _progressPolicy.verticalSnapshot(
      novelId: _args.novelId,
      episodeId: current.currentEpisode.episodeId,
      scrollOffset: offset,
      maxScrollExtent: maxScrollExtent,
    );
    state = AsyncData(
      current.copyWith(
        currentOffset: offset,
        progressSnapshot: snapshot,
      ),
    );

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 200), () async {
      await _saveProgressSnapshot(snapshot);
    });
  }

  Future<void> saveCurrentOffsetNow(double offset) async {
    return saveCurrentProgressNow(
      _progressPolicy.verticalSnapshot(
        novelId: _args.novelId,
        episodeId: state.value?.currentEpisode.episodeId ?? _args.episodeId,
        scrollOffset: offset,
      ),
    );
  }

  Future<void> saveCurrentProgressNow(
    NovelReaderProgressSnapshot snapshot,
  ) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    _saveDebounce?.cancel();
    state = AsyncData(
      current.copyWith(
        currentOffset: snapshot.scrollOffset,
        progressSnapshot: snapshot,
      ),
    );
    await _saveProgressSnapshot(snapshot);
  }

  Future<void> onPagedPageChanged(
    int pageIndex,
    NovelReaderPageLayout layout,
  ) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final snapshot = _progressPolicy.pagedSnapshot(
      novelId: _args.novelId,
      episodeId: current.currentEpisode.episodeId,
      flowMode: current.preferences.flowMode,
      pageIndex: pageIndex,
      layout: layout,
    );
    _saveDebounce?.cancel();
    state = AsyncData(current.copyWith(progressSnapshot: snapshot));
    await _saveProgressSnapshot(snapshot);
  }

  void searchInCurrentChapter(String keyword) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final results = ref.read(novelReaderSearchServiceProvider).search(
          document: current.document,
          keyword: keyword,
        );
    state = AsyncData(
      current.copyWith(
        searchKeyword: keyword.trim(),
        searchResults: results,
        currentSearchIndex: results.isEmpty ? -1 : 0,
      ),
    );
  }

  void clearSearch() {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        searchKeyword: '',
        searchResults: const <NovelReaderSearchResult>[],
        currentSearchIndex: -1,
      ),
    );
  }

  void selectSearchResult(String resultId) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final index = current.searchResults.indexWhere(
      (result) => result.resultId == resultId,
    );
    if (index < 0) {
      return;
    }
    state = AsyncData(current.copyWith(currentSearchIndex: index));
  }

  Future<void> addBookmarkAtCurrentPosition(
    NovelReaderTextAnchor anchor, {
    String? note,
  }) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final now = DateTime.now();
    final bookmark = NovelReaderBookmark(
      bookmarkId: 'reader-bookmark:${now.microsecondsSinceEpoch}',
      novelId: _args.novelId,
      episodeId: current.currentEpisode.episodeId,
      anchor: anchor.copyWith(episodeId: current.currentEpisode.episodeId),
      title: current.currentEpisode.episodeTitle,
      snippet: _snippetForAnchor(current.document, anchor),
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    final repository = ref.read(novelRepositoryProvider);
    await repository.addReaderBookmark(bookmark: bookmark);
    await _reloadBookmarks(repository);
  }

  Future<void> removeBookmark(String bookmarkId) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final repository = ref.read(novelRepositoryProvider);
    final bookmark = _findBookmark(current.bookmarks, bookmarkId);
    if (bookmark?.bookmarkId.startsWith('episode-bookmark:') == true) {
      await repository.toggleEpisodeBookmark(
        novelId: _args.novelId,
        episodeId: bookmark!.episodeId,
        isBookmarked: false,
      );
      await _reloadBookmarks(repository);
      return;
    }
    await repository.removeReaderBookmark(bookmarkId: bookmarkId);
    await _reloadBookmarks(repository);
  }

  Future<void> toggleCurrentEpisodeBookmark() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final repository = ref.read(novelRepositoryProvider);
    await repository.toggleEpisodeBookmark(
      novelId: _args.novelId,
      episodeId: current.currentEpisode.episodeId,
      isBookmarked: !current.hasCurrentEpisodeBookmark,
    );
    await _reloadBookmarks(repository);
  }

  Future<NovelReaderCacheResult> cacheCurrentEpisode() {
    return _runCacheOperation(
      (service, current) => service.cacheCurrentEpisode(
        novelId: _args.novelId,
        episodeId: current.currentEpisode.episodeId,
        onProgress: _updateCacheProgress,
      ),
    );
  }

  Future<NovelReaderCacheResult> cacheFollowingEpisodes({int count = 5}) {
    return _runCacheOperation(
      (service, current) => service.cacheFollowingEpisodes(
        novelId: _args.novelId,
        episodeId: current.currentEpisode.episodeId,
        count: count,
        onProgress: _updateCacheProgress,
      ),
    );
  }

  Future<NovelReaderCacheResult> deleteCurrentEpisodeCache() {
    return _runCacheOperation(
      (service, current) => service.deleteCurrentEpisodeCache(
        novelId: _args.novelId,
        episodeId: current.currentEpisode.episodeId,
        onProgress: _updateCacheProgress,
      ),
    );
  }

  Future<void> refreshCurrentEpisode() async {
    final current = state.value;
    final repository = ref.read(novelRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await repository.refreshEpisodes(novelId: _args.novelId);
      return _load(
        current?.currentEpisode.episodeId ?? _args.episodeId,
        preservedProgress: current?.readingProgress,
      );
    });
  }

  Future<NovelReaderViewState> _load(
    String episodeId, {
    NovelReadingProgress? preservedProgress,
  }) async {
    final repository = ref.read(novelRepositoryProvider);
    NovelItem? novel;
    try {
      novel = await repository.getDetail(novelId: _args.novelId);
    } catch (_) {
      novel = null;
    }
    final episodes = await repository.getEpisodes(
      novelId: _args.novelId,
      descending: false,
    );
    if (episodes.isEmpty) {
      throw StateError('小说章节目录为空');
    }
    final currentEpisode = episodes.firstWhere(
      (episode) => episode.episodeId == episodeId,
      orElse: () => episodes.first,
    );

    final downloadService = ref.read(novelDownloadServiceProvider);
    final content = await downloadService.getDownloadedChapterContent(
          novelId: _args.novelId,
          episodeId: currentEpisode.episodeId,
        ) ??
        await repository.getChapterContent(episodeId: currentEpisode.episodeId);
    if (content == null) {
      throw StateError('章节内容不存在');
    }
    final document = ref.read(novelReaderDocumentParserProvider).parse(
          episodeId: content.episodeId,
          rawHtml: content.rawHtml,
          fallbackParagraphs: content.paragraphs,
        );

    final preferences = await repository.getReaderPreferences();
    final progress = await repository.getReadingProgress(novelId: _args.novelId);
    final restoreProgress = _progressForEpisode(
      episodeId: currentEpisode.episodeId,
      currentProgress: progress,
      preservedProgress: preservedProgress,
    );
    final progressSnapshot = _progressPolicy.fromReadingProgress(
      novelId: _args.novelId,
      episodeId: currentEpisode.episodeId,
      flowMode: preferences.flowMode,
      progress: restoreProgress,
    );
    final offset = progressSnapshot.scrollOffset;
    final bookmarks = await repository.listReaderBookmarks(novelId: _args.novelId);
    final currentEpisodeBookmarks = _bookmarksForEpisode(
      bookmarks,
      currentEpisode.episodeId,
    );
    final downloadedEpisodeIds =
        await ref.read(novelReaderCacheServiceProvider).getDownloadedEpisodeIds(
              novelId: _args.novelId,
              episodeIds: episodes.map((episode) => episode.episodeId),
            );

    return NovelReaderViewState(
      novel: novel,
      episodes: episodes,
      currentEpisode: currentEpisode,
      currentContent: content,
      document: document,
      preferences: preferences,
      readingProgress: progress,
      progressSnapshot: progressSnapshot,
      currentOffset: offset,
      bookmarks: bookmarks,
      currentEpisodeBookmarks: currentEpisodeBookmarks,
      searchResults: const <NovelReaderSearchResult>[],
      currentSearchIndex: -1,
      searchKeyword: '',
      downloadedEpisodeIds: downloadedEpisodeIds,
    );
  }

  NovelReadingProgress? _progressForEpisode({
    required String episodeId,
    required NovelReadingProgress? currentProgress,
    required NovelReadingProgress? preservedProgress,
  }) {
    if (currentProgress?.episodeId == episodeId) {
      return currentProgress;
    }
    if (preservedProgress?.episodeId == episodeId) {
      return preservedProgress;
    }
    return null;
  }

  Future<void> _saveProgressSnapshot(NovelReaderProgressSnapshot snapshot) {
    return ref.read(novelRepositoryProvider).saveReadingProgress(
          novelId: _args.novelId,
          episodeId: snapshot.episodeId,
          scrollOffset: snapshot.scrollOffset,
          flowMode: snapshot.flowMode,
          pageIndex: snapshot.pageIndex,
          anchorNodeId: snapshot.anchorNodeId,
          progressPercent: snapshot.progressPercent,
        );
  }

  Future<void> _reloadBookmarks(NovelRepository repository) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final bookmarks = await repository.listReaderBookmarks(novelId: _args.novelId);
    state = AsyncData(
      current.copyWith(
        bookmarks: bookmarks,
        currentEpisodeBookmarks: _bookmarksForEpisode(
          bookmarks,
          current.currentEpisode.episodeId,
        ),
      ),
    );
  }

  List<NovelReaderBookmark> _bookmarksForEpisode(
    List<NovelReaderBookmark> bookmarks,
    String episodeId,
  ) {
    return bookmarks
        .where((bookmark) => bookmark.episodeId == episodeId)
        .toList(growable: false);
  }

  NovelReaderBookmark? _findBookmark(
    List<NovelReaderBookmark> bookmarks,
    String bookmarkId,
  ) {
    for (final bookmark in bookmarks) {
      if (bookmark.bookmarkId == bookmarkId) {
        return bookmark;
      }
    }
    return null;
  }

  String _snippetForAnchor(
    NovelReaderDocument document,
    NovelReaderTextAnchor anchor,
  ) {
    final nodeId = anchor.nodeId;
    if (nodeId != null) {
      for (final node in document.nodes) {
        if (node.id == nodeId) {
          final text = _textForNode(node).trim();
          if (text.isNotEmpty) {
            final start = anchor.textOffset.clamp(0, text.length).toInt();
            final end = (start + 36).clamp(0, text.length).toInt();
            return text.substring(start, end);
          }
        }
      }
    }
    final plainText = document.plainText.trim();
    if (plainText.isEmpty) {
      return '当前位置';
    }
    return plainText.length <= 36 ? plainText : plainText.substring(0, 36);
  }

  String _textForNode(NovelReaderNode node) {
    final ownText = node.text;
    if (ownText != null && ownText.isNotEmpty) {
      return ownText;
    }
    if (node.link != null) {
      return node.link!.text;
    }
    return node.children
        .map(_textForNode)
        .where((text) => text.trim().isNotEmpty)
        .join('\n');
  }

  Future<NovelReaderCacheResult> _runCacheOperation(
    Future<NovelReaderCacheResult> Function(
      NovelReaderCacheService service,
      NovelReaderViewState current,
    ) operation,
  ) async {
    final current = state.value;
    if (current == null || current.isCachingEpisodes) {
      return const NovelReaderCacheResult.empty();
    }
    state = AsyncData(
      current.copyWith(
        isCachingEpisodes: true,
        cacheCurrent: 0,
        cacheTotal: 0,
        clearCacheError: true,
      ),
    );
    final service = ref.read(novelReaderCacheServiceProvider);
    late final NovelReaderCacheResult result;
    try {
      result = await operation(service, current);
    } catch (error) {
      result = NovelReaderCacheResult(
        totalCount: 1,
        successCount: 0,
        failureCount: 1,
        errorMessage: error.toString(),
      );
    }
    final latest = state.value ?? current;
    var downloadedEpisodeIds = latest.downloadedEpisodeIds;
    try {
      downloadedEpisodeIds = await service.getDownloadedEpisodeIds(
        novelId: _args.novelId,
        episodeIds: latest.episodes.map((episode) => episode.episodeId),
      );
    } catch (_) {}
    state = AsyncData(
      latest.copyWith(
        downloadedEpisodeIds: downloadedEpisodeIds,
        isCachingEpisodes: false,
        cacheCurrent: result.totalCount,
        cacheTotal: result.totalCount,
        cacheError: result.hasFailures ? result.errorMessage ?? '部分章节缓存失败' : null,
        clearCacheError: !result.hasFailures,
      ),
    );
    return result;
  }

  void _updateCacheProgress(int current, int total) {
    final viewState = state.value;
    if (viewState == null) {
      return;
    }
    state = AsyncData(
      viewState.copyWith(
        isCachingEpisodes: true,
        cacheCurrent: current,
        cacheTotal: total,
      ),
    );
  }
}

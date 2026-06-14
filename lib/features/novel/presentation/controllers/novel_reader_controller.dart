import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_reader_cache_service.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_transition_state.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_bootstrap_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_preference_impact_analyzer.dart';

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
    required this.persistedPreferences,
    required this.effectivePreferences,
    required this.readingProgress,
    required this.progressSnapshot,
    required this.currentOffset,
    this.bookmarks = const <NovelReaderBookmark>[],
    this.currentEpisodeBookmarks = const <NovelReaderBookmark>[],
    this.searchResults = const <NovelReaderSearchResult>[],
    this.currentSearchIndex = -1,
    this.searchKeyword = '',
    this.downloadedEpisodeIds = const <String>{},
    this.transition,
    this.isHydratingSupplemental = false,
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
  final NovelReaderPreferences persistedPreferences;
  final NovelReaderPreferences effectivePreferences;
  final NovelReadingProgress? readingProgress;
  final NovelReaderProgressSnapshot progressSnapshot;
  final double currentOffset;
  final List<NovelReaderBookmark> bookmarks;
  final List<NovelReaderBookmark> currentEpisodeBookmarks;
  final List<NovelReaderSearchResult> searchResults;
  final int currentSearchIndex;
  final String searchKeyword;
  final Set<String> downloadedEpisodeIds;
  final NovelReaderTransitionState? transition;
  final bool isHydratingSupplemental;
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

  NovelReaderPreferences get preferences => effectivePreferences;

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
    NovelReaderPreferences? persistedPreferences,
    NovelReaderPreferences? effectivePreferences,
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
    NovelReaderTransitionState? transition,
    bool clearTransition = false,
    bool? isHydratingSupplemental,
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
      persistedPreferences:
          persistedPreferences ?? this.persistedPreferences,
      effectivePreferences:
          effectivePreferences ?? this.effectivePreferences,
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
      transition: clearTransition ? null : (transition ?? this.transition),
      isHydratingSupplemental:
          isHydratingSupplemental ?? this.isHydratingSupplemental,
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
  final NovelReaderProgressPolicy _progressPolicy =
      const NovelReaderProgressPolicy();
  final NovelReaderPreferenceImpactAnalyzer _preferenceImpactAnalyzer =
      const DefaultNovelReaderPreferenceImpactAnalyzer();
  Timer? _saveDebounce;
  int _activeSessionToken = 0;
  int _transitionRequestSerial = 0;

  @override
  FutureOr<NovelReaderViewState> build() async {
    ref.onDispose(() => _saveDebounce?.cancel());
    return _loadInitialCriticalState(_args.episodeId);
  }

  void previewPreferences(NovelReaderPreferences next) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final diff = _preferenceImpactAnalyzer.compare(
      current.effectivePreferences,
      next,
    );
    if (!diff.hasChanges) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        effectivePreferences: next,
        progressSnapshot: current.progressSnapshot.copyWith(
          flowMode: next.flowMode,
        ),
      ),
    );
  }

  Future<void> commitPreferences(NovelReaderPreferences next) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final persistedDiff = _preferenceImpactAnalyzer.compare(
      current.persistedPreferences,
      next,
    );
    if (!persistedDiff.hasChanges) {
      if (current.effectivePreferences == current.persistedPreferences) {
        return;
      }
      state = AsyncData(
        current.copyWith(
          effectivePreferences: current.persistedPreferences,
          progressSnapshot: current.progressSnapshot.copyWith(
            flowMode: current.persistedPreferences.flowMode,
          ),
        ),
      );
      return;
    }
    await ref.read(novelRepositoryProvider).upsertReaderPreferences(next);
    final latest = state.value ?? current;
    state = AsyncData(
      latest.copyWith(
        persistedPreferences: next,
        effectivePreferences: next,
        progressSnapshot: latest.progressSnapshot.copyWith(
          flowMode: next.flowMode,
        ),
      ),
    );
  }

  void revertPreferencePreview() {
    final current = state.value;
    if (current == null ||
        current.effectivePreferences == current.persistedPreferences) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        effectivePreferences: current.persistedPreferences,
        progressSnapshot: current.progressSnapshot.copyWith(
          flowMode: current.persistedPreferences.flowMode,
        ),
      ),
    );
  }

  Future<bool> openEpisode(String episodeId) async {
    final current = state.value;
    if (current == null) {
      return false;
    }
    if (current.currentEpisode.episodeId == episodeId) {
      return true;
    }
    return _runEpisodeTransition(
      episodeId: episodeId,
      kind: NovelReaderTransitionKind.switchingEpisode,
    );
  }

  Future<bool> openEpisodeFromCatalog(String episodeId) {
    return openEpisode(episodeId);
  }

  Future<bool> goToPreviousEpisode() async {
    final current = state.value;
    if (current == null) {
      return false;
    }
    final previous = current.previousEpisode;
    if (previous == null) {
      return true;
    }
    return openEpisode(previous.episodeId);
  }

  Future<bool> goToNextEpisode() async {
    final current = state.value;
    if (current == null) {
      return false;
    }
    final next = current.nextEpisode;
    if (next == null) {
      return true;
    }
    return openEpisode(next.episodeId);
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
      flowMode: current.effectivePreferences.flowMode,
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

  Future<bool> refreshCurrentEpisode() async {
    final current = state.value;
    final repository = ref.read(novelRepositoryProvider);
    if (current == null) {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() async {
        await repository.refreshEpisodes(novelId: _args.novelId);
        return _loadInitialCriticalState(_args.episodeId);
      });
      return state.hasValue;
    }
    return _runEpisodeTransition(
      episodeId: current.currentEpisode.episodeId,
      kind: NovelReaderTransitionKind.refreshingEpisode,
      refreshEpisodes: true,
    );
  }

  Future<NovelReaderViewState> _loadInitialCriticalState(
    String episodeId, {
    NovelReadingProgress? preservedProgress,
  }) async {
    final context = NovelReaderLoadContext(
      novelId: _args.novelId,
      requestedEpisodeId: episodeId,
      preservedProgress: preservedProgress,
    );
    final critical = await _loadCriticalBootstrap(context);
    if (!ref.mounted) {
      return _initialStateFromCritical(critical);
    }
    final sessionToken = _activeSessionToken + 1;
    _activeSessionToken = sessionToken;
    final viewState = _initialStateFromCritical(critical);
    _scheduleHydrateSupplemental(
      context: context,
      critical: critical,
      sessionToken: sessionToken,
    );
    return viewState;
  }

  Future<NovelReaderCriticalBootstrap> _loadCriticalBootstrap(
    NovelReaderLoadContext context,
  ) {
    return ref.read(novelReaderBootstrapServiceProvider).loadCritical(context);
  }

  Future<bool> _runEpisodeTransition({
    required String episodeId,
    required NovelReaderTransitionKind kind,
    bool refreshEpisodes = false,
  }) async {
    final current = state.value;
    if (current == null) {
      return false;
    }
    final serial = ++_transitionRequestSerial;
    final context = NovelReaderLoadContext(
      novelId: _args.novelId,
      requestedEpisodeId: episodeId,
      preservedProgress: current.readingProgress,
    );
    state = AsyncData(
      current.copyWith(
        transition: NovelReaderTransitionState(
          kind: kind,
          targetEpisodeId: episodeId,
        ),
      ),
    );
    try {
      if (refreshEpisodes) {
        await ref.read(novelRepositoryProvider).refreshEpisodes(
              novelId: _args.novelId,
            );
        if (!ref.mounted) {
          return false;
        }
      }
      final critical = await _loadCriticalBootstrap(context);
      if (!ref.mounted || serial != _transitionRequestSerial) {
        return false;
      }
      final sessionToken = _activeSessionToken + 1;
      _activeSessionToken = sessionToken;
      final nextState = _transitionedStateFromCritical(
        previous: current,
        critical: critical,
      );
      state = AsyncData(nextState);
      _scheduleHydrateSupplemental(
        context: context,
        critical: critical,
        sessionToken: sessionToken,
      );
      return true;
    } catch (_) {
      if (serial != _transitionRequestSerial) {
        return false;
      }
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(clearTransition: true));
      return false;
    }
  }

  void _scheduleHydrateSupplemental({
    required NovelReaderLoadContext context,
    required NovelReaderCriticalBootstrap critical,
    required int sessionToken,
  }) {
    unawaited(() async {
      await Future<void>.delayed(Duration.zero);
      if (!ref.mounted || sessionToken != _activeSessionToken) {
        return;
      }
      await _hydrateSupplemental(
        context: context,
        critical: critical,
        sessionToken: sessionToken,
      );
    }());
  }

  Future<void> _hydrateSupplemental({
    required NovelReaderLoadContext context,
    required NovelReaderCriticalBootstrap critical,
    required int sessionToken,
  }) async {
    try {
      final supplemental = await ref
          .read(novelReaderBootstrapServiceProvider)
          .loadSupplemental(context, critical);
      if (!ref.mounted) {
        return;
      }
      final current = state.value;
      if (current == null ||
          !_canApplySupplemental(
            current: current,
            sessionToken: sessionToken,
            episodeId: critical.currentEpisode.episodeId,
          )) {
        return;
      }
      _mergeSupplemental(current, supplemental);
    } catch (_) {
      if (!ref.mounted) {
        return;
      }
      final current = state.value;
      if (current == null ||
          !_canApplySupplemental(
            current: current,
            sessionToken: sessionToken,
            episodeId: critical.currentEpisode.episodeId,
          )) {
        return;
      }
      state = AsyncData(
        current.copyWith(isHydratingSupplemental: false),
      );
    }
  }

  bool _canApplySupplemental({
    required NovelReaderViewState current,
    required int sessionToken,
    required String episodeId,
  }) {
    return sessionToken == _activeSessionToken &&
        current.currentEpisode.episodeId == episodeId;
  }

  void _mergeSupplemental(
    NovelReaderViewState current,
    NovelReaderSupplementalBootstrap supplemental,
  ) {
    state = AsyncData(
      current.copyWith(
        novel: supplemental.novel,
        bookmarks: supplemental.bookmarks,
        currentEpisodeBookmarks: supplemental.currentEpisodeBookmarks,
        downloadedEpisodeIds: supplemental.downloadedEpisodeIds,
        isHydratingSupplemental: false,
      ),
    );
  }

  NovelReaderViewState _initialStateFromCritical(
    NovelReaderCriticalBootstrap critical,
  ) {
    return NovelReaderViewState(
      novel: null,
      episodes: critical.episodes,
      currentEpisode: critical.currentEpisode,
      currentContent: critical.currentContent,
      document: critical.document,
      persistedPreferences: critical.persistedPreferences,
      effectivePreferences: critical.effectivePreferences,
      readingProgress: critical.readingProgress,
      progressSnapshot: critical.progressSnapshot,
      currentOffset: critical.currentOffset,
      currentEpisodeBookmarks: const <NovelReaderBookmark>[],
      searchResults: const <NovelReaderSearchResult>[],
      currentSearchIndex: -1,
      searchKeyword: '',
      downloadedEpisodeIds: const <String>{},
      transition: null,
      isHydratingSupplemental: true,
    );
  }

  NovelReaderViewState _transitionedStateFromCritical({
    required NovelReaderViewState previous,
    required NovelReaderCriticalBootstrap critical,
  }) {
    final currentEpisodeBookmarks = _bookmarksForEpisode(
      previous.bookmarks,
      critical.currentEpisode.episodeId,
    );
    return previous.copyWith(
      episodes: critical.episodes,
      currentEpisode: critical.currentEpisode,
      currentContent: critical.currentContent,
      document: critical.document,
      persistedPreferences: critical.persistedPreferences,
      effectivePreferences: critical.effectivePreferences,
      readingProgress: critical.readingProgress,
      progressSnapshot: critical.progressSnapshot,
      currentOffset: critical.currentOffset,
      currentEpisodeBookmarks: currentEpisodeBookmarks,
      searchKeyword: '',
      searchResults: const <NovelReaderSearchResult>[],
      currentSearchIndex: -1,
      clearTransition: true,
      isHydratingSupplemental: true,
    );
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
        cacheError:
            result.hasFailures ? result.errorMessage ?? '部分章节缓存失败' : null,
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

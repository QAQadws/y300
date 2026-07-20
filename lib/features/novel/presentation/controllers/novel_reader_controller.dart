import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_transition_state.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_bootstrap_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_preference_impact_analyzer.dart';

class NovelReaderArgs {
  const NovelReaderArgs({required this.novelId, required this.episodeId});

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
    this.transition,
    this.isHydratingSupplemental = false,
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
  final NovelReaderTransitionState? transition;
  final bool isHydratingSupplemental;

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
    NovelReaderTransitionState? transition,
    bool clearTransition = false,
    bool? isHydratingSupplemental,
  }) {
    return NovelReaderViewState(
      novel: clearNovel ? null : (novel ?? this.novel),
      episodes: episodes ?? this.episodes,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      currentContent: currentContent ?? this.currentContent,
      document: document ?? this.document,
      persistedPreferences: persistedPreferences ?? this.persistedPreferences,
      effectivePreferences: effectivePreferences ?? this.effectivePreferences,
      readingProgress: clearReadingProgress
          ? null
          : (readingProgress ?? this.readingProgress),
      progressSnapshot: progressSnapshot ?? this.progressSnapshot,
      currentOffset: currentOffset ?? this.currentOffset,
      bookmarks: bookmarks ?? this.bookmarks,
      currentEpisodeBookmarks:
          currentEpisodeBookmarks ?? this.currentEpisodeBookmarks,
      searchResults: searchResults ?? this.searchResults,
      currentSearchIndex: currentSearchIndex ?? this.currentSearchIndex,
      searchKeyword: searchKeyword ?? this.searchKeyword,
      transition: clearTransition ? null : (transition ?? this.transition),
      isHydratingSupplemental:
          isHydratingSupplemental ?? this.isHydratingSupplemental,
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
  final Map<String, NovelReadingProgress> _knownReadingProgressByEpisodeId =
      <String, NovelReadingProgress>{};
  int _activeSessionToken = 0;
  int _transitionRequestSerial = 0;
  int _preferenceCommitSerial = 0;

  @override
  FutureOr<NovelReaderViewState> build() async {
    ref.onDispose(ref.read(novelReaderProgressCommitterProvider).cancel);
    return _loadInitialCriticalState(_args.episodeId);
  }

  void previewPreferences(NovelReaderPreferences next) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final effectiveNext = next;
    final diff = _preferenceImpactAnalyzer.compare(
      current.effectivePreferences,
      effectiveNext,
    );
    if (!diff.hasChanges) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        effectivePreferences: effectiveNext,
        progressSnapshot: current.progressSnapshot.copyWith(
          flowMode: effectiveNext.flowMode,
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
      final persistedEffective = current.persistedPreferences;
      if (current.effectivePreferences == persistedEffective) {
        return;
      }
      state = AsyncData(
        current.copyWith(
          effectivePreferences: persistedEffective,
          progressSnapshot: current.progressSnapshot.copyWith(
            flowMode: persistedEffective.flowMode,
          ),
        ),
      );
      return;
    }
    final commitSerial = ++_preferenceCommitSerial;
    await ref.read(novelReaderPreferencesRepositoryProvider).save(next);
    if (commitSerial != _preferenceCommitSerial) {
      return;
    }
    final latest = state.value ?? current;
    final effectivePreferences =
        latest.effectivePreferences == current.effectivePreferences
        ? next
        : latest.effectivePreferences;
    state = AsyncData(
      latest.copyWith(
        persistedPreferences: next,
        effectivePreferences: effectivePreferences,
        progressSnapshot: latest.progressSnapshot.copyWith(
          flowMode: effectivePreferences.flowMode,
        ),
      ),
    );

    // A traditional/simplified conversion change requires re-building the
    // source document; reload the current episode through the bootstrap path
    // so conversion is re-applied. Other impacts are pure relayout/repaint
    // handled by the render layer reading the updated preferences.
    if (persistedDiff.impacts.contains(
      NovelReaderPreferenceImpact.contentRebuild,
    )) {
      await _rebuildCurrentEpisodeDocument(commitSerial);
    }
  }

  /// Reloads the current episode document so preference-driven content
  /// transforms (e.g. text conversion) take effect without leaving the page.
  Future<void> _rebuildCurrentEpisodeDocument(int commitSerial) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final context = NovelReaderLoadContext(
      novelId: _args.novelId,
      requestedEpisodeId: current.currentEpisode.episodeId,
      preservedProgress: current.readingProgress,
    );
    final critical = await _loadCriticalBootstrap(context);
    if (!ref.mounted || commitSerial != _preferenceCommitSerial) {
      return;
    }
    final latest = state.value ?? current;
    state = AsyncData(
      latest.copyWith(
        currentContent: critical.currentContent,
        document: critical.document,
      ),
    );
  }

  void revertPreferencePreview() {
    final current = state.value;
    if (current == null) {
      return;
    }
    final persistedEffective = current.persistedPreferences;
    if (current.effectivePreferences == persistedEffective) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        effectivePreferences: persistedEffective,
        progressSnapshot: current.progressSnapshot.copyWith(
          flowMode: persistedEffective.flowMode,
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
    _applyProgressSnapshot(snapshot);
    ref.read(novelReaderProgressCommitterProvider).schedule(snapshot);
  }

  void onPagedPositionChanged(NovelReaderPaginationPosition position) {
    final current = state.value;
    if (current == null ||
        current.currentEpisode.episodeId != position.episodeId ||
        current.preferences.flowMode == NovelReaderFlowMode.vertical ||
        position.pageCount <= 0 ||
        position.paginationKey.trim().isEmpty) {
      return;
    }
    final snapshot = _progressPolicy.pagedSnapshot(
      novelId: _args.novelId,
      episodeId: position.episodeId,
      flowMode: current.preferences.flowMode,
      pageIndex: position.pageIndex,
      pageCount: position.pageCount,
      paginationKey: position.paginationKey,
      isPageCountFinal: position.isPageCountFinal,
      anchorNodeId: position.anchor.nodeId,
      anchorTextOffset: position.anchor.textOffset,
    );
    _applyProgressSnapshot(snapshot);
    ref.read(novelReaderProgressCommitterProvider).schedule(snapshot);
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
    _applyProgressSnapshot(snapshot);
    await ref.read(novelReaderProgressCommitterProvider).flush(snapshot);
    _syncPersistedReadingProgress(snapshot);
  }

  void searchInCurrentChapter(String keyword) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final results = ref
        .read(novelReaderSearchServiceProvider)
        .search(document: current.document, keyword: keyword);
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

  Future<bool> updateWork() async {
    final current = state.value;
    if (current == null) {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() async {
        await ref.read(novelChapterUpdateServiceProvider).update(_args.novelId);
        return _loadInitialCriticalState(_args.episodeId);
      });
      return state.hasValue;
    }
    return _runEpisodeTransition(
      episodeId: current.currentEpisode.episodeId,
      kind: NovelReaderTransitionKind.updatingWork,
      updateWork: true,
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
    bool updateWork = false,
  }) async {
    final current = state.value;
    if (current == null) {
      return false;
    }
    final serial = ++_transitionRequestSerial;
    final context = NovelReaderLoadContext(
      novelId: _args.novelId,
      requestedEpisodeId: episodeId,
      preservedProgress: _preservedProgressForEpisode(
        episodeId: episodeId,
        current: current,
      ),
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
      if (updateWork) {
        await ref.read(novelChapterUpdateServiceProvider).update(_args.novelId);
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
    final hydrationService = ref.read(
      novelReaderSupplementalHydrationServiceProvider,
    );
    try {
      final bookmarks = await hydrationService.loadBookmarks(
        novelId: context.novelId,
      );
      _mergeSupplementalBookmarks(
        sessionToken: sessionToken,
        episodeId: critical.currentEpisode.episodeId,
        bookmarks: bookmarks,
      );
    } catch (_) {}
    if (!_isSupplementalRequestCurrent(
      sessionToken: sessionToken,
      episodeId: critical.currentEpisode.episodeId,
    )) {
      return;
    }

    try {
      final novel = await hydrationService.loadNovel(novelId: context.novelId);
      _mergeSupplementalNovel(
        sessionToken: sessionToken,
        episodeId: critical.currentEpisode.episodeId,
        novel: novel,
      );
    } catch (_) {}
    if (!_isSupplementalRequestCurrent(
      sessionToken: sessionToken,
      episodeId: critical.currentEpisode.episodeId,
    )) {
      return;
    }

    _completeSupplementalHydration(
      sessionToken: sessionToken,
      episodeId: critical.currentEpisode.episodeId,
    );
  }

  bool _isSupplementalRequestCurrent({
    required int sessionToken,
    required String episodeId,
  }) {
    if (!ref.mounted) {
      return false;
    }
    final current = state.value;
    if (current == null) {
      return false;
    }
    return _canApplySupplemental(
      current: current,
      sessionToken: sessionToken,
      episodeId: episodeId,
    );
  }

  bool _canApplySupplemental({
    required NovelReaderViewState current,
    required int sessionToken,
    required String episodeId,
  }) {
    return sessionToken == _activeSessionToken &&
        current.currentEpisode.episodeId == episodeId;
  }

  void _mergeSupplementalBookmarks({
    required int sessionToken,
    required String episodeId,
    required List<NovelReaderBookmark> bookmarks,
  }) {
    if (!ref.mounted) {
      return;
    }
    final current = state.value;
    if (current == null ||
        !_canApplySupplemental(
          current: current,
          sessionToken: sessionToken,
          episodeId: episodeId,
        )) {
      return;
    }
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

  void _mergeSupplementalNovel({
    required int sessionToken,
    required String episodeId,
    required NovelItem? novel,
  }) {
    if (!ref.mounted) {
      return;
    }
    final current = state.value;
    if (current == null ||
        !_canApplySupplemental(
          current: current,
          sessionToken: sessionToken,
          episodeId: episodeId,
        )) {
      return;
    }
    state = AsyncData(current.copyWith(novel: novel));
  }

  void _completeSupplementalHydration({
    required int sessionToken,
    required String episodeId,
  }) {
    if (!ref.mounted) {
      return;
    }
    final current = state.value;
    if (current == null ||
        !_canApplySupplemental(
          current: current,
          sessionToken: sessionToken,
          episodeId: episodeId,
        )) {
      return;
    }
    state = AsyncData(current.copyWith(isHydratingSupplemental: false));
  }

  NovelReaderViewState _initialStateFromCritical(
    NovelReaderCriticalBootstrap critical,
  ) {
    _rememberReadingProgress(critical.readingProgress);
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
      transition: null,
      isHydratingSupplemental: true,
    );
  }

  NovelReaderViewState _transitionedStateFromCritical({
    required NovelReaderViewState previous,
    required NovelReaderCriticalBootstrap critical,
  }) {
    _rememberReadingProgress(critical.readingProgress);
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

  void _applyProgressSnapshot(NovelReaderProgressSnapshot snapshot) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        currentOffset: snapshot.scrollOffset,
        progressSnapshot: snapshot,
      ),
    );
  }

  void _syncPersistedReadingProgress(NovelReaderProgressSnapshot snapshot) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final readingProgress = _readingProgressFromSnapshot(snapshot);
    _rememberReadingProgress(readingProgress);
    state = AsyncData(current.copyWith(readingProgress: readingProgress));
  }

  NovelReadingProgress _readingProgressFromSnapshot(
    NovelReaderProgressSnapshot snapshot,
  ) {
    return NovelReadingProgress(
      novelId: snapshot.novelId,
      episodeId: snapshot.episodeId,
      scrollOffset: snapshot.scrollOffset,
      updatedAt: DateTime.now(),
      flowMode: snapshot.flowMode,
      pageIndex: snapshot.pageIndex,
      anchorNodeId: snapshot.anchorNodeId,
      anchorTextOffset: snapshot.anchorTextOffset,
      paginationKey: snapshot.paginationKey,
      progressPercent: snapshot.progressPercent,
    );
  }

  NovelReadingProgress? _preservedProgressForEpisode({
    required String episodeId,
    required NovelReaderViewState current,
  }) {
    final cached = _knownReadingProgressByEpisodeId[episodeId];
    if (cached != null) {
      return cached;
    }
    if (current.readingProgress?.episodeId == episodeId) {
      return current.readingProgress;
    }
    if (current.progressSnapshot.episodeId == episodeId) {
      return _readingProgressFromSnapshot(current.progressSnapshot);
    }
    return null;
  }

  void _rememberReadingProgress(NovelReadingProgress? progress) {
    if (progress == null) {
      return;
    }
    _knownReadingProgressByEpisodeId[progress.episodeId] = progress;
  }

  Future<void> _reloadBookmarks(NovelRepository repository) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final bookmarks = await repository.listReaderBookmarks(
      novelId: _args.novelId,
    );
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
      for (final block in document.blocks) {
        if (block.anchorId == nodeId) {
          final text = block.novelPlainText.trim();
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
}

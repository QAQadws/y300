import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';

@immutable
class ComicCommentSessionKey {
  const ComicCommentSessionKey({
    required this.episodeId,
    required this.sourceTid,
  });

  final String episodeId;
  final String sourceTid;

  String get id => '$episodeId:$sourceTid';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ComicCommentSessionKey &&
            other.episodeId == episodeId &&
            other.sourceTid == sourceTid;
  }

  @override
  int get hashCode => Object.hash(episodeId, sourceTid);
}

@immutable
class ComicCommentSessionState {
  const ComicCommentSessionState({
    required this.key,
    required this.isLoading,
    this.result,
    this.isRefreshing = false,
    this.refreshFailed = false,
    this.isLoadingMore = false,
    this.appendError,
    this.isExpanded = false,
  });
  const ComicCommentSessionState.initial(ComicCommentSessionKey key)
    : this(key: key, isLoading: false);
  final ComicCommentSessionKey key;
  final bool isLoading;
  final ComicCommentLoadResult? result;
  final bool isRefreshing;
  final bool refreshFailed;
  final bool isLoadingMore;
  final ComicCommentLoadErrorCode? appendError;
  final bool isExpanded;
  bool get hasAttempted => isLoading || result != null;
}

/// One ordered feed, shared by the reader tail and its action context.
class ComicCommentSessionController extends ChangeNotifier {
  ComicCommentSessionController({
    required ComicCommentSessionKey key,
    required ComicCommentLoader loader,
    Future<void> Function(String)? invalidateThread,
    this.maxAutomaticAttempts = 2,
    this.automaticRetryDelay = const Duration(milliseconds: 500),
    Future<void> Function(Duration)? delay,
  }) : _key = key,
       _loader = loader,
       _invalidateThread = invalidateThread,
       _delay = delay ?? Future<void>.delayed,
       _state = ComicCommentSessionState.initial(key),
       assert(maxAutomaticAttempts > 0);
  final ComicCommentSessionKey _key;
  final ComicCommentLoader _loader;
  final Future<void> Function(String)? _invalidateThread;
  final int maxAutomaticAttempts;
  final Duration automaticRetryDelay;
  final Future<void> Function(Duration) _delay;
  final Map<int, ComicCommentLoadResult> _pages = {};
  ComicCommentSessionState _state;
  ComicCommentCancellationToken? _activeToken;
  Future<void>? _flight;
  Future<void>? _resetBarrier;
  Set<int>? _failedRefreshPages;
  int _generation = 0;
  int _ownerGeneration = 0;
  bool _disposed = false;
  ComicCommentSessionKey get key => _key;
  ComicCommentSessionState get state => _state;
  int get generation => _ownerGeneration;
  bool isCurrent(int generation) =>
      !_disposed && generation == _ownerGeneration;

  Future<void> load() => _initial(expand: true);
  Future<void> loadContext() => _initial(expand: false);

  Future<void> _initial({required bool expand}) {
    if (_disposed) return Future.value();
    final barrier = _resetBarrier;
    if (barrier != null) {
      final owner = _ownerGeneration;
      return barrier.then((_) async {
        if (isCurrent(owner)) await _initial(expand: expand);
      });
    }
    if (expand && !_state.isExpanded) {
      _state = ComicCommentSessionState(
        key: key,
        isLoading: _state.isLoading,
        result: _state.result,
        isRefreshing: _state.isRefreshing,
        refreshFailed: _state.refreshFailed,
        isLoadingMore: _state.isLoadingMore,
        appendError: _state.appendError,
        isExpanded: true,
      );
      if (_state.hasAttempted) notifyListeners();
    }
    if (_flight != null) return _flight!;
    if (_state.result != null) return Future.value();
    return _start({1}, automatic: true);
  }

  Future<void> loadMore() {
    final next = _state.result?.nextPage;
    if (_disposed ||
        _flight != null ||
        !_state.isExpanded ||
        next == null ||
        _state.appendError != null ||
        _state.refreshFailed) {
      return Future.value();
    }
    return _start({next}, append: true);
  }

  Future<void> retry() {
    if (_disposed || _flight != null) return Future.value();
    if (_state.refreshFailed) {
      return _start(_failedRefreshPages ?? {1}, refresh: true);
    }
    if (_state.appendError != null && _state.result?.nextPage != null) {
      return _start({_state.result!.nextPage!}, append: true);
    }
    return _start({1}, refresh: _pages.isNotEmpty);
  }

  Future<void> refreshAfterMutation({int? page}) {
    final targets = page == null
        ? <int>{1, if (_pages.isNotEmpty) (_pages.keys.toList()..sort()).last}
        : <int>{page};
    return _start(targets, refresh: true, supersede: true);
  }

  Future<void> resetSession() async {
    if (_disposed) return;
    final hadAttempted = _state.hasAttempted;
    final expanded = _state.isExpanded;
    _generation++;
    _ownerGeneration++;
    _activeToken?.cancel();
    _flight = null;
    _pages.clear();
    _failedRefreshPages = null;
    _state = ComicCommentSessionState(
      key: key,
      isLoading: false,
      isExpanded: expanded,
    );
    final generation = _ownerGeneration;
    final previousBarrier = _resetBarrier;
    // A new account must not read the previous account's snapshot while its
    // invalidation is still pending, including requests triggered by visibility.
    final barrier = _resetBarrier = () async {
      if (previousBarrier != null) await previousBarrier;
      await _invalidate();
    }();
    notifyListeners();
    await barrier;
    if (identical(_resetBarrier, barrier)) _resetBarrier = null;
    if (isCurrent(generation) && hadAttempted) await _initial(expand: expanded);
  }

  Future<void> _start(
    Set<int> targets, {
    bool automatic = false,
    bool append = false,
    bool refresh = false,
    bool supersede = false,
  }) {
    final barrier = _resetBarrier;
    if (barrier != null) {
      final owner = _ownerGeneration;
      return barrier.then((_) async {
        if (isCurrent(owner)) {
          await _start(
            targets,
            automatic: automatic,
            append: append,
            refresh: refresh,
            supersede: supersede,
          );
        }
      });
    }
    if (_disposed || (!supersede && _flight != null)) {
      return _flight ?? Future.value();
    }
    final generation = ++_generation;
    _activeToken?.cancel();
    final token = _activeToken = ComicCommentCancellationToken();
    _publish(
      loading: _pages.isEmpty,
      refreshing: refresh && _pages.isNotEmpty,
      loadingMore: append,
    );
    late final Future<void> flight;
    flight =
        _run(
          targets,
          token,
          generation,
          automatic: automatic,
          append: append,
          refresh: refresh,
        ).whenComplete(() {
          if (identical(_flight, flight)) _flight = null;
        });
    return _flight = flight;
  }

  Future<void> _run(
    Set<int> targets,
    ComicCommentCancellationToken token,
    int generation, {
    required bool automatic,
    required bool append,
    required bool refresh,
  }) async {
    if (refresh) await _invalidate();
    if (!_current(generation, token)) return;
    final updates = <int, ComicCommentLoadResult>{};
    final failedPages = <int>{};
    ComicCommentLoadResult? failure;
    for (final page in targets.toList()..sort()) {
      ComicCommentLoadResult? result;
      for (
        var attempt = 1;
        attempt <= (automatic ? maxAutomaticAttempts : 1);
        attempt++
      ) {
        try {
          result = await _loader.loadPage(
            sourceTid: key.sourceTid,
            page: page,
            cancellationToken: token,
          );
        } catch (_) {
          result = ComicCommentLoadResult.failure(
            key.sourceTid,
            ComicCommentLoadErrorCode.firstPageUnavailable,
          );
        }
        if (!_current(generation, token)) return;
        if (!automatic ||
            !result.isTransientFailure ||
            attempt == maxAutomaticAttempts) {
          break;
        }
        await Future.any<void>([
          _delay(automaticRetryDelay),
          token.whenCancelled,
        ]);
        if (!_current(generation, token)) return;
      }
      if (!result!.isComplete) {
        failure = result;
        failedPages.add(page);
        if (refresh) continue;
        break;
      }
      if (append) {
        final existing = _state.result!.items.map((item) => item.pid).toSet();
        if (result.items.every((item) => existing.contains(item.pid)) ||
            (result.nextPage != null && result.nextPage! <= page)) {
          failure = ComicCommentLoadResult.failure(
            key.sourceTid,
            ComicCommentLoadErrorCode.invalidPageResponse,
          );
          break;
        }
      }
      updates[page] = result;
    }
    if (!_current(generation, token)) return;
    _pages.addAll(updates);
    if (failure == null) {
      _failedRefreshPages = null;
    } else if (refresh) {
      _failedRefreshPages = failedPages;
    }
    _state = ComicCommentSessionState(
      key: key,
      isLoading: false,
      isExpanded: _state.isExpanded,
      result: failure != null && _pages.isNotEmpty && updates.isEmpty
          ? _state.result
          : _pages.isEmpty
          ? failure
          : ComicCommentLoadResult.merge(key.sourceTid, _pages),
      refreshFailed: refresh && failure != null && _pages.isNotEmpty,
      appendError: append ? failure?.errorCode : null,
    );
    notifyListeners();
  }

  void _publish({
    bool loading = false,
    bool refreshing = false,
    bool loadingMore = false,
    bool? expanded,
  }) {
    _state = ComicCommentSessionState(
      key: key,
      isLoading: loading,
      result: _state.result,
      isRefreshing: refreshing,
      isLoadingMore: loadingMore,
      isExpanded: expanded ?? _state.isExpanded,
    );
    notifyListeners();
  }

  Future<void> _invalidate() async {
    if (_loader is ComicCommentLoaderCache) {
      (_loader as ComicCommentLoaderCache).invalidate(key.sourceTid);
    }
    try {
      await _invalidateThread?.call(key.sourceTid);
    } catch (_) {
      /* The confirmed write is still valid. */
    }
  }

  bool _current(int generation, ComicCommentCancellationToken token) =>
      !_disposed && generation == _generation && identical(_activeToken, token);
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _ownerGeneration++;
    _activeToken?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_use_cases.dart';
import 'package:y300/features/history/presentation/models/history_view_state.dart';

final historyControllerProvider = Provider<HistoryController>((ref) {
  final controller = HistoryController(
    repository: ref.watch(historyRepositoryProvider),
    queryHistory: ref.watch(queryHistoryUseCaseProvider),
    deleteHistoryEntry: ref.watch(deleteHistoryEntryUseCaseProvider),
    restoreHistoryEntry: ref.watch(restoreHistoryEntryUseCaseProvider),
    clearHistory: ref.watch(clearHistoryUseCaseProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

class HistoryController extends ChangeNotifier {
  HistoryController({
    required HistoryRepository repository,
    required QueryHistoryUseCase queryHistory,
    required DeleteHistoryEntryUseCase deleteHistoryEntry,
    required RestoreHistoryEntryUseCase restoreHistoryEntry,
    required ClearHistoryUseCase clearHistory,
    this.pageSize = 50,
    this.searchDebounce = const Duration(milliseconds: 250),
  }) : _repository = repository,
       _queryHistory = queryHistory,
       _deleteHistoryEntry = deleteHistoryEntry,
       _restoreHistoryEntry = restoreHistoryEntry,
       _clearHistory = clearHistory;

  final HistoryRepository _repository;
  final QueryHistoryUseCase _queryHistory;
  final DeleteHistoryEntryUseCase _deleteHistoryEntry;
  final RestoreHistoryEntryUseCase _restoreHistoryEntry;
  final ClearHistoryUseCase _clearHistory;
  final int pageSize;
  final Duration searchDebounce;

  HistoryViewState _state = HistoryViewState.initial();
  HistoryViewState get state => _state;

  StreamSubscription<HistoryChange>? _changeSubscription;
  Timer? _searchTimer;
  bool _initialized = false;
  bool _disposed = false;
  bool _refreshScheduled = false;
  String _appliedSearchText = '';
  int _queryGeneration = 0;
  int _mutationDepth = 0;
  bool _mutationRefreshPending = false;

  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;
    _changeSubscription = _repository.watchChanges().listen(
      _handleRepositoryChange,
    );
    await refresh(showLoading: true);
  }

  Future<void> refresh({bool showLoading = false}) async {
    if (_disposed) {
      return;
    }
    final generation = ++_queryGeneration;
    _state = _state.copyWith(
      isInitialLoading: showLoading || _state.items.isEmpty,
      isLoadingMore: false,
      clearError: true,
      clearLoadMoreError: true,
    );
    _notify();
    final querySearchText = _state.searchText;
    try {
      final page = await _queryHistory(
        HistoryQuery(searchText: querySearchText, limit: pageSize),
      );
      if (!_isCurrent(generation)) {
        return;
      }
      _appliedSearchText = querySearchText;
      _state = _state.copyWith(
        isInitialLoading: false,
        items: page.items,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        isLoadingMore: false,
        clearError: true,
        clearLoadMoreError: true,
      );
      _notify();
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _state = _state.copyWith(
        isInitialLoading: false,
        errorMessage: error.toString(),
        isLoadingMore: false,
      );
      _notify();
    }
  }

  void updateSearchText(String value) {
    if (_disposed || value == _state.searchText) {
      return;
    }
    _searchTimer?.cancel();
    _state = _state.copyWith(searchText: value, clearError: true);
    _notify();
    _searchTimer = Timer(searchDebounce, () {
      unawaited(refresh());
    });
  }

  Future<void> clearSearch() async {
    _searchTimer?.cancel();
    final needsRefresh =
        _state.searchText.isNotEmpty || _appliedSearchText.isNotEmpty;
    if (!needsRefresh) {
      return;
    }
    if (_state.searchText.isNotEmpty) {
      _state = _state.copyWith(searchText: '', clearError: true);
      _notify();
    }
    await refresh();
  }

  Future<void> loadMore() async {
    if (_disposed ||
        _state.isInitialLoading ||
        _state.isLoadingMore ||
        _state.searchText != _appliedSearchText ||
        !_state.hasMore ||
        _state.nextCursor == null) {
      return;
    }
    final generation = _queryGeneration;
    final searchText = _state.searchText;
    final cursor = _state.nextCursor;
    _state = _state.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    _notify();
    try {
      final page = await _queryHistory(
        HistoryQuery(searchText: searchText, cursor: cursor, limit: pageSize),
      );
      if (!_isCurrent(generation) || searchText != _state.searchText) {
        return;
      }
      final merged = <HistoryEntry>[];
      final seen = <HistoryTargetKey>{};
      for (final item in <HistoryEntry>[..._state.items, ...page.items]) {
        if (seen.add(item.target)) {
          merged.add(item);
        }
      }
      _state = _state.copyWith(
        items: List<HistoryEntry>.unmodifiable(merged),
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
      _notify();
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _state = _state.copyWith(
        isLoadingMore: false,
        loadMoreError: error.toString(),
      );
      _notify();
    }
  }

  Future<void> deleteEntry(HistoryEntry entry) async {
    final previous = _state;
    _state = _state.copyWith(
      items: List<HistoryEntry>.unmodifiable(
        _state.items.where((item) => item.target != entry.target),
      ),
    );
    _notify();
    try {
      await _runMutation(() => _deleteHistoryEntry(entry.target));
    } catch (_) {
      if (!_disposed) {
        _state = previous;
        _notify();
      }
      rethrow;
    }
  }

  Future<void> restoreEntry(HistoryEntry entry) {
    return _runMutation(() => _restoreHistoryEntry(entry));
  }

  Future<void> clearAll() async {
    final previous = _state;
    _state = _state.copyWith(
      items: const <HistoryEntry>[],
      hasMore: false,
      clearCursor: true,
    );
    _notify();
    try {
      await _runMutation(_clearHistory.call);
    } catch (_) {
      if (!_disposed) {
        _state = previous;
        _notify();
      }
      rethrow;
    }
  }

  Future<void> _runMutation(Future<void> Function() action) async {
    _mutationDepth += 1;
    try {
      await action();
    } finally {
      _mutationDepth -= 1;
      if (_mutationDepth == 0 && _mutationRefreshPending && !_disposed) {
        _mutationRefreshPending = false;
        await refresh();
      }
    }
  }

  void _handleRepositoryChange(HistoryChange change) {
    if (_disposed) {
      return;
    }
    if (_mutationDepth > 0) {
      _mutationRefreshPending = true;
      return;
    }
    if (_refreshScheduled) {
      return;
    }
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (!_disposed) {
        unawaited(refresh());
      }
    });
  }

  bool _isCurrent(int generation) {
    return !_disposed && generation == _queryGeneration;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _searchTimer?.cancel();
    unawaited(_changeSubscription?.cancel());
    super.dispose();
  }
}

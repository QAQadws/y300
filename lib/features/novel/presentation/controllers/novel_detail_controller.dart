import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';

class NovelDetailArgs {
  const NovelDetailArgs({required this.novelId});

  final String novelId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is NovelDetailArgs && other.novelId == novelId;
  }

  @override
  int get hashCode => novelId.hashCode;
}

class NovelDetailViewState {
  const NovelDetailViewState({
    required this.detail,
    required this.episodes,
    required this.isRefreshing,
    required this.sortDescending,
    this.hint,
  });

  final NovelItem detail;
  final List<NovelEpisodeItem> episodes;
  final bool isRefreshing;
  final bool sortDescending;
  final String? hint;

  NovelDetailViewState copyWith({
    NovelItem? detail,
    List<NovelEpisodeItem>? episodes,
    bool? isRefreshing,
    bool? sortDescending,
    String? hint,
    bool clearHint = false,
  }) {
    return NovelDetailViewState(
      detail: detail ?? this.detail,
      episodes: episodes ?? this.episodes,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      sortDescending: sortDescending ?? this.sortDescending,
      hint: clearHint ? null : (hint ?? this.hint),
    );
  }
}

final novelDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<NovelDetailController, NovelDetailViewState, NovelDetailArgs>(
  (args) => NovelDetailController(args),
);

class NovelDetailController extends AsyncNotifier<NovelDetailViewState> {
  NovelDetailController(this._args);

  final NovelDetailArgs _args;

  @override
  FutureOr<NovelDetailViewState> build() async {
    return _load(sortDescending: false);
  }

  Future<void> toggleSortOrder() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final nextDescending = !current.sortDescending;
    final sorted = _sortEpisodes(current.episodes, descending: nextDescending);
    state = AsyncData(
      current.copyWith(
        sortDescending: nextDescending,
        episodes: sorted,
      ),
    );
  }

  Future<void> refreshEpisodes() async {
    final current = state.value;
    if (current == null || current.isRefreshing) {
      return;
    }

    state = AsyncData(current.copyWith(isRefreshing: true, clearHint: true));

    try {
      final repository = ref.read(novelRepositoryProvider);
      final result = await repository.refreshEpisodes(novelId: _args.novelId);
      final refreshed = await _load(sortDescending: current.sortDescending);
      state = AsyncData(
        refreshed.copyWith(
          hint: '刷新完成：新增${result.insertedCount}，更新${result.updatedCount}',
          isRefreshing: false,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isRefreshing: false,
          hint: '刷新失败：$error',
        ),
      );
    }
  }

  Future<NovelDetailViewState> _load({required bool sortDescending}) async {
    final repository = ref.read(novelRepositoryProvider);
    final detail = await repository.getDetail(novelId: _args.novelId);
    if (detail == null) {
      throw StateError('小说不存在或已删除');
    }

    final episodes = await repository.getEpisodes(
      novelId: _args.novelId,
      descending: false,
    );
    return NovelDetailViewState(
      detail: detail,
      episodes: _sortEpisodes(episodes, descending: sortDescending),
      isRefreshing: false,
      sortDescending: sortDescending,
      hint: null,
    );
  }

  List<NovelEpisodeItem> _sortEpisodes(List<NovelEpisodeItem> source, {required bool descending}) {
    final items = List<NovelEpisodeItem>.from(source);
    items.sort((a, b) {
      final orderCmp = a.orderIndex.compareTo(b.orderIndex);
      if (orderCmp != 0) {
        return descending ? -orderCmp : orderCmp;
      }
      final pidA = int.tryParse(a.sourcePid ?? '') ?? -1;
      final pidB = int.tryParse(b.sourcePid ?? '') ?? -1;
      final pidCmp = pidA.compareTo(pidB);
      return descending ? -pidCmp : pidCmp;
    });
    return items;
  }
}

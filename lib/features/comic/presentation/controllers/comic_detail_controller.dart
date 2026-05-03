import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

class ComicDetailArgs {
  const ComicDetailArgs({required this.comicId});

  final String comicId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ComicDetailArgs && other.comicId == comicId;
  }

  @override
  int get hashCode => comicId.hashCode;
}

class ComicDetailViewState {
  const ComicDetailViewState({
    required this.detail,
    required this.episodes,
    required this.isRefreshing,
    required this.sortDescending,
    this.refreshHint,
  });

  final ComicDetail detail;
  final List<ComicEpisodeItem> episodes;
  final bool isRefreshing;
  final bool sortDescending;
  final String? refreshHint;

  ComicDetailViewState copyWith({
    ComicDetail? detail,
    List<ComicEpisodeItem>? episodes,
    bool? isRefreshing,
    bool? sortDescending,
    String? refreshHint,
    bool clearHint = false,
  }) {
    return ComicDetailViewState(
      detail: detail ?? this.detail,
      episodes: episodes ?? this.episodes,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      sortDescending: sortDescending ?? this.sortDescending,
      refreshHint: clearHint ? null : (refreshHint ?? this.refreshHint),
    );
  }
}

final comicDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ComicDetailController, ComicDetailViewState, ComicDetailArgs>(
      (arg) => ComicDetailController(arg),
    );

class ComicDetailController extends AsyncNotifier<ComicDetailViewState> {
  ComicDetailController(this._args);

  final ComicDetailArgs _args;

  @override
  FutureOr<ComicDetailViewState> build() async {
    return _load(_args.comicId, sortDescending: true);
  }

  Future<void> toggleSortOrder() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final nextDescending = !current.sortDescending;
    state = AsyncData(current.copyWith(sortDescending: nextDescending));
    final repository = ref.read(comicRepositoryProvider);
    final episodes = await repository.getComicEpisodes(
      comicId: current.detail.comicId,
      descending: false,
    );
    final sorted = _sortEpisodesByTid(episodes: episodes, descending: nextDescending);
    state = AsyncData(
      (state.value ?? current).copyWith(
        episodes: sorted,
        sortDescending: nextDescending,
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
      final refreshService = ref.read(comicEpisodeRefreshServiceProvider);
      final repository = ref.read(comicRepositoryProvider);
      final links = await refreshService.fetchEpisodeLinksFromTid(current.detail.sourceTid);

      if (links.isEmpty) {
        state = AsyncData(
          current.copyWith(
            isRefreshing: false,
            refreshHint: '未提取到新的章节链接',
          ),
        );
        return;
      }

      final mergeResult = await repository.mergeEpisodesFromLinks(
        comicId: current.detail.comicId,
        episodeLinks: links,
        fallbackSourceTid: current.detail.sourceTid,
      );

      final refreshed = await _load(
        current.detail.comicId,
        sortDescending: current.sortDescending,
      );
      state = AsyncData(
        refreshed.copyWith(
          isRefreshing: false,
          refreshHint: '章节刷新完成：新增${mergeResult.insertedCount}，更新${mergeResult.updatedCount}',
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isRefreshing: false,
          refreshHint: '刷新章节失败：$error',
        ),
      );
    }
  }

  Future<ComicDetailViewState> _load(
    String comicId, {
    required bool sortDescending,
  }) async {
    final repository = ref.read(comicRepositoryProvider);
    final detail = await repository.getComicDetail(comicId: comicId);
    if (detail == null) {
      throw StateError('漫画不存在或已被删除');
    }

    final episodes = await repository.getComicEpisodes(
      comicId: comicId,
      descending: false,
    );
    final sorted = _sortEpisodesByTid(episodes: episodes, descending: sortDescending);

    return ComicDetailViewState(
      detail: detail,
      episodes: sorted,
      isRefreshing: false,
      sortDescending: sortDescending,
      refreshHint: null,
    );
  }

  List<ComicEpisodeItem> _sortEpisodesByTid({
    required List<ComicEpisodeItem> episodes,
    required bool descending,
  }) {
    final copy = List<ComicEpisodeItem>.from(episodes);
    copy.sort((a, b) {
      final leftTid = int.tryParse(a.sourceTid) ?? -1;
      final rightTid = int.tryParse(b.sourceTid) ?? -1;
      final tidCmp = leftTid.compareTo(rightTid);
      if (tidCmp != 0) {
        return descending ? -tidCmp : tidCmp;
      }
      final orderCmp = a.orderIndex.compareTo(b.orderIndex);
      return descending ? -orderCmp : orderCmp;
    });
    return copy;
  }
}

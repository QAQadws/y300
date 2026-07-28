import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/providers/comic_refresh_outcome_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/models/library_operation_failure.dart';
import 'package:y300/features/comic/presentation/comic_presentation_models.dart';

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
    this.refreshNotice,
  });

  final ComicDetail detail;
  final List<ComicEpisodeItem> episodes;
  final bool isRefreshing;
  final bool sortDescending;
  final ComicDetailRefreshNotice? refreshNotice;

  ComicDetailViewState copyWith({
    ComicDetail? detail,
    List<ComicEpisodeItem>? episodes,
    bool? isRefreshing,
    bool? sortDescending,
    ComicDetailRefreshNotice? refreshNotice,
    bool clearNotice = false,
  }) {
    return ComicDetailViewState(
      detail: detail ?? this.detail,
      episodes: episodes ?? this.episodes,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      sortDescending: sortDescending ?? this.sortDescending,
      refreshNotice: clearNotice ? null : (refreshNotice ?? this.refreshNotice),
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
    final sorted = _sortEpisodesByTid(
      episodes: episodes,
      descending: nextDescending,
    );
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

    state = AsyncData(current.copyWith(isRefreshing: true, clearNotice: true));

    try {
      final refreshService = ref.read(comicEpisodeRefreshServiceProvider);
      final refreshOutcomeApplier = ref.read(
        comicRefreshOutcomeApplierProvider,
      );
      final featureFlags = ref.read(comicReaderFeatureFlagsProvider);
      final outcome = await refreshService.fetchCatalogThenFallback(
        ComicEpisodeRefreshRequest(
          comicId: current.detail.comicId,
          sourceTid: current.detail.sourceTid,
          displayTitle: current.detail.displayTitle,
          sourceTitle: current.detail.sourceTitle,
          customTitle: featureFlags.readerCustomMetadataEnabled
              ? current.detail.customTitle
              : null,
          customSearchTitle: featureFlags.readerCustomMetadataEnabled
              ? current.detail.customSearchTitle
              : null,
        ),
      );

      if (!outcome.hasLinks) {
        state = AsyncData(
          current.copyWith(
            isRefreshing: false,
            refreshNotice: const ComicDetailRefreshNotice(
              code: ComicDetailRefreshNoticeCode.noLinks,
            ),
          ),
        );
        return;
      }

      final applyResult = await refreshOutcomeApplier.apply(
        ComicRefreshApplyRequest(
          comicId: current.detail.comicId,
          sourceTid: current.detail.sourceTid,
          links: outcome.links,
          source: outcome.source,
          mutationSource: LibraryMutationSource.comicRefresh,
          reason: 'comic_detail_controller_refresh_completed',
        ),
      );

      final refreshed = await _load(
        current.detail.comicId,
        sortDescending: current.sortDescending,
      );
      state = AsyncData(
        refreshed.copyWith(
          isRefreshing: false,
          refreshNotice: ComicDetailRefreshNotice(
            code: ComicDetailRefreshNoticeCode.completed,
            insertedCount: applyResult.insertedCount,
            updatedCount: applyResult.updatedCount,
          ),
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isRefreshing: false,
          refreshNotice: ComicDetailRefreshNotice(
            code: ComicDetailRefreshNoticeCode.failed,
            detail: error,
          ),
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
      throw const LibraryOperationException(
        LibraryOperationFailureCode.workNotFound,
      );
    }

    final episodes = await repository.getComicEpisodes(
      comicId: comicId,
      descending: false,
    );
    final sorted = _sortEpisodesByTid(
      episodes: episodes,
      descending: sortDescending,
    );

    return ComicDetailViewState(
      detail: detail,
      episodes: sorted,
      isRefreshing: false,
      sortDescending: sortDescending,
      refreshNotice: null,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/data/use_cases/bulk_download_use_case_providers.dart';
import 'package:y300/features/comic/data/services/comic_download_service.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/providers/comic_refresh_outcome_providers.dart';
import 'package:y300/features/comic/data/providers/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/models/comic_reader_exit_result.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/adapters/comic_detail_adapter.dart';
import 'package:y300/features/comic/presentation/comic_reader_page.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/presentation/mappers/library_detail_history_visit_mapper.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

/// 漫画详情页（Phase 4）：统一详情页薄壳接入。
class ComicDetailPage extends ConsumerWidget {
  const ComicDetailPage({super.key, required this.comicId});

  final String comicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQueue = ref.watch(comicSearchRefreshQueueServiceProvider);
    final historyRecorder = ref.watch(historyVisitRecorderProvider);
    final adapter = ComicDetailAdapter(
      ref.watch(comicRepositoryProvider),
      refreshService: ref.watch(comicEpisodeRefreshServiceProvider),
      searchQueue: searchQueue,
      firstEpisodeCoverService: ref.watch(
        comicFirstEpisodeCoverServiceProvider,
      ),
      refreshOutcomeApplier: ref.watch(comicRefreshOutcomeApplierProvider),
      downloadService: ref.watch(comicDownloadServiceProvider),
      downloadQueue: ref.watch(comicDownloadQueueProvider),
      imageCacheService: ref.watch(imageCacheServiceProvider),
      bulkDownloadUseCase: ref.watch(bulkDownloadUseCaseProvider),
      incrementalDiscovery: ref.watch(comicIncrementalEpisodeDiscoveryProvider),
      discoveryService: ref.watch(comicEpisodeDiscoveryServiceProvider),
      featureFlags: ref.watch(comicReaderFeatureFlagsProvider),
      titleAnalyzer: ref.watch(comicTitleAnalyzerProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
    );
    return UnifiedDetailPage(
      adapter: adapter,
      workId: comicId,
      shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
      imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
      pickCoverImage: () async {
        // 用通用图片选择器选一张本地图作为自定义封面来源（仅取第一张）。
        final picked = await ref
            .read(composerImagePickerProvider)
            .pickImagesInOrder();
        if (picked.isEmpty) {
          return null;
        }
        final path = picked.first.path.trim();
        return path.isEmpty ? null : path;
      },
      onFirstContentPresented: (header, chapters) async {
        final draft = const LibraryDetailHistoryVisitMapper().map(
          module: LibraryModuleKey.comic,
          header: header,
          chapters: chapters,
        );
        await historyRecorder.record(draft);
      },
      onOpenReader: (context, target) async {
        var nextTarget = target;
        while (context.mounted) {
          final result = await Navigator.of(context).push<Object?>(
            MaterialPageRoute<Object?>(
              builder: (_) => ComicReaderPage(
                comicId: nextTarget.workId,
                episodeId: nextTarget.episodeId,
              ),
            ),
          );
          if (result is! ComicReaderExitResult ||
              !result.shouldOpenEpisode ||
              result.lastReadEpisodeId == nextTarget.episodeId) {
            break;
          }
          nextTarget = ReaderRouteTarget(
            workId: result.comicId,
            episodeId: result.lastReadEpisodeId,
          );
        }
      },
      onOpenThread: (context, target) async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ThreadDetailPage(
              tid: target.tid,
              subject: target.subject ?? '',
              initialPage: target.initialPage,
              targetPid: target.targetPid,
            ),
          ),
        );
      },
    );
  }
}

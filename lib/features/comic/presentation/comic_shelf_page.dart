import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/comic/data/use_cases/bulk_download_use_case_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/presentation/adapters/comic_shelf_adapter.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
import 'package:y300/features/favorites/data/use_cases/unfavorite_use_case_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_task_workflow_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_view_preferences_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_shelf_page.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_providers.dart';

/// 漫画书架页（Phase 3）。
///
/// 当前页面只负责注入漫画适配器和详情跳转，通用交互由 [UnifiedShelfPage] 统一承载。
class ComicShelfPage extends ConsumerWidget {
  const ComicShelfPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(comicSearchQueueTaskProgressRegistrationProvider);
    final taskProgressHub = ref.watch(libraryTaskProgressHubWorkflowProvider);
    final adapter = ComicShelfAdapter(
      ref.watch(comicRepositoryProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
      imageCacheServiceResolver: () => ref.read(imageCacheServiceProvider),
      featureFlags: ref.watch(comicReaderFeatureFlagsProvider),
      shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
      taskProgressHub: taskProgressHub,
      duplicateMergeService: ref.watch(comicDuplicateMergeServiceProvider),
      categoryAssignUseCaseResolver: () =>
          ref.read(comicShelfCategoryAssignUseCaseProvider),
      readingStateBatchWriterResolver: () =>
          ref.read(readingStateBatchWriterProvider),
      bulkDownloadUseCaseResolver: () => ref.read(bulkDownloadUseCaseProvider),
      unfavoriteWorkUseCaseResolver: () =>
          ref.read(unfavoriteWorkUseCaseProvider),
    );
    return UnifiedShelfPage(
      adapter: adapter,
      viewPreferencesRepository: ref.watch(
        libraryViewPreferencesRepositoryProvider,
      ),
      imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
      isActive: isActive,
      taskProgressHub: taskProgressHub,
      selectionHost: ref.watch(shelfSelectionHostControllerProvider),
      coverPrecacheServiceResolver: () =>
          ref.read(forumImagePrecacheServiceProvider),
      onOpenWork: (context, workId) async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ComicDetailPage(comicId: workId),
          ),
        );
      },
    );
  }
}

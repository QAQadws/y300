import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/favorites/data/use_cases/unfavorite_use_case_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_task_workflow_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_shelf_page.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_providers.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/presentation/adapters/novel_shelf_adapter.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';

/// 小说书架页（Phase 3）。
///
/// 仅保留模块级依赖注入，通用书架交互完全复用统一页面。
class NovelShelfPage extends ConsumerWidget {
  const NovelShelfPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskProgressHub = ref.watch(libraryTaskProgressHubWorkflowProvider);
    final adapter = NovelShelfAdapter(
      ref.watch(novelRepositoryProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
      imageCacheServiceResolver: () => ref.read(imageCacheServiceProvider),
      shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
      taskProgressHub: taskProgressHub,
      categoryAssignUseCaseResolver: () =>
          ref.read(novelShelfCategoryAssignUseCaseProvider),
      readingStateBatchWriterResolver: () =>
          ref.read(readingStateBatchWriterProvider),
      unfavoriteWorkUseCaseResolver: () =>
          ref.read(unfavoriteWorkUseCaseProvider),
    );
    return UnifiedShelfPage(
      adapter: adapter,
      imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
      isActive: isActive,
      taskProgressHub: taskProgressHub,
      selectionHost: ref.watch(shelfSelectionHostControllerProvider),
      coverPrecacheService: ref.watch(forumImagePrecacheServiceProvider),
      onOpenWork: (context, workId) async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NovelDetailPage(novelId: workId),
          ),
        );
      },
    );
  }
}

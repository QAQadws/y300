import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/presentation/adapters/comic_shelf_adapter.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_shelf_page.dart';

/// 漫画书架页（Phase 3）。
///
/// 当前页面只负责注入漫画适配器和详情跳转，通用交互由 [UnifiedShelfPage] 统一承载。
class ComicShelfPage extends ConsumerWidget {
  const ComicShelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ComicShelfAdapter(
      ref.watch(comicRepositoryProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
      imageCacheServiceResolver: () => ref.read(imageCacheServiceProvider),
      featureFlags: ref.watch(comicReaderFeatureFlagsProvider),
    );
    return UnifiedShelfPage(
      adapter: adapter,
      imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
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

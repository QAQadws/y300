import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_reader_exit_result.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/adapters/comic_detail_adapter.dart';
import 'package:y300/features/comic/presentation/comic_reader_page.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

/// 漫画详情页（Phase 4）：统一详情页薄壳接入。
class ComicDetailPage extends ConsumerWidget {
  const ComicDetailPage({
    super.key,
    required this.comicId,
  });

  final String comicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ComicDetailAdapter(
      ref.watch(comicRepositoryProvider),
      refreshService: ref.watch(comicEpisodeRefreshServiceProvider),
      downloadService: ref.watch(comicDownloadServiceProvider),
      imageCacheService: ref.watch(imageCacheServiceProvider),
      featureFlags: ref.watch(comicReaderFeatureFlagsProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
    );
    return UnifiedDetailPage(
      adapter: adapter,
      workId: comicId,
      imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
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
            ),
          ),
        );
      },
    );
  }
}

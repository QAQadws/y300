import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/presentation/adapters/novel_detail_adapter.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

/// 小说详情页（Phase 4）：统一详情页薄壳接入。
class NovelDetailPage extends ConsumerWidget {
  const NovelDetailPage({super.key, required this.novelId});

  final String novelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = NovelDetailAdapter(
      ref.watch(novelRepositoryProvider),
      downloadService: ref.watch(novelDownloadServiceProvider),
      imageCacheService: ref.watch(imageCacheServiceProvider),
      readingStateBatchWriter: ref.watch(readingStateBatchWriterProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
    );
    return UnifiedDetailPage(
      adapter: adapter,
      workId: novelId,
      imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
      onOpenReader: (context, target) async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NovelReaderPage(
              novelId: target.workId,
              initialEpisodeId: target.episodeId,
            ),
          ),
        );
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

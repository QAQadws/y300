import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/presentation/adapters/novel_detail_adapter.dart';
import 'package:y300/features/novel/presentation/controllers/novel_chapter_hydration_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/widgets/novel_chapter_hydration_panel.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

/// 小说详情页：统一详情页薄壳与 Phase 3 首次章节水合入口。
class NovelDetailPage extends ConsumerStatefulWidget {
  const NovelDetailPage({super.key, required this.novelId});

  final String novelId;

  @override
  ConsumerState<NovelDetailPage> createState() => _NovelDetailPageState();
}

class _NovelDetailPageState extends ConsumerState<NovelDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = novelChapterHydrationControllerProvider(widget.novelId);
      try {
        await ref.read(provider.future);
      } catch (_) {
        // AsyncValue renders initialization failures in the status panel.
        return;
      }
      if (!mounted) {
        return;
      }
      await ref.read(provider.notifier).ensureHydrated();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hydrationProvider = novelChapterHydrationControllerProvider(
      widget.novelId,
    );
    final hydration = ref.watch(hydrationProvider);
    final adapter = NovelDetailAdapter(
      ref.watch(novelRepositoryProvider),
      downloadService: ref.watch(novelDownloadServiceProvider),
      imageCacheService: ref.watch(imageCacheServiceProvider),
      readingStateBatchWriter: ref.watch(readingStateBatchWriterProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
      sourceStateRepository: ref.watch(novelSourceStateRepositoryProvider),
    );
    final hydrationPanel = hydration.when<Widget?>(
      data: (value) => value.isReady
          ? null
          : NovelChapterHydrationPanel(
              state: value,
              onRetry: () {
                ref.read(hydrationProvider.notifier).retry();
              },
            ),
      loading: () => NovelChapterHydrationPanel(
        state: const NovelChapterHydrationViewState(
          status: NovelChapterHydrationViewStatus.pending,
        ),
        onRetry: () {},
      ),
      error: (error, _) => NovelChapterHydrationPanel(
        state: NovelChapterHydrationViewState(
          status: NovelChapterHydrationViewStatus.failed,
          errorMessage: error.toString(),
        ),
        onRetry: () {
          ref.invalidate(hydrationProvider);
        },
      ),
    );
    return UnifiedDetailPage(
      adapter: adapter,
      workId: widget.novelId,
      imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
      shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
      chapterStatus: hydrationPanel,
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

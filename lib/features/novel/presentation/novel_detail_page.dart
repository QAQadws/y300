import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';
import 'package:y300/features/novel/presentation/adapters/novel_detail_adapter.dart';
import 'package:y300/features/novel/presentation/controllers/novel_chapter_hydration_controller.dart';
import 'package:y300/features/novel/presentation/controllers/novel_chapter_open_mode_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/widgets/novel_chapter_hydration_panel.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

/// 小说详情页：统一详情页薄壳、首次章节水合与双打开模式入口。
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
    final openModeState = ref.watch(novelChapterOpenModeControllerProvider);
    final openMode = openModeState.value ?? NovelChapterOpenMode.reader;
    final adapter = NovelDetailAdapter(
      ref.watch(novelRepositoryProvider),
      downloadService: ref.watch(novelDownloadServiceProvider),
      imageCacheService: ref.watch(imageCacheServiceProvider),
      readingStateBatchWriter: ref.watch(readingStateBatchWriterProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
      sourceStateRepository: ref.watch(novelSourceStateRepositoryProvider),
      chapterUpdateServiceFactory: () =>
          ref.read(novelChapterUpdateServiceProvider),
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
      chapterModeControl: SegmentedButton<NovelChapterOpenMode>(
        key: const Key('novel-chapter-open-mode-control'),
        segments: const <ButtonSegment<NovelChapterOpenMode>>[
          ButtonSegment<NovelChapterOpenMode>(
            value: NovelChapterOpenMode.reader,
            icon: Icon(Icons.menu_book_outlined),
            label: Text('阅读器'),
          ),
          ButtonSegment<NovelChapterOpenMode>(
            value: NovelChapterOpenMode.sourcePost,
            icon: Icon(Icons.forum_outlined),
            label: Text('原帖'),
          ),
        ],
        selected: <NovelChapterOpenMode>{openMode},
        showSelectedIcon: false,
        onSelectionChanged: openModeState.isLoading
            ? null
            : (selection) => _updateOpenMode(selection.first),
      ),
      onOpenChapter: _openChapter,
      onRefreshCompleted: (_) async {
        ref.invalidate(hydrationProvider);
        try {
          await ref.read(hydrationProvider.future);
        } catch (_) {
          // The chapter status panel renders source-state reload failures.
        }
      },
      onOpenReader: _openReader,
      onOpenThread: _openThread,
    );
  }

  Future<void> _updateOpenMode(NovelChapterOpenMode mode) async {
    try {
      await ref
          .read(novelChapterOpenModeControllerProvider.notifier)
          .updateMode(mode);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('保存章节打开方式失败：$error');
    }
  }

  Future<void> _openChapter(
    BuildContext context,
    LibraryChapterItem chapter,
  ) async {
    final mode =
        ref.read(novelChapterOpenModeControllerProvider).value ??
        NovelChapterOpenMode.reader;
    if (mode == NovelChapterOpenMode.reader) {
      await _openReader(
        context,
        ReaderRouteTarget(workId: widget.novelId, episodeId: chapter.episodeId),
      );
      return;
    }

    final tid = chapter.sourceTid?.trim() ?? '';
    final pid = chapter.sourcePid?.trim() ?? '';
    try {
      final route = await ref
          .read(novelChapterSourceRouteResolverProvider)
          .resolve(NovelChapterSourceReference(tid: tid, pid: pid));
      if (!context.mounted) {
        return;
      }
      await _openThread(
        context,
        ThreadRouteTarget(
          tid: route.tid,
          subject: chapter.title,
          initialPage: route.page,
          targetPid: route.pid,
        ),
      );
    } on NovelChapterSourceRouteException catch (error) {
      if (!context.mounted) {
        return;
      }
      await _showSourceRouteFailure(
        context: context,
        message: error.message,
        fallbackTid: tid,
        subject: chapter.title,
      );
    }
  }

  Future<void> _showSourceRouteFailure({
    required BuildContext context,
    required String message,
    required String fallbackTid,
    required String subject,
  }) async {
    final canOpenThreadHome = RegExp(r'^[1-9]\d*$').hasMatch(fallbackTid);
    final openThreadHome = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const Key('novel-source-route-failure-dialog'),
          title: const Text('无法定位原帖楼层'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            if (canOpenThreadHome)
              FilledButton(
                key: const Key('novel-source-route-open-thread-home'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('打开帖子首页'),
              ),
          ],
        );
      },
    );
    if (openThreadHome != true || !context.mounted) {
      return;
    }
    await _openThread(
      context,
      ThreadRouteTarget(tid: fallbackTid, subject: subject),
    );
  }

  Future<void> _openReader(
    BuildContext context,
    ReaderRouteTarget target,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NovelReaderPage(
          novelId: target.workId,
          initialEpisodeId: target.episodeId,
        ),
      ),
    );
  }

  Future<void> _openThread(
    BuildContext context,
    ThreadRouteTarget target,
  ) async {
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
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

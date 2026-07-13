import 'package:flutter/material.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_chapter_hydration_controller.dart';

class NovelChapterHydrationPanel extends StatelessWidget {
  const NovelChapterHydrationPanel({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final NovelChapterHydrationViewState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isReady) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final failed = state.status == NovelChapterHydrationViewStatus.failed;
    return Semantics(
      key: const Key('novel-chapter-hydration-panel'),
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: colorScheme.surfaceContainerLow,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _message(state),
                    key: const Key('novel-chapter-hydration-message'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: failed ? colorScheme.error : null,
                    ),
                  ),
                  if (!failed) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      key: const Key('novel-chapter-hydration-progress'),
                      value: _progressValue(state.progress),
                    ),
                  ],
                ],
              ),
            ),
            if (failed) ...[
              const SizedBox(width: 12),
              TextButton.icon(
                key: const Key('novel-chapter-hydration-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _message(NovelChapterHydrationViewState state) {
    if (state.status == NovelChapterHydrationViewStatus.failed) {
      return '章节加载失败：${state.errorMessage ?? '未知错误'}';
    }
    if (state.status == NovelChapterHydrationViewStatus.recoveringMetadata) {
      return '正在恢复小说来源信息';
    }
    final progress = state.progress;
    if (progress == null || progress.phase == NovelChapterSyncPhase.preparing) {
      return '正在准备章节';
    }
    if (progress.phase == NovelChapterSyncPhase.committing) {
      return '正在保存 ${progress.acceptedCount} 个章节';
    }
    final currentPage = progress.currentPage ?? 1;
    final totalPages = progress.totalPages;
    final pageText = totalPages == null || totalPages < currentPage
        ? '第 $currentPage 页'
        : '第 $currentPage/$totalPages 页';
    return '正在加载$pageText · 已发现 ${progress.acceptedCount} 章';
  }

  double? _progressValue(NovelChapterSyncProgress? progress) {
    final current = progress?.currentPage;
    final total = progress?.totalPages;
    if (current == null || total == null || total <= 0) {
      return null;
    }
    return (current / total).clamp(0.0, 1.0).toDouble();
  }
}

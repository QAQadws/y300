import 'package:flutter/material.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_chapter_hydration_controller.dart';
import 'package:y300/features/novel/presentation/novel_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

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
                    NovelTextResolver.hydrationMessage(
                      AppLocalizations.of(context),
                      state,
                    ),
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
                label: Text(AppLocalizations.of(context).commonRetry),
              ),
            ],
          ],
        ),
      ),
    );
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

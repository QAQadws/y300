import 'package:flutter/material.dart';

enum ReaderMoreAction {
  markReadToggle,
  setCurrentPageAsCover,
  cacheEpisode,
  cacheUnread,
  clearEpisodeCache,
  retryFailedImages,
}

class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.comicTitle,
    required this.episodeTitle,
    required this.isBookmarked,
    required this.isCurrentEpisodeRead,
    required this.failedImageCount,
    required this.onBack,
    required this.onOpenDetail,
    required this.onToggleBookmark,
    required this.onOpenThread,
    required this.onMoreActionSelected,
  });

  final String comicTitle;
  final String episodeTitle;
  final bool isBookmarked;
  final bool isCurrentEpisodeRead;
  final int failedImageCount;
  final VoidCallback onBack;
  final VoidCallback onOpenDetail;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenThread;
  final ValueChanged<ReaderMoreAction> onMoreActionSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              IconButton(
                key: const Key('comic-reader-top-back-button'),
                tooltip: '返回',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: InkWell(
                  key: const Key('comic-reader-title-button'),
                  onTap: onOpenDetail,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comicTitle,
                          key: const Key('comic-reader-top-comic-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          episodeTitle,
                          key: const Key('comic-reader-top-episode-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('comic-reader-bookmark-button'),
                tooltip: isBookmarked ? '取消书签' : '添加书签',
                onPressed: onToggleBookmark,
                icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border),
              ),
              IconButton(
                key: const Key('comic-reader-open-thread-button'),
                tooltip: '打开原帖',
                onPressed: onOpenThread,
                icon: const Icon(Icons.open_in_new),
              ),
              PopupMenuButton<ReaderMoreAction>(
                key: const Key('comic-reader-more-button'),
                tooltip: '更多',
                icon: const Icon(Icons.more_vert),
                onSelected: onMoreActionSelected,
                itemBuilder: (context) => [
                  PopupMenuItem<ReaderMoreAction>(
                    key: const Key('comic-reader-mark-read-toggle'),
                    value: ReaderMoreAction.markReadToggle,
                    child: _MenuItem(
                      icon: isCurrentEpisodeRead
                          ? Icons.radio_button_unchecked
                          : Icons.check_circle_outline,
                      label: isCurrentEpisodeRead ? '标记本章未读' : '标记本章已读',
                    ),
                  ),
                  const PopupMenuItem<ReaderMoreAction>(
                    key: Key('comic-reader-set-cover'),
                    value: ReaderMoreAction.setCurrentPageAsCover,
                    child: _MenuItem(
                      icon: Icons.image_outlined,
                      label: '将当前页设为封面',
                    ),
                  ),
                  const PopupMenuItem<ReaderMoreAction>(
                    key: Key('comic-reader-cache-episode'),
                    value: ReaderMoreAction.cacheEpisode,
                    child: _MenuItem(
                      icon: Icons.download_for_offline_outlined,
                      label: '缓存本章',
                    ),
                  ),
                  const PopupMenuItem<ReaderMoreAction>(
                    key: Key('comic-reader-cache-unread'),
                    value: ReaderMoreAction.cacheUnread,
                    child: _MenuItem(
                      icon: Icons.download_done_outlined,
                      label: '缓存未读章节',
                    ),
                  ),
                  const PopupMenuItem<ReaderMoreAction>(
                    key: Key('comic-reader-clear-cache'),
                    value: ReaderMoreAction.clearEpisodeCache,
                    child: _MenuItem(
                      icon: Icons.cleaning_services_outlined,
                      label: '清除本章缓存',
                    ),
                  ),
                  PopupMenuItem<ReaderMoreAction>(
                    key: const Key('comic-reader-retry-failed'),
                    value: ReaderMoreAction.retryFailedImages,
                    enabled: failedImageCount > 0,
                    child: _MenuItem(
                      icon: Icons.refresh,
                      label: failedImageCount > 0
                          ? '重试失败图片（$failedImageCount）'
                          : '重试失败图片',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    );
  }
}

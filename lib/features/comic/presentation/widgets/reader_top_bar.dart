import 'package:flutter/material.dart';

class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.episodeTitle,
    required this.onBack,
    required this.onCacheEpisode,
    required this.onCacheUnread,
  });

  final String episodeTitle;
  final VoidCallback onBack;
  final VoidCallback onCacheEpisode;
  final VoidCallback onCacheUnread;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                key: const Key('comic-reader-top-back-button'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  episodeTitle,
                  key: const Key('comic-reader-top-episode-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: const Key('comic-reader-cache-episode'),
                tooltip: '缓存本话',
                onPressed: onCacheEpisode,
                icon: const Icon(Icons.download_for_offline_outlined),
              ),
              IconButton(
                key: const Key('comic-reader-cache-unread'),
                tooltip: '缓存全部未读',
                onPressed: onCacheUnread,
                icon: const Icon(Icons.download_done_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

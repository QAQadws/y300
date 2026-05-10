import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/forum/presentation/forum_display_page.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/shared/widgets/app_skeleton.dart';

class ForumHomePage extends ConsumerWidget {
  const ForumHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(forumHomeControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('论坛首页'),
        actions: [
          IconButton(
            key: const Key('forum-home-search-button'),
            tooltip: '搜索论坛',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ForumSearchPage(),
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: state.when(
        loading: () => const ForumHomeSkeleton(key: Key('forum-home-skeleton')),
        error: (error, _) => _ForumHomeErrorView(
          message: error.toString(),
          onRetry: () => ref.read(forumHomeControllerProvider.notifier).refresh(),
        ),
        data: (data) => _ForumHomeContent(data: data),
      ),
    );
  }
}

class _ForumHomeContent extends ConsumerWidget {
  const _ForumHomeContent({required this.data});

  final ForumHomeViewData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(forumHomeControllerProvider.notifier).refresh(),
      child: ListView(
        key: const Key('forum-home-list'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '共${data.sectionCount} 个分组，${data.regularForumCount} 个版块',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final section in data.sections) ...[
            Text(
              section.title,
              key: Key('forum-section-title-${section.title}'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final forum in section.favoriteItems) ...[
              _FavoriteForumCard(
                item: forum,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ForumDisplayPage(
                        fid: forum.fid,
                        title: forum.title,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            for (final forum in section.items) ...[
              _ForumCard(
                item: forum,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ForumDisplayPage(
                        fid: forum.fid,
                        title: forum.name,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _FavoriteForumCard extends StatelessWidget {
  const _FavoriteForumCard({required this.item, required this.onTap});

  final FavoriteForum item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final description = item.description.trim();
    return InkWell(
      key: Key('forum-favorite-card-${item.fid}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withAlpha(90),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: Theme.of(context).textTheme.titleSmall),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Text(
              '主题 ${item.threads}  帖子 ${item.posts}  今日 ${item.todayPosts}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ForumCard extends StatelessWidget {
  const _ForumCard({required this.item, required this.onTap});

  final ForumItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final description = item.description.trim();

    return InkWell(
      key: Key('forum-card-${item.fid}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: Theme.of(context).textTheme.titleSmall),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Text(
              '主题 ${item.threads}  帖子 ${item.posts}  今日 ${item.todayPosts}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ForumHomeErrorView extends StatelessWidget {
  const _ForumHomeErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('forum-home-retry-button'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

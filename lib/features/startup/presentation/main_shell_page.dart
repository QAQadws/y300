import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_refresh_workflow_providers.dart';
import 'package:y300/features/comic/presentation/comic_tab_page.dart';
import 'package:y300/features/library_shared/data/library_task_workflow_providers.dart';
import 'package:y300/features/favorites/presentation/favorite_shelf_page.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/more/presentation/more_page.dart';
import 'package:y300/features/novel/presentation/novel_tab_page.dart';

final mainShellBackgroundTaskStarterProvider = Provider<Future<void> Function()>((ref) {
  return () => ref.read(comicSearchRefreshQueueServiceProvider).start();
});

/// 应用主壳：承载论坛、收藏、漫画、小说、更多五栏 Tab，避免业务页面相互耦合。
class MainShellPage extends ConsumerStatefulWidget {
  const MainShellPage({super.key});

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage> {
  int _currentIndex = 0;
  final Set<int> _builtIndexes = <int>{0};

  @override
  void initState() {
    super.initState();
    // 主壳创建后恢复搜索刷新队列，确保用户离开详情页或收藏页后任务仍继续。
    unawaited(ref.read(mainShellBackgroundTaskStarterProvider).call());
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(favoriteSyncTaskProgressRegistrationProvider);
    ref.watch(comicSearchQueueTaskProgressRegistrationProvider);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _buildIndexedPages(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
            _builtIndexes.add(index);
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: '论坛',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: '漫画',
          ),
          NavigationDestination(
            icon: SizedBox(
              width: 24,
              height: 24,
              child: Center(child: Icon(Icons.local_library_outlined)),
            ),
            selectedIcon: SizedBox(
              width: 24,
              height: 24,
              child: Center(child: Icon(Icons.local_library)),
            ),
            label: '小说',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_outlined),
            selectedIcon: Icon(Icons.more_horiz),
            label: '更多',
          ),
        ],
      ),
    );
  }

  List<Widget> _buildIndexedPages() {
    return List<Widget>.generate(_pageCount, (index) {
      if (_builtIndexes.contains(index)) {
        final isActive = index == _currentIndex;
        return TickerMode(
          enabled: isActive,
          child: _buildPage(index, isActive: isActive),
        );
      }
      return const SizedBox.shrink();
    });
  }

  int get _pageCount => 5;

  Widget _buildPage(int index, {required bool isActive}) {
    return switch (index) {
      0 => const ForumHomePage(),
      1 => FavoriteShelfPage(isActive: isActive),
      2 => ComicTabPage(isActive: isActive),
      3 => NovelTabPage(isActive: isActive),
      4 => const MorePage(),
      _ => const SizedBox.shrink(),
    };
  }
}

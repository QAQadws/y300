import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/comic/data/providers/comic_refresh_workflow_providers.dart';
import 'package:y300/features/comic/presentation/comic_tab_page.dart';
import 'package:y300/features/library_shared/data/providers/library_task_workflow_providers.dart';
import 'package:y300/features/favorites/presentation/favorite_shelf_page.dart';
import 'package:y300/features/forum/presentation/forum_shell_page.dart';
import 'package:y300/features/library_shared/data/providers/library_task_notification_providers.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_action_bar.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_providers.dart';
import 'package:y300/features/more/presentation/more_page.dart';
import 'package:y300/features/novel/presentation/novel_tab_page.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';

final mainShellBackgroundTaskStarterProvider = Provider<Future<void> Function()>((ref) {
  return () => ref.read(comicSearchRefreshQueueServiceProvider).start();
});

/// Best-effort startup hook for the system task notification service. Failures
/// (including a denied permission) must never block the shell, so callers run
/// it detached.
final mainShellNotificationInitializerProvider =
    Provider<Future<void> Function()>((ref) {
  return () async {
    final service = ref.read(libraryTaskNotificationServiceProvider);
    await service.initialize();
    await service.ensurePermission();
  };
});

final mainShellReplyDraftAttachmentMaintenanceStarterProvider =
    Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await ref
          .read(composerDraftAttachmentMaintenanceServiceProvider)
          .maintain();
    } catch (_) {
      // 回复草稿附件维护是启动后的 best-effort 清理，失败不阻塞主壳。
    }
  };
});

final mainShellYamiboSessionWarmupProvider = Provider<Future<void> Function()>((
  ref,
) {
  return () async {
    try {
      await ref.read(yamiboApiClientProvider).getDiscuz(module: 'profile');
    } catch (_) {
      // Profile warmup only refreshes shared formhash/session metadata.
      // Startup and the forum shell must remain usable if it fails.
    }
  };
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
    // 初始化系统通知能力并请求权限；失败不应阻塞主壳，detach 执行即可。
    unawaited(ref.read(mainShellNotificationInitializerProvider).call());
    // 清理遗忘回复草稿中的过期临时附件，避免只依赖用户重新打开草稿。
    unawaited(
      ref
          .read(mainShellReplyDraftAttachmentMaintenanceStarterProvider)
          .call(),
    );
    // 首页 HTML 通常拿不到 formhash；启动后预热 profile API，让后续
    // 搜索/回复/收藏/发帖可以复用 YamiboSessionStore 中的新鲜 formhash。
    unawaited(
      ref.read(mainShellYamiboSessionWarmupProvider).call().catchError((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(favoriteSyncTaskProgressRegistrationProvider);
    ref.watch(comicSearchQueueTaskProgressRegistrationProvider);
    // 启动进度->系统通知桥接，让收藏同步/漫画搜索等待进入通知栏。
    ref.watch(libraryTaskNotificationBridgeProvider);
    final selectionHost = ref.watch(shelfSelectionHostControllerProvider);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _buildIndexedPages(),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: selectionHost,
        builder: (context, _) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) {
              const begin = Offset(0, 1);
              return SlideTransition(
                position: animation.drive(
                  Tween<Offset>(begin: begin, end: Offset.zero).chain(
                    CurveTween(curve: Curves.easeOutCubic),
                  ),
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            child: selectionHost.isActive
                ? SelectionActionBar(
                    key: const ValueKey<String>('main-shell-selection-bar'),
                    actions: selectionHost.state?.selectionActions ??
                        const <SelectionAction>[],
                    onActionTap: _handleSelectionActionTap,
                  )
                : NavigationBar(
                    key: const ValueKey<String>('main-shell-navigation-bar'),
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
        },
      ),
    );
  }

  Future<void> _handleSelectionActionTap(SelectionAction action) async {
    final selectionHost = ref.read(shelfSelectionHostControllerProvider);
    if (!selectionHost.isActive) {
      return;
    }
    String? targetCategoryId;

    try {
      if (action.id == SelectionActionIds.assignCategory) {
        targetCategoryId = await _pickTargetCategory(selectionHost);
        if (targetCategoryId == null || targetCategoryId.trim().isEmpty) {
          return;
        }
      }

      if (action.needsConfirm) {
        final confirmed = await _confirmSelectionAction(
          action,
          selectionHost.state,
        );
        if (confirmed != true || !mounted) {
          return;
        }
      }

      final result = await selectionHost.executeAction(
        actionId: action.id,
        targetCategoryId: targetCategoryId,
      );
      if (!mounted) {
        return;
      }
      _showSelectionMessage(result.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSelectionMessage('批量操作失败：$error');
    }
  }

  Future<bool?> _confirmSelectionAction(
    SelectionAction action,
    ShelfSelectionHostState? state,
  ) {
    final selectedCount = state?.selectedCount ?? 0;
    final title = action.id == SelectionActionIds.unfavorite
        ? '确认取消收藏'
        : '确认执行操作';
    final content = action.id == SelectionActionIds.unfavorite
        ? '将取消已选 $selectedCount 项收藏。若作品已无其它活跃收藏来源，相关本地作品、章节、封面缓存和下载也会被清除。是否继续？'
        : '将对已选 $selectedCount 项执行“${action.label}”，是否继续？';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _pickTargetCategory(
    ShelfSelectionHostController selectionHost,
  ) async {
    final state = selectionHost.state;
    if (state == null) {
      return null;
    }
    final categories = await selectionHost.loadAvailableCategories();
    if (!mounted) {
      return null;
    }
    final available = categories
        .where((category) => category.categoryId != state.activeCategoryId)
        .toList(growable: false);
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final category in available)
                ListTile(
                  title: Text(category.name),
                  onTap: () {
                    Navigator.of(sheetContext).pop(category.categoryId);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新建分类'),
                onTap: () {
                  Navigator.of(sheetContext).pop(_createCategorySelectionSentinel);
                },
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null) {
      return null;
    }
    if (selected != _createCategorySelectionSentinel) {
      return selected;
    }
    final categoryName = await _showCreateCategoryDialog();
    if (!mounted || categoryName == null || categoryName.trim().isEmpty) {
      return null;
    }
    return selectionHost.createCategory(categoryName.trim());
  }

  Future<String?> _showCreateCategoryDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('新建分类'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '请输入分类名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  void _showSelectionMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(trimmed)));
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

  static const String _createCategorySelectionSentinel =
      '__create-selection-category__';

  Widget _buildPage(int index, {required bool isActive}) {
    return switch (index) {
      0 => const ForumShellPage(),
      1 => FavoriteShelfPage(isActive: isActive),
      2 => ComicTabPage(isActive: isActive),
      3 => NovelTabPage(isActive: isActive),
      4 => const MorePage(),
      _ => const SizedBox.shrink(),
    };
  }
}

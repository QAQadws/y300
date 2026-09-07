import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/history_entry_router.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_shell_destination_presentation.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/data/services/cache_budget_scheduler.dart';
import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/providers/comic_refresh_workflow_providers.dart';
import 'package:y300/features/comic/presentation/comic_tab_page.dart';
import 'package:y300/features/library_shared/data/providers/library_task_workflow_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_migration_providers.dart';
import 'package:y300/features/favorites/presentation/favorite_shelf_page.dart';
import 'package:y300/features/forum/presentation/forum_shell_page.dart';
import 'package:y300/features/history/presentation/history_page.dart';
import 'package:y300/features/library_shared/data/providers/library_task_notification_providers.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_action_bar.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_action_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_providers.dart';
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/features/library_shared/presentation/services/library_shelf_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/services/library_task_text_resolver.dart';
import 'package:y300/features/more/presentation/more_page.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/novel/presentation/novel_tab_page.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/storage/data/storage_providers.dart';

final mainShellBackgroundTaskStarterProvider =
    Provider<Future<void> Function()>((ref) {
      return () async {
        final migrator = ref.read(libraryCoverLegacyMigratorProvider);
        final mergeRecovery = ref.read(comicCoverMergeRecoveryProvider);
        if (mergeRecovery != null) {
          await _startBackgroundTaskSafely(
            mergeRecovery.recoverPendingCoverMerges,
          );
        }
        // Custom covers are user assets: finish their lossless adoption before
        // any shelf can render. Regenerable source covers continue in the
        // detached maintenance batch below.
        await _startBackgroundTaskSafely(migrator.migrateCustomAssets);
        unawaited(
          Future.wait<void>(<Future<void>>[
            _startBackgroundTaskSafely(
              ref.read(mainShellCacheBudgetSchedulerProvider).start,
            ),
            _startBackgroundTaskSafely(
              ref.read(comicSearchRefreshQueueServiceProvider).start,
            ),
            _startBackgroundTaskSafely(() async {
              await ref.read(storageRootAccessGateProvider).ensureReady();
              await ref.read(comicDownloadQueueProvider).start();
            }),
            _startBackgroundTaskSafely(migrator.migrateSourceAssets),
          ]),
        );
      };
    });

Future<void> _startBackgroundTaskSafely(Future<void> Function() starter) async {
  try {
    await starter();
  } catch (_) {
    // Independent startup maintenance must not make the main shell unusable.
  }
}

final mainShellCacheBudgetSchedulerProvider = Provider<CacheBudgetScheduler>((
  ref,
) {
  final scheduler = CacheBudgetScheduler(
    source: ref.watch(cacheMutationBusProvider),
    enforce: () async {
      final maxBytes = await ref
          .read(dataStorageSettingsRepositoryProvider)
          .getCacheMaxBytes();
      await ref
          .read(cacheMaintenanceServiceProvider)
          .prune(CachePruneRequest(maxCacheBytes: maxBytes));
    },
  );
  ref.onDispose(() => unawaited(scheduler.dispose()));
  return scheduler;
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
      await ref
          .read(yamiboForumClientProvider)
          .loadCurrentUserProfile(
            const CurrentUserProfileQuery(),
            cachePolicy: CacheLoadPolicy.networkFirst,
          );
    } catch (_) {
      // Profile warmup only refreshes shared formhash/session metadata.
      // Startup and the forum shell must remain usable if it fails.
    }
  };
});

/// 应用主壳：承载可配置业务入口和固定的“更多”入口。
class MainShellPage extends ConsumerStatefulWidget {
  const MainShellPage({super.key});

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage> {
  MainShellDestination? _currentDestination;
  final Set<MainShellDestination> _builtDestinations = <MainShellDestination>{};
  late final Future<void> _coverMigrationReady;

  @override
  void initState() {
    super.initState();
    // This future completes after custom-cover migration; other startup work
    // is detached by the starter and does not delay the shell.
    _coverMigrationReady = ref
        .read(mainShellBackgroundTaskStarterProvider)
        .call();
    // 初始化系统通知能力并请求权限；失败不应阻塞主壳，detach 执行即可。
    unawaited(ref.read(mainShellNotificationInitializerProvider).call());
    // 清理遗忘回复草稿中的过期临时附件，避免只依赖用户重新打开草稿。
    unawaited(
      ref.read(mainShellReplyDraftAttachmentMaintenanceStarterProvider).call(),
    );
    // 首页 HTML 通常拿不到 formhash；启动后预热 profile API，让后续
    // 搜索/回复/收藏/发帖可以复用 YamiboSessionStore 中的新鲜 formhash。
    unawaited(
      ref.read(mainShellYamiboSessionWarmupProvider).call().catchError((_) {}),
    );
    // Resolve the process-wide image cache transport before the first remote
    // image needs it. Failure remains local to image placeholders/retries.
    unawaited(_warmImageCacheManager());
  }

  Future<void> _warmImageCacheManager() async {
    try {
      await ref.read(imageCacheManagerProvider.future);
    } catch (_) {
      // Cache initialization is best effort and must never delay the shell.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _coverMigrationReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildReadyShell(context);
      },
    );
  }

  Widget _buildReadyShell(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.watch(favoriteSyncTaskProgressRegistrationProvider);
    ref.watch(comicSearchQueueTaskProgressRegistrationProvider);
    // 启动进度->系统通知桥接，让收藏同步/漫画搜索等待进入通知栏。
    ref
        .watch(libraryTaskNotificationBridgeProvider)
        .start(
          localeId: l10n.localeName,
          textResolver: (progress) =>
              LibraryTaskTextResolver.notification(l10n, progress),
        );
    final selectionHost = ref.watch(shelfSelectionHostControllerProvider);
    final navigationState = ref
        .watch(mainNavigationSettingsControllerProvider)
        .value;
    if (navigationState == null) {
      return const Scaffold(
        body: SizedBox.expand(key: Key('main-shell-navigation-loading')),
      );
    }
    final settings = navigationState.settings;
    final visibleDestinations = settings.visibleDestinations;
    final visibleSet = visibleDestinations.toSet();
    _builtDestinations.removeWhere(
      (destination) => !visibleSet.contains(destination),
    );
    final currentDestination = _resolveCurrentDestination(settings);
    _currentDestination = currentDestination;
    _builtDestinations.add(currentDestination);

    return Scaffold(
      body: IndexedStack(
        index: MainShellDestination.values.indexOf(currentDestination),
        children: _buildIndexedPages(
          settings,
          currentDestination: currentDestination,
        ),
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
                  Tween<Offset>(
                    begin: begin,
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)),
                ),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: selectionHost.isActive
                ? SelectionActionBar(
                    key: const ValueKey<String>('main-shell-selection-bar'),
                    actions:
                        selectionHost.state?.selectionActions ??
                        const <SelectionAction>[],
                    l10n: l10n,
                    onActionTap: _handleSelectionActionTap,
                  )
                : NavigationBar(
                    key: const ValueKey<String>('main-shell-navigation-bar'),
                    selectedIndex: visibleDestinations.indexOf(
                      currentDestination,
                    ),
                    onDestinationSelected: (index) {
                      final destination = visibleDestinations[index];
                      setState(() {
                        _currentDestination = destination;
                        _builtDestinations.add(destination);
                      });
                    },
                    destinations: visibleDestinations
                        .map(_buildNavigationDestination)
                        .toList(growable: false),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _handleSelectionActionTap(SelectionAction action) async {
    final l10n = AppLocalizations.of(context);
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
      _showSelectionMessage(
        SelectionActionTextResolver.resultMessage(l10n, action.id, result),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSelectionMessage(
        l10n.librarySelectionActionFailed(
          LibraryErrorSummary.resolve(l10n, error),
        ),
      );
    }
  }

  Future<bool?> _confirmSelectionAction(
    SelectionAction action,
    ShelfSelectionHostState? state,
  ) {
    final l10n = AppLocalizations.of(context);
    final selectedCount = state?.selectedCount ?? 0;
    final title = action.id == SelectionActionIds.unfavorite
        ? l10n.librarySelectionConfirmUnfavoriteTitle
        : l10n.librarySelectionConfirmActionTitle;
    final content = action.id == SelectionActionIds.unfavorite
        ? l10n.librarySelectionConfirmUnfavoriteBody(selectedCount)
        : l10n.librarySelectionConfirmActionBody(
            selectedCount,
            SelectionActionTextResolver.label(l10n, action.id),
          );
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonConfirm),
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
    final l10n = AppLocalizations.of(context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(l10n.librarySelectionSelectCategory),
                enabled: false,
              ),
              for (final category in available)
                ListTile(
                  title: Text(
                    LibraryShelfTextResolver.categoryName(l10n, category),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop(category.categoryId);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(l10n.librarySelectionCreateCategory),
                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop(_createCategorySelectionSentinel);
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

  Future<String?> _showCreateCategoryDialog() {
    return showDialog<String>(
      context: context,
      builder: (_) => const _CreateSelectionCategoryDialog(),
    );
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

  MainShellDestination _resolveCurrentDestination(
    MainNavigationSettings settings,
  ) {
    final current = _currentDestination;
    if (current != null && settings.visibleDestinations.contains(current)) {
      return current;
    }
    return settings.visibleManagedDestinations.first;
  }

  NavigationDestination _buildNavigationDestination(
    MainShellDestination destination,
  ) {
    return NavigationDestination(
      icon: _buildNavigationIcon(destination.icon),
      selectedIcon: _buildNavigationIcon(destination.selectedIcon),
      label: destination.localizedLabel(AppLocalizations.of(context)),
    );
  }

  Widget _buildNavigationIcon(IconData icon) {
    return SizedBox(width: 24, height: 24, child: Center(child: Icon(icon)));
  }

  List<Widget> _buildIndexedPages(
    MainNavigationSettings settings, {
    required MainShellDestination currentDestination,
  }) {
    return MainShellDestination.values
        .map((destination) {
          if (!settings.isVisible(destination) ||
              !_builtDestinations.contains(destination)) {
            return SizedBox.shrink(
              key: ValueKey<String>('main-shell-empty-${destination.name}'),
            );
          }
          final isActive = destination == currentDestination;
          return KeyedSubtree(
            key: ValueKey<String>('main-shell-page-${destination.name}'),
            child: TickerMode(
              enabled: isActive,
              child: _buildPage(destination, isActive: isActive),
            ),
          );
        })
        .toList(growable: false);
  }

  static const String _createCategorySelectionSentinel =
      '__create-selection-category__';

  Widget _buildPage(
    MainShellDestination destination, {
    required bool isActive,
  }) {
    return switch (destination) {
      MainShellDestination.forum => ForumShellPage(isActive: isActive),
      MainShellDestination.favorites => FavoriteShelfPage(isActive: isActive),
      MainShellDestination.comic => ComicTabPage(isActive: isActive),
      MainShellDestination.novel => NovelTabPage(isActive: isActive),
      MainShellDestination.history => HistoryPage(
        onOpenEntry: ref.read(historyEntryRouterProvider).open,
        imageReferer: ref.watch(forumImageRefererProvider),
      ),
      MainShellDestination.more => const MorePage(),
    };
  }
}

class _CreateSelectionCategoryDialog extends StatefulWidget {
  const _CreateSelectionCategoryDialog();

  @override
  State<_CreateSelectionCategoryDialog> createState() =>
      _CreateSelectionCategoryDialogState();
}

class _CreateSelectionCategoryDialogState
    extends State<_CreateSelectionCategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('selection-create-category-dialog'),
      title: Text(l10n.librarySelectionCreateCategory),
      content: TextField(
        key: const Key('selection-create-category-name-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.librarySelectionCategoryNameHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}

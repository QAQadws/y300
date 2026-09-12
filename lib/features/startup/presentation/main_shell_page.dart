import 'dart:async';

import 'package:y300/features/library_shared/data/providers/library_cover_thumbnail_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/main_destination_page.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_shell_destination_presentation.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_bottom_bar.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/data/services/cache_budget_scheduler.dart';
import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/providers/comic_refresh_workflow_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_task_workflow_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_migration_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_task_notification_providers.dart';
import 'package:y300/features/library_shared/presentation/services/library_task_text_resolver.dart';
import 'package:y300/features/more/presentation/more_page.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
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
            _startBackgroundTaskSafely(
              ref.read(libraryCoverLegacyThumbnailCleanupProvider).run,
            ),
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
      bottomNavigationBar: ShelfSelectionBottomBar(
        fallback: NavigationBar(
          key: const ValueKey<String>('main-shell-navigation-bar'),
          selectedIndex: visibleDestinations.indexOf(currentDestination),
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
      ),
    );
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

  Widget _buildPage(
    MainShellDestination destination, {
    required bool isActive,
  }) {
    return switch (destination) {
      MainShellDestination.more => const MorePage(),
      _ => MainDestinationPage(destination: destination, isActive: isActive),
    };
  }
}

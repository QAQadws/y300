import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/startup/main_shell_startup_coordinator.dart';
import 'package:y300/app/storage/storage_accounting_providers.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/data/services/cache_budget_scheduler.dart';
import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/providers/comic_refresh_workflow_providers.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_migration_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_thumbnail_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_task_notification_providers.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final mainShellStartupCoordinatorFactoryProvider =
    Provider<MainShellStartupCoordinator Function()>((ref) {
      var ownerActive = true;
      ref.onDispose(() => ownerActive = false);
      return () => MainShellStartupCoordinator(
        prepareLibrary: ref.read(mainShellBackgroundTaskStarterProvider),
        initializeNotifications: ref.read(
          mainShellNotificationInitializerProvider,
        ),
        warmups: [
          ref.read(mainShellReplyDraftAttachmentMaintenanceStarterProvider),
          ref.read(mainShellYamiboSessionWarmupProvider),
          ref.read(mainShellImageCacheWarmupProvider),
        ],
        isOwnerActive: () => ownerActive,
      );
    });

final mainShellBackgroundTaskStarterProvider = Provider<MainShellLifecycleTask>(
  (ref) {
    return (isActive) async {
      bool canContinue() => ref.mounted && isActive();
      if (!canContinue()) return;
      final migrator = ref.read(libraryCoverLegacyMigratorProvider);
      final mergeRecovery = ref.read(comicCoverMergeRecoveryProvider);
      await runMainShellBackgroundTasks(
        isActive: canContinue,
        recoverCoverMerges: mergeRecovery?.recoverPendingCoverMerges,
        migrateCustomCovers: migrator.migrateCustomAssets,
        maintenance: [
          () => ref.read(mainShellCacheBudgetSchedulerProvider).start(),
          () => ref.read(comicSearchRefreshQueueServiceProvider).start(),
          () async {
            await ref.read(storageRootAccessGateProvider).ensureReady();
            // A shell may disappear while the exclusive storage gate waits.
            if (!canContinue()) return;
            await ref.read(comicDownloadQueueProvider).start();
          },
          migrator.migrateSourceAssets,
          () => ref.read(libraryCoverLegacyThumbnailCleanupProvider).run(),
        ],
      );
    };
  },
);

final mainShellCacheBudgetSchedulerProvider = Provider<CacheBudgetScheduler>((
  ref,
) {
  final scheduler = CacheBudgetScheduler(
    source: ref.watch(cacheMutationBusProvider),
    enforce: () async {
      if (!ref.mounted) return;
      final maxBytes = await ref
          .read(dataStorageSettingsRepositoryProvider)
          .getCacheMaxBytes();
      if (!ref.mounted) return;
      await ref
          .read(cacheMaintenanceServiceProvider)
          .prune(CachePruneRequest(maxCacheBytes: maxBytes));
    },
  );
  ref.onDispose(() => unawaited(scheduler.dispose()));
  return scheduler;
});

/// Permission/channel failures remain isolated from readiness and navigation.
final mainShellNotificationInitializerProvider =
    Provider<MainShellLifecycleTask>((ref) {
      return (isActive) async {
        if (!ref.mounted || !isActive()) return;
        try {
          final service = ref.read(libraryTaskNotificationServiceProvider);
          await service.initialize();
          if (!ref.mounted || !isActive()) return;
          await service.ensurePermission();
        } catch (_) {
          // Unsupported platform channels must not surface an unhandled error.
        }
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
          // Draft attachment maintenance is best effort at startup.
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
      // Warm shared formhash/session metadata without blocking the forum shell.
    }
  };
});

final mainShellImageCacheWarmupProvider = Provider<Future<void> Function()>((
  ref,
) {
  return () async {
    try {
      await ref.read(imageCacheManagerProvider.future);
    } catch (_) {
      // Transport initialization failure remains local to image retries.
    }
  };
});

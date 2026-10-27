import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/favorites/data/providers/favorite_directory_providers.dart';
import 'package:y300/features/favorites/data/providers/favorite_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/thread/domain/services/thread_favorite_action_service.dart';

final threadFavoriteActionServiceProvider =
    Provider<ThreadFavoriteActionService>((ref) {
      final shelfRefreshBus = ref.watch(libraryShelfRefreshBusProvider);
      return DefaultThreadFavoriteActionService(
        command: ref.watch(favoriteThreadCommandProvider),
        refreshFavoriteModule: ({required String tid}) async {
          final result = await ref
              .read(favoriteSyncServiceProvider)
              .syncRecentlyAddedThread(tid: tid);
          if (result.failedDetailTids.contains(tid.trim())) {
            throw StateError('favorite_target_detail_sync_incomplete');
          }
        },
        notifyFavoriteModule: ({required String reason, required String tid}) {
          shelfRefreshBus.notify(
            modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
            reason: reason,
            source: LibraryMutationSource.threadFavoriteAction,
            tid: tid,
          );
        },
      );
    });

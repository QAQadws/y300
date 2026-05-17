import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/favorites/data/favorite_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/thread/data/discuz_thread_favorite_api_repository.dart';
import 'package:y300/features/thread/data/thread_favorite_repository.dart';
import 'package:y300/features/thread/domain/services/thread_favorite_action_service.dart';

final threadFavoriteRepositoryProvider = Provider<ThreadFavoriteRepository>((ref) {
  return DiscuzThreadFavoriteApiRepository(
    profileRepository: ref.read(profileRepositoryProvider),
    cookieStore: ref.read(cookieStoreProvider),
  );
});

final threadFavoriteActionServiceProvider = Provider<ThreadFavoriteActionService>((ref) {
  final shelfRefreshBus = ref.watch(libraryShelfRefreshBusProvider);
  return DefaultThreadFavoriteActionService(
    repository: ref.watch(threadFavoriteRepositoryProvider),
    refreshFavoriteModule: ({required String tid}) async {
      await ref.read(favoriteSyncServiceProvider).syncRecentlyAddedThread(tid: tid);
    },
    notifyFavoriteModule: ({required String reason}) {
      shelfRefreshBus.notify(
        modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
        reason: reason,
      );
    },
  );
});

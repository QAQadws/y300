import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/favorites/data/providers/favorite_providers.dart';
import 'package:y300/features/favorites/data/use_cases/unfavorite_use_cases_impl.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/data/providers/work_purge_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/thread/data/providers/thread_favorite_providers.dart';

final unfavoriteWorkUseCaseProvider = Provider<UnfavoriteWorkUseCase>((ref) {
  return DefaultUnfavoriteWorkUseCase(
    threadFavoriteRepository: ref.watch(threadFavoriteRepositoryProvider),
    favoriteLinkService: ref.watch(favoriteLinkServiceProvider),
    localFavoriteRepository: ref.watch(localFavoriteRepositoryProvider),
    workPurgeService: ref.watch(workPurgeServiceProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});

final unfavoriteThreadUseCaseProvider = Provider<UnfavoriteThreadUseCase>((
  ref,
) {
  return DefaultUnfavoriteThreadUseCase(
    threadFavoriteRepository: ref.watch(threadFavoriteRepositoryProvider),
    favoriteLinkService: ref.watch(favoriteLinkServiceProvider),
    localFavoriteRepository: ref.watch(localFavoriteRepositoryProvider),
    workPurgeService: ref.watch(workPurgeServiceProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});

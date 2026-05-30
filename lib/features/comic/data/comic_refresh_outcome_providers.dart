import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

final comicRefreshOutcomeApplierProvider =
    Provider<ComicRefreshOutcomeApplier>((ref) {
  return DefaultComicRefreshOutcomeApplier(
    repository: ref.watch(comicRepositoryProvider),
    firstEpisodeCoverPromoter: ref.watch(comicFirstEpisodeCoverServiceProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/favorites/data/providers/favorite_providers.dart';
import 'package:y300/features/favorites/data/repositories/favorite_parse_job_repository.dart';
import 'package:y300/features/favorites/data/services/favorite_parse_coordinator.dart';
import 'package:y300/features/favorites/domain/services/favorite_parse_service.dart';

final favoriteParseJobRepositoryProvider = Provider<FavoriteParseJobRepository>(
  (ref) => FavoriteParseJobRepository(AppDatabase.open()),
);

final favoriteParseRecoveryProvider = Provider<void>((ref) {
  if (ref.watch(verifiedSessionOwnerProvider) != null) {
    ref.watch(favoriteParseServiceProvider);
  }
});

final favoriteParseServiceProvider = Provider<FavoriteParseService>((ref) {
  final owner = ref.watch(verifiedSessionOwnerProvider);
  if (owner == null) throw StateError('favorite_parse_login_required');
  final executor =
      ref.watch(favoriteSyncServiceProvider) as FavoriteThreadParseExecutor;
  var mounted = true;
  final service = DefaultFavoriteParseCoordinator(
    accountId: owner.uid,
    repository: ref.watch(favoriteParseJobRepositoryProvider),
    executor: executor,
    isOwnerCurrent: () =>
        mounted && ref.read(verifiedSessionOwnerProvider) == owner,
  );
  ref.onDispose(() {
    mounted = false;
    service.close();
  });
  unawaited(service.resume().catchError((Object _) {}));
  return service;
});

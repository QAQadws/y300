import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/favorite_shelf_bootstrapper.dart';

class DefaultFavoriteShelfBootstrapper implements FavoriteShelfBootstrapper {
  DefaultFavoriteShelfBootstrapper({
    required LocalFavoriteRepository repository,
    required FavoriteSyncService syncService,
  })  : _repository = repository,
        _syncService = syncService;

  final LocalFavoriteRepository _repository;
  final FavoriteSyncService _syncService;
  Future<void>? _startFuture;

  @override
  Future<void> startIfNeeded() {
    final existing = _startFuture;
    if (existing != null) {
      return existing;
    }
    final future = _run();
    _startFuture = future;
    return future;
  }

  Future<void> _run() async {
    try {
      final snapshot = await _repository.getSyncSnapshot();
      if (snapshot == null) {
        await _syncService.sync();
        return;
      }

      final missingDetails = await _repository.countMissingDetailRecords();
      if (missingDetails > 0) {
        await _syncService.sync();
      } else {
        await _syncService.runBackgroundMaintenance();
      }
    } catch (_) {
      // Keep shelf bootstrap non-blocking. The sync service owns progress and
      // error reporting; startup should not prevent the shelf metadata path.
    }
  }
}

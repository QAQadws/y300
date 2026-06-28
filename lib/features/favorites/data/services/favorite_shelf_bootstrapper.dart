import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/services/favorite_shelf_bootstrapper.dart';

class DefaultFavoriteShelfBootstrapper implements FavoriteShelfBootstrapper {
  DefaultFavoriteShelfBootstrapper({
    required LocalFavoriteRepository repository,
    required FavoriteSyncService syncService,
  })  : _repository = repository,
        _syncService = syncService;

  final LocalFavoriteRepository _repository;
  final FavoriteSyncService _syncService;
  Future<void>? _startFuture;
  var _hasCompletedBootstrap = false;

  @override
  Future<void> startIfNeeded() {
    if (_hasCompletedBootstrap) {
      return Future<void>.value();
    }
    final existing = _startFuture;
    if (existing != null) {
      return existing;
    }
    final future = _run().whenComplete(() {
      _startFuture = null;
    });
    _startFuture = future;
    return future;
  }

  Future<void> _run() async {
    try {
      final snapshot = await _repository.getSyncSnapshot();
      if (snapshot == null) {
        await _syncService.sync();
        _hasCompletedBootstrap = await _hasStableBaseline();
        return;
      }

      final missingDetails = await _repository.countMissingDetailRecords();
      if (missingDetails > 0) {
        await _syncService.sync();
        _hasCompletedBootstrap = await _hasStableBaseline();
      } else {
        _hasCompletedBootstrap = true;
        await _syncService.runBackgroundMaintenance();
      }
    } catch (_) {
      // Keep shelf bootstrap non-blocking. The sync service owns progress and
      // error reporting; startup should not prevent the shelf metadata path.
    }
  }

  Future<bool> _hasStableBaseline() async {
    final snapshot = await _repository.getSyncSnapshot();
    if (snapshot == null) {
      return false;
    }
    final missingDetails = await _repository.countMissingDetailRecords();
    return missingDetails == 0;
  }
}

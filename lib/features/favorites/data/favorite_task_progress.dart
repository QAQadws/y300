import 'package:flutter/foundation.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

class FavoriteSyncShelfTaskProgressListenable
    implements ValueListenable<LibraryShelfTaskProgress?> {
  const FavoriteSyncShelfTaskProgressListenable(this._source);

  final ValueListenable<FavoriteSyncProgress> _source;

  @override
  LibraryShelfTaskProgress? get value {
    final progress = _source.value;
    if (!progress.isActive) {
      return null;
    }
    return LibraryShelfTaskProgress(
      message: progress.message,
      current: progress.current,
      total: progress.total,
      source: LibraryMutationSource.favoriteSync,
      visible: true,
      reloadOnCompletion: true,
    );
  }

  @override
  void addListener(VoidCallback listener) {
    _source.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _source.removeListener(listener);
  }
}

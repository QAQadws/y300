import 'package:flutter/foundation.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

class FavoriteSyncShelfTaskProgressListenable extends ChangeNotifier
    implements ValueListenable<LibraryShelfTaskProgress?> {
  FavoriteSyncShelfTaskProgressListenable(
    ValueListenable<FavoriteSyncProgress> source,
    ValueListenable<LibraryTaskNotificationPermissionState?> permissionState,
  ) : _source = source,
      _permissionState = permissionState {
    _source.addListener(_handleChange);
    _permissionState.addListener(_handleChange);
  }

  final ValueListenable<FavoriteSyncProgress> _source;
  final ValueListenable<LibraryTaskNotificationPermissionState?> _permissionState;

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
      visible: !_isNotificationPermissionGranted,
      reloadOnCompletion: true,
    );
  }

  bool get _isNotificationPermissionGranted =>
      _permissionState.value ==
      LibraryTaskNotificationPermissionState.granted;

  void _handleChange() {
    notifyListeners();
  }

  @override
  void dispose() {
    _source.removeListener(_handleChange);
    _permissionState.removeListener(_handleChange);
    super.dispose();
  }
}

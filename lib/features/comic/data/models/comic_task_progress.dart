import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

class ComicSearchQueueShelfTaskProgressListenable extends ChangeNotifier
    implements ValueListenable<LibraryShelfTaskProgress?> {
  ComicSearchQueueShelfTaskProgressListenable(
    ValueListenable<ComicSearchRefreshQueueSnapshot> source,
    ValueListenable<LibraryTaskNotificationPermissionState?> permissionState,
  ) : _source = source,
      _permissionState = permissionState {
    _source.addListener(_handleChange);
    _permissionState.addListener(_handleChange);
  }

  final ValueListenable<ComicSearchRefreshQueueSnapshot> _source;
  final ValueListenable<LibraryTaskNotificationPermissionState?>
  _permissionState;

  @override
  LibraryShelfTaskProgress? get value {
    final snapshot = _source.value;
    final title = snapshot.headTitle;
    if (!snapshot.active || title == null || title.trim().isEmpty) {
      return null;
    }
    return LibraryShelfTaskProgress(
      code: LibraryShelfTaskProgressCode.comicSearchWaiting,
      subject: title,
      estimatedDuration: snapshot.estimatedDuration,
      source: LibraryMutationSource.comicSearchQueue,
      visible: !_isNotificationPermissionGranted,
      reloadOnCompletion: true,
    );
  }

  bool get _isNotificationPermissionGranted =>
      _permissionState.value == LibraryTaskNotificationPermissionState.granted;

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

import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

class ComicSearchQueueShelfTaskProgressListenable
    implements ValueListenable<LibraryShelfTaskProgress?> {
  const ComicSearchQueueShelfTaskProgressListenable(this._source);

  final ValueListenable<ComicSearchRefreshQueueSnapshot> _source;

  @override
  LibraryShelfTaskProgress? get value {
    final snapshot = _source.value;
    final message = snapshot.waitingMessage;
    if (!snapshot.active || message == null) {
      return null;
    }
    return LibraryShelfTaskProgress(
      message: message,
      source: LibraryMutationSource.comicSearchQueue,
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

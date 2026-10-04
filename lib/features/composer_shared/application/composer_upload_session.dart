import 'dart:async';

import 'package:y300/features/composer_shared/application/composer_upload_batch.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';

/// Owns upload lifetime; controller patches and text insertion stay with the UI.
final class ComposerUploadSession {
  ComposerUploadSession({required ComposerImageUploadCoordinator coordinator})
    : _coordinator = coordinator;

  final ComposerImageUploadCoordinator _coordinator;
  StreamSubscription<ComposerImageUploadEvent>? _subscription;
  ComposerUploadBatch? _batch;
  int _generation = 0;
  bool _closed = false;
  Future<void>? _closing;

  /// Reset/close also invalidates a picker that has not returned any images yet.
  bool Function() captureSelectionValidity() {
    final generation = _generation;
    return () => _isCurrent(generation);
  }

  void start({
    required String fid,
    required List<ComposerImageAttachment> attachments,
    required ComposerInsertionAnchor? anchor,
    required void Function(ComposerImageUploadEvent) onEvent,
    required void Function(Object, StackTrace) onError,
  }) {
    if (_closed || attachments.isEmpty) return;
    final generation = ++_generation;
    _batch = ComposerUploadBatch(
      anchor: anchor,
      localIds: attachments.map((attachment) => attachment.localId),
    );
    final previous = _subscription;
    _subscription = null;
    unawaited(previous?.cancel());
    final subscription = _coordinator
        .uploadInOrder(fid: fid, attachments: attachments)
        .listen(
          (event) {
            if (!_isCurrent(generation)) return;
            onEvent(event);
            if (event.type == ComposerImageUploadEventType.completed) {
              _settle(generation);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_isCurrent(generation)) return;
            onError(error, stackTrace);
            _settle(generation);
          },
        );
    // A synchronous source may reset/close/start another run inside onEvent
    // before listen returns. Never install its now-obsolete subscription.
    if (_isCurrent(generation)) {
      _subscription = subscription;
    } else {
      unawaited(subscription.cancel());
    }
  }

  /// Both completion and partial-success error handling consume the same batch.
  ComposerUploadBatch? consumeBatch() {
    final batch = _batch;
    _batch = null;
    return batch;
  }

  Future<void> cancel() {
    if (_closed) return _closing ?? Future<void>.value();
    return _cancelRun();
  }

  Future<void> _cancelRun() async {
    _generation += 1;
    _batch = null;
    _coordinator.cancel();
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  Future<void> close() {
    if (_closed) return _closing ?? Future<void>.value();
    _closed = true;
    return _closing = _cancelRun();
  }

  bool _isCurrent(int generation) => !_closed && generation == _generation;

  void _settle(int generation) {
    if (!_isCurrent(generation)) return;
    _generation += 1;
    _batch = null;
  }
}

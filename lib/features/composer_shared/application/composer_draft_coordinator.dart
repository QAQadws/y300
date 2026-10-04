import 'dart:async';

import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_draft_repository.dart';

/// Owns local durability without knowing controller patches or submit rules.
final class ComposerDraftCoordinator<TState> {
  ComposerDraftCoordinator({
    required ComposerDraftRepository repository,
    required this.identity,
    required TState? Function() readState,
    required bool Function(TState) shouldPersist,
    required ComposerDraftSnapshot Function(TState) snapshotFor,
    this.debounce = defaultSaveDebounce,
  }) : _repository = repository,
       _readState = readState,
       _shouldPersist = shouldPersist,
       _snapshotFor = snapshotFor;

  static const defaultSaveDebounce = Duration(milliseconds: 700);

  final ComposerDraftRepository _repository;
  final ComposerDraftIdentity identity;
  final Duration debounce;
  final TState? Function() _readState;
  final bool Function(TState) _shouldPersist;
  final ComposerDraftSnapshot Function(TState) _snapshotFor;
  Timer? _timer;
  Future<void> _writeTail = Future<void>.value();
  bool _closed = false;
  bool _discarded = false;
  bool _discardCleanupPending = false;
  Future<bool>? _discardResult;
  int _writeEpoch = 0;

  Future<ComposerDraftSnapshot?> restore() async {
    if (_closed) return null;
    try {
      await _repository.pruneDrafts();
    } catch (_) {
      // Maintenance failure must not block restoring this editor's input.
    }
    if (_closed) return null;
    final draft = await _repository.loadDraft(identity);
    return _closed ? null : draft;
  }

  /// Restored attachment verification keeps its existing load-error behavior.
  Future<void> saveRestoredSnapshot(ComposerDraftSnapshot draft) {
    if (_closed || _discarded) return Future<void>.value();
    final epoch = _writeEpoch;
    final snapshot = _captureSnapshot(draft);
    return _enqueue(() async {
      if (epoch == _writeEpoch) await _repository.saveDraft(snapshot);
    });
  }

  void scheduleSave() {
    if (_closed) return;
    // A new edit starts a new draft after an explicit reset or successful send.
    if (_discarded) _writeEpoch += 1;
    _discarded = false;
    _discardCleanupPending = false;
    cancelPendingSave();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  void cancelPendingSave() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> flush() async {
    cancelPendingSave();
    if (_closed || _discarded) return;
    final current = _readState();
    if (current != null) await saveState(current);
  }

  Future<void> saveState(TState value) {
    if (_closed || _discarded) return Future<void>.value();
    return _persistState(value);
  }

  /// Serial deletion follows an already running write and invalidates queued
  /// older snapshots. A confirmed send may still clean up after route exit.
  Future<bool> discard() {
    cancelPendingSave();
    _discarded = true;
    _discardCleanupPending = false;
    final epoch = ++_writeEpoch;
    return _discardResult = _discardOnce(epoch);
  }

  Future<bool> _discardOnce(int epoch) async {
    try {
      await _enqueue(() => _repository.deleteDraft(identity));
      return true;
    } catch (_) {
      if (epoch == _writeEpoch && _discarded) {
        _discardCleanupPending = true;
        if (_closed) await _retryDiscardCleanup();
      }
      return false;
    }
  }

  /// Capture the last input and its collections synchronously. Late callbacks
  /// cannot enqueue another snapshot, and a discarded draft stays discarded.
  Future<void> close() {
    cancelPendingSave();
    if (_discarded) {
      _closed = true;
      return _finishDiscardCleanup();
    }
    if (_closed) return _writeTail;
    final current = _readState();
    _closed = true;
    return current == null ? _writeTail : _persistState(current);
  }

  Future<void> _finishDiscardCleanup() async {
    // Include an in-flight discard's failure handling in the close barrier.
    await _discardResult;
    if (_discardCleanupPending) await _retryDiscardCleanup();
    await _writeTail;
  }

  Future<void> _retryDiscardCleanup() async {
    if (!_discarded || !_discardCleanupPending) return;
    _discardCleanupPending = false;
    final epoch = _writeEpoch;
    try {
      await _enqueue(() async {
        if (epoch == _writeEpoch && _discarded) {
          await _repository.deleteDraft(identity);
        }
      });
    } catch (_) {
      // Keep one best-effort exit cleanup opportunity, without a retry loop
      // or restoring content that the server has already accepted.
    }
  }

  Future<void> _persistState(TState value) async {
    final epoch = _writeEpoch;
    final snapshot = _shouldPersist(value)
        ? _captureSnapshot(_snapshotFor(value))
        : null;
    try {
      await _enqueue(() async {
        if (epoch != _writeEpoch) return;
        if (snapshot == null) {
          await _repository.deleteDraft(identity);
        } else {
          await _repository.saveDraft(snapshot);
        }
      });
    } catch (_) {
      // Saving and empty-draft cleanup remain best effort while editing/leaving.
    }
  }

  ComposerDraftSnapshot _captureSnapshot(ComposerDraftSnapshot draft) =>
      ComposerDraftSnapshot(
        identity: draft.identity,
        message: draft.message,
        subject: draft.subject,
        extras: Map<String, String>.unmodifiable(draft.extras),
        useSignature: draft.useSignature,
        updatedAt: draft.updatedAt,
        imageAttachments: List.unmodifiable(draft.imageAttachments),
      );

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writeTail.then((_) => operation());
    _writeTail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

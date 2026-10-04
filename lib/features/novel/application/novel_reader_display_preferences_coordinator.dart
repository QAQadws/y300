import 'dart:async';

import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

class NovelReaderDisplayPreferencesCoordinator {
  NovelReaderDisplayPreferencesCoordinator({
    required void Function(NovelReaderPreferences) preview,
    required Future<void> Function(NovelReaderPreferences) commit,
    required void Function() revertPreview,
    required void Function() onFailure,
    Future<void>? precedingCommit,
  }) : _preview = preview,
       _commit = commit,
       _revertPreview = revertPreview,
       _onFailure = onFailure,
       _baselineConfirmed = precedingCommit == null,
       _commitTail = precedingCommit ?? Future<void>.value();

  final void Function(NovelReaderPreferences) _preview;
  final Future<void> Function(NovelReaderPreferences) _commit;
  final void Function() _revertPreview;
  final void Function() _onFailure;
  Timer? _previewThrottle;
  Timer? _persistDebounce;
  NovelReaderPreferences? _pending;
  NovelReaderPreferences? _lastPreviewed;
  NovelReaderPreferences? _lastPersisted;
  NovelReaderPreferences? _queuedPreferences;
  Future<void> _commitTail;
  bool _baselineConfirmed;
  void Function()? _pendingFailure;
  int _revision = 0;
  int _queueSerial = 0;
  bool _disposed = false;

  void begin({
    required NovelReaderPreferences preferences,
    required NovelReaderPreferences persistedPreferences,
  }) {
    if (_disposed) return;
    _cancelTimers();
    _revision += 1;
    _pending = preferences;
    _lastPreviewed = preferences;
    // A retired writer can finish after this session loaded its baseline.
    _lastPersisted = _baselineConfirmed ? persistedPreferences : null;
    _pendingFailure = _onFailure;
  }

  void change(NovelReaderPreferences preferences) {
    if (_disposed) return;
    _pending = preferences;
    _pendingFailure = _onFailure;
    _revision += 1;
    if (_previewThrottle?.isActive != true) {
      _applyPendingPreview();
      _previewThrottle = Timer(const Duration(milliseconds: 90), () {
        _previewThrottle = null;
        _applyPendingPreview();
      });
    }
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 520), () {
      _persistDebounce = null;
      unawaited(_enqueuePendingCommit());
    });
  }

  Future<void> flush() {
    if (_disposed) return _commitTail;
    _cancelTimers();
    _applyPendingPreview();
    return _enqueuePendingCommit();
  }

  Future<void> commitImmediately(
    NovelReaderPreferences preferences, {
    void Function()? onFailure,
  }) {
    if (_disposed) return _commitTail;
    _cancelTimers();
    _revision += 1;
    _pending = preferences;
    _pendingFailure = onFailure ?? _onFailure;
    _applyPendingPreview();
    return _enqueuePendingCommit();
  }

  Future<void> dispose() {
    _disposed = true;
    _revision += 1;
    _cancelTimers();
    _pending = null;
    return _commitTail;
  }

  void _cancelTimers() {
    _previewThrottle?.cancel();
    _previewThrottle = null;
    _persistDebounce?.cancel();
    _persistDebounce = null;
  }

  void _applyPendingPreview() {
    final preferences = _pending;
    if (_disposed || preferences == null || preferences == _lastPreviewed) {
      return;
    }
    _lastPreviewed = preferences;
    _preview(preferences);
  }

  Future<void> _enqueuePendingCommit() {
    final preferences = _pending;
    if (preferences == null || preferences == _queuedPreferences) {
      // Dismissal must also await an identical save already in flight.
      return _commitTail;
    }
    final revision = _revision;
    final serial = ++_queueSerial;
    _queuedPreferences = preferences;
    _commitTail = _commitTail.then((_) async {
      try {
        // A queued value may have been superseded before the preceding save ends.
        if (_disposed ||
            _pending != preferences ||
            preferences == _lastPersisted) {
          return;
        }
        await _commit(preferences);
        _lastPersisted = preferences;
        _baselineConfirmed = true;
      } catch (_) {
        _lastPersisted = null;
        _baselineConfirmed = false;
        if (_disposed || revision != _revision) return;
        _revertPreview();
        _lastPreviewed = null;
        _pendingFailure?.call();
      } finally {
        if (serial == _queueSerial) _queuedPreferences = null;
      }
    });
    return _commitTail;
  }
}

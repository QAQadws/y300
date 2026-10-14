import 'dart:async';

import '../domain/models/forum_html_reader_preferences.dart';
import '../domain/repositories/forum_html_reader_preferences_repository.dart';

/// A repository owner has one active save and one replaceable pending value.
/// Completing a merged pending future confirms the latest value of that group.
final class ForumHtmlReaderPreferenceWriter {
  ForumHtmlReaderPreferenceWriter(this.repository);

  final ForumHtmlReaderPreferencesRepository repository;
  _Save? _running;
  _Save? _pending;
  Completer<void>? _idle;
  Future<ForumHtmlReaderPreferences>? _loading;
  ForumHtmlReaderPreferences? _lastSuccessful;
  ForumHtmlReaderPreferences? get lastSuccessful => _lastSuccessful;
  bool _confirmed = false;

  // Custom controllers can supply their own loaded display baseline. It is
  // useful for rollback but does not prove storage is equal for deduplication.
  void retainRollbackBaseline(ForumHtmlReaderPreferences value) {
    _lastSuccessful ??= value;
  }

  Future<ForumHtmlReaderPreferences> load() => _loading ??= _load();

  Future<ForumHtmlReaderPreferences> _load() async {
    // Wait for writes already issued. A new drain waits for this load instead,
    // preventing an older repository snapshot from confirming a newer save.
    final precedingWrites = _idle?.future;
    try {
      await (precedingWrites ?? Future<void>.value());
      final value = await repository.load();
      _lastSuccessful = value;
      _confirmed = true;
      return value;
    } finally {
      _loading = null;
    }
  }

  Future<void> save(ForumHtmlReaderPreferences value) {
    final pending = _pending;
    if (pending != null) {
      pending.value = value;
      return pending.done.future;
    }
    if (_running?.value == value) return _running!.done.future;
    if (_running == null && _confirmed && lastSuccessful == value) {
      return Future<void>.value();
    }
    final next = _Save(value);
    _pending = next;
    if (_idle == null) {
      _idle = Completer<void>();
      unawaited(_drain());
    }
    return next.done.future;
  }

  Future<void> _drain() async {
    final loading = _loading;
    if (loading != null) {
      try {
        await loading;
      } catch (_) {
        // A load failure does not retire an explicitly requested full save.
      }
    }
    while (_pending != null) {
      final job = _pending!;
      _pending = null;
      _running = job;
      try {
        if (!_confirmed || job.value != lastSuccessful) {
          await repository.save(job.value);
          _lastSuccessful = job.value;
          _confirmed = true;
        }
        job.done.complete();
      } catch (error, stack) {
        // SharedPreferences writes several keys. A failed save may have written
        // a prefix; an equal later request must still rewrite the full snapshot.
        _confirmed = false;
        job.done.completeError(error, stack);
      }
      _running = null;
    }
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }
}

final class _Save {
  _Save(this.value);
  ForumHtmlReaderPreferences value;
  final done = Completer<void>();
}

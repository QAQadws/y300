import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';
import 'package:y300/features/profile/domain/repositories/blog_draft_repository.dart';
import 'package:y300/features/profile/presentation/blog/blog_draft_mapper.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';

/// Owns local durability; no transport tickets, uploads or UI text live here.
final class BlogDraftCoordinator extends ChangeNotifier {
  BlogDraftCoordinator({
    required this.accountId,
    required BlogDraftRepository repository,
    this.debounce = const Duration(milliseconds: 700),
    DateTime Function()? now,
  }) : _repository = repository,
       _now = now ?? DateTime.now;
  final String accountId;
  final BlogDraftRepository _repository;
  final Duration debounce;
  final DateTime Function() _now;
  BlogDraftSnapshot? snapshot;
  bool loaded = false;
  bool loadFailed = false;
  bool saveFailed = false;
  bool _active = true;
  bool _disposed = false;
  Timer? _timer;
  int _epoch = 0;
  Future<void> _tail = Future.value();
  bool get pending => snapshot?.pendingSubmission == true;

  Future<bool> load() async {
    final epoch = _epoch;
    try {
      final value = await _repository.load(accountId);
      if (!_active || epoch != _epoch) return false;
      snapshot = value;
      loaded = true;
      loadFailed = false;
    } catch (_) {
      if (!_active || epoch != _epoch) return false;
      loadFailed = true;
    }
    _notify();
    return loaded;
  }

  void update(
    BlogEditorDraft draft, {
    required bool changed,
    required bool creatingCategory,
    List<BlogDraftImage> images = const [],
  }) {
    if (!_active || !loaded) return;
    final known = {
      for (final item in snapshot?.images ?? <BlogDraftImage>[])
        item.picId: item,
      for (final item in images) item.picId: item,
    };
    snapshot = changed || creatingCategory || pending
        ? snapshotBlogDraft(
            accountId: accountId,
            draft: draft,
            updatedAt: _now(),
            creatingCategory: creatingCategory,
            images: known.values.toList(),
            pendingSubmission: pending,
          )
        : null;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  Future<bool> setPending(bool value) async {
    final current = snapshot;
    if (!_active || !loaded || current == null) return false;
    final next = snapshotBlogDraft(
      accountId: accountId,
      draft: restoreBlogDraft(current),
      updatedAt: _now(),
      creatingCategory: current.creatingCategory,
      images: current.images,
      pendingSubmission: value,
    );
    snapshot = next;
    final epoch = _epoch;
    _notify();
    final saved = await flush();
    // Never unlock a pending submission until its acknowledgment is durable.
    if (!saved && _active && epoch == _epoch && identical(snapshot, next)) {
      snapshot = current;
      _notify();
    }
    return saved;
  }

  Future<bool> flush() {
    _timer?.cancel();
    _timer = null;
    if (!_active || !loaded) return Future.value(false);
    final current = snapshot;
    final epoch = _epoch;
    return _write(() async {
      if (epoch != _epoch) return;
      if (current == null) {
        await _repository.delete(accountId);
      } else {
        await _repository.save(current);
      }
    });
  }

  Future<bool> reset() async {
    if (!_active) return false;
    _timer?.cancel();
    final epoch = ++_epoch;
    if (!await _write(() => _repository.delete(accountId))) return false;
    if (!_active || epoch != _epoch) return false;
    snapshot = null;
    loaded = true;
    loadFailed = false;
    _notify();
    return true;
  }

  Future<bool> complete() {
    _timer?.cancel();
    ++_epoch;
    _active = false;
    return _write(() => _repository.delete(accountId));
  }

  Future<bool> _write(Future<void> Function() action) async {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    var saved = true;
    try {
      await next;
    } catch (_) {
      saved = false;
    }
    saveFailed = !saved;
    _notify();
    return saved;
  }

  void expire() {
    // Capture the old account's immutable last input before clearing its UI.
    if (_active && loaded) unawaited(flush());
    _active = false;
    _timer?.cancel();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_active && loaded) unawaited(flush());
    _disposed = true;
    _active = false;
    _timer?.cancel();
    super.dispose();
  }
}

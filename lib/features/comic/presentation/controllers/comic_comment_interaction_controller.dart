import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/services/thread_interaction_context_loader.dart';

/// One chapter's action context. Comment pagination has its own lifecycle.
class ComicCommentInteractionController extends ChangeNotifier {
  ComicCommentInteractionController({
    required this.sourceTid,
    required ThreadInteractionContextLoader loader,
    required Future<void> Function(String) invalidateThread,
    required Future<void> Function() refreshComments,
  }) : _loader = loader,
       _invalidateThread = invalidateThread,
       _refreshComments = refreshComments;

  final String sourceTid;
  final ThreadInteractionContextLoader _loader;
  final Future<void> Function(String) _invalidateThread;
  final Future<void> Function() _refreshComments;
  DataReadResult<ThreadInteractionContext, ThreadDetailReadCapabilities>?
  result;
  bool isLoading = false;
  bool isBusy = false;
  bool _visible = false;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _flight;

  ThreadInteractionContext? get context => result?.dataOrNull;

  void setVisible(bool visible) {
    if (_disposed) return;
    _visible = visible;
    if (visible && result == null) unawaited(load());
  }

  Future<void> load({bool force = false}) {
    if (_disposed) return Future.value();
    if (_flight != null) return _flight!;
    if (!force && result != null) return Future.value();
    final generation = _generation;
    isLoading = true;
    notifyListeners();
    late final Future<void> flight;
    flight = _load(generation).whenComplete(() {
      if (identical(_flight, flight)) _flight = null;
    });
    return _flight = flight;
  }

  Future<void> _load(int generation) async {
    DataReadResult<ThreadInteractionContext, ThreadDetailReadCapabilities> next;
    try {
      next = await _loader.load(sourceTid);
    } catch (_) {
      next = const DataReadFailure(
        kind: DataReadFailureKind.network,
        code: 'thread_interaction_unavailable',
        diagnosticMessage: 'thread_interaction_unavailable',
      );
    }
    if (!_isCurrent(generation)) return;
    result = next;
    isLoading = false;
    notifyListeners();
  }

  void resetSession() {
    if (_disposed) return;
    _generation++;
    _flight = null;
    result = null;
    isBusy = false;
    isLoading = false;
    notifyListeners();
    unawaited(_reloadSession(_generation));
  }

  Future<void> _reloadSession(int generation) async {
    await _invalidate();
    if (_isCurrent(generation) && _visible) await load();
  }

  /// The invocation reports only a proven write, never an optimistic update.
  Future<void> perform({
    required Future<bool> Function(ThreadInteractionContext, bool Function())
    invoke,
    required bool refreshComments,
  }) async {
    if (_disposed || isBusy || isLoading) return;
    final generation = _generation;
    isBusy = true;
    notifyListeners();
    try {
      if (context == null) await load(force: true);
      if (!_isCurrent(generation) || context == null) return;
      final applied = await invoke(context!, () => _isCurrent(generation));
      if (!applied) return;
      // Even if the chapter was disposed during submission, invalidate the
      // original thread; only the active chapter may receive UI refreshes.
      await _invalidate();
      if (!_isCurrent(generation)) return;
      if (refreshComments) unawaited(_refreshComments());
      await load(force: true);
    } finally {
      if (_isCurrent(generation)) {
        isBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _invalidate() async {
    try {
      await _invalidateThread(sourceTid);
    } catch (_) {
      // A cache maintenance failure cannot undo a confirmed remote write.
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

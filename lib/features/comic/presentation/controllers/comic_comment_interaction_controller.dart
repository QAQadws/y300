import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/thread/domain/services/thread_interaction_context_loader.dart';

/// Action availability is a projection of the feed's shared first-page read.
class ComicCommentInteractionController extends ChangeNotifier {
  ComicCommentInteractionController({
    required this.session,
    required Future<void> Function(String) invalidateThread,
  }) : _invalidateThread = invalidateThread {
    session.addListener(_changed);
  }
  final ComicCommentSessionController session;
  final Future<void> Function(String) _invalidateThread;
  String get sourceTid => session.key.sourceTid;
  bool isBusy = false;
  bool _disposed = false;
  bool get isLoading => session.state.isLoading;
  DataReadResult<ThreadInteractionContext, ThreadDetailReadCapabilities>?
  get result {
    final source = session.state.result;
    if (source == null) return null;
    final read = source.reads[1];
    if (read != null) {
      return ThreadInteractionContextLoader.project(sourceTid, read);
    }
    return DataReadFailure(
      kind: source.errorCode == ComicCommentLoadErrorCode.unauthorized
          ? DataReadFailureKind.unauthorized
          : DataReadFailureKind.network,
      code: 'thread_interaction_unavailable',
      diagnosticMessage: 'thread_interaction_unavailable',
    );
  }

  ThreadInteractionContext? get context => result?.dataOrNull;
  void setVisible(bool visible) {
    if (!_disposed && visible && result == null) {
      unawaited(session.loadContext());
    }
  }

  Future<void> load({bool force = false}) =>
      force ? session.retry() : session.loadContext();
  void resetSession() {
    if (!_disposed) unawaited(session.resetSession());
  }

  Future<void> perform({
    required Future<bool> Function(ThreadInteractionContext, bool Function())
    invoke,
    bool refreshComments = true,
    int? page,
    int? Function()? refreshPage,
  }) async {
    if (_disposed || isBusy || isLoading) return;
    final generation = session.generation;
    bool current() => !_disposed && session.isCurrent(generation);
    isBusy = true;
    notifyListeners();
    try {
      if (context == null) await load(force: true);
      if (!current() || context == null) return;
      final applied = await invoke(context!, current);
      if (!applied) return;
      try {
        await _invalidateThread(sourceTid);
      } catch (_) {
        /* Retain the confirmed write. */
      }
      if (!current()) return;
      await session.refreshAfterMutation(
        page: refreshPage != null
            ? refreshPage()
            : page ?? (refreshComments ? null : 1),
      );
    } finally {
      if (!_disposed) {
        isBusy = false;
        notifyListeners();
      }
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_changed);
    super.dispose();
  }
}

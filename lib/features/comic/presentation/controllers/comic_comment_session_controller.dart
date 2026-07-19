import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';

@immutable
class ComicCommentSessionKey {
  const ComicCommentSessionKey({
    required this.episodeId,
    required this.sourceTid,
  });

  final String episodeId;
  final String sourceTid;

  String get id => '$episodeId:$sourceTid';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ComicCommentSessionKey &&
            other.episodeId == episodeId &&
            other.sourceTid == sourceTid;
  }

  @override
  int get hashCode => Object.hash(episodeId, sourceTid);
}

@immutable
class ComicCommentSessionState {
  const ComicCommentSessionState({
    required this.key,
    required this.isLoading,
    this.result,
  });

  const ComicCommentSessionState.initial(ComicCommentSessionKey key)
    : this(key: key, isLoading: false);

  final ComicCommentSessionKey key;
  final bool isLoading;
  final ComicCommentLoadResult? result;

  bool get hasAttempted => isLoading || result != null;
}

/// Owns one reader-scoped comment request and its stale-result boundary.
///
/// The controller deliberately knows nothing about widgets or reader layout.
/// A new episode/source key gets a new controller instance, while repeated
/// tail visits reuse the same completed result without another request.
class ComicCommentSessionController extends ChangeNotifier {
  ComicCommentSessionController({
    required ComicCommentSessionKey key,
    required ComicCommentLoader loader,
  }) : _key = key,
       _loader = loader,
       _state = ComicCommentSessionState.initial(key);

  final ComicCommentSessionKey _key;
  final ComicCommentLoader _loader;

  ComicCommentSessionState _state;
  ComicCommentCancellationToken? _activeToken;
  int _generation = 0;
  bool _disposed = false;

  ComicCommentSessionKey get key => _key;
  ComicCommentSessionState get state => _state;

  Future<void> load() => _run(force: false);

  Future<void> retry() => _run(force: true);

  Future<void> _run({required bool force}) async {
    if (_disposed || _state.isLoading) {
      return;
    }
    if (!force && _state.result != null) {
      return;
    }

    final generation = ++_generation;
    _activeToken?.cancel();
    final token = ComicCommentCancellationToken();
    _activeToken = token;
    _state = ComicCommentSessionState(
      key: _key,
      isLoading: true,
      result: _state.result,
    );
    notifyListeners();

    ComicCommentLoadResult result;
    try {
      result = await _loader.loadAll(
        sourceTid: _key.sourceTid,
        cancellationToken: token,
      );
    } catch (_) {
      result = ComicCommentLoadResult(
        sourceTid: _key.sourceTid,
        status: ComicCommentLoadStatus.failure,
        items: const <ComicCommentItem>[],
        loadedPages: const <int>{},
        expectedPages: 0,
        errorCode: ComicCommentLoadErrorCode.firstPageUnavailable,
        errorMessage: '回帖加载失败',
      );
    }

    if (!_isCurrent(generation, token)) {
      return;
    }
    _activeToken = null;
    _state = ComicCommentSessionState(
      key: _key,
      isLoading: false,
      result: result,
    );
    notifyListeners();
  }

  bool _isCurrent(int generation, ComicCommentCancellationToken token) {
    return !_disposed &&
        generation == _generation &&
        identical(_activeToken, token);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation += 1;
    _activeToken?.cancel();
    _activeToken = null;
    super.dispose();
  }
}

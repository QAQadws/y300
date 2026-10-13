import 'package:flutter/foundation.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'forum_html_preparation_executor.dart';

/// A mounted consumer owns its document and rejects retired asynchronous work.
final class ForumHtmlPreparationController extends ChangeNotifier {
  ForumHtmlPreparationController({ForumHtmlPreparationExecutor? executor})
    : _executor = executor ?? ForumHtmlPreparationExecutor.shared;

  final ForumHtmlPreparationExecutor _executor;
  Object? _identity;
  ForumHtmlPreparationRequest? _request;
  ForumHtmlPreparedRenderDocument? _document;
  ForumHtmlPreparationLease? _lease;
  Object? _error;
  StackTrace? _stack;
  int _generation = 0;
  bool _waitingForCapacity = false;
  bool _closed = false;

  Object? get identity => _identity;
  bool get hasError => _error != null;

  ForumHtmlPreparedRenderDocument? resolve(
    ForumHtmlPreparationRequest request,
  ) {
    if (_closed) throw StateError('Preparation controller is closed');
    if (_identity != request.identity) {
      reset();
      _identity = request.identity;
      if (!_executor.usesBackground(request)) {
        // Synchronous failures keep the original retry-on-rebuild behavior.
        return _document = request.prepareSynchronously();
      }
      _request = request;
      _acquire();
    }
    if (_error != null) Error.throwWithStackTrace(_error!, _stack!);
    if (_document == null && _request == null) {
      return _document = request.prepareSynchronously();
    }
    return _document;
  }

  void _acquire() {
    final request = _request;
    if (_closed || request == null || _lease != null) return;
    final lease = _executor.tryAcquire(request);
    if (lease == null) {
      if (!_waitingForCapacity) {
        _waitingForCapacity = true;
        _executor.addListener(_acquire);
      }
      return;
    }
    _stopWaiting();
    _lease = lease;
    final generation = _generation;
    lease.future.then(
      (document) {
        lease.release();
        if (_closed || _generation != generation || _lease != lease) return;
        _lease = null;
        _request = null;
        if (document == null) {
          _error = StateError('Preparation request was retired');
          _stack = StackTrace.current;
        } else {
          _document = document;
        }
        notifyListeners();
      },
      onError: (Object error, StackTrace stack) {
        lease.release();
        if (_closed || _generation != generation || _lease != lease) return;
        _lease = null;
        _request = null;
        _error = error;
        _stack = stack;
        notifyListeners();
      },
    );
  }

  void _stopWaiting() {
    if (!_waitingForCapacity) return;
    _waitingForCapacity = false;
    _executor.removeListener(_acquire);
  }

  void reset() {
    _generation++;
    _stopWaiting();
    _lease?.release();
    _lease = null;
    _identity = null;
    _request = null;
    _document = null;
    _error = null;
    _stack = null;
  }

  @override
  void dispose() {
    reset();
    _closed = true;
    super.dispose();
  }
}

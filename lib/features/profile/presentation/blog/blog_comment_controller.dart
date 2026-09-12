import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

enum BlogCommentPhase {
  idle,
  preparing,
  ready,
  submitting,
  failed,
  unknown,
  applied,
  expired,
}

@immutable
final class BlogCommentState {
  const BlogCommentState({
    this.phase = BlogCommentPhase.idle,
    this.message = '',
    this.initialMessage = '',
    this.failure,
  });
  final BlogCommentPhase phase;
  final String message;
  final String initialMessage;
  final Object? failure;
  bool get busy =>
      phase == BlogCommentPhase.preparing ||
      phase == BlogCommentPhase.submitting;
  bool get dirty => message != initialMessage;
}

/// Transient comment form and input. Nothing is written to drafts or caches.
/// A failed POST requires fresh preparation; an unknown POST cannot be resent.
final class BlogCommentController extends ValueNotifier<BlogCommentState> {
  BlogCommentController({
    required this.target,
    required UserBlogCommentService service,
    required String? Function() currentActor,
  }) : _service = service,
       _currentActor = currentActor,
       super(const BlogCommentState());

  final UserBlogCommentTarget target;
  final UserBlogCommentService _service;
  final String? Function() _currentActor;
  UserBlogCommentPreparation? _preparation;
  ForumRequestCancellation? _cancellation;
  bool _seededInput = false;
  bool _inputEdited = false;
  bool _disposed = false;
  int _generation = 0;

  bool get _actorMatches => _currentActor() == target.actorUserId;

  void updateMessage(String message) {
    if (_disposed ||
        value.busy ||
        value.phase == BlogCommentPhase.expired ||
        value.phase == BlogCommentPhase.applied) {
      return;
    }
    _inputEdited = true;
    value = BlogCommentState(
      phase: value.phase,
      message: message,
      initialMessage: value.initialMessage,
      failure: value.failure,
    );
  }

  Future<void> prepare() async {
    if (_disposed ||
        value.busy ||
        {
          BlogCommentPhase.unknown,
          BlogCommentPhase.applied,
          BlogCommentPhase.expired,
        }.contains(value.phase)) {
      return;
    }
    if (!_actorMatches) {
      expire();
      return;
    }
    final generation = ++_generation;
    final cancellation = ForumRequestCancellation();
    _cancellation = cancellation;
    _preparation = null;
    _setPhase(BlogCommentPhase.preparing);
    try {
      final result = await _service.prepare(target, cancellation: cancellation);
      if (!_accept(generation, cancellation)) return;
      final ready = result.dataOrNull;
      if (ready == null ||
          ready.target != target ||
          result
              is! DataReadSuccess<
                UserBlogCommentPreparation,
                DataCapabilitySet<UserBlogCommentAction>
              > ||
          !result.capabilities.supports(target.action)) {
        _setPhase(
          BlogCommentPhase.failed,
          result.failureOrNull ?? _invalidPreparation,
        );
        return;
      }
      _preparation = ready;
      final message = _seededInput || _inputEdited
          ? value.message
          : ready.initialMessage;
      final initial = _seededInput
          ? value.initialMessage
          : ready.initialMessage;
      _seededInput = true;
      value = BlogCommentState(
        phase: BlogCommentPhase.ready,
        message: message,
        initialMessage: initial,
      );
    } catch (_) {
      if (_accept(generation, cancellation)) {
        _setPhase(BlogCommentPhase.failed, _readFailed);
      }
    }
  }

  Future<UserBlogCommentReceipt?> submit() async {
    if (_disposed ||
        value.phase != BlogCommentPhase.ready ||
        _preparation == null) {
      return null;
    }
    if (!_actorMatches) {
      expire();
      return null;
    }
    if (target.action != UserBlogCommentAction.delete &&
        value.message.trim().isEmpty) {
      _setPhase(BlogCommentPhase.ready, _emptyInput);
      return null;
    }
    final ready = _preparation!;
    final generation = ++_generation;
    final cancellation = ForumRequestCancellation();
    _cancellation = cancellation;
    _preparation = null;
    _setPhase(BlogCommentPhase.submitting);
    try {
      final result = await _service.execute(
        UserBlogCommentSubmission(
          preparation: ready,
          actorUserId: target.actorUserId,
          message: target.action == UserBlogCommentAction.delete
              ? ''
              : value.message,
          cancellation: cancellation,
        ),
      );
      if (!_accept(generation, cancellation)) return null;
      if (result case DataCommandApplied(:final receipt)) {
        if (receipt.target != target ||
            !RegExp(r'^[1-9]\d*$').hasMatch(receipt.commentId) ||
            ((target.action == UserBlogCommentAction.edit ||
                    target.action == UserBlogCommentAction.delete) &&
                receipt.commentId != target.commentId)) {
          _setPhase(BlogCommentPhase.unknown, _unprovedReceipt);
          return null;
        }
        _setPhase(BlogCommentPhase.applied);
        return receipt;
      }
      _setPhase(
        result is DataCommandOutcomeUnknown
            ? BlogCommentPhase.unknown
            : BlogCommentPhase.failed,
        result.failureOrNull,
      );
    } catch (_) {
      if (_accept(generation, cancellation)) {
        _setPhase(BlogCommentPhase.unknown, _unprovedReceipt);
      }
    }
    return null;
  }

  void expire() {
    if (_disposed || value.phase == BlogCommentPhase.expired) return;
    ++_generation;
    _cancellation?.cancel();
    _preparation = null;
    value = const BlogCommentState(phase: BlogCommentPhase.expired);
  }

  bool _accept(int generation, ForumRequestCancellation cancellation) {
    if (_disposed || generation != _generation || cancellation.isCancelled) {
      return false;
    }
    if (!_actorMatches) {
      expire();
      return false;
    }
    return true;
  }

  void _setPhase(BlogCommentPhase phase, [Object? failure]) {
    value = BlogCommentState(
      phase: phase,
      message: value.message,
      initialMessage: value.initialMessage,
      failure: failure,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancellation?.cancel();
    _preparation = null;
    super.dispose();
  }
}

const _emptyInput = DataCommandFailure(
  kind: DataCommandFailureKind.validation,
  retryPolicy: DataCommandRetryPolicy.afterInputChange,
  code: 'blog_comment_input_required',
  diagnosticMessage: 'blog_comment_input_required',
);
const _invalidPreparation = DataReadFailure<Object?, Object?>(
  kind: DataReadFailureKind.parse,
  code: 'blog_comment_preparation_mismatch',
  diagnosticMessage: 'blog_comment_preparation_mismatch',
);
const _readFailed = DataReadFailure<Object?, Object?>(
  kind: DataReadFailureKind.network,
  code: 'blog_comment_prepare_failed',
  diagnosticMessage: 'blog_comment_prepare_failed',
);
const _unprovedReceipt = DataCommandFailure(
  kind: DataCommandFailureKind.parse,
  retryPolicy: DataCommandRetryPolicy.never,
  code: 'blog_comment_receipt_unknown',
  diagnosticMessage: 'blog_comment_receipt_unknown',
);

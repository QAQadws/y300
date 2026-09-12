import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

enum BlogActionPhase {
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
final class BlogActionState {
  const BlogActionState(this.phase, [this.failure]);
  final BlogActionPhase phase;
  final Object? failure;
  bool get busy =>
      phase == BlogActionPhase.preparing || phase == BlogActionPhase.submitting;
}

/// A confirmation owns one transient ticket. Merely opening it cannot write.
final class BlogActionController extends ValueNotifier<BlogActionState> {
  BlogActionController({
    required this.target,
    required UserBlogOperations service,
    required String? Function() currentActor,
  }) : _service = service,
       _currentActor = currentActor,
       super(const BlogActionState(BlogActionPhase.idle));

  final UserBlogTarget target;
  final UserBlogOperations _service;
  final String? Function() _currentActor;
  UserBlogActionPreparation? _preparation;
  ForumRequestCancellation? _cancellation;
  bool _disposed = false;
  int _generation = 0;

  Future<void> prepare() async {
    if (_disposed ||
        !{BlogActionPhase.idle, BlogActionPhase.failed}.contains(value.phase)) {
      return;
    }
    if (_currentActor() != target.actorUserId) {
      expire();
      return;
    }
    if (!{
      UserBlogAction.delete,
      UserBlogAction.pin,
      UserBlogAction.unpin,
    }.contains(target.action)) {
      value = const BlogActionState(
        BlogActionPhase.failed,
        _invalidPreparation,
      );
      return;
    }
    final generation = ++_generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    _preparation = null;
    value = const BlogActionState(BlogActionPhase.preparing);
    try {
      final result = await _service.prepareAction(
        target,
        cancellation: cancellation,
      );
      if (!_accept(generation, cancellation)) return;
      if (result case DataReadSuccess(
        :final data,
        :final capabilities,
      ) when data.target == target && capabilities.supports(target.action)) {
        _preparation = data;
        value = const BlogActionState(BlogActionPhase.ready);
      } else {
        value = BlogActionState(
          BlogActionPhase.failed,
          result.failureOrNull ?? _invalidPreparation,
        );
      }
    } catch (_) {
      if (_accept(generation, cancellation)) {
        value = const BlogActionState(BlogActionPhase.failed, _readFailed);
      }
    }
  }

  Future<UserBlogReceipt?> submit() async {
    if (_disposed ||
        value.phase != BlogActionPhase.ready ||
        _preparation == null) {
      return null;
    }
    if (_currentActor() != target.actorUserId) {
      expire();
      return null;
    }
    final prepared = _preparation!;
    _preparation = null;
    final generation = ++_generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    value = const BlogActionState(BlogActionPhase.submitting);
    try {
      final result = await _service.executeAction(
        prepared,
        actorUserId: target.actorUserId,
        cancellation: cancellation,
      );
      if (!_accept(generation, cancellation)) return null;
      if (result case DataCommandApplied(:final receipt)) {
        if (receipt.target != target ||
            receipt.blogId != target.blogId ||
            !RegExp(r'^[1-9]\d*$').hasMatch(receipt.blogId)) {
          value = const BlogActionState(
            BlogActionPhase.unknown,
            _unknownReceipt,
          );
          return null;
        }
        value = const BlogActionState(BlogActionPhase.applied);
        return receipt;
      }
      value = BlogActionState(
        result is DataCommandOutcomeUnknown
            ? BlogActionPhase.unknown
            : BlogActionPhase.failed,
        result.failureOrNull,
      );
    } catch (_) {
      if (_accept(generation, cancellation)) {
        value = const BlogActionState(BlogActionPhase.unknown, _unknownReceipt);
      }
    }
    return null;
  }

  void expire() {
    if (_disposed || value.phase == BlogActionPhase.expired) return;
    ++_generation;
    _cancellation?.cancel();
    _preparation = null;
    value = const BlogActionState(BlogActionPhase.expired);
  }

  bool _accept(int generation, ForumRequestCancellation cancellation) {
    if (_disposed || generation != _generation || cancellation.isCancelled) {
      return false;
    }
    if (_currentActor() != target.actorUserId) {
      expire();
      return false;
    }
    return true;
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

const _invalidPreparation = DataReadFailure<Object?, Object?>(
  kind: DataReadFailureKind.parse,
  code: 'blog_action_preparation_mismatch',
  diagnosticMessage: 'blog_action_preparation_mismatch',
);
const _readFailed = DataReadFailure<Object?, Object?>(
  kind: DataReadFailureKind.network,
  code: 'blog_action_prepare_failed',
  diagnosticMessage: 'blog_action_prepare_failed',
);
const _unknownReceipt = DataCommandFailure(
  kind: DataCommandFailureKind.parse,
  retryPolicy: DataCommandRetryPolicy.never,
  code: 'blog_action_receipt_unknown',
  diagnosticMessage: 'blog_action_receipt_unknown',
);

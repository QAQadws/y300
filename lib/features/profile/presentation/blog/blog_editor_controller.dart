import 'package:flutter/foundation.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// One transient publishing/editing session, with no persisted draft or ticket.
final class BlogEditorController extends ValueNotifier<BlogEditorState> {
  BlogEditorController({
    required this.target,
    required UserBlogOperations service,
    required String? Function() currentActor,
  }) : _service = service,
       _currentActor = currentActor,
       super(const BlogEditorState());

  final UserBlogTarget target;
  final UserBlogOperations _service;
  final String? Function() _currentActor;
  UserBlogEditorPreparation? _preparation;
  BlogEditorDraft? _lastServerVersion;
  ForumRequestCancellation? _cancellation;
  int _generation = 0;
  bool _disposed = false;

  Future<void> prepare() async {
    if (_disposed ||
        !{BlogEditorPhase.idle, BlogEditorPhase.failed}.contains(value.phase)) {
      return;
    }
    if (!_checkActor()) return;
    if (!{UserBlogAction.create, UserBlogAction.edit}.contains(target.action)) {
      _setPhase(BlogEditorPhase.failed, failure: _invalidPreparation);
      return;
    }
    final generation = ++_generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    _preparation = null;
    _setPhase(BlogEditorPhase.preparing);
    try {
      final result = await _service.prepareEditor(
        target,
        cancellation: cancellation,
      );
      if (!_accept(generation, cancellation)) return;
      if (result case DataReadSuccess(
        :final data,
        :final capabilities,
      ) when data.target == target && capabilities.supports(target.action)) {
        final server = BlogEditorDraft.from(data);
        final first = _lastServerVersion == null;
        final changed = !first && server != _lastServerVersion;
        _lastServerVersion = server;
        _preparation = data;
        value = BlogEditorState(
          phase: BlogEditorPhase.ready,
          draft: first ? server : value.draft,
          original: first ? server : value.original,
          serverVersion: server,
          options: BlogEditorOptions.from(data),
          needsReview: value.needsReview || changed,
        );
      } else {
        _setPhase(
          BlogEditorPhase.failed,
          failure: result.failureOrNull ?? _invalidPreparation,
        );
      }
    } catch (_) {
      if (_accept(generation, cancellation)) {
        _setPhase(BlogEditorPhase.failed, failure: _readFailed);
      }
    }
  }

  void update(BlogEditorDraft draft) {
    if (_disposed ||
        value.options == null ||
        !{
          BlogEditorPhase.ready,
          BlogEditorPhase.failed,
        }.contains(value.phase)) {
      return;
    }
    if (!_checkActor()) return;
    value = BlogEditorState(
      phase: value.phase,
      draft: draft,
      original: value.original,
      serverVersion: value.serverVersion,
      options: value.options,
      needsReview: value.needsReview,
    );
  }

  /// A retried form can describe edits made elsewhere. The user must review it
  /// before overwriting, or explicitly replace their draft with the new version.
  void reviewServerVersion({required bool keepLocal}) {
    if (_disposed ||
        value.phase != BlogEditorPhase.ready ||
        !value.needsReview) {
      return;
    }
    if (!_checkActor()) return;
    value = BlogEditorState(
      phase: value.phase,
      draft: keepLocal ? value.draft : value.serverVersion!,
      original: value.serverVersion!,
      serverVersion: value.serverVersion,
      options: value.options,
    );
  }

  Future<UserBlogReceipt?> submit() async {
    if (_disposed ||
        value.phase != BlogEditorPhase.ready ||
        _preparation == null) {
      return null;
    }
    if (!_checkActor()) return null;
    final issue = value.needsReview
        ? BlogEditorIssue.serverChanged
        : value.options!.validate(value.draft);
    if (issue != null) {
      _setPhase(BlogEditorPhase.ready, issue: issue);
      return null;
    }
    final prepared = _preparation!;
    final input = value.draft;
    _preparation = null;
    final generation = ++_generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    _setPhase(BlogEditorPhase.submitting);
    try {
      final result = await _service.save(
        UserBlogEditorSubmission(
          preparation: prepared,
          actorUserId: target.actorUserId,
          subject: input.subject,
          bodyHtml: input.bodyHtml,
          tags: input.tags,
          siteCategoryId: input.siteCategoryId,
          personalCategoryId: input.personalCategoryId,
          newPersonalCategory: input.newPersonalCategory.trim().isEmpty
              ? null
              : input.newPersonalCategory,
          publishFeed: input.publishFeed,
          cancellation: cancellation,
        ),
      );
      if (!_accept(generation, cancellation)) return null;
      if (result case DataCommandApplied(:final receipt)) {
        if (receipt.target != target ||
            !RegExp(r'^[1-9]\d*$').hasMatch(receipt.blogId) ||
            (target.action == UserBlogAction.edit &&
                receipt.blogId != target.blogId)) {
          _setPhase(BlogEditorPhase.unknown, failure: _unknownReceipt);
          return null;
        }
        _setPhase(BlogEditorPhase.applied);
        return receipt;
      }
      _setPhase(
        result is DataCommandOutcomeUnknown
            ? BlogEditorPhase.unknown
            : BlogEditorPhase.failed,
        failure: result.failureOrNull,
      );
    } catch (_) {
      if (_accept(generation, cancellation)) {
        _setPhase(BlogEditorPhase.unknown, failure: _unknownReceipt);
      }
    }
    return null;
  }

  bool _checkActor() {
    if (_currentActor() == target.actorUserId) return true;
    expire();
    return false;
  }

  bool _accept(int generation, ForumRequestCancellation cancellation) =>
      !_disposed &&
      generation == _generation &&
      !cancellation.isCancelled &&
      _checkActor();

  void _setPhase(
    BlogEditorPhase phase, {
    Object? failure,
    BlogEditorIssue? issue,
  }) {
    value = BlogEditorState(
      phase: phase,
      draft: value.draft,
      original: value.original,
      serverVersion: value.serverVersion,
      options: value.options,
      needsReview: value.needsReview,
      failure: failure,
      issue: issue,
    );
  }

  void expire() {
    if (_disposed || value.phase == BlogEditorPhase.expired) return;
    ++_generation;
    _cancellation?.cancel();
    _preparation = null;
    _lastServerVersion = null;
    value = const BlogEditorState(phase: BlogEditorPhase.expired);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancellation?.cancel();
    _preparation = null;
    _lastServerVersion = null;
    super.dispose();
  }
}

const _invalidPreparation = DataReadFailure<Object?, Object?>(
  kind: DataReadFailureKind.parse,
  code: 'blog_editor_preparation_mismatch',
  diagnosticMessage: 'blog_editor_preparation_mismatch',
);
const _readFailed = DataReadFailure<Object?, Object?>(
  kind: DataReadFailureKind.network,
  code: 'blog_editor_prepare_failed',
  diagnosticMessage: 'blog_editor_prepare_failed',
);
const _unknownReceipt = DataCommandFailure(
  kind: DataCommandFailureKind.parse,
  retryPolicy: DataCommandRetryPolicy.never,
  code: 'blog_editor_receipt_unknown',
  diagnosticMessage: 'blog_editor_receipt_unknown',
);

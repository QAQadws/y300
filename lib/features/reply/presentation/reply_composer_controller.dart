import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/services/composer_submission_error_presenter.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_controller_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';
import 'package:y300/features/reply/data/providers/reply_providers.dart';
import 'package:y300/features/reply/data/repositories/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';

final replyComposerControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ReplyComposerController, ReplyComposerState, ReplyComposerArgs>(
      (args) => ReplyComposerController(args),
    );

/// 回复编辑器控制器。Phase 2：通用流程下沉到 [ComposerControllerBase]，
/// 这里只保留楼层引用准备 + reply 专属的 submit 调用。
class ReplyComposerController
    extends ComposerControllerBase<ReplyComposerState> {
  ReplyComposerController(this._args);

  final ReplyComposerArgs _args;
  ReplyRepository? _replyRepository;
  ComposerSubmissionErrorPresenter? _errorPresenter;

  @override
  ComposerDraftIdentity get draftIdentity => _args.identity;

  @override
  String get uploadFid => _args.target.fid;

  @override
  FutureOr<ReplyComposerState> build() async {
    _replyRepository = ref.read(replyRepositoryProvider);
    _errorPresenter = ref.read(composerSubmissionErrorPresenterProvider);
    return super.build();
  }

  @override
  Future<ReplyComposerState> buildInitialState({
    required ComposerDraftSnapshot? restoredDraft,
    required ComposerPreferences preferences,
  }) async {
    return ReplyComposerState.initial(
      target: _args.target,
      message: restoredDraft?.message ?? '',
      useSignature:
          restoredDraft?.useSignature ?? preferences.newDraftUseSignature,
      isPreparing: _shouldPreparePostReply,
      restoredDraft: restoredDraft != null,
      imageAttachments:
          restoredDraft?.imageAttachments ?? const <ComposerImageAttachment>[],
    );
  }

  @override
  void onAfterBuild(ReplyComposerState initial) {
    if (_shouldPreparePostReply) {
      // 沿用回复页原有时序：用 microtask 把楼层引用准备推迟到 build 完成之后，
      // 但仍然在调用方的下一个 await 间隙之前执行。
      unawaited(Future<void>.microtask(_preparePostReply));
    }
  }

  /// 必须转发 `ComposerStatePatch` 的每一个字段：漏掉任何一个都会让基类的
  /// 通用流程静默失效（例如漏掉 messageRevision 会把光标插入退化成尾部追加）。
  @override
  ReplyComposerState applyPatch(
    ReplyComposerState current,
    ComposerStatePatch patch,
  ) {
    return current.copyWith(
      message: patch.message,
      useSignature: patch.useSignature,
      isSubmitting: patch.isSubmitting,
      restoredDraft: patch.restoredDraft,
      imageAttachments: patch.imageAttachments,
      isUploadingImages: patch.isUploadingImages,
      imageUploadCurrent: patch.imageUploadCurrent,
      imageUploadTotal: patch.imageUploadTotal,
      messageRevision: patch.messageRevision,
      lastMessageMutation: patch.lastMessageMutation,
      pendingAttachmentAids: patch.pendingAttachmentAids,
      pendingAttachmentMessage: patch.pendingAttachmentMessage,
      errorMessage: patch.errorMessage,
      imageUploadError: patch.imageUploadError,
      clearErrorMessage: patch.clearErrorMessage,
      clearImageUploadError: patch.clearImageUploadError,
      clearLastMessageMutation: patch.clearLastMessageMutation,
      clearPendingAttachmentMessage: patch.clearPendingAttachmentMessage,
    );
  }

  @override
  bool canPickImages(ReplyComposerState state) {
    return state.canPickImages;
  }

  @override
  String? preflightValidate(ReplyComposerState state) {
    if (state.message.trim().isEmpty) {
      return '请输入回复内容';
    }
    final missingPostReference =
        state.target.isPostReply &&
        (state.isPreparing || state.preparation == null);
    if (missingPostReference) {
      return '楼层回复引用准备失败，请重试';
    }
    return null;
  }

  @override
  Future<ComposerSubmissionOutcome> performSubmit({
    required ReplyComposerState state,
    required List<String> uploadedAids,
  }) async {
    final reference = state.preparation?.reference;
    final result = await _replyRepository!.sendReply(
      draft: ReplyDraft(
        fid: state.target.fid,
        tid: state.target.tid,
        message: state.message.trim(),
        useSignature: state.useSignature,
        formHash: reference?.formHash,
        repPid: reference?.repPid,
        repPost: reference?.repPost,
        noticeAuthor: reference?.noticeAuthor,
        noticeTrimStr: reference?.noticeTrimStr,
        noticeAuthorMsg: reference?.noticeAuthorMsg,
        uploadedAttachmentAids: uploadedAids,
      ),
    );
    if (result case ApiSuccess<ReplySubmissionResult>(:final data)) {
      return ComposerSubmissionOutcome.success(
        message: data.message.isEmpty ? '回复成功' : data.message,
      );
    }
    final error = (result as ApiFailure<ReplySubmissionResult>).error;
    final errorMessage = _errorPresenter?.present(error) ?? error.message;
    return ComposerSubmissionOutcome.failure(errorMessage: errorMessage);
  }

  /// 楼层引用准备：reply 专属流程，发帖页不会用到。
  Future<void> retryPreparePostReply() {
    return _preparePostReply();
  }

  bool get _shouldPreparePostReply {
    return _args.target.isPostReply && _args.replyFormUri != null;
  }

  Future<void> _preparePostReply() async {
    final replyFormUri = _args.replyFormUri;
    if (replyFormUri == null || !_args.target.isPostReply) {
      return;
    }
    final current = state.value ?? latestState;
    if (current != null) {
      _setReplyState(
        current.copyWith(
          isPreparing: true,
          clearPreparation: true,
          clearPreparationError: true,
          clearErrorMessage: true,
        ),
      );
    }

    final result = await _replyRepository!.preparePostReply(
      replyFormUri: replyFormUri,
    );
    final latest = state.value ?? latestState;
    if (latest == null) {
      return;
    }
    if (result case ApiSuccess<ReplyPreparation>(:final data)) {
      _setReplyState(
        latest.copyWith(
          isPreparing: false,
          preparation: data,
          clearPreparationError: true,
        ),
      );
      return;
    }
    final error = (result as ApiFailure<ReplyPreparation>).error;
    _setReplyState(
      latest.copyWith(
        isPreparing: false,
        preparationError: error.message,
        errorMessage: error.message,
      ),
    );
  }

  /// reply 专属字段（preparation / preparationError）走自己的 setter，
  /// 不经过 [ComposerStatePatch]，避免污染基类抽象。
  void _setReplyState(ReplyComposerState value) {
    setStateValue(value);
  }

  /// 兼容旧调用点：基类 [submit] 返回 [ComposerSubmitInvocationResult]，
  /// reply 这里把它窄化为 [ReplyComposerResult]，旧页面/测试不需要改签名。
  @override
  Future<ReplyComposerResult> submit() async {
    final result = await super.submit();
    return ReplyComposerResult.fromInvocation(result);
  }

  /// 历史方法名，仍然可用，等同于 [submit]。
  Future<ReplyComposerResult> submitReply() => submit();
}

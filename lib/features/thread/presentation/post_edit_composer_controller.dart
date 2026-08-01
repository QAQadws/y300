import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_controller_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';
import 'package:y300/features/thread/data/providers/post_edit_providers.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_draft_extras_codec.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';

final postEditComposerControllerProvider = AsyncNotifierProvider.autoDispose
    .family<
      PostEditComposerController,
      PostEditComposerState,
      PostEditComposerArgs
    >(PostEditComposerController.new);

final class PostEditComposerController
    extends ComposerControllerBase<PostEditComposerState> {
  PostEditComposerController(this._args);

  final PostEditComposerArgs _args;
  final PostEditDraftExtrasCodec _extrasCodec =
      const PostEditDraftExtrasCodec();

  @override
  ComposerKind get composerKind => ComposerKind.postEdit;

  @override
  ComposerDraftIdentity get draftIdentity => ComposerDraftIdentity.postEdit(
    fid: _args.target.fid,
    tid: _args.target.tid,
    pid: _args.target.pid,
  );

  @override
  String get uploadFid => _args.target.fid;

  @override
  Future<PostEditComposerState> buildInitialState({
    required ComposerDraftSnapshot? restoredDraft,
    required ComposerPreferences preferences,
  }) async {
    final draftFingerprint = restoredDraft == null
        ? null
        : _extrasCodec.baselineFingerprint(restoredDraft.extras);
    final hasMatchingDraft =
        restoredDraft != null &&
        draftFingerprint == _args.snapshot.baselineFingerprint;
    final conflict = restoredDraft != null && !hasMatchingDraft
        ? PostEditDraftConflict(
            localDraft: restoredDraft,
            latestSnapshot: _args.snapshot,
          )
        : null;
    return PostEditComposerState.initial(
      target: _args.target,
      snapshot: _args.snapshot,
      message: hasMatchingDraft ? restoredDraft.message : null,
      useSignature: hasMatchingDraft
          ? restoredDraft.useSignature
          : preferences.newDraftUseSignature,
      restoredDraft: hasMatchingDraft,
      pendingConflict: conflict,
      imageAttachments: hasMatchingDraft
          ? restoredDraft.imageAttachments
          : const <ComposerImageAttachment>[],
    );
  }

  @override
  PostEditComposerState applyPatch(
    PostEditComposerState current,
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
      pendingAttachmentNotice: patch.pendingAttachmentNotice,
      failure: patch.failure,
      imageUploadFailure: patch.imageUploadFailure,
      clearFailure: patch.clearFailure,
      clearImageUploadFailure: patch.clearImageUploadFailure,
      clearLastMessageMutation: patch.clearLastMessageMutation,
      clearPendingAttachmentNotice: patch.clearPendingAttachmentNotice,
    );
  }

  @override
  ComposerDraftSnapshot? restoreDraft(ComposerDraftSnapshot? restoredDraft) {
    if (restoredDraft == null || restoredDraft.identity != draftIdentity) {
      return null;
    }
    return restoredDraft;
  }

  @override
  bool shouldPersistDraft(PostEditComposerState value) {
    return value.isDirtyAgainstBaseline;
  }

  @override
  Map<String, String> draftExtrasFor(PostEditComposerState value) {
    return _extrasCodec.encode(baselineFingerprint: value.baselineFingerprint);
  }

  @override
  ComposerDraftSnapshot draftSnapshotFor(PostEditComposerState value) {
    final conflict = value.pendingConflict;
    if (conflict != null) {
      return conflict.localDraft;
    }
    return super.draftSnapshotFor(value);
  }

  @override
  PostEditComposerState resetToBaseline(PostEditComposerState value) {
    return value.copyWith(
      message: value.snapshot.rawMessage,
      messageRevision: value.messageRevision + 1,
      restoredDraft: false,
      imageAttachments: const [],
      pendingAttachmentAids: const [],
      clearPendingAttachmentNotice: true,
      clearPendingConflict: true,
      clearFailure: true,
      clearImageUploadFailure: true,
      clearLastMessageMutation: true,
    );
  }

  @override
  ComposerValidationFailure? preflightValidate(PostEditComposerState state) {
    if (state.message.trim().isEmpty) {
      return const ComposerValidationFailure(
        code: ComposerValidationFailureCode.contentRequired,
      );
    }
    return null;
  }

  @override
  Future<ComposerSubmissionOutcome> performSubmit({
    required PostEditComposerState state,
    required List<String> uploadedAids,
  }) async {
    return const ComposerSubmissionOutcome.failure(
      failure: ComposerSubmissionFailure(
        code: ComposerSubmissionFailureCode.unknown,
        kind: ComposerKind.postEdit,
        detail: 'native submit is disabled until post edit phase five',
      ),
    );
  }

  Future<void> reconcileWebViewReturn() async {
    final current = state.value ?? latestState;
    if (current == null) {
      return;
    }
    setStateValue(
      current.copyWith(
        webReturnVerificationState:
            PostEditWebReturnVerificationState.verifying,
      ),
    );
    final result = await ref
        .read(postEditRepositoryProvider)
        .loadForm(current.target);
    final latest = state.value ?? latestState;
    if (latest == null) {
      return;
    }
    if (result case ApiFailure<PostEditPreparation>()) {
      setStateValue(
        latest.copyWith(
          webReturnVerificationState:
              PostEditWebReturnVerificationState.unconfirmed,
          serverMutationPossible: true,
        ),
      );
      return;
    }
    final preparation = (result as ApiSuccess<PostEditPreparation>).data;
    final latestSnapshot = preparation.snapshot;
    if (latestSnapshot == null || !preparation.isNativeSupported) {
      setStateValue(
        latest.copyWith(
          webReturnVerificationState:
              PostEditWebReturnVerificationState.unconfirmed,
          serverMutationPossible: true,
        ),
      );
      return;
    }
    if (latestSnapshot.baselineFingerprint == latest.baselineFingerprint) {
      setStateValue(
        latest.copyWith(
          webReturnVerificationState:
              PostEditWebReturnVerificationState.unchanged,
          serverMutationPossible: true,
        ),
      );
      return;
    }
    if (!latest.isDirtyAgainstBaseline) {
      setStateValue(
        latest.copyWith(
          snapshot: latestSnapshot,
          baselineMessage: latestSnapshot.rawMessage,
          baselineFingerprint: latestSnapshot.baselineFingerprint,
          message: latestSnapshot.rawMessage,
          restoredDraft: false,
          webReturnVerificationState:
              PostEditWebReturnVerificationState.changedClean,
          serverMutationPossible: true,
        ),
      );
      await discardDraft();
      return;
    }
    final localDraft = draftSnapshotFor(latest);
    setStateValue(
      latest.copyWith(
        snapshot: latestSnapshot,
        baselineMessage: latestSnapshot.rawMessage,
        baselineFingerprint: latestSnapshot.baselineFingerprint,
        pendingConflict: PostEditDraftConflict(
          localDraft: localDraft,
          latestSnapshot: latestSnapshot,
        ),
        webReturnVerificationState: PostEditWebReturnVerificationState.conflict,
        serverMutationPossible: true,
      ),
    );
  }

  Future<void> useServerVersion() async {
    final current = state.value ?? latestState;
    final conflict = current?.pendingConflict;
    if (current == null || conflict == null) {
      return;
    }
    setStateValue(
      current.copyWith(
        snapshot: conflict.latestSnapshot,
        baselineMessage: conflict.latestSnapshot.rawMessage,
        baselineFingerprint: conflict.latestSnapshot.baselineFingerprint,
        message: conflict.latestSnapshot.rawMessage,
        restoredDraft: false,
        webReturnVerificationState: PostEditWebReturnVerificationState.idle,
        clearPendingConflict: true,
      ),
    );
    await discardDraft();
  }

  Future<void> keepLocalVersion() async {
    final current = state.value ?? latestState;
    final conflict = current?.pendingConflict;
    if (current == null || conflict == null) {
      return;
    }
    setStateValue(
      current.copyWith(
        snapshot: conflict.latestSnapshot,
        baselineMessage: conflict.latestSnapshot.rawMessage,
        baselineFingerprint: conflict.latestSnapshot.baselineFingerprint,
        message: conflict.localDraft.message,
        useSignature: conflict.localDraft.useSignature,
        imageAttachments: conflict.localDraft.imageAttachments,
        restoredDraft: true,
        webReturnVerificationState: PostEditWebReturnVerificationState.idle,
        clearPendingConflict: true,
      ),
    );
    await flushDraft();
  }
}

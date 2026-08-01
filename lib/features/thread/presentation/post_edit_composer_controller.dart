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
import 'package:y300/features/thread/domain/services/post_edit_attachment_session_resolver.dart';
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
  void onAfterBuild(PostEditComposerState initial) {
    ref.onDispose(() {
      _attachmentOperationGeneration += 1;
    });
  }

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
    final deletedAidTombstones = hasMatchingDraft
        ? _extrasCodec.deletedAidTombstones(restoredDraft.extras)
        : const <String>{};
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
      deletedAidTombstones: deletedAidTombstones,
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
    return _extrasCodec.encode(
      baselineFingerprint: value.baselineFingerprint,
      deletedAidTombstones: value.attachmentSession.deletedAidTombstones,
    );
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
      attachmentSession: PostEditAttachmentSession.fromImages(
        value.snapshot.existingImages,
      ),
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
    final refreshedSession = latest.attachmentSession.copyWith(
      existingImagesByAid: {
        for (final image in latestSnapshot.existingImages) image.aid: image,
      },
      deletingAids: const <String>{},
    );
    if (!latest.isDirtyAgainstBaseline) {
      setStateValue(
        latest.copyWith(
          snapshot: latestSnapshot,
          baselineMessage: latestSnapshot.rawMessage,
          baselineFingerprint: latestSnapshot.baselineFingerprint,
          message: latestSnapshot.rawMessage,
          attachmentSession: refreshedSession,
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
        attachmentSession: refreshedSession,
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
        imageAttachments: const <ComposerImageAttachment>[],
        attachmentSession: PostEditAttachmentSession.fromImages(
          conflict.latestSnapshot.existingImages,
        ),
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
        attachmentSession: PostEditAttachmentSession.fromImages(
          conflict.latestSnapshot.existingImages,
          deletedAidTombstones: _extrasCodec.deletedAidTombstones(
            conflict.localDraft.extras,
          ),
        ),
        restoredDraft: true,
        webReturnVerificationState: PostEditWebReturnVerificationState.idle,
        clearPendingConflict: true,
      ),
    );
    await flushDraft();
  }

  PostEditAttachmentSessionResolver attachmentResolver(
    PostEditComposerState value,
  ) {
    return PostEditAttachmentSessionResolver(
      session: value.attachmentSession,
      localAttachments: value.imageAttachments,
      referer: value.snapshot.sourceUri.toString(),
    );
  }

  Future<void> deleteImage(String aid) async {
    final current = state.value ?? latestState;
    if (current == null || current.isSubmitting) {
      return;
    }
    final normalizedAid = aid.trim();
    if (normalizedAid.isEmpty ||
        current.attachmentSession.deletingAids.contains(normalizedAid) ||
        (!_hasLocalAid(current, normalizedAid) &&
            !current.attachmentSession.existingImagesByAid.containsKey(
              normalizedAid,
            ))) {
      return;
    }

    final operation = ++_attachmentOperationGeneration;
    setStateValue(
      current.copyWith(
        attachmentSession: current.attachmentSession.copyWith(
          deletingAids: {
            ...current.attachmentSession.deletingAids,
            normalizedAid,
          },
        ),
        clearLastAttachmentDeleteOutcome: true,
        attachmentVerificationUnconfirmed: false,
      ),
    );
    final result = await ref
        .read(postEditRepositoryProvider)
        .deleteImage(
          PostEditAttachmentDeleteCommand(
            target: current.target,
            aid: normalizedAid,
            formHash: current.snapshot.formHash,
            expectedBaselineFingerprint: current.baselineFingerprint,
          ),
        );
    if (operation != _attachmentOperationGeneration) {
      return;
    }
    final latest = state.value ?? latestState;
    if (latest == null) {
      return;
    }
    if (result case ApiFailure<PostEditAttachmentDeleteResult>()) {
      await _reconcileDelete(
        latest,
        normalizedAid,
        operation: operation,
        confirmedByResponse: false,
        responseOutcome: PostEditAttachmentDeleteOutcome.unconfirmed,
      );
      return;
    }
    final deleteResult =
        (result as ApiSuccess<PostEditAttachmentDeleteResult>).data;
    await _reconcileDelete(
      latest,
      normalizedAid,
      operation: operation,
      confirmedByResponse:
          deleteResult.outcome == PostEditAttachmentDeleteOutcome.deleted,
      responseOutcome: deleteResult.outcome,
    );
  }

  int _attachmentOperationGeneration = 0;

  bool _hasLocalAid(PostEditComposerState state, String aid) {
    return state.imageAttachments.any(
      (attachment) => attachment.aid?.trim() == aid,
    );
  }

  Future<void> _reconcileDelete(
    PostEditComposerState current,
    String aid, {
    required int operation,
    required bool confirmedByResponse,
    PostEditAttachmentDeleteOutcome? responseOutcome,
  }) async {
    final readback = await ref
        .read(postEditRepositoryProvider)
        .loadForm(current.target);
    if (operation != _attachmentOperationGeneration) {
      return;
    }
    final latest = state.value ?? latestState;
    if (latest == null) {
      return;
    }
    if (readback case ApiSuccess<PostEditPreparation>(
      :final data,
    ) when data.snapshot != null && data.isNativeSupported) {
      final snapshot = data.snapshot!;
      final aidStillExists = snapshot.existingImages.any(
        (image) => image.aid == aid,
      );
      if (aidStillExists && !confirmedByResponse) {
        setStateValue(
          latest.copyWith(
            attachmentSession: latest.attachmentSession.copyWith(
              deletingAids: latest.attachmentSession.deletingAids.difference(
                <String>{aid},
              ),
            ),
            lastAttachmentDeleteOutcome:
                responseOutcome ?? PostEditAttachmentDeleteOutcome.notDeleted,
            attachmentVerificationUnconfirmed:
                responseOutcome == PostEditAttachmentDeleteOutcome.unconfirmed,
            serverMutationPossible:
                latest.serverMutationPossible ||
                responseOutcome == PostEditAttachmentDeleteOutcome.unconfirmed,
          ),
        );
        return;
      }
      final tombstones = {
        ...latest.attachmentSession.deletedAidTombstones,
        if (!aidStillExists || confirmedByResponse) aid,
      };
      setStateValue(
        latest.copyWith(
          snapshot: snapshot,
          baselineMessage: snapshot.rawMessage,
          baselineFingerprint: snapshot.baselineFingerprint,
          attachmentSession: PostEditAttachmentSession.fromImages(
            snapshot.existingImages,
            deletingAids: const <String>{},
            deletedAidTombstones: tombstones,
          ),
          lastAttachmentDeleteOutcome: confirmedByResponse || !aidStillExists
              ? PostEditAttachmentDeleteOutcome.deleted
              : PostEditAttachmentDeleteOutcome.unconfirmed,
          attachmentVerificationUnconfirmed:
              confirmedByResponse && aidStillExists,
          serverMutationPossible: true,
        ),
      );
      await flushDraft();
      return;
    }

    final keepTombstone = confirmedByResponse;
    setStateValue(
      latest.copyWith(
        attachmentSession: latest.attachmentSession.copyWith(
          deletingAids: latest.attachmentSession.deletingAids.difference(
            <String>{aid},
          ),
          deletedAidTombstones: keepTombstone
              ? {...latest.attachmentSession.deletedAidTombstones, aid}
              : latest.attachmentSession.deletedAidTombstones,
        ),
        lastAttachmentDeleteOutcome: confirmedByResponse
            ? PostEditAttachmentDeleteOutcome.deleted
            : PostEditAttachmentDeleteOutcome.unconfirmed,
        attachmentVerificationUnconfirmed: true,
        serverMutationPossible: true,
      ),
    );
    await flushDraft();
  }
}

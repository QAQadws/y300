import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/services/composer_submission_failure_classifier.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_controller_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';
import 'package:y300/features/thread/data/providers/post_edit_providers.dart';
import 'package:y300/features/thread/application/post_edit_submission_coordinator.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_diagnostic_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submission_attempt.dart';
import 'package:y300/features/thread/domain/services/post_edit_attachment_session_resolver.dart';
import 'package:y300/features/thread/domain/services/post_edit_submission_mapper.dart';
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
  final PostEditSubmissionMapper _submissionMapper =
      const PostEditSubmissionMapper();
  final ComposerSubmissionFailureClassifier _failureClassifier =
      const ComposerSubmissionFailureClassifier();
  int _prepareGeneration = 0;
  int _webReconcileGeneration = 0;
  PostEditSubmissionCoordinator? _submissions;
  final Map<String, int> _deleteGenerationByAid = <String, int>{};
  ThreadReadAccessEvidence? lastReadAccessEvidence;

  @override
  bool get draftsEnabled => false;

  @override
  ComposerKind get composerKind => ComposerKind.postEdit;

  @override
  bool get sanitizeAttachmentsBeforeSubmit => false;

  @override
  bool shouldPersistDraft(PostEditComposerState value) => false;

  @override
  String get uploadFid => _args.target.fid;

  @override
  void onAfterBuild(PostEditComposerState initial) {
    _submissions?.close();
    final submissions = _submissions = PostEditSubmissionCoordinator(
      executeCommand: (request) =>
          ref.read(threadPostEditCommandProvider).execute(request),
      loadPreparation: (request) =>
          ref.read(threadPostEditPreparationRepositoryProvider).load(request),
      beginPreparation: () => ++_prepareGeneration,
      isPreparationCurrent: (request) =>
          request == _prepareGeneration && _ownsTarget(initial.target),
      onDiagnostic: (reason, operation) =>
          _recordDiagnostic(reason, operation: operation),
    );
    ref.onDispose(() {
      submissions.close();
      _prepareGeneration += 1;
      _webReconcileGeneration += 1;
      for (final aid in _deleteGenerationByAid.keys.toList()) {
        _deleteGenerationByAid[aid] = _nextGeneration(
          _deleteGenerationByAid[aid],
        );
      }
    });
  }

  int _nextGeneration(int? current) => (current ?? 0) + 1;

  @override
  Future<PostEditComposerState> buildInitialState({
    required ComposerDraftSnapshot? restoredDraft,
    required ComposerPreferences preferences,
  }) async {
    return PostEditComposerState.initial(
      target: _args.target,
      snapshot: _args.snapshot,
      subject: _args.snapshot.subject,
      message: _args.snapshot.message,
      useSignature: _args.snapshot.useSignature,
      nativeSupported: true,
    );
  }

  @override
  PostEditComposerState applyPatch(
    PostEditComposerState current,
    ComposerStatePatch patch,
  ) {
    final localMutation =
        patch.message != null ||
        patch.imageAttachments != null ||
        patch.useSignature != null;
    if (localMutation) {
      // A local edit invalidates a pending server read. A response based on
      // the previous message must never replace the current editor state.
      _webReconcileGeneration += 1;
      _submissions?.invalidate();
    }
    final uploaded =
        patch.imageAttachments?.any(
          (attachment) => attachment.canEnterSubmitPayload,
        ) ??
        false;
    final serverMutationPossible =
        current.serverMutationPossible ||
        uploaded ||
        (patch.pendingAttachmentAids?.isNotEmpty ?? false);
    return current.copyWith(
      message: patch.message,
      useSignature: patch.useSignature,
      isSubmitting: patch.isSubmitting,
      restoredDraft: false,
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
      draftAttachmentVerification: patch.draftAttachmentVerification,
      clearLastSubmitOutcome: patch.message != null,
      serverMutationPossible: serverMutationPossible,
      submitState: localMutation && _hasPendingSubmission(current)
          ? PostEditSubmitState.unconfirmed
          : null,
      submitBlocked: localMutation && _hasPendingSubmission(current)
          ? true
          : null,
    );
  }

  void updateSubject(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    _webReconcileGeneration += 1;
    _submissions?.invalidate();
    setStateValue(
      current.copyWith(
        subject: value,
        restoredDraft: false,
        clearFailure: true,
        clearLastSubmitOutcome: true,
        submitState: _hasPendingSubmission(current)
            ? PostEditSubmitState.unconfirmed
            : null,
        submitBlocked: _hasPendingSubmission(current) ? true : null,
      ),
    );
  }

  void updateMinimumReadAccess(int value) {
    final current = state.value;
    if (current == null ||
        current.isSubmitting ||
        current.submitState != PostEditSubmitState.idle ||
        current.webReturnVerificationState ==
            PostEditWebReturnVerificationState.verifying ||
        !current.target.isFirstPost ||
        !current.snapshot.readAccess.canModify ||
        (value != current.snapshot.readAccess.currentValue &&
            !current.snapshot.readAccess.allows(value))) {
      return;
    }
    _webReconcileGeneration += 1;
    setStateValue(
      current.copyWith(minimumReadAccess: value, clearFailure: true),
    );
  }

  /// Returns only warnings; the builder remains the single source of truth
  /// for whether an attachment can be sent. The page uses this to ask for an
  /// explicit confirmation without rewriting the user's BBCode.
  List<String> danglingAttachmentAids(PostEditComposerState value) {
    return _submissionMapper
        .map(
          message: value.message,
          localAttachments: value.imageAttachments,
          attachmentSession: value.attachmentSession,
          now: DateTime.now(),
        )
        .danglingAids;
  }

  @override
  PostEditComposerState resetToBaseline(PostEditComposerState value) {
    _submissions?.invalidate();
    return value.copyWith(
      message: value.snapshot.message,
      subject: value.snapshot.subject,
      resetReadAccess: true,
      useSignature: value.snapshot.useSignature,
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
      submitState: PostEditSubmitState.idle,
      clearLastSubmitOutcome: true,
      submitBlocked: false,
      confirmedOverwriteIntent: false,
      attachmentVerificationUnconfirmed: false,
    );
  }

  @override
  ComposerValidationFailure? preflightValidate(PostEditComposerState state) {
    if (!state.isReadAccessValid) {
      return const ComposerValidationFailure(
        code: ComposerValidationFailureCode.readAccessUnavailable,
      );
    }
    if (state.target.isFirstPost && state.subject.trim().isEmpty) {
      return const ComposerValidationFailure(
        code: ComposerValidationFailureCode.contentRequired,
      );
    }
    if (state.message.trim().isEmpty) {
      return const ComposerValidationFailure(
        code: ComposerValidationFailureCode.contentRequired,
      );
    }
    return null;
  }

  @override
  Future<ComposerSubmitInvocationResult> submit() async {
    final current = state.value;
    if (current == null || !current.canSubmit) {
      return ComposerSubmitInvocationResult.notSent(failure: current?.failure);
    }
    return super.submit();
  }

  @override
  Future<ComposerSubmissionOutcome> performSubmit({
    required PostEditComposerState state,
    required List<String> uploadedAids,
  }) async {
    lastReadAccessEvidence = null;
    final projection = _submissionMapper.map(
      message: state.message,
      localAttachments: state.imageAttachments,
      attachmentSession: state.attachmentSession,
      now: DateTime.now(),
    );
    final request = _submissions?.submit(
      PostEditSubmissionAttempt(
        preparation: state.snapshot,
        subject: state.subject,
        message: state.message,
        useSignature: state.useSignature,
        minimumReadAccess: state.minimumReadAccess,
        newImageAttachmentIds: projection.newAttachmentAids,
        removedImageAttachmentIds: state.attachmentSession.deletedAidTombstones
            .toList(growable: false),
      ),
    );
    if (request == null) {
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    setStateValue(
      state.copyWith(
        submitState: PostEditSubmitState.submitting,
        submitBlocked: false,
        clearFailure: true,
      ),
    );
    return _applySubmissionResolution(state, await request);
  }

  /// A user-requested proof read never repeats the uncertain command.
  Future<void> retrySubmitVerification() async {
    final current = state.value ?? latestState;
    final submissions = _submissions;
    if (current == null || submissions == null) return;
    if (current.submitState == PostEditSubmitState.verifying &&
        submissions.isRunning) {
      return;
    }
    final request = submissions.verifyUncertain();
    if (request == null) {
      if (!submissions.isRunning) await reconcileWebViewReturn();
      return;
    }
    setStateValue(current.copyWith(submitState: PostEditSubmitState.verifying));
    _applySubmissionResolution(current, await request);
  }

  ComposerSubmissionOutcome _applySubmissionResolution(
    PostEditComposerState current,
    PostEditSubmissionResolution result,
  ) {
    final operation = result.operation;
    if (result.kind == PostEditSubmissionResolutionKind.superseded ||
        !_isCurrentSubmission(operation)) {
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    final prepared = identical(current.snapshot, result.attempt.preparation)
        ? current
        : _replaceSnapshotKeepingLocal(current, result.attempt.preparation);
    return switch (result.kind) {
      PostEditSubmissionResolutionKind.applied => _acceptAppliedSubmission(
        prepared,
        result,
      ),
      PostEditSubmissionResolutionKind.rejected => _failFromCommandFailure(
        prepared,
        operation: operation,
        failure: result.failure!,
      ),
      PostEditSubmissionResolutionKind.unconfirmed => _markUnconfirmed(
        prepared,
        operation: operation,
        detail: result.detail,
        nativeSupported: result.nativeSupported,
      ),
      PostEditSubmissionResolutionKind.partialSuccess => _markPartialSuccess(
        prepared,
        operation: operation,
        snapshot: result.snapshot,
      ),
      PostEditSubmissionResolutionKind.conflict => _markConflict(
        prepared,
        operation: operation,
        snapshot: result.snapshot!,
      ),
      PostEditSubmissionResolutionKind.superseded => _failureOutcome(
        ComposerSubmissionFailureCode.unknown,
      ),
    };
  }

  ComposerSubmissionOutcome _acceptAppliedSubmission(
    PostEditComposerState current,
    PostEditSubmissionResolution result,
  ) {
    lastReadAccessEvidence = result.readAccess;
    return _confirmSuccess(
      current,
      operation: result.operation,
      snapshot: result.snapshot,
    );
  }

  ComposerSubmissionOutcome _confirmSuccess(
    PostEditComposerState current, {
    required PostEditSubmissionOperation operation,
    ThreadPostEditPreparation? snapshot,
  }) {
    if (!_isCurrentSubmission(operation)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit_success',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    final next = snapshot == null
        ? current
        : _replaceSnapshotKeepingLocal(current, snapshot);
    setStateValue(
      next.copyWith(
        submitState: PostEditSubmitState.idle,
        lastSubmitOutcome: PostEditSubmitResponseKind.confirmedSuccess,
        submitBlocked: false,
        serverMutationPossible: true,
      ),
    );
    return const ComposerSubmissionOutcome.success();
  }

  ComposerSubmissionOutcome _markPartialSuccess(
    PostEditComposerState current, {
    required PostEditSubmissionOperation operation,
    required ThreadPostEditPreparation? snapshot,
  }) {
    if (!_isCurrentSubmission(operation)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit_partial',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    final next = snapshot == null
        ? current
        : _replaceSnapshotKeepingLocal(current, snapshot);
    setStateValue(
      next.copyWith(
        submitState: PostEditSubmitState.partialSuccess,
        lastSubmitOutcome: PostEditSubmitResponseKind.partialSuccess,
        serverMutationPossible: true,
        submitBlocked: true,
      ),
    );
    return _failureOutcome(
      ComposerSubmissionFailureCode.server,
      detail: 'attachment_association_unconfirmed',
    );
  }

  ComposerSubmissionOutcome _markConflict(
    PostEditComposerState current, {
    required ThreadPostEditPreparation snapshot,
    required PostEditSubmissionOperation operation,
  }) {
    if (!_isCurrentSubmission(operation)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit_conflict',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    _recordDiagnostic(
      PostEditContractReasonCode.ambiguousResult,
      operation: 'submit_conflict',
    );
    setStateValue(
      _replaceSnapshotKeepingLocal(current, snapshot).copyWith(
        pendingConflict: _captureConflict(current, snapshot),
        submitState: PostEditSubmitState.unconfirmed,
        lastSubmitOutcome: PostEditSubmitResponseKind.ambiguous,
        submitBlocked: true,
        serverMutationPossible: true,
      ),
    );
    return _failureOutcome(
      ComposerSubmissionFailureCode.unknown,
      detail: 'submit_conflict',
    );
  }

  ComposerSubmissionOutcome _markUnconfirmed(
    PostEditComposerState current, {
    required PostEditSubmissionOperation operation,
    String? detail,
    bool? nativeSupported,
  }) {
    if (!_isCurrentSubmission(operation)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit_unconfirmed',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    _recordDiagnostic(
      _reasonForUnconfirmedDetail(detail),
      operation: 'submit_unconfirmed',
    );
    setStateValue(
      current.copyWith(
        submitState: PostEditSubmitState.unconfirmed,
        lastSubmitOutcome: PostEditSubmitResponseKind.ambiguous,
        submitBlocked: true,
        serverMutationPossible: true,
        nativeSupported: nativeSupported,
      ),
    );
    return _failureOutcome(
      ComposerSubmissionFailureCode.unknown,
      detail: detail,
    );
  }

  ComposerSubmissionOutcome _failAndKeepState(
    PostEditComposerState current, {
    required PostEditSubmissionOperation operation,
    required PostEditSubmitResponseKind kind,
    required ComposerSubmissionFailureCode code,
    String? detail,
    bool blockSubmit = false,
  }) {
    if (_isCurrentSubmission(operation)) {
      setStateValue(
        current.copyWith(
          submitState: PostEditSubmitState.idle,
          lastSubmitOutcome: kind,
          submitBlocked: blockSubmit,
        ),
      );
    }
    return _failureOutcome(code, detail: detail);
  }

  ComposerSubmissionOutcome _failFromCommandFailure(
    PostEditComposerState current, {
    required PostEditSubmissionOperation operation,
    required DataCommandFailure failure,
  }) {
    final classified = _failureClassifier.classifyCommand(
      failure,
      kind: composerKind,
      outcomeUnknown: false,
    );
    final authentication =
        classified.code == ComposerSubmissionFailureCode.authenticationRequired;
    final permission =
        classified.code == ComposerSubmissionFailureCode.permissionDenied;
    return _failAndKeepState(
      current,
      operation: operation,
      kind: authentication
          ? PostEditSubmitResponseKind.authenticationFailure
          : permission
          ? PostEditSubmitResponseKind.permissionFailure
          : PostEditSubmitResponseKind.businessFailure,
      code: classified.code,
      detail: classified.detail,
      blockSubmit: authentication || permission,
    );
  }

  ComposerSubmissionOutcome _failureOutcome(
    ComposerSubmissionFailureCode code, {
    String? detail,
  }) {
    return ComposerSubmissionOutcome.failure(
      failure: ComposerSubmissionFailure(
        code: code,
        kind: composerKind,
        detail: detail,
      ),
    );
  }

  bool _isCurrentSubmission(PostEditSubmissionOperation operation) =>
      _submissions?.accepts(operation) ?? false;

  bool _hasPendingSubmission(PostEditComposerState value) =>
      value.submitState == PostEditSubmitState.submitting ||
      value.submitState == PostEditSubmitState.verifying;

  bool _isCurrentPrepareGeneration(int generation, PostEditTarget target) {
    return generation == _prepareGeneration && _ownsTarget(target);
  }

  bool _ownsTarget(PostEditTarget target) {
    return target == _args.target;
  }

  bool _isCurrentWebReconcileGeneration(
    int generation,
    int prepareGeneration,
    PostEditTarget target,
  ) {
    return generation == _webReconcileGeneration &&
        _isCurrentPrepareGeneration(prepareGeneration, target);
  }

  bool _isCurrentDeleteGeneration(
    String aid,
    int generation,
    PostEditTarget target,
  ) {
    return _deleteGenerationByAid[aid] == generation && _ownsTarget(target);
  }

  PostEditContractReasonCode _reasonForUnconfirmedDetail(String? detail) {
    final normalized = detail?.trim().toLowerCase() ?? '';
    if (normalized.contains('formhash')) {
      return PostEditContractReasonCode.formExpired;
    }
    if (normalized.contains('verification') ||
        normalized.contains('readback')) {
      return PostEditContractReasonCode.readbackFailure;
    }
    if (normalized.contains('not_supported')) {
      return PostEditContractReasonCode.contractChanged;
    }
    if (normalized.contains('conflict')) {
      return PostEditContractReasonCode.ambiguousResult;
    }
    return PostEditContractReasonCode.unconfirmed;
  }

  void _recordDiagnostic(
    PostEditContractReasonCode reasonCode, {
    required String operation,
  }) {
    try {
      ref
          .read(postEditContractDiagnosticRecorderProvider)
          .record(
            PostEditContractDiagnosticEvent(
              operation: operation,
              reasonCode: reasonCode,
              target: _args.target,
            ),
          );
    } catch (_) {
      // Diagnostics are best effort and must never affect editor state.
    }
  }

  PostEditComposerState _replaceSnapshotKeepingLocal(
    PostEditComposerState current,
    ThreadPostEditPreparation snapshot,
  ) {
    final session = current.attachmentSession.copyWith(
      existingImagesByAid: {
        for (final image in snapshot.existingImages) image.aid: image,
      },
      deletingAids: const <String>{},
    );
    return current.copyWith(
      snapshot: snapshot,
      baselineSubject: snapshot.subject,
      baselineMessage: snapshot.message,
      baselineFingerprint: snapshot.revision,
      // No local threshold intent exists when the old form could not prove it.
      minimumReadAccess:
          current.minimumReadAccess ?? snapshot.readAccess.currentValue,
      attachmentSession: session,
    );
  }

  PostEditConflictState _captureConflict(
    PostEditComposerState current,
    ThreadPostEditPreparation snapshot,
  ) {
    return PostEditConflictState(
      localSubject: current.subject,
      localMessage: current.message,
      localMinimumReadAccess: current.minimumReadAccess,
      localUseSignature: current.useSignature,
      localImageAttachments: current.imageAttachments,
      localAttachmentSession: current.attachmentSession,
      latestSnapshot: snapshot,
    );
  }

  Future<void> reconcileWebViewReturn() async {
    final current = state.value ?? latestState;
    if (current == null) {
      return;
    }
    _submissions?.invalidate();
    final webGeneration = ++_webReconcileGeneration;
    final prepareGeneration = ++_prepareGeneration;
    setStateValue(
      current.copyWith(
        webReturnVerificationState:
            PostEditWebReturnVerificationState.verifying,
        submitState: _hasPendingSubmission(current)
            ? PostEditSubmitState.unconfirmed
            : null,
        submitBlocked: _hasPendingSubmission(current) ? true : null,
      ),
    );
    final result = await ref
        .read(threadPostEditPreparationRepositoryProvider)
        .load(
          ThreadPostEditPreparationRequest(
            target: current.target.toClientTarget(),
          ),
        );
    final latest = state.value ?? latestState;
    if (latest == null ||
        !_isCurrentWebReconcileGeneration(
          webGeneration,
          prepareGeneration,
          current.target,
        )) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'web_reconcile',
      );
      return;
    }
    if (result
        case DataReadFailure<
              ThreadPostEditPreparation,
              ThreadPostEditCapabilities
            >()) {
      setStateValue(
        latest.copyWith(
          webReturnVerificationState:
              PostEditWebReturnVerificationState.unconfirmed,
          submitBlocked: true,
          submitState: PostEditSubmitState.unconfirmed,
          serverMutationPossible: true,
          nativeSupported: false,
        ),
      );
      return;
    }
    final latestSnapshot =
        (result
                as DataReadSuccess<
                  ThreadPostEditPreparation,
                  ThreadPostEditCapabilities
                >)
            .data;
    if (latestSnapshot.revision == latest.baselineFingerprint) {
      setStateValue(
        latest.copyWith(
          webReturnVerificationState:
              PostEditWebReturnVerificationState.unchanged,
        ),
      );
      return;
    }
    if (!latest.isDirtyAgainstBaseline) {
      setStateValue(
        latest.copyWith(
          snapshot: latestSnapshot,
          baselineSubject: latestSnapshot.subject,
          baselineMessage: latestSnapshot.message,
          baselineFingerprint: latestSnapshot.revision,
          subject: latestSnapshot.subject,
          resetReadAccess: true,
          useSignature: latestSnapshot.useSignature,
          message: latestSnapshot.message,
          imageAttachments: const <ComposerImageAttachment>[],
          attachmentSession: PostEditAttachmentSession.fromImages(
            latestSnapshot.existingImages,
          ),
          restoredDraft: false,
          webReturnVerificationState:
              PostEditWebReturnVerificationState.changedClean,
          serverMutationPossible: true,
        ),
      );
      return;
    }
    setStateValue(
      _replaceSnapshotKeepingLocal(latest, latestSnapshot).copyWith(
        pendingConflict: _captureConflict(latest, latestSnapshot),
        webReturnVerificationState: PostEditWebReturnVerificationState.conflict,
        submitBlocked: true,
      ),
    );
  }

  Future<void> useServerVersion() async {
    final current = state.value ?? latestState;
    final conflict = current?.pendingConflict;
    if (current == null || conflict == null) {
      return;
    }
    _submissions?.invalidate();
    _webReconcileGeneration += 1;
    _prepareGeneration += 1;
    setStateValue(
      current.copyWith(
        snapshot: conflict.latestSnapshot,
        baselineSubject: conflict.latestSnapshot.subject,
        baselineMessage: conflict.latestSnapshot.message,
        baselineFingerprint: conflict.latestSnapshot.revision,
        subject: conflict.latestSnapshot.subject,
        resetReadAccess: true,
        useSignature: conflict.latestSnapshot.useSignature,
        message: conflict.latestSnapshot.message,
        restoredDraft: false,
        imageAttachments: const <ComposerImageAttachment>[],
        attachmentSession: PostEditAttachmentSession.fromImages(
          conflict.latestSnapshot.existingImages,
        ),
        webReturnVerificationState: PostEditWebReturnVerificationState.idle,
        submitState: PostEditSubmitState.idle,
        submitBlocked: false,
        confirmedOverwriteIntent: false,
        clearPendingConflict: true,
      ),
    );
  }

  Future<void> keepLocalVersion() async {
    final current = state.value ?? latestState;
    final conflict = current?.pendingConflict;
    if (current == null || conflict == null) {
      return;
    }
    _submissions?.invalidate();
    _webReconcileGeneration += 1;
    _prepareGeneration += 1;
    final localSession = conflict.localAttachmentSession.copyWith(
      existingImagesByAid: {
        for (final image in conflict.latestSnapshot.existingImages)
          image.aid: image,
      },
      deletingAids: const <String>{},
    );
    setStateValue(
      current.copyWith(
        snapshot: conflict.latestSnapshot,
        baselineSubject: conflict.latestSnapshot.subject,
        baselineMessage: conflict.latestSnapshot.message,
        baselineFingerprint: conflict.latestSnapshot.revision,
        subject: conflict.localSubject,
        minimumReadAccess:
            conflict.localMinimumReadAccess ??
            conflict.latestSnapshot.readAccess.currentValue,
        message: conflict.localMessage,
        useSignature: conflict.localUseSignature,
        imageAttachments: conflict.localImageAttachments,
        attachmentSession: localSession,
        webReturnVerificationState: PostEditWebReturnVerificationState.idle,
        submitState: PostEditSubmitState.idle,
        submitBlocked: false,
        confirmedOverwriteIntent: true,
        clearPendingConflict: true,
      ),
    );
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

    final operation = _nextGeneration(_deleteGenerationByAid[normalizedAid]);
    _submissions?.invalidate();
    _deleteGenerationByAid[normalizedAid] = operation;
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
        serverMutationPossible: true,
        submitState: _hasPendingSubmission(current)
            ? PostEditSubmitState.unconfirmed
            : null,
        submitBlocked: _hasPendingSubmission(current) ? true : null,
      ),
    );
    final result = await ref
        .read(postEditImageAttachmentDeleteCommandProvider)
        .execute(
          DeletePostImageAttachmentRequest(
            tid: current.target.tid,
            pid: current.target.pid,
            aid: normalizedAid,
          ),
        );
    if (!_isCurrentDeleteGeneration(normalizedAid, operation, current.target)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'delete_attachment',
      );
      return;
    }
    final latest = state.value ?? latestState;
    if (latest == null) {
      return;
    }
    final confirmedByResponse =
        result is DataCommandApplied<ForumImageAttachmentDeleteReceipt>;
    final responseOutcome = switch (result) {
      DataCommandApplied<ForumImageAttachmentDeleteReceipt>() =>
        PostEditAttachmentDeleteOutcome.deleted,
      DataCommandRejected<ForumImageAttachmentDeleteReceipt>() =>
        PostEditAttachmentDeleteOutcome.notDeleted,
      _ => PostEditAttachmentDeleteOutcome.unconfirmed,
    };
    await _reconcileDelete(
      latest,
      normalizedAid,
      operation: operation,
      confirmedByResponse: confirmedByResponse,
      responseOutcome: responseOutcome,
    );
  }

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
        .read(threadPostEditPreparationRepositoryProvider)
        .load(
          ThreadPostEditPreparationRequest(
            target: current.target.toClientTarget(),
          ),
        );
    if (!_isCurrentDeleteGeneration(aid, operation, current.target)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'delete_reconcile',
      );
      return;
    }
    final latest = state.value ?? latestState;
    if (latest == null) {
      return;
    }
    if (readback case DataReadSuccess<
      ThreadPostEditPreparation,
      ThreadPostEditCapabilities
    >(
      :final data,
    )) {
      final snapshot = data;
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
            serverMutationPossible: true,
          ),
        );
        return;
      }
      final tombstones = {
        ...latest.attachmentSession.deletedAidTombstones,
        if (!aidStillExists || confirmedByResponse) aid,
      };
      final remoteImages = snapshot.existingImages.where(
        (image) => !tombstones.contains(image.aid),
      );
      setStateValue(
        latest.copyWith(
          snapshot: snapshot,
          baselineSubject: snapshot.subject,
          baselineMessage: snapshot.message,
          baselineFingerprint: snapshot.revision,
          attachmentSession: PostEditAttachmentSession.fromImages(
            remoteImages,
            deletingAids: latest.attachmentSession.deletingAids.difference(
              <String>{aid},
            ),
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
      return;
    }

    setStateValue(
      latest.copyWith(
        attachmentSession: latest.attachmentSession.copyWith(
          deletingAids: latest.attachmentSession.deletingAids.difference(
            <String>{aid},
          ),
          deletedAidTombstones: confirmedByResponse
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
    _recordDiagnostic(
      PostEditContractReasonCode.readbackFailure,
      operation: 'delete_reconcile',
    );
  }
}

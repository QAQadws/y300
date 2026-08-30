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
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_diagnostic_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_attachment_session_resolver.dart';
import 'package:y300/features/thread/domain/services/post_edit_message_canonicalizer.dart';
import 'package:y300/features/thread/domain/services/post_edit_submission_mapper.dart';
import 'package:y300/features/thread/domain/services/post_edit_submit_verification_service.dart';
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
  final PostEditSubmitVerificationService _verificationService =
      const PostEditSubmitVerificationService();
  final ComposerSubmissionFailureClassifier _failureClassifier =
      const ComposerSubmissionFailureClassifier();
  final PostEditMessageCanonicalizer _messageCanonicalizer =
      const PostEditMessageCanonicalizer();
  int _prepareGeneration = 0;
  int _webReconcileGeneration = 0;
  int _submitGeneration = 0;
  final Map<String, int> _deleteGenerationByAid = <String, int>{};
  String? _lastUncertainSubmitSubject;
  String? _lastUncertainSubmitMessage;
  List<String> _lastUncertainSubmitAttachNewAids = const <String>[];

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
    ref.onDispose(() {
      _prepareGeneration += 1;
      _webReconcileGeneration += 1;
      _submitGeneration += 1;
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
    if (patch.message != null || patch.imageAttachments != null) {
      // A local edit invalidates a pending server read. A response based on
      // the previous message must never replace the current editor state.
      _webReconcileGeneration += 1;
      if (current.isSubmitting ||
          current.submitState != PostEditSubmitState.idle) {
        _submitGeneration += 1;
      }
    }
    if (patch.message != null) {
      _lastUncertainSubmitMessage = null;
      _lastUncertainSubmitAttachNewAids = const <String>[];
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
    );
  }

  void updateSubject(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    _webReconcileGeneration += 1;
    if (current.isSubmitting ||
        current.submitState != PostEditSubmitState.idle) {
      _submitGeneration += 1;
    }
    _lastUncertainSubmitSubject = null;
    _lastUncertainSubmitMessage = null;
    _lastUncertainSubmitAttachNewAids = const <String>[];
    setStateValue(
      current.copyWith(
        subject: value,
        restoredDraft: false,
        clearFailure: true,
        clearLastSubmitOutcome: true,
      ),
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
    return value.copyWith(
      message: value.snapshot.message,
      subject: value.snapshot.subject,
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
  Future<ComposerSubmissionOutcome> performSubmit({
    required PostEditComposerState state,
    required List<String> uploadedAids,
  }) async {
    final generation = ++_submitGeneration;
    if (!_isCurrentSubmitGeneration(generation)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    setStateValue(
      state.copyWith(
        submitState: PostEditSubmitState.submitting,
        submitBlocked: false,
        clearFailure: true,
      ),
    );
    return _submitWithRetry(
      this.state.value ?? latestState ?? state,
      generation: generation,
      formHashRetried: false,
    );
  }

  Future<ComposerSubmissionOutcome> _submitWithRetry(
    PostEditComposerState current, {
    required int generation,
    required bool formHashRetried,
  }) async {
    final projection = _submissionMapper.map(
      message: current.message,
      localAttachments: current.imageAttachments,
      attachmentSession: current.attachmentSession,
      now: DateTime.now(),
    );

    if (!_isCurrentSubmitGeneration(generation)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    final result = await ref
        .read(threadPostEditCommandProvider)
        .execute(
          ThreadPostEditSubmission(
            preparation: current.snapshot,
            subject: current.subject,
            message: current.message,
            useSignature: current.useSignature,
            newImageAttachmentIds: projection.newAttachmentAids,
            removedImageAttachmentIds: current
                .attachmentSession
                .deletedAidTombstones
                .toList(growable: false),
          ),
        );
    if (!_isCurrentSubmitGeneration(generation)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    switch (result) {
      case DataCommandApplied<ThreadPostEditReceipt>():
        return _confirmSuccess(current, generation: generation);
      case DataCommandRejected<ThreadPostEditReceipt>(:final failure):
        if (failure.kind == DataCommandFailureKind.staleFormhash) {
          if (formHashRetried) {
            return _markUnconfirmed(
              current,
              generation: generation,
              detail: 'formhash_retry_exhausted',
            );
          }
          return _refreshFormHashAndRetry(current, generation: generation);
        }
        return _failFromCommandFailure(
          current,
          generation: generation,
          failure: failure,
        );
      case DataCommandNotSent<ThreadPostEditReceipt>(:final failure):
        return _failFromCommandFailure(
          current,
          generation: generation,
          failure: failure,
        );
      case DataCommandOutcomeUnknown<ThreadPostEditReceipt>(:final failure):
        _lastUncertainSubmitMessage = current.message;
        _lastUncertainSubmitSubject = current.subject;
        _lastUncertainSubmitAttachNewAids = projection.newAttachmentAids;
        if (failure.code == 'post_edit_attachment_state_unconfirmed') {
          return _markPartialSuccess(
            current,
            generation: generation,
            snapshot: null,
          );
        }
        return _markUnconfirmed(
          current,
          generation: generation,
          detail: failure.code,
        );
      case DataCommandUnsupported<ThreadPostEditReceipt>(:final failure):
        return _markUnconfirmed(
          current,
          generation: generation,
          detail: failure.code,
          nativeSupported: false,
        );
    }
  }

  Future<ComposerSubmissionOutcome> _refreshFormHashAndRetry(
    PostEditComposerState current, {
    required int generation,
  }) async {
    final prepareGeneration = ++_prepareGeneration;
    final preparation = await ref
        .read(threadPostEditPreparationRepositoryProvider)
        .load(
          ThreadPostEditPreparationRequest(
            target: current.target.toClientTarget(),
          ),
        );
    if (!_isCurrentSubmitGeneration(generation) ||
        !_isCurrentPrepareGeneration(prepareGeneration, current.target)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'formhash_refresh',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    if (preparation
        case DataReadFailure<
              ThreadPostEditPreparation,
              ThreadPostEditCapabilities
            >()) {
      _recordDiagnostic(
        PostEditContractReasonCode.readbackFailure,
        operation: 'formhash_refresh',
      );
      return _markUnconfirmed(
        current,
        generation: generation,
        detail: 'formhash_refresh_failed',
      );
    }
    final snapshot =
        (preparation
                as DataReadSuccess<
                  ThreadPostEditPreparation,
                  ThreadPostEditCapabilities
                >)
            .data;
    if (snapshot.revision != current.baselineFingerprint) {
      return _markConflict(current, snapshot: snapshot, generation: generation);
    }
    final refreshed = _replaceSnapshotKeepingLocal(current, snapshot);
    setStateValue(refreshed);
    return _submitWithRetry(
      refreshed,
      generation: generation,
      formHashRetried: true,
    );
  }

  /// Retries only the verification GET for an uncertain result. It never
  /// resubmits the multipart payload.
  Future<void> retrySubmitVerification() async {
    final current = state.value ?? latestState;
    final subject = _lastUncertainSubmitSubject;
    final message = _lastUncertainSubmitMessage;
    if (current == null || subject == null || message == null) {
      await reconcileWebViewReturn();
      return;
    }
    final generation = ++_submitGeneration;
    await _verifyReadback(
      current,
      attachNewAids: _lastUncertainSubmitAttachNewAids,
      generation: generation,
      submittedSubject: subject,
      submittedMessage: message,
    );
  }

  Future<ComposerSubmissionOutcome> _verifyReadback(
    PostEditComposerState current, {
    required List<String> attachNewAids,
    required int generation,
    String? submittedSubject,
    String? submittedMessage,
  }) async {
    final prepareGeneration = ++_prepareGeneration;
    if (!_isCurrentSubmitGeneration(generation) ||
        !_isCurrentPrepareGeneration(prepareGeneration, current.target)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit_verification',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    setStateValue(current.copyWith(submitState: PostEditSubmitState.verifying));
    final readback = await ref
        .read(threadPostEditPreparationRepositoryProvider)
        .load(
          ThreadPostEditPreparationRequest(
            target: current.target.toClientTarget(),
          ),
        );
    if (!_isCurrentSubmitGeneration(generation) ||
        !_isCurrentPrepareGeneration(prepareGeneration, current.target)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit_verification',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    if (readback
        case DataReadFailure<
              ThreadPostEditPreparation,
              ThreadPostEditCapabilities
            >()) {
      _recordDiagnostic(
        PostEditContractReasonCode.readbackFailure,
        operation: 'submit_verification',
      );
      return _markUnconfirmed(
        current,
        generation: generation,
        detail: 'submit_verification_failed',
      );
    }
    final snapshot =
        (readback
                as DataReadSuccess<
                  ThreadPostEditPreparation,
                  ThreadPostEditCapabilities
                >)
            .data;
    final verification = _verificationService.verify(
      before: current.snapshot,
      after: snapshot,
      submittedSubject: submittedSubject ?? current.subject,
      submittedMessage: submittedMessage ?? current.message,
      attachNewAids: attachNewAids,
    );
    switch (verification.kind) {
      case PostEditSubmitResponseKind.confirmedSuccess:
        return _confirmSuccess(
          current,
          generation: generation,
          snapshot: snapshot,
        );
      case PostEditSubmitResponseKind.partialSuccess:
        return _markPartialSuccess(
          current,
          generation: generation,
          snapshot: snapshot,
        );
      case PostEditSubmitResponseKind.ambiguous:
        if (snapshot.revision != current.baselineFingerprint &&
            (_messageCanonicalizer.canonicalize(snapshot.message) !=
                    _messageCanonicalizer.canonicalize(current.message) ||
                snapshot.subject.trim() != current.subject.trim())) {
          return _markConflict(
            current,
            snapshot: snapshot,
            generation: generation,
          );
        }
        return _markUnconfirmed(
          current,
          generation: generation,
          detail: verification.detail,
        );
      case PostEditSubmitResponseKind.businessFailure:
      case PostEditSubmitResponseKind.authenticationFailure:
      case PostEditSubmitResponseKind.permissionFailure:
      case PostEditSubmitResponseKind.formExpired:
        return _markUnconfirmed(
          current,
          generation: generation,
          detail: verification.detail,
        );
    }
  }

  ComposerSubmissionOutcome _confirmSuccess(
    PostEditComposerState current, {
    required int generation,
    ThreadPostEditPreparation? snapshot,
  }) {
    if (!_isCurrentSubmitGeneration(generation)) {
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
    _lastUncertainSubmitMessage = null;
    _lastUncertainSubmitSubject = null;
    _lastUncertainSubmitAttachNewAids = const <String>[];
    return const ComposerSubmissionOutcome.success();
  }

  Future<ComposerSubmissionOutcome> _markPartialSuccess(
    PostEditComposerState current, {
    required int generation,
    required ThreadPostEditPreparation? snapshot,
  }) async {
    if (!_isCurrentSubmitGeneration(generation)) {
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
        submitBlocked: false,
      ),
    );
    return _failureOutcome(
      ComposerSubmissionFailureCode.server,
      detail: 'attachment_association_unconfirmed',
    );
  }

  Future<ComposerSubmissionOutcome> _markConflict(
    PostEditComposerState current, {
    required ThreadPostEditPreparation snapshot,
    required int generation,
  }) async {
    if (!_isCurrentSubmitGeneration(generation)) {
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

  Future<ComposerSubmissionOutcome> _markUnconfirmed(
    PostEditComposerState current, {
    required int generation,
    String? detail,
    bool? nativeSupported,
  }) async {
    if (!_isCurrentSubmitGeneration(generation)) {
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
    required int generation,
    required PostEditSubmitResponseKind kind,
    required ComposerSubmissionFailureCode code,
    String? detail,
    bool blockSubmit = false,
  }) {
    if (_isCurrentSubmitGeneration(generation)) {
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
    required int generation,
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
      generation: generation,
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

  bool _isCurrentSubmitGeneration(int generation) {
    return generation == _submitGeneration;
  }

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
    final webGeneration = ++_webReconcileGeneration;
    final prepareGeneration = ++_prepareGeneration;
    setStateValue(
      current.copyWith(
        webReturnVerificationState:
            PostEditWebReturnVerificationState.verifying,
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
    _webReconcileGeneration += 1;
    _prepareGeneration += 1;
    setStateValue(
      current.copyWith(
        snapshot: conflict.latestSnapshot,
        baselineSubject: conflict.latestSnapshot.subject,
        baselineMessage: conflict.latestSnapshot.message,
        baselineFingerprint: conflict.latestSnapshot.revision,
        subject: conflict.latestSnapshot.subject,
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

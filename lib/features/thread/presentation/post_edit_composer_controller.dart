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
import 'package:y300/features/thread/domain/models/post_edit_diagnostic_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_attachment_session_resolver.dart';
import 'package:y300/features/thread/domain/services/post_edit_message_canonicalizer.dart';
import 'package:y300/features/thread/domain/services/post_edit_submit_payload_builder.dart';
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
  final PostEditSubmitPayloadBuilder _payloadBuilder =
      const PostEditSubmitPayloadBuilder();
  final PostEditSubmitVerificationService _verificationService =
      const PostEditSubmitVerificationService();
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
      subject: _args.snapshot.originalSubject,
      message: _args.snapshot.rawMessage,
      useSignature: _usesSignatureFromSnapshot(),
      nativeSupported: _args.preparation.isNativeSupported,
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
    try {
      return _payloadBuilder
          .build(
            PostEditSubmitCommand(
              target: value.target,
              snapshot: value.snapshot,
              subject: value.subject,
              message: value.message,
              imageAttachments: value.imageAttachments,
              attachmentSession: value.attachmentSession,
              now: DateTime.now(),
            ),
          )
          .danglingAids;
    } on PostEditSubmitPayloadBuildException {
      return const <String>[];
    }
  }

  @override
  PostEditComposerState resetToBaseline(PostEditComposerState value) {
    return value.copyWith(
      message: value.snapshot.rawMessage,
      subject: value.snapshot.originalSubject,
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
    late final PostEditSubmitPayload payload;
    try {
      payload = _payloadBuilder.build(
        PostEditSubmitCommand(
          target: current.target,
          snapshot: current.snapshot,
          subject: current.subject,
          message: current.message,
          imageAttachments: current.imageAttachments,
          attachmentSession: current.attachmentSession,
          now: DateTime.now(),
        ),
      );
    } on PostEditSubmitPayloadBuildException catch (error) {
      return _failAndKeepState(
        current,
        generation: generation,
        kind: PostEditSubmitResponseKind.businessFailure,
        code: ComposerSubmissionFailureCode.unknown,
        detail: error.failure.name,
      );
    }

    if (!_isCurrentSubmitGeneration(generation)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    final result = await ref
        .read(postEditRepositoryProvider)
        .submit(payload, target: current.target);
    if (!_isCurrentSubmitGeneration(generation)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    if (result case ApiFailure<PostEditSubmitResponse>(:final error)) {
      if (error.type == ApiErrorType.unauthorized) {
        return _failAndKeepState(
          current,
          generation: generation,
          kind: PostEditSubmitResponseKind.authenticationFailure,
          code: ComposerSubmissionFailureCode.authenticationRequired,
        );
      }
      return _verifyAfterUncertainSubmit(
        current,
        payload: payload,
        generation: generation,
      );
    }

    final response = (result as ApiSuccess<PostEditSubmitResponse>).data;
    switch (response.kind) {
      case PostEditSubmitResponseKind.confirmedSuccess:
        return _confirmSuccess(current, generation: generation);
      case PostEditSubmitResponseKind.formExpired:
        if (formHashRetried) {
          return _markUnconfirmed(
            current,
            generation: generation,
            detail: 'formhash_retry_exhausted',
          );
        }
        return _refreshFormHashAndRetry(current, generation: generation);
      case PostEditSubmitResponseKind.ambiguous:
        return _verifyAfterUncertainSubmit(
          current,
          payload: payload,
          generation: generation,
        );
      case PostEditSubmitResponseKind.partialSuccess:
        return _markPartialSuccess(
          current,
          generation: generation,
          snapshot: null,
        );
      case PostEditSubmitResponseKind.businessFailure:
        return _failAndKeepState(
          current,
          generation: generation,
          kind: response.kind,
          code: ComposerSubmissionFailureCode.server,
          detail: response.detail,
        );
      case PostEditSubmitResponseKind.authenticationFailure:
        return _failAndKeepState(
          current,
          generation: generation,
          kind: response.kind,
          code: ComposerSubmissionFailureCode.authenticationRequired,
          blockSubmit: true,
        );
      case PostEditSubmitResponseKind.permissionFailure:
        return _failAndKeepState(
          current,
          generation: generation,
          kind: response.kind,
          code: ComposerSubmissionFailureCode.permissionDenied,
          blockSubmit: true,
        );
    }
  }

  Future<ComposerSubmissionOutcome> _refreshFormHashAndRetry(
    PostEditComposerState current, {
    required int generation,
  }) async {
    final prepareGeneration = ++_prepareGeneration;
    final preparation = await ref
        .read(postEditRepositoryProvider)
        .loadForm(current.target);
    if (!_isCurrentSubmitGeneration(generation) ||
        !_isCurrentPrepareGeneration(prepareGeneration, current.target)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'formhash_refresh',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    if (preparation case ApiFailure<PostEditPreparation>()) {
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
    final next = (preparation as ApiSuccess<PostEditPreparation>).data;
    final snapshot = next.snapshot;
    if (snapshot == null || !next.isNativeSupported) {
      _recordDiagnostic(
        PostEditContractReasonCode.contractChanged,
        operation: 'formhash_refresh',
      );
      return _markUnconfirmed(
        current,
        generation: generation,
        detail: 'formhash_refresh_not_supported',
        nativeSupported: false,
      );
    }
    if (snapshot.baselineFingerprint != current.baselineFingerprint) {
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

  Future<ComposerSubmissionOutcome> _verifyAfterUncertainSubmit(
    PostEditComposerState current, {
    required PostEditSubmitPayload payload,
    required int generation,
  }) async {
    _lastUncertainSubmitMessage = current.message;
    _lastUncertainSubmitSubject = current.subject;
    _lastUncertainSubmitAttachNewAids = payload.attachNewAids;
    return _verifyReadback(current, payload: payload, generation: generation);
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
    final payload = PostEditSubmitPayload(
      submitUri: current.snapshot.submitUri,
      fields: const <MapEntry<String, String>>[],
      danglingAids: const <String>[],
      attachNewAids: _lastUncertainSubmitAttachNewAids,
    );
    await _verifyReadback(
      current,
      payload: payload,
      generation: generation,
      submittedSubject: subject,
      submittedMessage: message,
    );
  }

  Future<ComposerSubmissionOutcome> _verifyReadback(
    PostEditComposerState current, {
    required PostEditSubmitPayload payload,
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
        .read(postEditRepositoryProvider)
        .loadForm(current.target);
    if (!_isCurrentSubmitGeneration(generation) ||
        !_isCurrentPrepareGeneration(prepareGeneration, current.target)) {
      _recordDiagnostic(
        PostEditContractReasonCode.staleGeneration,
        operation: 'submit_verification',
      );
      return _failureOutcome(ComposerSubmissionFailureCode.unknown);
    }
    if (readback case ApiFailure<PostEditPreparation>()) {
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
    final preparation = (readback as ApiSuccess<PostEditPreparation>).data;
    final snapshot = preparation.snapshot;
    if (snapshot == null || !preparation.isNativeSupported) {
      _recordDiagnostic(
        PostEditContractReasonCode.contractChanged,
        operation: 'submit_verification',
      );
      return _markUnconfirmed(
        current,
        generation: generation,
        detail: 'submit_verification_not_supported',
        nativeSupported: false,
      );
    }
    final verification = _verificationService.verify(
      before: current.snapshot,
      after: snapshot,
      submittedSubject: submittedSubject ?? current.subject,
      submittedMessage: submittedMessage ?? current.message,
      attachNewAids: payload.attachNewAids,
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
        if (snapshot.baselineFingerprint != current.baselineFingerprint &&
            (_messageCanonicalizer.canonicalize(snapshot.rawMessage) !=
                    _messageCanonicalizer.canonicalize(current.message) ||
                snapshot.originalSubject.trim() != current.subject.trim())) {
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
    PostEditFormSnapshot? snapshot,
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
    required PostEditFormSnapshot? snapshot,
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
    required PostEditFormSnapshot snapshot,
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

  bool _usesSignatureFromSnapshot() {
    for (final field in _args.snapshot.successfulControls) {
      if (field.name.trim().toLowerCase() == 'usesig') {
        return field.value.trim() == '1';
      }
    }
    return true;
  }

  PostEditComposerState _replaceSnapshotKeepingLocal(
    PostEditComposerState current,
    PostEditFormSnapshot snapshot,
  ) {
    final session = current.attachmentSession.copyWith(
      existingImagesByAid: {
        for (final image in snapshot.existingImages) image.aid: image,
      },
      deletingAids: const <String>{},
    );
    return current.copyWith(
      snapshot: snapshot,
      baselineSubject: snapshot.originalSubject,
      baselineMessage: snapshot.rawMessage,
      baselineFingerprint: snapshot.baselineFingerprint,
      attachmentSession: session,
    );
  }

  PostEditConflictState _captureConflict(
    PostEditComposerState current,
    PostEditFormSnapshot snapshot,
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
        .read(postEditRepositoryProvider)
        .loadForm(current.target);
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
    if (result case ApiFailure<PostEditPreparation>()) {
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
    final preparation = (result as ApiSuccess<PostEditPreparation>).data;
    final latestSnapshot = preparation.snapshot;
    if (latestSnapshot == null || !preparation.isNativeSupported) {
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
    if (latestSnapshot.baselineFingerprint == latest.baselineFingerprint) {
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
          baselineSubject: latestSnapshot.originalSubject,
          baselineMessage: latestSnapshot.rawMessage,
          baselineFingerprint: latestSnapshot.baselineFingerprint,
          subject: latestSnapshot.originalSubject,
          message: latestSnapshot.rawMessage,
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
        baselineSubject: conflict.latestSnapshot.originalSubject,
        baselineMessage: conflict.latestSnapshot.rawMessage,
        baselineFingerprint: conflict.latestSnapshot.baselineFingerprint,
        subject: conflict.latestSnapshot.originalSubject,
        message: conflict.latestSnapshot.rawMessage,
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
        baselineSubject: conflict.latestSnapshot.originalSubject,
        baselineMessage: conflict.latestSnapshot.rawMessage,
        baselineFingerprint: conflict.latestSnapshot.baselineFingerprint,
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
        .read(postEditRepositoryProvider)
        .deleteImage(
          PostEditAttachmentDeleteCommand(
            target: current.target,
            aid: normalizedAid,
            formHash: current.snapshot.formHash,
            expectedBaselineFingerprint: current.baselineFingerprint,
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
          baselineSubject: snapshot.originalSubject,
          baselineMessage: snapshot.rawMessage,
          baselineFingerprint: snapshot.baselineFingerprint,
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

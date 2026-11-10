import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/post_edit_diagnostic_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submission_attempt.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_message_canonicalizer.dart';
import 'package:y300/features/thread/domain/services/post_edit_submit_verification_service.dart';

typedef PostEditCommandExecutor =
    Future<DataCommandResult<ThreadPostEditReceipt>> Function(
      ThreadPostEditSubmission,
    );
typedef PostEditPreparationReader =
    Future<
      DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>
    >
    Function(ThreadPostEditPreparationRequest);

enum PostEditSubmissionResolutionKind {
  applied,
  rejected,
  unconfirmed,
  partialSuccess,
  conflict,
  superseded,
}

final class PostEditSubmissionOperation {
  PostEditSubmissionOperation._(this.attempt, {required this.isVerification});

  final PostEditSubmissionAttempt attempt;
  final bool isVerification;
  Object? _preparationRequest;
}

/// Neutral flow result. Only the controller maps it to presentation state.
final class PostEditSubmissionResolution {
  const PostEditSubmissionResolution._(
    this.kind,
    this.operation,
    this.attempt, {
    this.snapshot,
    this.readAccess,
    this.failure,
    this.detail,
    this.nativeSupported,
  });

  final PostEditSubmissionResolutionKind kind;
  final PostEditSubmissionOperation operation;
  final PostEditSubmissionAttempt attempt;
  final ThreadPostEditPreparation? snapshot;
  final ThreadReadAccessEvidence? readAccess;
  final DataCommandFailure? failure;
  final String? detail;
  final bool? nativeSupported;
}

/// One editor owner's command and explicit verification flow. Shared form-read
/// arbitration is supplied by the host, which also owns WebView/delete reads.
final class PostEditSubmissionCoordinator {
  PostEditSubmissionCoordinator({
    required PostEditCommandExecutor executeCommand,
    required PostEditPreparationReader loadPreparation,
    required Object Function() beginPreparation,
    required bool Function(Object request) isPreparationCurrent,
    void Function(PostEditContractReasonCode reason, String operation)?
    onDiagnostic,
  }) : _executeCommand = executeCommand,
       _loadPreparation = loadPreparation,
       _beginPreparation = beginPreparation,
       _isPreparationCurrent = isPreparationCurrent,
       _onDiagnostic = onDiagnostic;

  final PostEditCommandExecutor _executeCommand;
  final PostEditPreparationReader _loadPreparation;
  final Object Function() _beginPreparation;
  final bool Function(Object request) _isPreparationCurrent;
  final void Function(PostEditContractReasonCode, String)? _onDiagnostic;
  static const _verification = PostEditSubmitVerificationService();
  static const _canonicalizer = PostEditMessageCanonicalizer();
  PostEditSubmissionOperation? _current;
  PostEditSubmissionAttempt? _uncertain;
  Future<PostEditSubmissionResolution>? _inFlight;
  bool _closed = false;

  bool get hasUncertainAttempt => _uncertain != null;
  bool get isRunning => _inFlight != null;

  bool accepts(PostEditSubmissionOperation operation) =>
      !_closed &&
      identical(_current, operation) &&
      (operation._preparationRequest == null ||
          _isPreparationCurrent(operation._preparationRequest!));

  void invalidate() {
    _current = null;
    _uncertain = null;
  }

  void close() {
    _closed = true;
    invalidate();
  }

  Future<PostEditSubmissionResolution>? submit(
    PostEditSubmissionAttempt attempt,
  ) {
    if (_closed || isRunning || hasUncertainAttempt) return null;
    final operation = PostEditSubmissionOperation._(
      attempt,
      isVerification: false,
    );
    return _run(operation, () => _submit(operation, attempt));
  }

  /// An uncertain command is never sent again. Repeated explicit verification
  /// taps share only the same in-flight GET and its immutable command intent.
  Future<PostEditSubmissionResolution>? verifyUncertain() {
    if (_closed) return null;
    if (isRunning) {
      return _current?.isVerification == true && accepts(_current!)
          ? _inFlight
          : null;
    }
    final attempt = _uncertain;
    if (attempt == null) return null;
    final operation = PostEditSubmissionOperation._(
      attempt,
      isVerification: true,
    );
    return _run(operation, () => _verify(operation, attempt));
  }

  Future<PostEditSubmissionResolution> _run(
    PostEditSubmissionOperation operation,
    Future<PostEditSubmissionResolution> Function() action,
  ) {
    _current = operation;
    final completion = Completer<PostEditSubmissionResolution>();
    final request = completion.future;
    // Reserve before publishing host state or invoking a port. The microtask
    // lets that publication retire this request before any remote work starts.
    _inFlight = request;
    unawaited(
      Future<void>.microtask(() async {
        try {
          completion.complete(await action());
        } catch (error, stackTrace) {
          completion.completeError(error, stackTrace);
        } finally {
          if (identical(_inFlight, request)) _inFlight = null;
        }
      }),
    );
    return request;
  }

  PostEditSubmissionResolution _result(
    PostEditSubmissionResolutionKind kind,
    PostEditSubmissionOperation operation,
    PostEditSubmissionAttempt attempt, {
    ThreadPostEditPreparation? snapshot,
    ThreadReadAccessEvidence? readAccess,
    DataCommandFailure? failure,
    String? detail,
    bool? nativeSupported,
  }) => PostEditSubmissionResolution._(
    kind,
    operation,
    attempt,
    snapshot: snapshot,
    readAccess: readAccess,
    failure: failure,
    detail: detail,
    nativeSupported: nativeSupported,
  );

  PostEditSubmissionResolution _stale(
    PostEditSubmissionOperation operation,
    PostEditSubmissionAttempt attempt,
  ) {
    _diagnose(
      PostEditContractReasonCode.staleGeneration,
      operation.isVerification ? 'submit_verification' : 'submit',
    );
    return _result(
      PostEditSubmissionResolutionKind.superseded,
      operation,
      attempt,
    );
  }

  Future<PostEditSubmissionResolution> _submit(
    PostEditSubmissionOperation operation,
    PostEditSubmissionAttempt initial,
  ) async {
    var attempt = initial;
    var formHashRetried = false;
    while (accepts(operation)) {
      final DataCommandResult<ThreadPostEditReceipt> result;
      try {
        result = await _executeCommand(attempt.toSubmission());
      } catch (_) {
        // A thrown command cannot prove that the server did not apply it.
        if (!accepts(operation)) return _stale(operation, attempt);
        _uncertain = attempt;
        return _result(
          PostEditSubmissionResolutionKind.unconfirmed,
          operation,
          attempt,
          detail: 'post_edit_submit_exception',
        );
      }
      if (!accepts(operation)) return _stale(operation, attempt);
      switch (result) {
        case DataCommandApplied<ThreadPostEditReceipt>(:final receipt):
          return _result(
            PostEditSubmissionResolutionKind.applied,
            operation,
            attempt,
            readAccess: receipt.readAccess,
          );
        case DataCommandRejected<ThreadPostEditReceipt>(:final failure):
          if (failure.kind != DataCommandFailureKind.staleFormhash) {
            return _result(
              PostEditSubmissionResolutionKind.rejected,
              operation,
              attempt,
              failure: failure,
            );
          }
          if (formHashRetried) {
            return _result(
              PostEditSubmissionResolutionKind.unconfirmed,
              operation,
              attempt,
              detail: 'formhash_retry_exhausted',
            );
          }
          final snapshot = await _readPreparation(
            operation,
            attempt,
            'formhash_refresh',
          );
          if (!accepts(operation)) return _stale(operation, attempt);
          if (snapshot == null) {
            return _result(
              PostEditSubmissionResolutionKind.unconfirmed,
              operation,
              attempt,
              detail: 'formhash_refresh_failed',
            );
          }
          if (snapshot.target != attempt.preparation.target) {
            return _result(
              PostEditSubmissionResolutionKind.unconfirmed,
              operation,
              attempt,
              detail: 'post_edit_target_mismatch',
              nativeSupported: false,
            );
          }
          if (snapshot.revision != attempt.preparation.revision) {
            return _result(
              PostEditSubmissionResolutionKind.conflict,
              operation,
              attempt,
              snapshot: snapshot,
            );
          }
          attempt = attempt.withPreparation(snapshot);
          formHashRetried = true;
        case DataCommandNotSent<ThreadPostEditReceipt>(:final failure):
          return _result(
            PostEditSubmissionResolutionKind.rejected,
            operation,
            attempt,
            failure: failure,
          );
        case DataCommandOutcomeUnknown<ThreadPostEditReceipt>(:final failure):
          _uncertain = attempt;
          return _result(
            failure.code == 'post_edit_attachment_state_unconfirmed'
                ? PostEditSubmissionResolutionKind.partialSuccess
                : PostEditSubmissionResolutionKind.unconfirmed,
            operation,
            attempt,
            detail: failure.code,
          );
        case DataCommandUnsupported<ThreadPostEditReceipt>(:final failure):
          return _result(
            PostEditSubmissionResolutionKind.unconfirmed,
            operation,
            attempt,
            detail: failure.code,
            nativeSupported: false,
          );
      }
    }
    return _stale(operation, attempt);
  }

  Future<ThreadPostEditPreparation?> _readPreparation(
    PostEditSubmissionOperation operation,
    PostEditSubmissionAttempt attempt,
    String diagnosticOperation,
  ) async {
    if (!accepts(operation)) return null;
    operation._preparationRequest = _beginPreparation();
    if (!accepts(operation)) return null;
    try {
      final result = await _loadPreparation(
        ThreadPostEditPreparationRequest(target: attempt.preparation.target),
      );
      if (!accepts(operation)) return null;
      if (result case DataReadSuccess<
        ThreadPostEditPreparation,
        ThreadPostEditCapabilities
      >(
        :final data,
      )) {
        return data;
      }
    } catch (_) {
      if (!accepts(operation)) return null;
    }
    _diagnose(PostEditContractReasonCode.readbackFailure, diagnosticOperation);
    return null;
  }

  void _diagnose(PostEditContractReasonCode reason, String operation) {
    try {
      _onDiagnostic?.call(reason, operation);
    } catch (_) {
      // Diagnostics cannot change the disposition of a write or proof read.
    }
  }

  Future<PostEditSubmissionResolution> _verify(
    PostEditSubmissionOperation operation,
    PostEditSubmissionAttempt attempt,
  ) async {
    final snapshot = await _readPreparation(
      operation,
      attempt,
      'submit_verification',
    );
    if (!accepts(operation)) return _stale(operation, attempt);
    if (snapshot == null || snapshot.target != attempt.preparation.target) {
      return _result(
        PostEditSubmissionResolutionKind.unconfirmed,
        operation,
        attempt,
        detail: 'submit_verification_failed',
      );
    }
    final verification = _verification.verify(
      before: attempt.preparation,
      after: snapshot,
      submittedSubject: attempt.subject,
      submittedMessage: attempt.message,
      submittedReadAccess: attempt.minimumReadAccess,
      attachNewAids: attempt.newImageAttachmentIds,
    );
    switch (verification.kind) {
      case PostEditSubmitResponseKind.confirmedSuccess:
        _uncertain = null;
        return _result(
          PostEditSubmissionResolutionKind.applied,
          operation,
          attempt,
          snapshot: snapshot,
        );
      case PostEditSubmitResponseKind.partialSuccess:
        return _result(
          PostEditSubmissionResolutionKind.partialSuccess,
          operation,
          attempt,
          snapshot: snapshot,
        );
      case PostEditSubmitResponseKind.ambiguous:
        if (snapshot.revision != attempt.preparation.revision &&
            (_canonicalizer.canonicalize(snapshot.message) !=
                    _canonicalizer.canonicalize(attempt.message) ||
                snapshot.subject.trim() != attempt.subject.trim() ||
                snapshot.readAccess.currentValue !=
                    attempt.minimumReadAccess)) {
          return _result(
            PostEditSubmissionResolutionKind.conflict,
            operation,
            attempt,
            snapshot: snapshot,
          );
        }
        return _result(
          PostEditSubmissionResolutionKind.unconfirmed,
          operation,
          attempt,
          detail: verification.detail,
        );
      case PostEditSubmitResponseKind.businessFailure:
      case PostEditSubmitResponseKind.authenticationFailure:
      case PostEditSubmitResponseKind.permissionFailure:
      case PostEditSubmitResponseKind.formExpired:
        return _result(
          PostEditSubmissionResolutionKind.unconfirmed,
          operation,
          attempt,
          detail: verification.detail,
        );
    }
  }
}

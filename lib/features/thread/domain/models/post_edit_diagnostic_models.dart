import 'package:y300/features/thread/domain/models/post_edit_models.dart';

/// Stable, locale-neutral reasons used by post-edit diagnostics.
///
/// These values are deliberately narrower than an exception message. They are
/// safe to aggregate and do not require retaining server HTML or user text.
enum PostEditContractReasonCode {
  invalidTarget,
  missingForm,
  duplicateForm,
  authenticationRequired,
  permissionDenied,
  postDeleted,
  invalidSubmitAction,
  missingCriticalControl,
  duplicateCriticalControl,
  targetMismatch,
  contractChanged,
  malformedAttachment,
  unsupportedSpecialThread,
  unsupportedThreadSort,
  unsupportedPluginField,
  unsupportedRegularAttachment,
  unsupportedHtmlMode,
  unknownSuccessfulControl,
  formExpired,
  ambiguousResult,
  partialSuccess,
  unconfirmed,
  networkFailure,
  readbackFailure,
  staleGeneration,
  cancelled,
}

final class PostEditContractDiagnosticEvent {
  const PostEditContractDiagnosticEvent({
    required this.operation,
    required this.reasonCode,
    required this.target,
    this.statusCode,
    this.elapsedMs,
    this.controlCount,
    this.controlNameDigest,
  });

  final String operation;
  final PostEditContractReasonCode reasonCode;
  final PostEditTarget target;
  final int? statusCode;
  final int? elapsedMs;
  final int? controlCount;
  final String? controlNameDigest;

  /// This is the only representation that may cross the logging boundary.
  /// It intentionally excludes edit URI, form fields, values and raw details.
  Map<String, Object?> toSafeLogFields() {
    return <String, Object?>{
      'operation': operation,
      'reason': reasonCode.name,
      'target': '${target.fid}/${target.tid}/${target.pid}',
      if (statusCode != null) 'status': statusCode,
      if (elapsedMs != null) 'elapsedMs': elapsedMs,
      if (controlCount != null) 'controlCount': controlCount,
      if (controlNameDigest != null) 'controlNameDigest': controlNameDigest,
    };
  }
}

abstract interface class PostEditContractDiagnosticRecorder {
  void record(PostEditContractDiagnosticEvent event);
}

final class NoopPostEditContractDiagnosticRecorder
    implements PostEditContractDiagnosticRecorder {
  const NoopPostEditContractDiagnosticRecorder();

  @override
  void record(PostEditContractDiagnosticEvent event) {}
}

import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/services/discuz_post_edit_delete_response_parser.dart';
import 'package:y300/features/thread/data/services/post_edit_form_parser.dart';
import 'package:y300/features/thread/data/services/post_edit_remote_data_source.dart';
import 'package:y300/features/thread/data/services/post_edit_submit_response_parser.dart';
import 'package:y300/features/thread/data/services/post_edit_contract_diagnostic_recorder.dart';
import 'package:y300/features/thread/domain/models/post_edit_diagnostic_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/repositories/post_edit_repository.dart';
import 'package:y300/features/thread/domain/services/post_edit_attachment_delete_uri_builder.dart';
import 'package:y300/features/thread/domain/services/post_edit_native_capability_classifier.dart';

class DiscuzPostEditRepository implements PostEditRepository {
  const DiscuzPostEditRepository({
    required PostEditRemoteDataSource remoteDataSource,
    this.formParser = const PostEditFormParser(),
    this.capabilityClassifier = const PostEditNativeCapabilityClassifier(),
    this.deleteUriBuilder = const PostEditAttachmentDeleteUriBuilder(),
    this.deleteResponseParser = const DiscuzPostEditDeleteResponseParser(),
    this.submitResponseParser = const PostEditSubmitResponseParser(),
    this.diagnosticRecorder = const NoopPostEditContractDiagnosticRecorder(),
  }) : _remoteDataSource = remoteDataSource;

  final PostEditRemoteDataSource _remoteDataSource;
  final PostEditFormParser formParser;
  final PostEditNativeCapabilityClassifier capabilityClassifier;
  final PostEditAttachmentDeleteUriBuilder deleteUriBuilder;
  final DiscuzPostEditDeleteResponseParser deleteResponseParser;
  final PostEditSubmitResponseParser submitResponseParser;
  final PostEditContractDiagnosticRecorder diagnosticRecorder;

  @override
  Future<ApiResult<PostEditPreparation>> loadForm(PostEditTarget target) async {
    final startedAt = DateTime.now();
    final remoteResult = await _remoteDataSource.get(target.editUri);
    if (remoteResult case ApiFailure<PostEditRemoteDocument>(:final error)) {
      _record(
        target: target,
        operation: 'load_form',
        reasonCode: _reasonForApiError(error),
        statusCode: error.statusCode,
        elapsedMs: _elapsedMs(startedAt),
      );
      return ApiFailure(error);
    }
    final remote = remoteResult.dataOrNull!;
    final parsed = formParser.parse(
      remote.html,
      target: target,
      sourceUri: remote.sourceUri,
    );
    if (parsed.snapshot == null) {
      _record(
        target: target,
        operation: 'parse_form',
        reasonCode: _reasonForParseFailure(parsed.failure),
        elapsedMs: _elapsedMs(startedAt),
      );
      return ApiSuccess(
        PostEditPreparation(
          target: target,
          decision: PostEditWebViewOnly(
            reason: _fallbackReason(parsed.failure),
          ),
        ),
      );
    }
    final snapshot = parsed.snapshot!;
    final decision = capabilityClassifier.classify(snapshot);
    if (decision case PostEditWebViewOnly(:final reason)) {
      _record(
        target: target,
        operation: 'classify_form',
        reasonCode: _reasonForFallback(reason),
        elapsedMs: _elapsedMs(startedAt),
        controlCount: snapshot.successfulControls.length,
        controlNameDigest: postEditControlNameDigest(
          snapshot.successfulControls.map((field) => field.name),
        ),
      );
    }
    return ApiSuccess(
      PostEditPreparation(
        target: target,
        snapshot: snapshot,
        decision: decision,
      ),
    );
  }

  @override
  Future<ApiResult<PostEditAttachmentDeleteResult>> deleteImage(
    PostEditAttachmentDeleteCommand command,
  ) async {
    final startedAt = DateTime.now();
    final remoteResult = await _remoteDataSource.deleteImage(
      deleteUriBuilder.build(command),
    );
    if (remoteResult case ApiFailure<PostEditRemoteDeleteDocument>(
      :final error,
    )) {
      _record(
        target: command.target,
        operation: 'delete_attachment',
        reasonCode: _reasonForApiError(error),
        statusCode: error.statusCode,
        elapsedMs: _elapsedMs(startedAt),
      );
      return ApiFailure(error);
    }
    final remote = remoteResult.dataOrNull!;
    final parsed = deleteResponseParser.parse(
      body: remote.body,
      aid: command.aid,
    );
    if (parsed.outcome != PostEditAttachmentDeleteOutcome.deleted) {
      _record(
        target: command.target,
        operation: 'delete_attachment',
        reasonCode: parsed.outcome == PostEditAttachmentDeleteOutcome.notDeleted
            ? PostEditContractReasonCode.unconfirmed
            : PostEditContractReasonCode.readbackFailure,
        elapsedMs: _elapsedMs(startedAt),
      );
    }
    return ApiSuccess(parsed);
  }

  @override
  Future<ApiResult<PostEditSubmitResponse>> submit(
    PostEditSubmitPayload payload, {
    required PostEditTarget target,
  }) async {
    final startedAt = DateTime.now();
    final remoteResult = await _remoteDataSource.submit(
      submitUri: payload.submitUri,
      fields: payload.fields,
    );
    if (remoteResult case ApiFailure<PostEditRemoteSubmitDocument>(
      :final error,
    )) {
      _record(
        target: target,
        operation: 'submit_form',
        reasonCode: _reasonForApiError(error),
        statusCode: error.statusCode,
        elapsedMs: _elapsedMs(startedAt),
      );
      return ApiFailure(error);
    }
    final remote = remoteResult.dataOrNull!;
    final parsed = submitResponseParser.parse(
      responseUri: remote.sourceUri,
      body: remote.body,
      target: target,
    );
    if (parsed.kind != PostEditSubmitResponseKind.confirmedSuccess) {
      _record(
        target: target,
        operation: 'submit_form',
        reasonCode: _reasonForSubmitResponse(parsed),
        statusCode: remote.statusCode,
        elapsedMs: _elapsedMs(startedAt),
      );
    }
    return ApiSuccess(parsed);
  }

  void _record({
    required PostEditTarget target,
    required String operation,
    required PostEditContractReasonCode reasonCode,
    int? statusCode,
    int? elapsedMs,
    int? controlCount,
    String? controlNameDigest,
  }) {
    try {
      diagnosticRecorder.record(
        PostEditContractDiagnosticEvent(
          operation: operation,
          reasonCode: reasonCode,
          target: target,
          statusCode: statusCode,
          elapsedMs: elapsedMs,
          controlCount: controlCount,
          controlNameDigest: controlNameDigest,
        ),
      );
    } catch (_) {
      // Diagnostics are best effort and must never change the repository
      // result or the editor state machine.
    }
  }

  int _elapsedMs(DateTime startedAt) {
    return DateTime.now().difference(startedAt).inMilliseconds;
  }

  PostEditContractReasonCode _reasonForApiError(ApiError error) {
    if (error.type == ApiErrorType.unauthorized) {
      return PostEditContractReasonCode.authenticationRequired;
    }
    final code = error.code?.trim().toLowerCase();
    if (code == 'post_deleted' || code == 'thread_deleted') {
      return PostEditContractReasonCode.postDeleted;
    }
    if (const <String>{
      'permission_denied',
      'permission',
      'nopermission',
      'postperm',
      'access_denied',
    }.contains(code)) {
      return PostEditContractReasonCode.permissionDenied;
    }
    return error.type == ApiErrorType.parse
        ? PostEditContractReasonCode.contractChanged
        : PostEditContractReasonCode.networkFailure;
  }

  PostEditContractReasonCode _reasonForParseFailure(
    PostEditFormParseFailureReason? failure,
  ) {
    return switch (failure) {
      PostEditFormParseFailureReason.missingForm =>
        PostEditContractReasonCode.missingForm,
      PostEditFormParseFailureReason.duplicateForm =>
        PostEditContractReasonCode.duplicateForm,
      PostEditFormParseFailureReason.authenticationRequired =>
        PostEditContractReasonCode.authenticationRequired,
      PostEditFormParseFailureReason.permissionDenied =>
        PostEditContractReasonCode.permissionDenied,
      PostEditFormParseFailureReason.postDeleted =>
        PostEditContractReasonCode.postDeleted,
      PostEditFormParseFailureReason.invalidSubmitAction =>
        PostEditContractReasonCode.invalidSubmitAction,
      PostEditFormParseFailureReason.missingCriticalControl =>
        PostEditContractReasonCode.missingCriticalControl,
      PostEditFormParseFailureReason.duplicateCriticalControl =>
        PostEditContractReasonCode.duplicateCriticalControl,
      PostEditFormParseFailureReason.targetMismatch =>
        PostEditContractReasonCode.targetMismatch,
      PostEditFormParseFailureReason.malformedAttachment =>
        PostEditContractReasonCode.malformedAttachment,
      PostEditFormParseFailureReason.invalidMethod ||
      PostEditFormParseFailureReason.invalidEnctype ||
      PostEditFormParseFailureReason.contractChanged ||
      null => PostEditContractReasonCode.contractChanged,
    };
  }

  PostEditContractReasonCode _reasonForFallback(PostEditFallbackReason reason) {
    return switch (reason) {
      PostEditFallbackReason.invalidTarget =>
        PostEditContractReasonCode.invalidTarget,
      PostEditFallbackReason.missingForm =>
        PostEditContractReasonCode.missingForm,
      PostEditFallbackReason.invalidSubmitAction =>
        PostEditContractReasonCode.invalidSubmitAction,
      PostEditFallbackReason.missingCriticalControl =>
        PostEditContractReasonCode.missingCriticalControl,
      PostEditFallbackReason.duplicateCriticalControl =>
        PostEditContractReasonCode.duplicateCriticalControl,
      PostEditFallbackReason.targetMismatch =>
        PostEditContractReasonCode.targetMismatch,
      PostEditFallbackReason.unsupportedSpecialThread =>
        PostEditContractReasonCode.unsupportedSpecialThread,
      PostEditFallbackReason.unsupportedThreadSort =>
        PostEditContractReasonCode.unsupportedThreadSort,
      PostEditFallbackReason.unsupportedPluginField =>
        PostEditContractReasonCode.unsupportedPluginField,
      PostEditFallbackReason.unsupportedRegularAttachment =>
        PostEditContractReasonCode.unsupportedRegularAttachment,
      PostEditFallbackReason.unsupportedHtmlMode =>
        PostEditContractReasonCode.unsupportedHtmlMode,
      PostEditFallbackReason.unknownSuccessfulControl =>
        PostEditContractReasonCode.unknownSuccessfulControl,
      PostEditFallbackReason.authenticationRequired =>
        PostEditContractReasonCode.authenticationRequired,
      PostEditFallbackReason.permissionDenied =>
        PostEditContractReasonCode.permissionDenied,
      PostEditFallbackReason.postDeleted =>
        PostEditContractReasonCode.postDeleted,
      PostEditFallbackReason.contractChanged =>
        PostEditContractReasonCode.contractChanged,
    };
  }

  PostEditContractReasonCode _reasonForSubmitResponse(
    PostEditSubmitResponse response,
  ) {
    final detail = response.detail?.toLowerCase();
    if (detail == 'post_deleted') {
      return PostEditContractReasonCode.postDeleted;
    }
    return switch (response.kind) {
      PostEditSubmitResponseKind.authenticationFailure =>
        PostEditContractReasonCode.authenticationRequired,
      PostEditSubmitResponseKind.permissionFailure =>
        PostEditContractReasonCode.permissionDenied,
      PostEditSubmitResponseKind.formExpired =>
        PostEditContractReasonCode.formExpired,
      PostEditSubmitResponseKind.partialSuccess =>
        PostEditContractReasonCode.partialSuccess,
      PostEditSubmitResponseKind.ambiguous =>
        PostEditContractReasonCode.ambiguousResult,
      PostEditSubmitResponseKind.businessFailure =>
        PostEditContractReasonCode.contractChanged,
      PostEditSubmitResponseKind.confirmedSuccess =>
        PostEditContractReasonCode.contractChanged,
    };
  }

  PostEditFallbackReason _fallbackReason(
    PostEditFormParseFailureReason? failure,
  ) {
    return switch (failure) {
      PostEditFormParseFailureReason.authenticationRequired =>
        PostEditFallbackReason.authenticationRequired,
      PostEditFormParseFailureReason.permissionDenied =>
        PostEditFallbackReason.permissionDenied,
      PostEditFormParseFailureReason.postDeleted =>
        PostEditFallbackReason.postDeleted,
      PostEditFormParseFailureReason.invalidSubmitAction =>
        PostEditFallbackReason.invalidSubmitAction,
      PostEditFormParseFailureReason.missingCriticalControl =>
        PostEditFallbackReason.missingCriticalControl,
      PostEditFormParseFailureReason.duplicateCriticalControl =>
        PostEditFallbackReason.duplicateCriticalControl,
      PostEditFormParseFailureReason.targetMismatch =>
        PostEditFallbackReason.targetMismatch,
      PostEditFormParseFailureReason.missingForm =>
        PostEditFallbackReason.missingForm,
      PostEditFormParseFailureReason.duplicateForm =>
        PostEditFallbackReason.contractChanged,
      PostEditFormParseFailureReason.invalidMethod ||
      PostEditFormParseFailureReason.invalidEnctype ||
      PostEditFormParseFailureReason.malformedAttachment ||
      PostEditFormParseFailureReason.contractChanged ||
      null => PostEditFallbackReason.contractChanged,
    };
  }
}

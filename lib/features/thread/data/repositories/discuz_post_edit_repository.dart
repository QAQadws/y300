import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/services/discuz_post_edit_delete_response_parser.dart';
import 'package:y300/features/thread/data/services/post_edit_form_parser.dart';
import 'package:y300/features/thread/data/services/post_edit_remote_data_source.dart';
import 'package:y300/features/thread/data/services/post_edit_submit_response_parser.dart';
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
  }) : _remoteDataSource = remoteDataSource;

  final PostEditRemoteDataSource _remoteDataSource;
  final PostEditFormParser formParser;
  final PostEditNativeCapabilityClassifier capabilityClassifier;
  final PostEditAttachmentDeleteUriBuilder deleteUriBuilder;
  final DiscuzPostEditDeleteResponseParser deleteResponseParser;
  final PostEditSubmitResponseParser submitResponseParser;

  @override
  Future<ApiResult<PostEditPreparation>> loadForm(PostEditTarget target) async {
    final remoteResult = await _remoteDataSource.get(target.editUri);
    if (remoteResult case ApiFailure<PostEditRemoteDocument>(:final error)) {
      return ApiFailure(error);
    }
    final remote = remoteResult.dataOrNull!;
    final parsed = formParser.parse(
      remote.html,
      target: target,
      sourceUri: remote.sourceUri,
    );
    if (parsed.snapshot == null) {
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
    return ApiSuccess(
      PostEditPreparation(
        target: target,
        snapshot: snapshot,
        decision: capabilityClassifier.classify(snapshot),
      ),
    );
  }

  @override
  Future<ApiResult<PostEditAttachmentDeleteResult>> deleteImage(
    PostEditAttachmentDeleteCommand command,
  ) async {
    final remoteResult = await _remoteDataSource.deleteImage(
      deleteUriBuilder.build(command),
    );
    if (remoteResult case ApiFailure<PostEditRemoteDeleteDocument>(
      :final error,
    )) {
      return ApiFailure(error);
    }
    final remote = remoteResult.dataOrNull!;
    return ApiSuccess(
      deleteResponseParser.parse(body: remote.body, aid: command.aid),
    );
  }

  @override
  Future<ApiResult<PostEditSubmitResponse>> submit(
    PostEditSubmitPayload payload, {
    required PostEditTarget target,
  }) async {
    final remoteResult = await _remoteDataSource.submit(
      submitUri: payload.submitUri,
      fields: payload.fields,
    );
    if (remoteResult case ApiFailure<PostEditRemoteSubmitDocument>(
      :final error,
    )) {
      return ApiFailure(error);
    }
    final remote = remoteResult.dataOrNull!;
    return ApiSuccess(
      submitResponseParser.parse(
        responseUri: remote.sourceUri,
        body: remote.body,
        target: target,
      ),
    );
  }

  PostEditFallbackReason _fallbackReason(
    PostEditFormParseFailureReason? failure,
  ) {
    return switch (failure) {
      PostEditFormParseFailureReason.authenticationRequired =>
        PostEditFallbackReason.authenticationRequired,
      PostEditFormParseFailureReason.permissionDenied =>
        PostEditFallbackReason.permissionDenied,
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

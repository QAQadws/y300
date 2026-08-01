import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/services/post_edit_form_parser.dart';
import 'package:y300/features/thread/data/services/post_edit_remote_data_source.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/repositories/post_edit_repository.dart';
import 'package:y300/features/thread/domain/services/post_edit_native_capability_classifier.dart';

class DiscuzPostEditRepository implements PostEditRepository {
  const DiscuzPostEditRepository({
    required PostEditRemoteDataSource remoteDataSource,
    this.formParser = const PostEditFormParser(),
    this.capabilityClassifier = const PostEditNativeCapabilityClassifier(),
  }) : _remoteDataSource = remoteDataSource;

  final PostEditRemoteDataSource _remoteDataSource;
  final PostEditFormParser formParser;
  final PostEditNativeCapabilityClassifier capabilityClassifier;

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

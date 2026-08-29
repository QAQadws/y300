import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_unused_image_repository.dart';

/// Y300 mapper over the package-owned unused attachment protocol.
final class PackageComposerUnusedImageRepository
    implements ComposerUnusedImageRepository {
  PackageComposerUnusedImageRepository({
    required ForumUnusedImageAttachmentDirectoryRepository directory,
    required ForumUnusedImageAttachmentDeleteCommand deleteCommand,
  }) : _directory = directory,
       _deleteCommand = deleteCommand;

  final ForumUnusedImageAttachmentDirectoryRepository _directory;
  final ForumUnusedImageAttachmentDeleteCommand _deleteCommand;
  final Map<String, ForumUnusedImageAttachmentDirectoryToken> _tokensByAid =
      <String, ForumUnusedImageAttachmentDirectoryToken>{};

  @override
  Future<ApiResult<List<ComposerUnusedImage>>> loadUnusedImages() async {
    final result = await _directory.load(
      const ForumUnusedImageAttachmentDirectoryRequest(),
    );
    return switch (result) {
      DataReadSuccess<
        ForumUnusedImageAttachmentDirectory,
        ForumUnusedImageAttachmentCapabilities
      >(
        :final data,
      ) =>
        _mapDirectory(data),
      DataReadFailure<
        ForumUnusedImageAttachmentDirectory,
        ForumUnusedImageAttachmentCapabilities
      >(
        :final kind,
        :final code,
        :final statusCode,
        :final diagnosticMessage,
      ) =>
        ApiFailure(
          ApiError(
            type: _errorType(kind),
            code: code,
            statusCode: statusCode,
            message: diagnosticMessage,
          ),
        ),
    };
  }

  ApiSuccess<List<ComposerUnusedImage>> _mapDirectory(
    ForumUnusedImageAttachmentDirectory data,
  ) {
    _tokensByAid
      ..clear()
      ..addEntries(data.items.map((item) => MapEntry(item.aid, data.token)));
    return ApiSuccess(
      List<ComposerUnusedImage>.unmodifiable(
        data.items.map(
          (item) => ComposerUnusedImage(
            aid: item.aid,
            thumbnailUri: item.thumbnail.uri,
            thumbnailRefererUri: item.thumbnail.referer,
            fileName: item.fileName,
            description: item.description,
          ),
        ),
      ),
    );
  }

  @override
  Future<ApiResult<ComposerUnusedImageDeleteResult>> deleteUnusedImage(
    String aid,
  ) async {
    final normalized = aid.trim();
    final token = _tokensByAid[normalized];
    if (token == null) {
      return const ApiFailure(
        ApiError(
          type: ApiErrorType.business,
          code: 'unused_attachment_proof_missing',
          message: 'unused_attachment_proof_missing',
        ),
      );
    }
    final result = await _deleteCommand.execute(
      DeleteUnusedImageAttachmentRequest(
        aid: normalized,
        directoryToken: token,
      ),
    );
    return switch (result) {
      DataCommandApplied<ForumImageAttachmentDeleteReceipt>(:final receipt) =>
        _deleted(normalized, receipt.deletedCount),
      DataCommandRejected<ForumImageAttachmentDeleteReceipt>() => ApiSuccess(
        ComposerUnusedImageDeleteResult(
          aid: normalized,
          outcome: ComposerUnusedImageDeleteOutcome.notDeleted,
        ),
      ),
      DataCommandNotSent<ForumImageAttachmentDeleteReceipt>(:final failure) ||
      DataCommandOutcomeUnknown<ForumImageAttachmentDeleteReceipt>(
        :final failure,
      ) ||
      DataCommandUnsupported<ForumImageAttachmentDeleteReceipt>(
        :final failure,
      ) => ApiFailure(
        ApiError(
          type: _commandErrorType(failure.kind),
          code: failure.code,
          statusCode: failure.statusCode,
          message: failure.diagnosticMessage,
        ),
      ),
    };
  }

  ApiSuccess<ComposerUnusedImageDeleteResult> _deleted(String aid, int count) {
    _tokensByAid.remove(aid);
    return ApiSuccess(
      ComposerUnusedImageDeleteResult(
        aid: aid,
        outcome: ComposerUnusedImageDeleteOutcome.deleted,
        deletedCount: count,
      ),
    );
  }
}

ApiErrorType _errorType(DataReadFailureKind kind) => switch (kind) {
  DataReadFailureKind.network => ApiErrorType.network,
  DataReadFailureKind.timeout => ApiErrorType.timeout,
  DataReadFailureKind.unauthorized => ApiErrorType.unauthorized,
  DataReadFailureKind.server => ApiErrorType.server,
  DataReadFailureKind.parse => ApiErrorType.parse,
  DataReadFailureKind.business ||
  DataReadFailureKind.unsupported => ApiErrorType.business,
  DataReadFailureKind.cancelled ||
  DataReadFailureKind.unknown => ApiErrorType.unknown,
};

ApiErrorType _commandErrorType(DataCommandFailureKind kind) => switch (kind) {
  DataCommandFailureKind.network => ApiErrorType.network,
  DataCommandFailureKind.timeout => ApiErrorType.timeout,
  DataCommandFailureKind.unauthenticated ||
  DataCommandFailureKind.staleFormhash => ApiErrorType.unauthorized,
  DataCommandFailureKind.server ||
  DataCommandFailureKind.securityChallenge => ApiErrorType.server,
  DataCommandFailureKind.parse => ApiErrorType.parse,
  DataCommandFailureKind.validation ||
  DataCommandFailureKind.permissionDenied ||
  DataCommandFailureKind.unsupported => ApiErrorType.business,
  DataCommandFailureKind.cancelled ||
  DataCommandFailureKind.unknown => ApiErrorType.unknown,
};

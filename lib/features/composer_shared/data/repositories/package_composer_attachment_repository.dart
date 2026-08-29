import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_attachment_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';

/// Maps the package attachment contract into Y300's editor attachment model.
final class PackageComposerAttachmentRepository
    implements
        ComposerAttachmentRepository,
        ComposerAttachmentUploadCancellation {
  PackageComposerAttachmentRepository({
    required ForumImageAttachmentUploadPreparationRepository preparation,
    required ForumImageAttachmentUploadCommand command,
    FileSystem fileSystem = const LocalFileSystem(),
    ComposerUploadCacheStorage cacheStorage =
        const NoopComposerUploadCacheStorage(),
    DateTime Function()? now,
  }) : _preparation = preparation,
       _command = command,
       _fileSystem = fileSystem,
       _cacheStorage = cacheStorage,
       _now = now ?? DateTime.now;

  final ForumImageAttachmentUploadPreparationRepository _preparation;
  final ForumImageAttachmentUploadCommand _command;
  final FileSystem _fileSystem;
  final ComposerUploadCacheStorage _cacheStorage;
  final DateTime Function() _now;
  ForumRequestCancellation? _activeCancellation;

  @override
  Future<ApiResult<ComposerImageUploadPermission>> prepareUpload({
    required String fid,
  }) async {
    final cancellation = ForumRequestCancellation();
    _activeCancellation = cancellation;
    final result = await _preparation.load(
      ForumImageAttachmentUploadPreparationRequest(
        fid: fid,
        cancellation: cancellation,
      ),
    );
    if (identical(_activeCancellation, cancellation)) {
      _activeCancellation = null;
    }
    return switch (result) {
      DataReadSuccess<
        ForumImageAttachmentUploadPreparation,
        ForumImageAttachmentUploadCapabilities
      >(
        :final data,
      ) =>
        ApiSuccess(
          ComposerImageUploadPermission(
            allowedExtensions: {
              for (final rule in data.extensionRules) rule.extension,
            },
            attachRemain: ComposerAttachRemain(
              size: data.remainingBytes ?? -1,
              count: data.remainingCount ?? -1,
            ),
            packagePreparation: data,
          ),
        ),
      DataReadFailure<
        ForumImageAttachmentUploadPreparation,
        ForumImageAttachmentUploadCapabilities
      >(
        :final kind,
        :final code,
        :final diagnosticMessage,
      ) =>
        ApiFailure(
          ApiError(
            type: _readErrorType(kind),
            code: _appFailureCode(code, kind: kind),
            message: diagnosticMessage,
          ),
        ),
    };
  }

  @override
  Future<ApiResult<ComposerUploadedImage>> uploadImage({
    required String fid,
    required ComposerImageUploadPermission permission,
    required ComposerImageAttachment attachment,
    void Function(double progress)? onProgress,
  }) async {
    final preparation = permission.packagePreparation;
    if (preparation == null || preparation.fid != fid.trim()) {
      return _failure(ComposerImageUploadFailureCode.permissionExpired);
    }
    final file = _fileSystem.file(attachment.localPath);
    if (!file.existsSync()) {
      return _failure(ComposerImageUploadFailureCode.fileMissing);
    }
    final cancellation = ForumRequestCancellation();
    _activeCancellation = cancellation;
    final result = await _command.execute(
      ForumImageAttachmentUploadSubmission(
        preparation: preparation,
        content: ForumImageAttachmentContent(
          fileName: _fileName(attachment),
          mimeType: attachment.mimeType,
          contentLength: file.lengthSync(),
          openRead: file.openRead,
        ),
        onProgress: onProgress,
        cancellation: cancellation,
      ),
    );
    if (identical(_activeCancellation, cancellation)) {
      _activeCancellation = null;
    }
    if (result case DataCommandApplied<ForumImageAttachmentUploadReceipt>(
      :final receipt,
    )) {
      String? cachePath;
      try {
        cachePath = await _cacheStorage.retainUploadedCopy(
          sourcePath: attachment.localPath,
          localId: attachment.localId,
          fileName: attachment.fileName,
        );
      } catch (_) {
        // Upload is already confirmed; local preview retention is best effort.
      }
      return ApiSuccess(
        ComposerUploadedImage(
          localId: attachment.localId,
          aid: receipt.aid,
          uploadedAt: _now(),
          cachePath: cachePath,
        ),
      );
    }
    final failure = result.failureOrNull!;
    return ApiFailure(
      ApiError(
        type: _commandErrorType(failure.kind),
        code: _appFailureCode(failure.code, kind: failure.kind),
        message: failure.diagnosticMessage,
        statusCode: failure.statusCode,
      ),
    );
  }

  @override
  void cancelActiveUpload() {
    _activeCancellation?.cancel();
    _activeCancellation = null;
  }

  ApiFailure<ComposerUploadedImage> _failure(
    ComposerImageUploadFailureCode code,
  ) => ApiFailure(
    ApiError(type: ApiErrorType.business, code: code.name, message: code.name),
  );

  String _fileName(ComposerImageAttachment attachment) {
    final explicit = attachment.fileName.trim();
    if (explicit.isNotEmpty) return explicit;
    final normalized = attachment.localPath.replaceAll('\\', '/');
    final value = normalized.split('/').last;
    return value.isEmpty ? 'upload-image' : value;
  }
}

ApiErrorType _readErrorType(DataReadFailureKind kind) => switch (kind) {
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
  DataCommandFailureKind.unauthenticated ||
  DataCommandFailureKind.staleFormhash => ApiErrorType.unauthorized,
  DataCommandFailureKind.network => ApiErrorType.network,
  DataCommandFailureKind.timeout => ApiErrorType.timeout,
  DataCommandFailureKind.server ||
  DataCommandFailureKind.securityChallenge => ApiErrorType.server,
  DataCommandFailureKind.parse => ApiErrorType.parse,
  DataCommandFailureKind.validation ||
  DataCommandFailureKind.permissionDenied ||
  DataCommandFailureKind.unsupported => ApiErrorType.business,
  DataCommandFailureKind.cancelled ||
  DataCommandFailureKind.unknown => ApiErrorType.unknown,
};

String _appFailureCode(String? packageCode, {required Enum kind}) {
  return switch (packageCode) {
    'attachment_extension_not_allowed' || 'attachment_extension_banned' =>
      ComposerImageUploadFailureCode.extensionNotAllowed.name,
    'attachment_upload_invalid' =>
      ComposerImageUploadFailureCode.invalidFileType.name,
    'attachment_group_file_size_exceeded' ||
    'attachment_extension_file_size_exceeded' =>
      ComposerImageUploadFailureCode.fileTooLarge.name,
    'attachment_upload_permission_denied' =>
      ComposerImageUploadFailureCode.permissionDenied.name,
    'attachment_invalid_image' =>
      ComposerImageUploadFailureCode.invalidImage.name,
    'attachment_save_failed' => ComposerImageUploadFailureCode.saveFailed.name,
    'attachment_upload_hash_invalid' ||
    'checkpost_upload_permission_invalid' ||
    'checkpost_session_identity_mismatch' =>
      ComposerImageUploadFailureCode.permissionExpired.name,
    'attachment_daily_quota_exceeded' || 'attachment_quota_exceeded' =>
      ComposerImageUploadFailureCode.quotaExceeded.name,
    'attachment_filename_rejected' =>
      ComposerImageUploadFailureCode.fileNameRejected.name,
    'attachment_dimensions_exceeded' =>
      ComposerImageUploadFailureCode.dimensionsExceeded.name,
    'attachment_upload_response_unconfirmed' =>
      ComposerImageUploadFailureCode.outcomeUnknown.name,
    _
        when kind == DataReadFailureKind.timeout ||
            kind == DataCommandFailureKind.timeout =>
      ComposerImageUploadFailureCode.timeout.name,
    _
        when kind == DataReadFailureKind.network ||
            kind == DataCommandFailureKind.network =>
      ComposerImageUploadFailureCode.network.name,
    _
        when kind == DataReadFailureKind.server ||
            kind == DataCommandFailureKind.server ||
            kind == DataCommandFailureKind.securityChallenge =>
      ComposerImageUploadFailureCode.server.name,
    _ => ComposerImageUploadFailureCode.unknown.name,
  };
}

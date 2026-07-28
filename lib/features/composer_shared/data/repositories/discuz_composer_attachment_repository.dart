import 'package:dio/dio.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/services/composer_attachment_remote_data_source.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_attachment_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';

class DiscuzComposerAttachmentRepository
    implements ComposerAttachmentRepository {
  DiscuzComposerAttachmentRepository({
    required ComposerAttachmentRemoteDataSource remoteDataSource,
    FileSystem fileSystem = const LocalFileSystem(),
    DateTime Function()? now,
  }) : _remoteDataSource = remoteDataSource,
       _fileSystem = fileSystem,
       _now = now ?? DateTime.now;

  final ComposerAttachmentRemoteDataSource _remoteDataSource;
  final FileSystem _fileSystem;
  final DateTime Function() _now;
  static const Set<String> _supportedImageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
  };

  @override
  Future<ApiResult<ComposerImageUploadPermission>> prepareUpload({
    required String fid,
  }) async {
    try {
      final permission = await _remoteDataSource.checkUploadPermission(
        fid: fid,
      );
      final validation = _validatePermission(permission);
      if (validation != null) {
        return ApiFailure<ComposerImageUploadPermission>(validation);
      }
      return ApiSuccess<ComposerImageUploadPermission>(permission);
    } on DioException catch (error) {
      return ApiFailure<ComposerImageUploadPermission>(_mapDioError(error));
    } catch (error) {
      return ApiFailure<ComposerImageUploadPermission>(
        ApiError(
          type: ApiErrorType.unknown,
          code: ComposerImageUploadFailureCode.unknown.name,
          message: error.toString(),
          raw: error,
        ),
      );
    }
  }

  @override
  Future<ApiResult<ComposerUploadedImage>> uploadImage({
    required String fid,
    required ComposerImageUploadPermission permission,
    required ComposerImageAttachment attachment,
    void Function(double progress)? onProgress,
  }) async {
    final permissionValidation = _validatePermission(permission);
    if (permissionValidation != null) {
      return ApiFailure<ComposerUploadedImage>(permissionValidation);
    }

    final file = _fileSystem.file(attachment.localPath);
    if (!file.existsSync()) {
      return const ApiFailure<ComposerUploadedImage>(
        ApiError(type: ApiErrorType.business, code: 'fileMissing', message: ''),
      );
    }

    if (!attachment.mimeType.toLowerCase().startsWith('image/')) {
      return const ApiFailure<ComposerUploadedImage>(
        ApiError(
          type: ApiErrorType.business,
          code: 'invalidFileType',
          message: '',
        ),
      );
    }

    final extension = _resolveExtension(attachment);
    if (!_supportedImageExtensions.contains(extension) ||
        !permission.canUploadExtension(extension)) {
      return ApiFailure<ComposerUploadedImage>(
        ApiError(
          type: ApiErrorType.business,
          code: ComposerImageUploadFailureCode.extensionNotAllowed.name,
          message: extension,
        ),
      );
    }

    try {
      final response = await _remoteDataSource.uploadImage(
        fid: fid,
        permission: permission,
        file: ComposerLocalImageFile(
          path: attachment.localPath,
          fileName: _resolveFileName(attachment),
          mimeType: attachment.mimeType,
        ),
        onSendProgress: (sent, total) {
          if (onProgress == null || total <= 0) {
            return;
          }
          onProgress((sent / total).clamp(0, 1).toDouble());
        },
      );
      final aid = _parsePositiveAid(response.aid);
      if (aid == null) {
        return ApiFailure<ComposerUploadedImage>(
          ApiError(
            type: ApiErrorType.business,
            code: ComposerImageUploadFailureCode.server.name,
            message: '',
            raw: response.rawBody,
            statusCode: response.statusCode,
          ),
        );
      }
      return ApiSuccess<ComposerUploadedImage>(
        ComposerUploadedImage(
          localId: attachment.localId,
          aid: aid,
          uploadedAt: _now(),
        ),
      );
    } on DioException catch (error) {
      return ApiFailure<ComposerUploadedImage>(_mapDioError(error));
    } catch (error) {
      return ApiFailure<ComposerUploadedImage>(
        ApiError(
          type: ApiErrorType.unknown,
          code: ComposerImageUploadFailureCode.unknown.name,
          message: error.toString(),
          raw: error,
        ),
      );
    }
  }

  ApiError? _validatePermission(ComposerImageUploadPermission permission) {
    if (permission.uid.trim().isEmpty || permission.uploadHash.trim().isEmpty) {
      return ApiError(
        type: ApiErrorType.business,
        code: ComposerImageUploadFailureCode.permissionExpired.name,
        message: '',
      );
    }
    if (!permission.allowedExtensions.any(
      (extension) => _supportedImageExtensions.contains(
        extension.trim().toLowerCase().replaceFirst('.', ''),
      ),
    )) {
      return ApiError(
        type: ApiErrorType.business,
        code: ComposerImageUploadFailureCode.extensionNotAllowed.name,
        message: '',
      );
    }
    if (!permission.attachRemain.hasSizeRemain ||
        !permission.attachRemain.hasCountRemain) {
      return ApiError(
        type: ApiErrorType.business,
        code: ComposerImageUploadFailureCode.quotaExceeded.name,
        message: '',
      );
    }
    return null;
  }

  String? _parsePositiveAid(String rawAid) {
    final value = rawAid.trim();
    if (value.isEmpty) {
      return null;
    }
    final aid = int.tryParse(value);
    if (aid == null || aid <= 0) {
      return null;
    }
    return value;
  }

  String _resolveExtension(ComposerImageAttachment attachment) {
    final source = attachment.fileName.trim().isNotEmpty
        ? attachment.fileName
        : attachment.localPath;
    final normalized = source.replaceAll('\\', '/');
    final fileName = normalized.substring(normalized.lastIndexOf('/') + 1);
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  String _resolveFileName(ComposerImageAttachment attachment) {
    final fileName = attachment.fileName.trim();
    if (fileName.isNotEmpty) {
      return fileName;
    }
    final normalized = attachment.localPath.replaceAll('\\', '/');
    final fallback = normalized.substring(normalized.lastIndexOf('/') + 1);
    return fallback.isNotEmpty ? fallback : 'upload-image';
  }

  ApiError _mapDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiError(
        type: ApiErrorType.timeout,
        code: ComposerImageUploadFailureCode.timeout.name,
        message: error.message ?? '',
        statusCode: statusCode,
        raw: error.response?.data,
      );
    }
    if (statusCode == 401 || statusCode == 403) {
      return ApiError(
        type: ApiErrorType.unauthorized,
        code: ComposerImageUploadFailureCode.permissionExpired.name,
        message: error.message ?? '',
        statusCode: statusCode,
        raw: error.response?.data,
      );
    }
    if (statusCode != null && statusCode >= 500) {
      return ApiError(
        type: ApiErrorType.server,
        code: ComposerImageUploadFailureCode.server.name,
        message: error.message ?? '',
        statusCode: statusCode,
        raw: error.response?.data,
      );
    }
    return ApiError(
      type: ApiErrorType.network,
      code: ComposerImageUploadFailureCode.network.name,
      message: error.message ?? '',
      statusCode: statusCode,
      raw: error.response?.data,
    );
  }
}

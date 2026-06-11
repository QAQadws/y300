import 'package:dio/dio.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/composer_attachment_remote_data_source.dart';
import 'package:y300/features/composer_shared/data/composer_attachment_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

class DiscuzComposerAttachmentRepository implements ComposerAttachmentRepository {
  DiscuzComposerAttachmentRepository({
    required ComposerAttachmentRemoteDataSource remoteDataSource,
    FileSystem fileSystem = const LocalFileSystem(),
    DateTime Function()? now,
  })  : _remoteDataSource = remoteDataSource,
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
      final permission =
          await _remoteDataSource.checkUploadPermission(fid: fid);
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
          message: '获取上传权限失败：$error',
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
        ApiError(type: ApiErrorType.business, message: '图片文件不存在，无法上传'),
      );
    }

    if (!attachment.mimeType.toLowerCase().startsWith('image/')) {
      return const ApiFailure<ComposerUploadedImage>(
        ApiError(type: ApiErrorType.business, message: '只能上传图片文件'),
      );
    }

    final extension = _resolveExtension(attachment);
    if (!_supportedImageExtensions.contains(extension) ||
        !permission.canUploadExtension(extension)) {
      return ApiFailure<ComposerUploadedImage>(
        ApiError(
          type: ApiErrorType.business,
          message: '当前版块不允许上传 ${extension.isEmpty ? '该类型' : extension} 图片',
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
            message: '图片上传失败',
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
          message: '上传图片失败：$error',
          raw: error,
        ),
      );
    }
  }

  ApiError? _validatePermission(ComposerImageUploadPermission permission) {
    if (permission.uid.trim().isEmpty || permission.uploadHash.trim().isEmpty) {
      return const ApiError(
        type: ApiErrorType.business,
        message: '上传权限无效，请重新登录后再试',
      );
    }
    if (!permission.allowedExtensions.any(
      (extension) => _supportedImageExtensions.contains(
        extension.trim().toLowerCase().replaceFirst('.', ''),
      ),
    )) {
      return const ApiError(
        type: ApiErrorType.business,
        message: '当前版块不允许上传图片',
      );
    }
    if (!permission.attachRemain.hasSizeRemain ||
        !permission.attachRemain.hasCountRemain) {
      return const ApiError(
        type: ApiErrorType.business,
        message: '附件额度不足，无法上传图片',
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
        message: error.message ?? '上传图片超时',
        statusCode: statusCode,
        raw: error.response?.data,
      );
    }
    if (statusCode == 401 || statusCode == 403) {
      return ApiError(
        type: ApiErrorType.unauthorized,
        message: error.message ?? '上传权限已失效，请重新登录',
        statusCode: statusCode,
        raw: error.response?.data,
      );
    }
    if (statusCode != null && statusCode >= 500) {
      return ApiError(
        type: ApiErrorType.server,
        message: error.message ?? '上传服务异常',
        statusCode: statusCode,
        raw: error.response?.data,
      );
    }
    return ApiError(
      type: ApiErrorType.network,
      message: error.message ?? '网络异常，图片上传失败',
      statusCode: statusCode,
      raw: error.response?.data,
    );
  }
}

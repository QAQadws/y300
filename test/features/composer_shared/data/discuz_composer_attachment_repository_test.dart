import 'package:dio/dio.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/services/composer_attachment_remote_data_source.dart';
import 'package:y300/features/composer_shared/data/repositories/discuz_composer_attachment_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

void main() {
  group('DiscuzComposerAttachmentRepository', () {
    test('prepareUpload returns permission when checkpost is valid', () async {
      final repository = _buildRepository(
        remoteDataSource: _FakeUploadRemoteDataSource(
          permission: _permission(),
        ),
      );

      final result = await repository.prepareUpload(fid: '33');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.uid, '597454');
      expect(result.dataOrNull?.uploadHash, 'upload-hash');
    });

    test('prepareUpload fails when uid is empty', () async {
      final repository = _buildRepository(
        remoteDataSource: _FakeUploadRemoteDataSource(
          permission: _permission(uid: ''),
        ),
      );

      final result = await repository.prepareUpload(fid: '33');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.business);
      expect(result.errorOrNull?.message, contains('上传权限无效'));
    });

    test('prepareUpload fails when upload hash is empty', () async {
      final repository = _buildRepository(
        remoteDataSource: _FakeUploadRemoteDataSource(
          permission: _permission(uploadHash: ''),
        ),
      );

      final result = await repository.prepareUpload(fid: '33');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('上传权限无效'));
    });

    test('prepareUpload fails when no image extension is allowed', () async {
      final repository = _buildRepository(
        remoteDataSource: _FakeUploadRemoteDataSource(
          permission: _permission(allowedExtensions: <String>{}),
        ),
      );

      final result = await repository.prepareUpload(fid: '33');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('不允许上传图片'));
    });

    test('prepareUpload fails when attach remain is exhausted', () async {
      final repository = _buildRepository(
        remoteDataSource: _FakeUploadRemoteDataSource(
          permission: _permission(
            attachRemain: const ComposerAttachRemain(size: -1, count: 0),
          ),
        ),
      );

      final result = await repository.prepareUpload(fid: '33');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('附件额度不足'));
    });

    test('uploadImage fails when local file does not exist', () async {
      final fileSystem = MemoryFileSystem();
      final repository = _buildRepository(
        remoteDataSource: _FakeUploadRemoteDataSource(),
        fileSystem: fileSystem,
      );

      final result = await repository.uploadImage(
        fid: '33',
        permission: _permission(),
        attachment: _attachment(localPath: '/gallery/missing.jpg'),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('图片文件不存在'));
    });

    test('uploadImage fails when mime is not image', () async {
      final fileSystem = _fileSystemWithFile('/gallery/file.txt');
      final repository = _buildRepository(
        remoteDataSource: _FakeUploadRemoteDataSource(),
        fileSystem: fileSystem,
      );

      final result = await repository.uploadImage(
        fid: '33',
        permission: _permission(),
        attachment: _attachment(
          localPath: '/gallery/file.txt',
          fileName: 'file.txt',
          mimeType: 'text/plain',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('只能上传图片'));
    });

    test('uploadImage fails when extension is not allowed', () async {
      final fileSystem = _fileSystemWithFile('/gallery/photo.webp');
      final repository = _buildRepository(
        remoteDataSource: _FakeUploadRemoteDataSource(),
        fileSystem: fileSystem,
      );

      final result = await repository.uploadImage(
        fid: '33',
        permission: _permission(allowedExtensions: {'jpg'}),
        attachment: _attachment(
          localPath: '/gallery/photo.webp',
          fileName: 'photo.webp',
          mimeType: 'image/webp',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('不允许上传'));
    });

    test('uploadImage returns uploaded image when remote returns positive aid',
        () async {
      final fileSystem = _fileSystemWithFile('/gallery/photo.jpg');
      final remoteDataSource = _FakeUploadRemoteDataSource(
        uploadResponse: const ComposerImageUploadResponse(
          aid: '123456',
          rawBody: '123456',
          statusCode: 200,
        ),
      );
      final now = DateTime(2026, 6, 8, 12);
      final repository = _buildRepository(
        remoteDataSource: remoteDataSource,
        fileSystem: fileSystem,
        now: () => now,
      );
      double? progress;

      final result = await repository.uploadImage(
        fid: '33',
        permission: _permission(),
        attachment: _attachment(localPath: '/gallery/photo.jpg'),
        onProgress: (value) => progress = value,
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.localId, 'local-1');
      expect(result.dataOrNull?.aid, '123456');
      expect(result.dataOrNull?.uploadedAt, now);
      expect(remoteDataSource.uploadedFiles.single.fileName, 'photo.jpg');
      expect(remoteDataSource.uploadedFiles.single.mimeType, 'image/jpeg');
      expect(progress, 0.5);
    });

    test('uploadImage fails when remote aid is negative non-number or empty',
        () async {
      for (final rawAid in <String>['-1', 'not-aid', '']) {
        final fileSystem = _fileSystemWithFile('/gallery/photo.jpg');
        final repository = _buildRepository(
          remoteDataSource: _FakeUploadRemoteDataSource(
            uploadResponse: ComposerImageUploadResponse(
              aid: rawAid,
              rawBody: rawAid,
              statusCode: 200,
            ),
          ),
          fileSystem: fileSystem,
        );

        final result = await repository.uploadImage(
          fid: '33',
          permission: _permission(),
          attachment: _attachment(localPath: '/gallery/photo.jpg'),
        );

        expect(result.isFailure, isTrue);
        expect(result.errorOrNull?.type, ApiErrorType.business);
      }
    });

    test('maps dio timeout to timeout failure', () async {
      final fileSystem = _fileSystemWithFile('/gallery/photo.jpg');
      final repository = _buildRepository(
        remoteDataSource: _FakeUploadRemoteDataSource(
          uploadException: DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionTimeout,
            message: 'timeout',
          ),
        ),
        fileSystem: fileSystem,
      );

      final result = await repository.uploadImage(
        fid: '33',
        permission: _permission(),
        attachment: _attachment(localPath: '/gallery/photo.jpg'),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.timeout);
    });

    test('maps unauthorized and server dio responses', () async {
      for (final entry in <int, ApiErrorType>{
        403: ApiErrorType.unauthorized,
        500: ApiErrorType.server,
      }.entries) {
        final fileSystem = _fileSystemWithFile('/gallery/photo.jpg');
        final repository = _buildRepository(
          remoteDataSource: _FakeUploadRemoteDataSource(
            uploadException: DioException(
              requestOptions: RequestOptions(path: '/'),
              response: Response<dynamic>(
                requestOptions: RequestOptions(path: '/'),
                statusCode: entry.key,
                data: 'error',
              ),
            ),
          ),
          fileSystem: fileSystem,
        );

        final result = await repository.uploadImage(
          fid: '33',
          permission: _permission(),
          attachment: _attachment(localPath: '/gallery/photo.jpg'),
        );

        expect(result.isFailure, isTrue);
        expect(result.errorOrNull?.type, entry.value);
        expect(result.errorOrNull?.statusCode, entry.key);
      }
    });
  });
}

DiscuzComposerAttachmentRepository _buildRepository({
  required ComposerAttachmentRemoteDataSource remoteDataSource,
  FileSystem? fileSystem,
  DateTime Function()? now,
}) {
  return DiscuzComposerAttachmentRepository(
    remoteDataSource: remoteDataSource,
    fileSystem: fileSystem ?? MemoryFileSystem(),
    now: now ?? DateTime.now,
  );
}

MemoryFileSystem _fileSystemWithFile(String path) {
  final fileSystem = MemoryFileSystem();
  final file = fileSystem.file(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(<int>[1, 2, 3]);
  return fileSystem;
}

ComposerImageUploadPermission _permission({
  String uid = '597454',
  String uploadHash = 'upload-hash',
  Set<String> allowedExtensions = const {'jpg', 'jpeg', 'png', 'gif'},
  ComposerAttachRemain attachRemain =
      const ComposerAttachRemain(size: -1, count: -1),
}) {
  return ComposerImageUploadPermission(
    uid: uid,
    uploadHash: uploadHash,
    allowedExtensions: allowedExtensions,
    attachRemain: attachRemain,
  );
}

ComposerImageAttachment _attachment({
  String localPath = '/gallery/photo.jpg',
  String fileName = 'photo.jpg',
  String mimeType = 'image/jpeg',
}) {
  return ComposerImageAttachment(
    localId: 'local-1',
    localPath: localPath,
    fileName: fileName,
    mimeType: mimeType,
    order: 0,
    status: ComposerImageAttachmentStatus.local,
  );
}

class _FakeUploadRemoteDataSource
    implements ComposerAttachmentRemoteDataSource {
  _FakeUploadRemoteDataSource({
    ComposerImageUploadPermission? permission,
    this.uploadResponse = const ComposerImageUploadResponse(
      aid: '123456',
      rawBody: '123456',
      statusCode: 200,
    ),
    this.uploadException,
  }) : permission = permission ?? _permission();

  final ComposerImageUploadPermission permission;
  final ComposerImageUploadResponse uploadResponse;
  final Object? uploadException;
  final List<ComposerLocalImageFile> uploadedFiles = <ComposerLocalImageFile>[];

  @override
  Future<ComposerImageUploadPermission> checkUploadPermission({
    required String fid,
  }) async {
    return permission;
  }

  @override
  Future<ComposerImageUploadResponse> uploadImage({
    required String fid,
    required ComposerImageUploadPermission permission,
    required ComposerLocalImageFile file,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final exception = uploadException;
    if (exception != null) {
      throw exception;
    }
    uploadedFiles.add(file);
    onSendProgress?.call(5, 10);
    return uploadResponse;
  }
}

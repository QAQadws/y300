import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/reader_shared/data/export/default_reader_image_export_service.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('y300-reader-export-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test(
    'resolves magic bytes, sanitizes name and delegates original file',
    () async {
      final file = File('${directory.path}/cached.bin');
      await file.writeAsBytes(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      final cache = _FakeImageCacheService(file.path);
      final sink = _RecordingExportSink();
      final service = DefaultReaderImageExportService(
        imageCacheService: cache,
        sink: sink,
      );

      final result = await service.export(
        _request(
          baseName: '作品/第 1 话:*',
          sourceUrl: 'https://img.test/download?format=jpg',
        ),
      );

      expect(result.success, isTrue);
      expect(sink.sourcePaths.single, file.path);
      expect(sink.mimeTypes.single, 'image/png');
      expect(sink.displayNames.single, '作品_第 1 话__.png');
    },
  );

  test('returns cacheUnavailable when cache has no usable file', () async {
    final service = DefaultReaderImageExportService(
      imageCacheService: _FakeImageCacheService(null),
      sink: _RecordingExportSink(),
    );

    final result = await service.export(_request());

    expect(result.success, isFalse);
    expect(
      result.failureReason,
      ReaderImageExportFailureReason.cacheUnavailable,
    );
  });

  test('maps cache service exceptions to cacheUnavailable', () async {
    final service = DefaultReaderImageExportService(
      imageCacheService: _ThrowingImageCacheService(),
      sink: _RecordingExportSink(),
    );

    final result = await service.export(_request());

    expect(result.success, isFalse);
    expect(
      result.failureReason,
      ReaderImageExportFailureReason.cacheUnavailable,
    );
  });

  test('deduplicates concurrent export of the same item', () async {
    final file = File('${directory.path}/cached.jpg');
    await file.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
    final sink = _BlockingExportSink();
    final service = DefaultReaderImageExportService(
      imageCacheService: _FakeImageCacheService(file.path),
      sink: sink,
    );
    final request = _request();

    final first = service.export(request);
    final second = service.export(request);
    expect(identical(first, second), isTrue);
    expect(sink.callCount, 0);

    sink.complete();
    await Future.wait(<Future<ReaderImageExportResult>>[first, second]);
    expect(sink.callCount, 1);
  });
}

ReaderImageExportRequest _request({
  String baseName = 'thread-image',
  String sourceUrl = 'https://img.test/image.jpg',
}) {
  return ReaderImageExportRequest(
    cacheRequest: ImageCacheRequest(
      cacheKey: 'reader-image',
      sourceUrl: sourceUrl,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: 'thread:1',
      role: ImageCacheRole.threadInline,
    ),
    metadata: ReaderImageExportMetadata(baseName: baseName),
  );
}

class _RecordingExportSink implements ReaderImageExportSink {
  final sourcePaths = <String>[];
  final displayNames = <String>[];
  final mimeTypes = <String>[];

  @override
  Future<ReaderImageExportDestination> save({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    String? albumName,
  }) async {
    sourcePaths.add(sourcePath);
    displayNames.add(displayName);
    mimeTypes.add(mimeType);
    return const ReaderImageExportDestination(
      platform: ReaderImageExportPlatform.android,
      locator: 'content://media/1',
      displayLocation: 'Pictures/Y300',
    );
  }
}

class _BlockingExportSink implements ReaderImageExportSink {
  final completer = Completer<ReaderImageExportDestination>();
  var callCount = 0;

  void complete() {
    completer.complete(
      const ReaderImageExportDestination(
        platform: ReaderImageExportPlatform.ios,
        locator: 'asset-id',
        displayLocation: '系统照片',
      ),
    );
  }

  @override
  Future<ReaderImageExportDestination> save({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    String? albumName,
  }) {
    callCount += 1;
    return completer.future;
  }
}

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService(this.localPath);

  final String? localPath;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: localPath != null,
      cacheKey: request.cacheKey,
      localPath: localPath,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async => CachedImageResult.failed;

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async => 0;
}

class _ThrowingImageCacheService extends _FakeImageCacheService {
  _ThrowingImageCacheService() : super(null);

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    throw const FileSystemException('cache unavailable');
  }
}

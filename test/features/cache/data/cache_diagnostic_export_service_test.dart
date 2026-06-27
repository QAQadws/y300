import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/cache_diagnostic_export_service.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

void main() {
  test('exports storage usage report as diagnostics json', () async {
    final root = await io.Directory.systemTemp.createTemp(
      'cache-diagnostic-export-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final service = JsonCacheDiagnosticExportService(
      storageService: _FakeDownloadStorageService(root.path),
      now: () => DateTime.utc(2026, 6, 27, 12),
    );
    final report = StorageUsageReport.fromSections(
      sections: const <StorageUsageSection>[
        StorageUsageSection(
          bucket: StorageBucket.imageCache,
          label: '图片缓存',
          bytes: 1024,
          clearable: true,
          slices: <StorageUsageSlice>[
            StorageUsageSlice(
              id: 'image:thread',
              label: '帖子图片',
              bytes: 1024,
              protected: false,
            ),
          ],
        ),
      ],
      calculatedAt: DateTime.utc(2026, 6, 27, 11),
    );

    final result = await service.exportUsageReport(report);

    expect(result.path, contains('cache-diagnostics-'));
    final file = io.File(result.path);
    expect(await file.exists(), isTrue);
    final payload =
        jsonDecode(await file.readAsString(encoding: utf8))
            as Map<String, dynamic>;
    expect(payload['totalBytes'], 1024);
    final sections = payload['sections'] as List<dynamic>;
    expect((sections.single as Map<String, dynamic>)['bucket'], 'image_cache');
  });
}

class _FakeDownloadStorageService implements DownloadStorageService {
  const _FakeDownloadStorageService(this.rootPath);

  final String rootPath;

  @override
  Future<DownloadStorageRoot> prepareRoot() async {
    return DownloadStorageRoot(
      path: rootPath,
      comicsPath: '$rootPath/comics',
      novelsPath: '$rootPath/novels',
      favoritesJsonPath: '$rootPath/favorites.json',
    );
  }

  @override
  Future<io.Directory> prepareComicDirectory({
    required String workId,
    required String title,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<io.Directory> prepareNovelDirectory({
    required String novelId,
    required String title,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> deleteComicDownloads({required String workId}) async => false;

  @override
  Future<bool> deleteNovelDownloads({required String novelId}) async => false;

  @override
  String safeFileName(String value, {String fallback = 'untitled'}) => value;

  @override
  String numberedFileName({
    required int index,
    required String title,
    required String extension,
  }) => title;

  @override
  Future<void> writeJsonAtomically(io.File file, Object? value) {
    throw UnimplementedError();
  }

  @override
  Future<void> writeFavoritesSnapshot(Map<String, Object?> json) {
    throw UnimplementedError();
  }

  @override
  Future<DownloadedComicEpisode?> findDownloadedComicEpisode({
    required String workId,
    required String title,
    required String episodeId,
  }) async {
    return null;
  }

  @override
  Future<DownloadedNovelChapter?> findDownloadedNovelChapter({
    required String novelId,
    required String title,
    required String episodeId,
  }) async {
    return null;
  }
}

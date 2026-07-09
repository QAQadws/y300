import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/more/data/data_storage_settings_repository.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/more/presentation/data_storage_page.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/more/presentation/data_storage_formatters.dart';

void main() {
  testWidgets('DataStoragePage builds dark theme chrome', (tester) async {
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: '/tmp/default-downloads',
      customPath: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          cacheMaintenanceServiceProvider.overrideWithValue(
            _FakeCacheMaintenanceService(),
          ),
          storageAccountingServiceProvider.overrideWithValue(
            _FakeStorageAccountingService(),
          ),
          cacheDiagnosticExportServiceProvider.overrideWithValue(
            _FakeCacheDiagnosticExportService(),
          ),
          downloadStorageServiceProvider.overrideWithValue(
            _FakeDownloadStorageService(repo: repo),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const DataStoragePage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.byKey(const Key('data-storage-image-cache-max-slider')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('data-storage-choose-directory-button')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('data-storage-choose-directory-button')),
      findsOneWidget,
    );
  });

  testWidgets(
    'DataStoragePage renders default and effective storage directory',
    (tester) async {
      final repo = _FakeDataStorageSettingsRepository(
        defaultPath: '/tmp/default-downloads',
        customPath: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
            cacheMaintenanceServiceProvider.overrideWithValue(
              _FakeCacheMaintenanceService(),
            ),
            storageAccountingServiceProvider.overrideWithValue(
              _FakeStorageAccountingService(),
            ),
            cacheDiagnosticExportServiceProvider.overrideWithValue(
              _FakeCacheDiagnosticExportService(),
            ),
            downloadStorageServiceProvider.overrideWithValue(
              _FakeDownloadStorageService(repo: repo),
            ),
          ],
          child: const MaterialApp(home: DataStoragePage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('data-storage-default-directory')),
        findsOneWidget,
      );
      expect(find.text('/tmp/default-downloads'), findsNWidgets(2));
      expect(
        find.byKey(const Key('data-storage-custom-directory')),
        findsNothing,
      );
    },
  );

  testWidgets('DataStoragePage renders storage usage report sections', (
    tester,
  ) async {
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: '/tmp/default-downloads',
      customPath: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          cacheMaintenanceServiceProvider.overrideWithValue(
            _FakeCacheMaintenanceService(),
          ),
          storageAccountingServiceProvider.overrideWithValue(
            _FakeStorageAccountingService(
              report: _usageReport(
                sections: const <StorageUsageSection>[
                  StorageUsageSection(
                    bucket: StorageBucket.imageCache,
                    label: '图片缓存',
                    bytes: 4096,
                    clearable: true,
                    categories: <StorageUsageCategory>[
                      StorageUsageCategory(
                        id: 'clearable',
                        label: '可清缓存',
                        bytes: 1024,
                        clearable: true,
                        protected: false,
                      ),
                      StorageUsageCategory(
                        id: 'sticky',
                        label: '长期缓存',
                        bytes: 2048,
                        clearable: false,
                        protected: false,
                      ),
                      StorageUsageCategory(
                        id: 'protected',
                        label: '受保护/下载内容',
                        bytes: 1024,
                        clearable: false,
                        protected: true,
                      ),
                    ],
                    slices: <StorageUsageSlice>[
                      StorageUsageSlice(
                        id: 'image:thread',
                        label: '帖子图片',
                        bytes: 1024,
                        protected: false,
                      ),
                    ],
                  ),
                  StorageUsageSection(
                    bucket: StorageBucket.libraryMetadata,
                    label: '书架数据',
                    bytes: 2048,
                    clearable: false,
                  ),
                ],
              ),
            ),
          ),
          cacheDiagnosticExportServiceProvider.overrideWithValue(
            _FakeCacheDiagnosticExportService(),
          ),
          downloadStorageServiceProvider.overrideWithValue(
            _FakeDownloadStorageService(repo: repo),
          ),
        ],
        child: const MaterialApp(home: DataStoragePage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-storage-usage-overview')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('data-storage-usage-total')), findsOneWidget);
    expect(find.text('缓存与数据总览'), findsOneWidget);
    expect(find.text('总计：6.0 KB'), findsOneWidget);
    expect(
      tester
          .widget<ExpansionTile>(
            find.byKey(const Key('data-storage-usage-overview')),
          )
          .subtitle,
      isNull,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('data-storage-usage-total'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('data-storage-cache-usage'))).dy,
      ),
    );

    // 总览默认收起：section/slice 尚未构建。
    expect(
      find.byKey(const Key('data-storage-usage-section-image_cache')),
      findsNothing,
    );

    // 展开后 section/slice 可见。
    await tester.tap(find.byKey(const Key('data-storage-usage-overview')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-storage-usage-section-image_cache')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-storage-usage-section-library_metadata')),
      findsOneWidget,
    );
    expect(find.text('帖子图片'), findsOneWidget);
    expect(
      find.byKey(const Key('data-storage-image-cache-category-clearable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-storage-image-cache-category-sticky')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-storage-image-cache-category-protected')),
      findsOneWidget,
    );
  });

  testWidgets(
    'DataStoragePage chooses custom storage directory and shows hint',
    (tester) async {
      final repo = _FakeDataStorageSettingsRepository(
        defaultPath: '/tmp/default-downloads',
        customPath: null,
        pickedPath: '/mnt/y300-downloads',
      );
      final storage = _FakeDownloadStorageService(repo: repo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
            cacheMaintenanceServiceProvider.overrideWithValue(
              _FakeCacheMaintenanceService(),
            ),
            storageAccountingServiceProvider.overrideWithValue(
              _FakeStorageAccountingService(),
            ),
            cacheDiagnosticExportServiceProvider.overrideWithValue(
              _FakeCacheDiagnosticExportService(),
            ),
            downloadStorageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(home: DataStoragePage()),
        ),
      );

      await tester.pumpAndSettle();
      final chooseButton = find.byKey(
        const Key('data-storage-choose-directory-button'),
      );
      await tester.scrollUntilVisible(
        chooseButton,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(chooseButton);
      await _tapVisibleCenter(tester, chooseButton);
      await tester.pumpAndSettle();

      final customDirectory = find.byKey(
        const Key('data-storage-custom-directory'),
      );
      await tester.scrollUntilVisible(
        customDirectory,
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(customDirectory, findsOneWidget);
      expect(find.text('/mnt/y300-downloads'), findsAtLeastNWidgets(1));
      expect(storage.prepareRootCalls, 2);

      await tester.scrollUntilVisible(
        find.byKey(const Key('data-storage-hint-text')),
        120,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('存储位置已更新'), findsOneWidget);
    },
  );

  testWidgets('DataStoragePage restores default storage directory', (
    tester,
  ) async {
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: '/tmp/default-downloads',
      customPath: '/mnt/y300-downloads',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          cacheMaintenanceServiceProvider.overrideWithValue(
            _FakeCacheMaintenanceService(),
          ),
          storageAccountingServiceProvider.overrideWithValue(
            _FakeStorageAccountingService(),
          ),
          cacheDiagnosticExportServiceProvider.overrideWithValue(
            _FakeCacheDiagnosticExportService(),
          ),
          downloadStorageServiceProvider.overrideWithValue(
            _FakeDownloadStorageService(repo: repo),
          ),
        ],
        child: const MaterialApp(home: DataStoragePage()),
      ),
    );

    await tester.pumpAndSettle();
    final restoreButton = find.byKey(
      const Key('data-storage-restore-default-button'),
    );
    await tester.scrollUntilVisible(
      restoreButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(restoreButton);
    await _tapVisibleCenter(tester, restoreButton);
    await tester.pumpAndSettle();
    expect(repo.customPath, isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('data-storage-default-directory')),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('data-storage-custom-directory')),
      findsNothing,
    );
    expect(find.text('/tmp/default-downloads'), findsAtLeastNWidgets(1));

    await tester.scrollUntilVisible(
      find.byKey(const Key('data-storage-hint-text')),
      120,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('已恢复默认存储位置'), findsOneWidget);
  });

  testWidgets('DataStoragePage reloads usage report', (tester) async {
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: '/tmp/default-downloads',
      customPath: null,
    );
    final accounting = _FakeStorageAccountingService(
      report: _usageReport(
        sections: const <StorageUsageSection>[
          StorageUsageSection(
            bucket: StorageBucket.imageCache,
            label: '图片缓存',
            bytes: 1024,
            clearable: true,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          cacheMaintenanceServiceProvider.overrideWithValue(
            _FakeCacheMaintenanceService(),
          ),
          storageAccountingServiceProvider.overrideWithValue(accounting),
          cacheDiagnosticExportServiceProvider.overrideWithValue(
            _FakeCacheDiagnosticExportService(),
          ),
          downloadStorageServiceProvider.overrideWithValue(
            _FakeDownloadStorageService(repo: repo),
          ),
        ],
        child: const MaterialApp(home: DataStoragePage()),
      ),
    );

    await tester.pumpAndSettle();
    final reloadButton = find.byKey(
      const Key('data-storage-reload-usage-button'),
    );
    expect(reloadButton, findsOneWidget);

    accounting.report = _usageReport(
      sections: const <StorageUsageSection>[
        StorageUsageSection(
          bucket: StorageBucket.imageCache,
          label: '图片缓存',
          bytes: 2048,
          clearable: true,
        ),
      ],
    );
    await tester.tap(reloadButton);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('data-storage-hint-text')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('存储统计已刷新'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('data-storage-usage-total')),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('总计：2.0 KB'), findsOneWidget);
  });

  testWidgets('DataStoragePage exports cache diagnostics', (tester) async {
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: '/tmp/default-downloads',
      customPath: null,
    );
    final exporter = _FakeCacheDiagnosticExportService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          cacheMaintenanceServiceProvider.overrideWithValue(
            _FakeCacheMaintenanceService(),
          ),
          storageAccountingServiceProvider.overrideWithValue(
            _FakeStorageAccountingService(),
          ),
          cacheDiagnosticExportServiceProvider.overrideWithValue(exporter),
          downloadStorageServiceProvider.overrideWithValue(
            _FakeDownloadStorageService(repo: repo),
          ),
        ],
        child: const MaterialApp(home: DataStoragePage()),
      ),
    );

    await tester.pumpAndSettle();
    final exportButton = find.byKey(
      const Key('data-storage-export-diagnostics-button'),
    );
    expect(exportButton, findsOneWidget);
    await tester.tap(exportButton);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('data-storage-hint-text')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(exporter.exportCalls, 1);
    expect(find.textContaining('缓存诊断已导出'), findsOneWidget);
  });

  test('formatDataStorageBytes uses KB, MB and GB units', () {
    expect(formatDataStorageBytes(512), '0.5 KB');
    expect(formatDataStorageBytes(4 * 1024 * 1024), '4.0 MB');
    expect(formatDataStorageBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
  });
}

StorageUsageReport _usageReport({
  List<StorageUsageSection> sections = const <StorageUsageSection>[
    StorageUsageSection(
      bucket: StorageBucket.imageCache,
      label: '图片缓存',
      bytes: 0,
      clearable: true,
    ),
  ],
}) {
  return StorageUsageReport.fromSections(
    sections: sections,
    calculatedAt: DateTime(2026, 1, 1),
  );
}

Future<void> _tapVisibleCenter(WidgetTester tester, Finder finder) async {
  final renderBox = tester.renderObject<RenderBox>(finder);
  final topLeft = renderBox.localToGlobal(Offset.zero);
  final bottomRight = renderBox.localToGlobal(
    renderBox.size.bottomRight(Offset.zero),
  );
  final rootSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  final visibleLeft = topLeft.dx.clamp(0.0, rootSize.width).toDouble();
  final visibleTop = topLeft.dy.clamp(0.0, rootSize.height).toDouble();
  final visibleRight = bottomRight.dx.clamp(0.0, rootSize.width).toDouble();
  final visibleBottom = bottomRight.dy.clamp(0.0, rootSize.height).toDouble();
  await tester.tapAt(
    Offset((visibleLeft + visibleRight) / 2, (visibleTop + visibleBottom) / 2),
  );
}

class _FakeDataStorageSettingsRepository
    implements DataStorageSettingsRepository {
  _FakeDataStorageSettingsRepository({
    required String defaultPath,
    required String? customPath,
    this.pickedPath,
  }) : _defaultPath = defaultPath,
       _customPath = customPath;

  final String _defaultPath;
  String? _customPath;
  final String? pickedPath;
  int _maxBytes = DataStorageSettingsRepositoryImpl.defaultImageCacheMaxBytes;

  String? get customPath => _customPath;

  @override
  Future<String> getDefaultStoragePath() async => _defaultPath;

  @override
  Future<String?> getCustomStoragePath() async => _customPath;

  @override
  Future<String?> pickDirectory() async => pickedPath;

  @override
  Future<void> setCustomStoragePath(String? path) async {
    _customPath = path;
  }

  @override
  Future<int> getImageCacheMaxBytes() async => _maxBytes;

  @override
  Future<void> setImageCacheMaxBytes(int bytes) async {
    _maxBytes = bytes;
  }
}

class _FakeDownloadStorageService implements DownloadStorageService {
  _FakeDownloadStorageService({required this.repo});

  final _FakeDataStorageSettingsRepository repo;
  int prepareRootCalls = 0;

  @override
  Future<DownloadStorageRoot> prepareRoot() async {
    prepareRootCalls += 1;
    final path =
        await repo.getCustomStoragePath() ?? await repo.getDefaultStoragePath();
    return DownloadStorageRoot(
      path: path,
      comicsPath: '$path/comics',
      novelsPath: '$path/novels',
      favoritesJsonPath: '$path/favorites.json',
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

class _FakeImageCacheService implements ImageCacheService {
  int usageBytes = 0;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: 'memory://${request.cacheKey}',
      fromCache: true,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
      fromCache: true,
    );
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async {
    return usageBytes;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {
    if (usageBytes > maxBytes) {
      usageBytes = maxBytes;
    }
  }

  @override
  Future<void> clearUnprotected() async {
    usageBytes = 0;
  }

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    usageBytes = 0;
    return 0;
  }
}

class _FakeStorageAccountingService implements StorageAccountingService {
  _FakeStorageAccountingService({this.report});

  StorageUsageReport? report;

  @override
  Future<StorageUsageReport> loadUsageReport() async {
    return report ?? _usageReport();
  }
}

class _FakeCacheMaintenanceService implements CacheMaintenanceService {
  @override
  Future<CacheClearResult> clear(CacheClearRequest request) async {
    return const CacheClearResult(
      imageCacheCleared: true,
      deletedDocuments: 0,
      deletedSnapshots: 0,
      deletedProtectedCoverRecords: 0,
    );
  }

  @override
  Future<CachePruneResult> prune(CachePruneRequest request) async {
    return const CachePruneResult(
      deletedDocuments: 0,
      deletedSnapshots: 0,
      deletedProtectedCoverRecords: 0,
    );
  }

  @override
  Future<StorageUsageReport> usageAfterMaintenance() async {
    return _usageReport();
  }
}

class _FakeCacheDiagnosticExportService
    implements CacheDiagnosticExportService {
  int exportCalls = 0;

  @override
  Future<CacheDiagnosticExportResult> exportUsageReport(
    StorageUsageReport report,
  ) async {
    exportCalls += 1;
    return CacheDiagnosticExportResult(
      path: '/tmp/default-downloads/diagnostics/cache.json',
      totalBytes: report.totalBytes,
      sectionCount: report.sections.length,
      exportedAt: DateTime(2026, 6, 27),
    );
  }
}

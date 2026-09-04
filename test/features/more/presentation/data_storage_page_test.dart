import 'dart:io' as io;

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
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
import 'package:y300/features/storage/domain/storage_root_access_gate.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';
import 'package:y300/features/more/presentation/data_storage_formatters.dart';

import '../../storage/test_support/ready_storage_root_access_gate.dart';

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
          storageRootAccessGateProvider.overrideWithValue(
            const ReadyStorageRootAccessGate(),
          ),
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
        child: LocalizedTestApp(
          theme: AppTheme.dark(),
          home: const DataStoragePage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.byKey(const Key('data-storage-cache-max-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-storage-choose-directory-button')),
      findsNothing,
    );
  });

  testWidgets('DataStoragePage commits cache limit once after slider release', (
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
          storageRootAccessGateProvider.overrideWithValue(
            const ReadyStorageRootAccessGate(),
          ),
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
        child: const LocalizedTestApp(home: DataStoragePage()),
      ),
    );
    await tester.pumpAndSettle();

    final slider = find.byKey(const Key('data-storage-cache-max-slider'));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    expect(repo.setCacheMaxBytesCalls, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(repo.setCacheMaxBytesCalls, 1);
  });

  testWidgets(
    'DataStoragePage hides path controls after migration is complete',
    (tester) async {
      final repo = _FakeDataStorageSettingsRepository(
        defaultPath: '/tmp/default-downloads',
        customPath: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
            storageRootAccessGateProvider.overrideWithValue(
              const ReadyStorageRootAccessGate(),
            ),
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
          child: const LocalizedTestApp(home: DataStoragePage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('data-storage-effective-directory')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('data-storage-default-directory')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('data-storage-custom-directory')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('data-storage-choose-directory-button')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('data-storage-restore-default-button')),
        findsNothing,
      );
    },
  );

  testWidgets('DataStoragePage separates clearable cache from total storage', (
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
          storageRootAccessGateProvider.overrideWithValue(
            const ReadyStorageRootAccessGate(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          cacheMaintenanceServiceProvider.overrideWithValue(
            _FakeCacheMaintenanceService(clearableBytes: 1024),
          ),
          storageAccountingServiceProvider.overrideWithValue(
            _FakeStorageAccountingService(
              report: _usageReport(
                sections: const <StorageUsageSection>[
                  StorageUsageSection(
                    bucket: StorageBucket.imageCache,
                    labelRef: StorageUsageLabelRef(
                      kind: StorageUsageLabelKind.bucket,
                      code: 'image_cache',
                    ),
                    bytes: 4096,
                    clearable: true,
                    categories: <StorageUsageCategory>[
                      StorageUsageCategory(
                        id: 'clearable',
                        labelRef: StorageUsageLabelRef(
                          kind: StorageUsageLabelKind.imageCategory,
                          code: 'clearable',
                        ),
                        bytes: 1024,
                        clearable: true,
                        protected: false,
                      ),
                      StorageUsageCategory(
                        id: 'sticky',
                        labelRef: StorageUsageLabelRef(
                          kind: StorageUsageLabelKind.imageCategory,
                          code: 'sticky',
                        ),
                        bytes: 2048,
                        clearable: false,
                        protected: false,
                      ),
                      StorageUsageCategory(
                        id: 'protected',
                        labelRef: StorageUsageLabelRef(
                          kind: StorageUsageLabelKind.imageCategory,
                          code: 'protected',
                        ),
                        bytes: 1024,
                        clearable: false,
                        protected: true,
                      ),
                    ],
                    slices: <StorageUsageSlice>[
                      StorageUsageSlice(
                        id: 'image:thread',
                        labelRef: StorageUsageLabelRef(
                          kind: StorageUsageLabelKind.imageRole,
                          code: 'thread_inline',
                        ),
                        bytes: 1024,
                        protected: false,
                      ),
                    ],
                  ),
                  StorageUsageSection(
                    bucket: StorageBucket.libraryMetadata,
                    labelRef: StorageUsageLabelRef(
                      kind: StorageUsageLabelKind.bucket,
                      code: 'library_metadata',
                    ),
                    bytes: 2048,
                    clearable: false,
                  ),
                  StorageUsageSection(
                    bucket: StorageBucket.history,
                    labelRef: StorageUsageLabelRef(
                      kind: StorageUsageLabelKind.bucket,
                      code: 'history',
                    ),
                    bytes: 1024,
                    clearable: false,
                    slices: <StorageUsageSlice>[
                      StorageUsageSlice(
                        id: 'history:entries',
                        labelRef: StorageUsageLabelRef(
                          kind: StorageUsageLabelKind.historyKind,
                          code: 'entries',
                          count: 12,
                        ),
                        bytes: 0,
                        protected: true,
                      ),
                    ],
                  ),
                  StorageUsageSection(
                    bucket: StorageBucket.download,
                    labelRef: StorageUsageLabelRef(
                      kind: StorageUsageLabelKind.bucket,
                      code: 'download',
                    ),
                    bytes: 1024 * 1024,
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
        child: const LocalizedTestApp(home: DataStoragePage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-storage-usage-overview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-storage-clearable-cache-size')),
      findsOneWidget,
    );
    expect(find.text('缓存与数据总览'), findsOneWidget);
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.text('应用数据总计：1.0 MB'), findsOneWidget);
    expect(find.textContaining('长期缓存、封面'), findsOneWidget);
    expect(
      tester
          .widget<ExpansionTile>(
            find.byKey(const Key('data-storage-usage-overview')),
          )
          .subtitle,
      isNotNull,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const Key('data-storage-clearable-cache-size')),
          )
          .dy,
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
    expect(
      find.byKey(const Key('data-storage-usage-section-history')),
      findsOneWidget,
    );
    expect(find.text('浏览记录：12'), findsOneWidget);
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

  testWidgets('DataStoragePage does not mount custom path mutation controls', (
    tester,
  ) async {
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: '/tmp/default-downloads',
      customPath: null,
      pickedPath: '/mnt/y300-downloads',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
          storageRootAccessGateProvider.overrideWithValue(
            const ReadyStorageRootAccessGate(),
          ),
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
        child: const LocalizedTestApp(home: DataStoragePage()),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('data-storage-choose-directory-button')),
      findsNothing,
    );
    expect(repo.customPath, isNull);
  });

  testWidgets('DataStoragePage keeps legacy custom path controls hidden', (
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
          storageRootAccessGateProvider.overrideWithValue(
            const ReadyStorageRootAccessGate(),
          ),
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
        child: const LocalizedTestApp(home: DataStoragePage()),
      ),
    );

    await tester.pumpAndSettle();
    expect(repo.customPath, '/mnt/y300-downloads');
    expect(
      find.byKey(const Key('data-storage-custom-directory')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('data-storage-restore-default-button')),
      findsNothing,
    );
  });

  testWidgets('blocked migration keeps paths read-only and can be retried', (
    tester,
  ) async {
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: '/tmp/default-downloads',
      customPath: '/mnt/y300-downloads',
    );
    final gate = _FixedStorageRootAccessGate(
      initial: _blockedMigrationResult,
      retryResult: ReadyStorageRootAccessGate.result,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
          storageRootAccessGateProvider.overrideWithValue(gate),
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
        child: const LocalizedTestApp(home: DataStoragePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-storage-migration-card')),
      findsOneWidget,
    );
    expect(find.text('/mnt/y300-downloads'), findsOneWidget);
    expect(find.text('/tmp/default-downloads'), findsOneWidget);
    expect(
      find.byKey(const Key('data-storage-choose-directory-button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('data-storage-migration-retry')));
    await tester.pumpAndSettle();

    expect(gate.retryCalls, 1);
    expect(find.byKey(const Key('data-storage-migration-card')), findsNothing);
  });

  testWidgets('cleanup pending does not block the other storage controls', (
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
          storageRootAccessGateProvider.overrideWithValue(
            _FixedStorageRootAccessGate(
              initial: _cleanupPendingMigrationResult,
              retryResult: ReadyStorageRootAccessGate.result,
            ),
          ),
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
        child: const LocalizedTestApp(home: DataStoragePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-storage-migration-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-storage-cache-max-slider')),
      findsOneWidget,
    );
    expect(find.text('/tmp/default-downloads'), findsNothing);
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
    final maintenance = _FakeCacheMaintenanceService(clearableBytes: 1024);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
          storageRootAccessGateProvider.overrideWithValue(
            const ReadyStorageRootAccessGate(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
          cacheMaintenanceServiceProvider.overrideWithValue(maintenance),
          storageAccountingServiceProvider.overrideWithValue(accounting),
          cacheDiagnosticExportServiceProvider.overrideWithValue(
            _FakeCacheDiagnosticExportService(),
          ),
          downloadStorageServiceProvider.overrideWithValue(
            _FakeDownloadStorageService(repo: repo),
          ),
        ],
        child: const LocalizedTestApp(home: DataStoragePage()),
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
    maintenance.clearableBytes = 2048;
    await tester.tap(reloadButton);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('data-storage-hint-text')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('存储统计已刷新'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('data-storage-clearable-cache-size')),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2.0 KB'), findsOneWidget);
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
          storageRootAccessGateProvider.overrideWithValue(
            const ReadyStorageRootAccessGate(),
          ),
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
        child: const LocalizedTestApp(home: DataStoragePage()),
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
  int _maxBytes = DataStorageSettingsRepositoryImpl.defaultCacheMaxBytes;
  int setCacheMaxBytesCalls = 0;

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
  Future<int> getCacheMaxBytes() async => _maxBytes;

  @override
  Future<void> setCacheMaxBytes(int bytes) async {
    setCacheMaxBytesCalls += 1;
    _maxBytes = bytes;
  }
}

const _blockedMigrationResult = StorageRootMigrationResult(
  disposition: StorageRootMigrationDisposition.blocked,
  status: StorageRootMigrationStatus(
    phase: StorageRootMigrationPhase.blocked,
    failureCode: StorageRootMigrationFailureCode.targetConflict,
    blocksStorageAccess: true,
  ),
);

const _cleanupPendingMigrationResult = StorageRootMigrationResult(
  disposition: StorageRootMigrationDisposition.cleanupPending,
  status: StorageRootMigrationStatus(
    phase: StorageRootMigrationPhase.cleanupPending,
    failureCode: StorageRootMigrationFailureCode.cleanupFailed,
    blocksStorageAccess: false,
  ),
);

final class _FixedStorageRootAccessGate implements StorageRootAccessGate {
  _FixedStorageRootAccessGate({
    required this.initial,
    required this.retryResult,
  });

  final StorageRootMigrationResult initial;
  final StorageRootMigrationResult retryResult;
  int retryCalls = 0;

  @override
  Future<StorageRootMigrationResult> ensureReady() async => initial;

  @override
  Future<StorageRootMigrationResult> retry() async {
    retryCalls += 1;
    return retryResult;
  }

  @override
  Future<T> runWithAccess<T>(Future<T> Function() operation) => operation();
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
  _FakeCacheMaintenanceService({this.clearableBytes = 0});

  int clearableBytes;

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

  @override
  Future<CacheCapacityReport> loadCapacityReport() async {
    return CacheCapacityReport(
      clearableBytes: clearableBytes,
      budgetedBytes: clearableBytes,
      longTermBytes: 0,
      calculatedAt: DateTime(2026, 6, 27),
    );
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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/models/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/more/data/data_storage_settings_repository.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

enum DataStorageNoticeCode {
  cachePartiallyCleared,
  cacheCleared,
  cacheLimitUpdated,
  directoryNotSelected,
  storageLocationUpdated,
  defaultStorageRestored,
  usageReloaded,
  diagnosticsExported,
}

class DataStorageNotice {
  const DataStorageNotice({required this.code, this.path});

  final DataStorageNoticeCode code;
  final String? path;
}

class DataStorageViewState {
  const DataStorageViewState({
    required this.clearableCacheBytes,
    required this.usageReport,
    required this.cacheMaxBytes,
    required this.storagePath,
    required this.defaultStoragePath,
    required this.customStoragePath,
    required this.isUpdating,
    this.notice,
  });

  final int clearableCacheBytes;
  final StorageUsageReport usageReport;
  final int cacheMaxBytes;
  final String storagePath;
  final String defaultStoragePath;
  final String? customStoragePath;
  final bool isUpdating;
  final DataStorageNotice? notice;

  @Deprecated('Use clearableCacheBytes instead.')
  int get imageCacheUsageBytes => clearableCacheBytes;

  @Deprecated('Use cacheMaxBytes instead.')
  int get imageCacheMaxBytes => cacheMaxBytes;

  @Deprecated('Use defaultStoragePath instead.')
  String get defaultDirectory => defaultStoragePath;

  @Deprecated('Use customStoragePath instead.')
  String? get customDirectory => customStoragePath;

  @Deprecated('Use storagePath instead.')
  String get effectiveDirectory => storagePath;

  DataStorageViewState copyWith({
    int? clearableCacheBytes,
    StorageUsageReport? usageReport,
    int? cacheMaxBytes,
    String? storagePath,
    String? defaultStoragePath,
    String? customStoragePath,
    bool? isUpdating,
    DataStorageNotice? notice,
    bool clearCustomStoragePath = false,
    bool clearNotice = false,
  }) {
    return DataStorageViewState(
      clearableCacheBytes: clearableCacheBytes ?? this.clearableCacheBytes,
      usageReport: usageReport ?? this.usageReport,
      cacheMaxBytes: cacheMaxBytes ?? this.cacheMaxBytes,
      storagePath: storagePath ?? this.storagePath,
      defaultStoragePath: defaultStoragePath ?? this.defaultStoragePath,
      customStoragePath: clearCustomStoragePath
          ? null
          : (customStoragePath ?? this.customStoragePath),
      isUpdating: isUpdating ?? this.isUpdating,
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }
}

final dataStorageSettingsRepositoryProvider =
    Provider<DataStorageSettingsRepository>((ref) {
      return DataStorageSettingsRepositoryImpl(
        storageLocationRepository: ref.watch(storageLocationRepositoryProvider),
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

final dataStoragePathPreviewProvider =
    FutureProvider.autoDispose<DataStoragePathPreview>((ref) async {
      final repository = ref.watch(dataStorageSettingsRepositoryProvider);
      final values = await Future.wait<Object?>(<Future<Object?>>[
        repository.getDefaultStoragePath(),
        repository.getCustomStoragePath(),
      ]);
      return DataStoragePathPreview(
        defaultStoragePath: values[0]! as String,
        customStoragePath: values[1] as String?,
      );
    });

final class DataStoragePathPreview {
  const DataStoragePathPreview({
    required this.defaultStoragePath,
    required this.customStoragePath,
  });

  final String defaultStoragePath;
  final String? customStoragePath;
}

final dataStorageControllerProvider =
    AsyncNotifierProvider.autoDispose<
      DataStorageController,
      DataStorageViewState
    >(DataStorageController.new);

class DataStorageController extends AsyncNotifier<DataStorageViewState> {
  late final DataStorageSettingsRepository _repository;
  late final CacheMaintenanceService _cacheMaintenanceService;
  late final CacheDiagnosticExportService _cacheDiagnosticExportService;
  late final StorageAccountingService _storageAccountingService;
  late final DownloadStorageService _downloadStorageService;

  @override
  Future<DataStorageViewState> build() async {
    _repository = ref.read(dataStorageSettingsRepositoryProvider);
    _cacheMaintenanceService = ref.read(cacheMaintenanceServiceProvider);
    _cacheDiagnosticExportService = ref.read(
      cacheDiagnosticExportServiceProvider,
    );
    _storageAccountingService = ref.read(storageAccountingServiceProvider);
    _downloadStorageService = ref.read(downloadStorageServiceProvider);
    final base = await _loadStorageState();
    final usageReport = await _loadDiagnosticUsageReport();
    final capacityReport = await _cacheMaintenanceService.loadCapacityReport();
    final maxBytes = await _repository.getCacheMaxBytes();

    return DataStorageViewState(
      clearableCacheBytes: capacityReport.clearableBytes,
      usageReport: usageReport,
      cacheMaxBytes: maxBytes,
      storagePath: base.storagePath,
      defaultStoragePath: base.defaultStoragePath,
      customStoragePath: base.customStoragePath,
      isUpdating: false,
    );
  }

  Future<void> clearCache() async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearNotice: true));
    final result = await _cacheMaintenanceService.clear(
      const CacheClearRequest(scope: CacheClearScope.userCleanup),
    );
    final usageReport = await _loadDiagnosticUsageReport(
      afterMaintenance: true,
    );
    final capacityReport = await _cacheMaintenanceService.loadCapacityReport();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        clearableCacheBytes: capacityReport.clearableBytes,
        usageReport: usageReport,
        isUpdating: false,
        notice: DataStorageNotice(
          code: result.isPartial
              ? DataStorageNoticeCode.cachePartiallyCleared
              : DataStorageNoticeCode.cacheCleared,
        ),
      ),
    );
  }

  @Deprecated('Use clearCache instead.')
  Future<void> clearImageCache() => clearCache();

  Future<void> updateCacheMaxBytes(int bytes) async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearNotice: true));
    await _repository.setCacheMaxBytes(bytes);
    final maxBytes = await _repository.getCacheMaxBytes();
    await _cacheMaintenanceService.prune(
      CachePruneRequest(maxCacheBytes: maxBytes),
    );
    final usageReport = await _loadDiagnosticUsageReport(
      afterMaintenance: true,
    );
    final capacityReport = await _cacheMaintenanceService.loadCapacityReport();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        clearableCacheBytes: capacityReport.clearableBytes,
        usageReport: usageReport,
        cacheMaxBytes: maxBytes,
        isUpdating: false,
        notice: const DataStorageNotice(
          code: DataStorageNoticeCode.cacheLimitUpdated,
        ),
      ),
    );
  }

  @Deprecated('Use updateCacheMaxBytes instead.')
  Future<void> updateImageCacheMaxBytes(int bytes) {
    return updateCacheMaxBytes(bytes);
  }

  Future<void> chooseStorageDirectory() async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearNotice: true));

    final selected = await _repository.pickDirectory();
    if (!ref.mounted) {
      return;
    }
    final normalized = selected?.trim();
    if (normalized == null || normalized.isEmpty) {
      state = AsyncData(
        current.copyWith(
          isUpdating: false,
          notice: const DataStorageNotice(
            code: DataStorageNoticeCode.directoryNotSelected,
          ),
        ),
      );
      return;
    }

    await _repository.setCustomStoragePath(normalized);
    final storage = await _loadStorageState();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        storagePath: storage.storagePath,
        defaultStoragePath: storage.defaultStoragePath,
        customStoragePath: storage.customStoragePath,
        isUpdating: false,
        notice: const DataStorageNotice(
          code: DataStorageNoticeCode.storageLocationUpdated,
        ),
      ),
    );
  }

  @Deprecated('Use chooseStorageDirectory instead.')
  Future<void> chooseCustomDirectory() {
    return chooseStorageDirectory();
  }

  Future<void> restoreDefaultStorageDirectory() async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearNotice: true));
    await _repository.setCustomStoragePath(null);
    final storage = await _loadStorageState();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        storagePath: storage.storagePath,
        defaultStoragePath: storage.defaultStoragePath,
        clearCustomStoragePath: storage.customStoragePath == null,
        customStoragePath: storage.customStoragePath,
        isUpdating: false,
        notice: const DataStorageNotice(
          code: DataStorageNoticeCode.defaultStorageRestored,
        ),
      ),
    );
  }

  @Deprecated('Use restoreDefaultStorageDirectory instead.')
  Future<void> restoreDefaultDirectory() {
    return restoreDefaultStorageDirectory();
  }

  Future<void> reloadUsage() async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearNotice: true));
    final usageReport = await _loadDiagnosticUsageReport();
    final capacityReport = await _cacheMaintenanceService.loadCapacityReport();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        clearableCacheBytes: capacityReport.clearableBytes,
        usageReport: usageReport,
        isUpdating: false,
        notice: const DataStorageNotice(
          code: DataStorageNoticeCode.usageReloaded,
        ),
      ),
    );
  }

  Future<void> exportCacheDiagnostics() async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearNotice: true));
    final usageReport = await _storageAccountingService.loadUsageReport();
    final capacityReport = await _cacheMaintenanceService.loadCapacityReport();
    final result = await _cacheDiagnosticExportService.exportUsageReport(
      usageReport,
    );
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        clearableCacheBytes: capacityReport.clearableBytes,
        usageReport: usageReport,
        isUpdating: false,
        notice: DataStorageNotice(
          code: DataStorageNoticeCode.diagnosticsExported,
          path: result.path,
        ),
      ),
    );
  }

  Future<_StorageState> _loadStorageState() async {
    final defaultPath = await _repository.getDefaultStoragePath();
    final customPath = await _repository.getCustomStoragePath();
    // prepareRoot is the single place that creates .nomedia files and the
    // favorites snapshot.  The More page should only request the prepared root.
    final root = await _downloadStorageService.prepareRoot();
    return _StorageState(
      storagePath: root.path,
      defaultStoragePath: defaultPath,
      customStoragePath: customPath,
    );
  }

  Future<StorageUsageReport> _loadDiagnosticUsageReport({
    bool afterMaintenance = false,
  }) {
    if (!kDebugMode) {
      return Future<StorageUsageReport>.value(
        StorageUsageReport.fromSections(
          sections: const <StorageUsageSection>[],
          calculatedAt: DateTime.now(),
        ),
      );
    }
    return afterMaintenance
        ? _cacheMaintenanceService.usageAfterMaintenance()
        : _storageAccountingService.loadUsageReport();
  }
}

class _StorageState {
  const _StorageState({
    required this.storagePath,
    required this.defaultStoragePath,
    required this.customStoragePath,
  });

  final String storagePath;
  final String defaultStoragePath;
  final String? customStoragePath;
}

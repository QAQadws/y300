import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/more/data/data_storage_settings_repository.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

class DataStorageViewState {
  const DataStorageViewState({
    required this.imageCacheUsageBytes,
    required this.usageReport,
    required this.imageCacheMaxBytes,
    required this.storagePath,
    required this.defaultStoragePath,
    required this.customStoragePath,
    required this.isUpdating,
    this.hint,
  });

  final int imageCacheUsageBytes;
  final StorageUsageReport usageReport;
  final int imageCacheMaxBytes;
  final String storagePath;
  final String defaultStoragePath;
  final String? customStoragePath;
  final bool isUpdating;
  final String? hint;

  @Deprecated('Use defaultStoragePath instead.')
  String get defaultDirectory => defaultStoragePath;

  @Deprecated('Use customStoragePath instead.')
  String? get customDirectory => customStoragePath;

  @Deprecated('Use storagePath instead.')
  String get effectiveDirectory => storagePath;

  DataStorageViewState copyWith({
    int? imageCacheUsageBytes,
    StorageUsageReport? usageReport,
    int? imageCacheMaxBytes,
    String? storagePath,
    String? defaultStoragePath,
    String? customStoragePath,
    bool? isUpdating,
    String? hint,
    bool clearCustomStoragePath = false,
    bool clearHint = false,
  }) {
    return DataStorageViewState(
      imageCacheUsageBytes: imageCacheUsageBytes ?? this.imageCacheUsageBytes,
      usageReport: usageReport ?? this.usageReport,
      imageCacheMaxBytes: imageCacheMaxBytes ?? this.imageCacheMaxBytes,
      storagePath: storagePath ?? this.storagePath,
      defaultStoragePath: defaultStoragePath ?? this.defaultStoragePath,
      customStoragePath: clearCustomStoragePath
          ? null
          : (customStoragePath ?? this.customStoragePath),
      isUpdating: isUpdating ?? this.isUpdating,
      hint: clearHint ? null : (hint ?? this.hint),
    );
  }
}

final dataStorageSettingsRepositoryProvider =
    Provider<DataStorageSettingsRepository>((ref) {
      return DataStorageSettingsRepositoryImpl(
        storageLocationRepository: ref.watch(storageLocationRepositoryProvider),
      );
    });

final dataStorageControllerProvider =
    AsyncNotifierProvider.autoDispose<
      DataStorageController,
      DataStorageViewState
    >(DataStorageController.new);

class DataStorageController extends AsyncNotifier<DataStorageViewState> {
  late final DataStorageSettingsRepository _repository;
  late final ImageCacheService _imageCacheService;
  late final StorageAccountingService _storageAccountingService;
  late final DownloadStorageService _downloadStorageService;

  @override
  Future<DataStorageViewState> build() async {
    _repository = ref.read(dataStorageSettingsRepositoryProvider);
    _imageCacheService = ref.read(imageCacheServiceProvider);
    _storageAccountingService = ref.read(storageAccountingServiceProvider);
    _downloadStorageService = ref.read(downloadStorageServiceProvider);
    final base = await _loadStorageState();
    final usageReport = await _storageAccountingService.loadUsageReport();
    final maxBytes = await _repository.getImageCacheMaxBytes();

    return DataStorageViewState(
      imageCacheUsageBytes: _imageCacheUsageBytes(usageReport),
      usageReport: usageReport,
      imageCacheMaxBytes: maxBytes,
      storagePath: base.storagePath,
      defaultStoragePath: base.defaultStoragePath,
      customStoragePath: base.customStoragePath,
      isUpdating: false,
    );
  }

  Future<void> clearImageCache() async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearHint: true));
    await _imageCacheService.clearUnprotected();
    final usageReport = await _storageAccountingService.loadUsageReport();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        imageCacheUsageBytes: _imageCacheUsageBytes(usageReport),
        usageReport: usageReport,
        isUpdating: false,
        hint: '已清除非封面图片缓存',
      ),
    );
  }

  Future<void> updateImageCacheMaxBytes(int bytes) async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearHint: true));
    await _repository.setImageCacheMaxBytes(bytes);
    final maxBytes = await _repository.getImageCacheMaxBytes();
    await _imageCacheService.pruneToLimit(maxBytes: maxBytes);
    final usageReport = await _storageAccountingService.loadUsageReport();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        imageCacheUsageBytes: _imageCacheUsageBytes(usageReport),
        usageReport: usageReport,
        imageCacheMaxBytes: maxBytes,
        isUpdating: false,
        hint: '图片缓存上限已更新',
      ),
    );
  }

  Future<void> chooseStorageDirectory() async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearHint: true));

    final selected = await _repository.pickDirectory();
    if (!ref.mounted) {
      return;
    }
    final normalized = selected?.trim();
    if (normalized == null || normalized.isEmpty) {
      state = AsyncData(current.copyWith(isUpdating: false, hint: '未选择目录'));
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
        hint: '存储位置已更新',
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
    state = AsyncData(current.copyWith(isUpdating: true, clearHint: true));
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
        hint: '已恢复默认存储位置',
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
    state = AsyncData(current.copyWith(isUpdating: true, clearHint: true));
    final usageReport = await _storageAccountingService.loadUsageReport();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        imageCacheUsageBytes: _imageCacheUsageBytes(usageReport),
        usageReport: usageReport,
        isUpdating: false,
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

  int _imageCacheUsageBytes(StorageUsageReport report) {
    for (final section in report.sections) {
      if (section.bucket == StorageBucket.imageCache) {
        return section.bytes;
      }
    }
    return 0;
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

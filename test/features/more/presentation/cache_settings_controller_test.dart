import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/more/data/data_storage_settings_repository.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

void main() {
  test('loads download storage path and prepares root on first build', () async {
    final storage = _FakeDownloadStorageService(rootPath: 'C:/default-storage');
    final container = ProviderContainer(
      overrides: [
        dataStorageSettingsRepositoryProvider.overrideWithValue(
          _FakeDataStorageSettingsRepository(
            defaultPath: 'C:/default-storage',
            customPath: null,
          ),
        ),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        downloadStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final subscription = _keepDataStorageControllerAlive(container);
    addTearDown(subscription.close);

    final state = await container.read(dataStorageControllerProvider.future);

    expect(state.defaultStoragePath, 'C:/default-storage');
    expect(state.customStoragePath, isNull);
    expect(state.storagePath, 'C:/default-storage');
    expect(storage.prepareRootCalls, 1);
  });

  test('choose storage directory saves download directory and prepares structure', () async {
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: 'C:/default-storage',
      customPath: null,
      pickedPath: 'D:/downloads/Y300',
    );
    final storage = _FakeDownloadStorageService(repo: repo);
    final container = ProviderContainer(
      overrides: [
        dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        downloadStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final subscription = _keepDataStorageControllerAlive(container);
    addTearDown(subscription.close);

    await container.read(dataStorageControllerProvider.future);
    await container.read(dataStorageControllerProvider.notifier).chooseStorageDirectory();

    final value = container.read(dataStorageControllerProvider).value!;
    expect(repo.customPath, 'D:/downloads/Y300');
    expect(value.customStoragePath, 'D:/downloads/Y300');
    expect(value.storagePath, 'D:/downloads/Y300');
    expect(storage.prepareRootCalls, 2);
  });

  test('choose storage directory creates download storage nomedia files', () async {
    final temp = await io.Directory.systemTemp.createTemp('y300-data-storage-');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final custom = p.join(temp.path, 'custom-root');
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: p.join(temp.path, 'default-root'),
      customPath: null,
      pickedPath: custom,
    );
    final container = ProviderContainer(
      overrides: [
        dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        downloadStorageServiceProvider.overrideWithValue(
          DefaultDownloadStorageService(
            locationRepository: _FakeStorageLocationRepository(repo),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = _keepDataStorageControllerAlive(container);
    addTearDown(subscription.close);

    await container.read(dataStorageControllerProvider.future);
    await container.read(dataStorageControllerProvider.notifier).chooseStorageDirectory();

    final value = container.read(dataStorageControllerProvider).value!;
    expect(value.storagePath, custom);
    expect(await io.File(p.join(value.storagePath, '.nomedia')).exists(), isTrue);
    expect(await io.File(p.join(value.storagePath, 'comics', '.nomedia')).exists(), isTrue);
    expect(await io.File(p.join(value.storagePath, 'novels', '.nomedia')).exists(), isTrue);
    expect(await io.File(p.join(value.storagePath, 'favorites.json')).exists(), isTrue);
  });

  test('restore default clears download directory without deleting old path', () async {
    final oldCustom = io.Directory.systemTemp.createTempSync('y300-old-storage-');
    addTearDown(() async {
      if (await oldCustom.exists()) {
        await oldCustom.delete(recursive: true);
      }
    });
    final repo = _FakeDataStorageSettingsRepository(
      defaultPath: 'C:/default-storage',
      customPath: oldCustom.path,
    );
    final storage = _FakeDownloadStorageService(repo: repo);
    final container = ProviderContainer(
      overrides: [
        dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
        imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        downloadStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final subscription = _keepDataStorageControllerAlive(container);
    addTearDown(subscription.close);

    await container.read(dataStorageControllerProvider.future);
    await container.read(dataStorageControllerProvider.notifier).restoreDefaultStorageDirectory();

    final value = container.read(dataStorageControllerProvider).value!;
    expect(repo.customPath, isNull);
    expect(value.customStoragePath, isNull);
    expect(value.storagePath, 'C:/default-storage');
    expect(await oldCustom.exists(), isTrue);
  });

  test('clear image cache calls clearUnprotected and reloads usage', () async {
    final imageCache = _FakeImageCacheService(usageBytes: 128 * 1024);
    final container = ProviderContainer(
      overrides: [
        dataStorageSettingsRepositoryProvider.overrideWithValue(
          _FakeDataStorageSettingsRepository(defaultPath: 'C:/default-storage'),
        ),
        imageCacheServiceProvider.overrideWithValue(imageCache),
        downloadStorageServiceProvider.overrideWithValue(
          _FakeDownloadStorageService(rootPath: 'C:/default-storage'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = _keepDataStorageControllerAlive(container);
    addTearDown(subscription.close);

    await container.read(dataStorageControllerProvider.future);
    await container.read(dataStorageControllerProvider.notifier).clearImageCache();

    final value = container.read(dataStorageControllerProvider).value!;
    expect(imageCache.clearUnprotectedCalls, 1);
    expect(value.imageCacheUsageBytes, 0);
  });

  test('update image cache max clamps value, saves it and prunes cache', () async {
    final repo = _FakeDataStorageSettingsRepository(defaultPath: 'C:/default-storage');
    final imageCache = _FakeImageCacheService(usageBytes: 4096 * 1024 * 1024);
    final container = ProviderContainer(
      overrides: [
        dataStorageSettingsRepositoryProvider.overrideWithValue(repo),
        imageCacheServiceProvider.overrideWithValue(imageCache),
        downloadStorageServiceProvider.overrideWithValue(
          _FakeDownloadStorageService(rootPath: 'C:/default-storage'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = _keepDataStorageControllerAlive(container);
    addTearDown(subscription.close);

    await container.read(dataStorageControllerProvider.future);
    await container.read(dataStorageControllerProvider.notifier).updateImageCacheMaxBytes(4096 * 1024 * 1024);

    final value = container.read(dataStorageControllerProvider).value!;
    expect(repo.maxBytes, DataStorageSettingsRepositoryImpl.maxImageCacheMaxBytes);
    expect(imageCache.lastPruneMaxBytes, DataStorageSettingsRepositoryImpl.maxImageCacheMaxBytes);
    expect(value.imageCacheMaxBytes, DataStorageSettingsRepositoryImpl.maxImageCacheMaxBytes);
  });
}

ProviderSubscription<AsyncValue<DataStorageViewState>> _keepDataStorageControllerAlive(
  ProviderContainer container,
) {
  return container.listen(dataStorageControllerProvider, (_, _) {});
}

class _FakeDataStorageSettingsRepository implements DataStorageSettingsRepository {
  _FakeDataStorageSettingsRepository({
    required String defaultPath,
    String? customPath,
    String? pickedPath,
  })  : _defaultPath = defaultPath,
        _customPath = customPath,
        _pickedPath = pickedPath;

  final String _defaultPath;
  String? _customPath;
  final String? _pickedPath;
  int maxBytes = DataStorageSettingsRepositoryImpl.defaultImageCacheMaxBytes;

  String? get customPath => _customPath;

  @override
  Future<String> getDefaultStoragePath() async => _defaultPath;

  @override
  Future<String?> getCustomStoragePath() async => _customPath;

  @override
  Future<String?> pickDirectory() async => _pickedPath;

  @override
  Future<void> setCustomStoragePath(String? path) async {
    _customPath = path;
  }

  @override
  Future<int> getImageCacheMaxBytes() async => maxBytes;

  @override
  Future<void> setImageCacheMaxBytes(int bytes) async {
    maxBytes = bytes
        .clamp(
          DataStorageSettingsRepositoryImpl.minImageCacheMaxBytes,
          DataStorageSettingsRepositoryImpl.maxImageCacheMaxBytes,
        )
        .toInt();
  }
}

class _FakeDownloadStorageService implements DownloadStorageService {
  _FakeDownloadStorageService({
    this.rootPath,
    _FakeDataStorageSettingsRepository? repo,
  }) : _repo = repo;

  final String? rootPath;
  final _FakeDataStorageSettingsRepository? _repo;
  int prepareRootCalls = 0;

  @override
  Future<DownloadStorageRoot> prepareRoot() async {
    prepareRootCalls += 1;
    final resolved = rootPath ?? await _resolveFromRepository();
    return DownloadStorageRoot(
      path: resolved,
      comicsPath: '$resolved/comics',
      novelsPath: '$resolved/novels',
      favoritesJsonPath: '$resolved/favorites.json',
    );
  }

  Future<String> _resolveFromRepository() async {
    final repo = _repo!;
    final custom = await repo.getCustomStoragePath();
    return custom ?? await repo.getDefaultStoragePath();
  }

  @override
  Future<io.Directory> prepareComicDirectory({required String workId, required String title}) {
    throw UnimplementedError();
  }

  @override
  Future<io.Directory> prepareNovelDirectory({required String novelId, required String title}) {
    throw UnimplementedError();
  }

  @override
  String safeFileName(String value, {String fallback = 'untitled'}) => value;

  @override
  String numberedFileName({required int index, required String title, required String extension}) => title;

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

class _FakeStorageLocationRepository implements StorageLocationRepository {
  _FakeStorageLocationRepository(this.repo);

  final _FakeDataStorageSettingsRepository repo;

  @override
  Future<String> getDefaultStorageRoot() {
    return repo.getDefaultStoragePath();
  }

  @override
  Future<String?> getCustomStorageRoot() {
    return repo.getCustomStoragePath();
  }

  @override
  Future<String?> pickDirectory() {
    return repo.pickDirectory();
  }

  @override
  Future<void> setCustomStorageRoot(String? path) {
    return repo.setCustomStoragePath(path);
  }
}

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({this.usageBytes = 0});

  int usageBytes;
  int clearUnprotectedCalls = 0;
  int? lastPruneMaxBytes;

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
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => usageBytes;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {
    lastPruneMaxBytes = maxBytes;
    if (usageBytes > maxBytes) {
      usageBytes = maxBytes;
    }
  }

  @override
  Future<void> clearUnprotected() async {
    clearUnprotectedCalls += 1;
    usageBytes = 0;
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/cache/data/providers/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/data/services/cache_budget_coordinator.dart';
import 'package:y300/features/cache/data/services/app_image_cache_info_repository.dart';
import 'package:y300/features/cache/data/services/default_image_cache_service.dart';
import 'package:y300/features/cache/data/services/image_cache_file_access.dart';
import 'package:y300/features/cache/data/services/image_cache_manager_factory.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory cacheRoot;
  late BaseCacheManager manager;
  late Database database;
  late _HookedImageCacheRepository imageRepository;
  late ImageCacheFileAccess fileAccess;

  setUp(() async {
    cacheRoot = await Directory.systemTemp.createTemp(
      'y300_image_cache_manager_',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => switch (call.method) {
        'getApplicationSupportDirectory' => cacheRoot.path,
        _ => null,
      },
    );
    database = await AppDatabase.open(
      databaseName: p.join(cacheRoot.path, 'app.sqlite'),
    );
    imageRepository = _HookedImageCacheRepository(Future.value(database));
    fileAccess = ImageCacheFileAccess();
    manager = ImageCacheManagerFactory(
      fileService: HttpFileService(),
      repository: imageRepository,
      fileAccess: fileAccess,
    ).create(cacheDirectoryPath: cacheRoot.path);
    await manager.emptyCache();
  });

  tearDown(() async {
    await manager.emptyCache();
    await manager.dispose();
    await database.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      null,
    );
    if (await cacheRoot.exists()) {
      await cacheRoot.delete(recursive: true);
    }
  });

  test('factory preserves the shared cache and enables image resizing', () {
    expect(manager, isA<BaseCacheManager>());
    expect(manager, isA<ImageCacheManager>());
  });

  test(
    'App indexed prefix cannot starve bounded unindexed count and age cleanup',
    () async {
      final now = DateTime.now();
      final indexed = <File>[];
      for (var index = 0; index < 510; index++) {
        indexed.add(
          await _seedFile(
            manager,
            imageRepository,
            fileAccess: fileAccess,
            key: 'indexed-$index',
            touched: now.subtract(const Duration(days: 60)),
            retention: index.isEven
                ? ImageRetentionClass.ephemeral
                : ImageRetentionClass.sticky,
          ),
        );
      }
      final unowned = <File>[];
      for (var index = 0; index < 205; index++) {
        unowned.add(
          await _seedFile(
            manager,
            imageRepository,
            fileAccess: fileAccess,
            key: 'unowned-$index',
            touched: now.subtract(Duration(days: 2, seconds: index)),
          ),
        );
      }
      final expired = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'expired',
        touched: now.subtract(const Duration(days: 45)),
      );
      final fresh = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'fresh',
        touched: now,
      );
      await _runAutomaticCleanup(manager);

      expect(indexed.every((file) => file.existsSync()), isTrue);
      expect(await imageRepository.getByKey('indexed-0'), isNotNull);
      expect(await imageRepository.getByKey('indexed-1'), isNotNull);
      expect(await expired.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
      expect(unowned.where((file) => file.existsSync()), hasLength(199));
      expect(
        await (manager as CacheManager).config.repo.getAllObjects(),
        hasLength(710),
      );
    },
  );

  test(
    'App byte budget deletes regular files and keeps sticky files',
    () async {
      final old = DateTime.now().subtract(const Duration(days: 60));
      final regular = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'budget-regular',
        touched: old,
        retention: ImageRetentionClass.ephemeral,
      );
      final sticky = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'budget-sticky',
        touched: old,
        retention: ImageRetentionClass.sticky,
      );
      await _runAutomaticCleanup(manager);
      expect(await regular.exists(), isTrue);
      expect(await sticky.exists(), isTrue);
      final service = DefaultImageCacheService(
        repository: imageRepository,
        cacheManagerFuture: Future.value(manager),
        directoryResolver: const ImageCacheDirectoryResolver(),
        fileAccess: fileAccess,
      );
      final result = await CacheBudgetCoordinator(
        participants: [service],
      ).pruneToLimit(maxBytes: 0);

      expect(result.deletedEntries, 1);
      expect(await regular.exists(), isFalse);
      expect(await imageRepository.getByKey('budget-regular'), isNull);
      expect(await manager.getFileFromCache('budget-regular'), isNull);
      expect(await sticky.exists(), isTrue);
      expect(await imageRepository.getByKey('budget-sticky'), isNotNull);
      expect(await manager.getFileFromCache('budget-sticky'), isNotNull);
    },
  );

  test(
    'App cache publication is protected until its retention is indexed',
    () async {
      final file = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'publishing-sticky',
        touched: DateTime.now().subtract(const Duration(days: 60)),
      );
      await fileAccess.protect('publishing-sticky', () async {
        await _runAutomaticCleanup(manager);
        expect(await file.exists(), isTrue);
        await imageRepository.upsert(
          _record(
            key: 'publishing-sticky',
            file: file,
            retention: ImageRetentionClass.sticky,
          ),
        );
      });
      await _runAutomaticCleanup(manager);
      expect(await file.exists(), isTrue);
      expect(await manager.getFileFromCache('publishing-sticky'), isNotNull);
    },
  );

  test(
    'ownership gained after the cleanup scan is checked again before deleting',
    () async {
      final file = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'late-sticky',
        touched: DateTime.now().subtract(const Duration(days: 60)),
      );
      imageRepository.afterLookup = () => imageRepository.upsert(
        _record(
          key: 'late-sticky',
          file: file,
          retention: ImageRetentionClass.sticky,
        ),
      );
      await _runAutomaticCleanup(manager);
      expect(await file.exists(), isTrue);
      expect(await manager.getFileFromCache('late-sticky'), isNotNull);
    },
  );

  test('a file refreshed after the cleanup scan is not deleted', () async {
    final file = await _seedFile(
      manager,
      imageRepository,
      fileAccess: fileAccess,
      key: 'late-refresh',
      touched: DateTime.now().subtract(const Duration(days: 60)),
    );
    final repository = (manager as CacheManager).config.repo;
    imageRepository.afterLookup = () async {
      final current = (await repository.get('late-refresh'))!;
      await repository.update(current);
    };
    await _runAutomaticCleanup(manager);
    expect(await file.exists(), isTrue);
    expect(await manager.getFileFromCache('late-refresh'), isNotNull);
  });

  test(
    'same key copied to a protected path does not retain an orphan original',
    () async {
      final original = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'relocated',
        touched: DateTime.now().subtract(const Duration(days: 60)),
      );
      final protected = await original.copy(
        p.join(cacheRoot.path, 'protected.png'),
      );
      await imageRepository.upsert(
        _record(
          key: 'relocated',
          file: protected,
          retention: ImageRetentionClass.protected,
        ),
      );
      await _runAutomaticCleanup(manager);
      expect(await original.exists(), isFalse);
      expect(await protected.exists(), isTrue);
      expect(
        (await imageRepository.getByKey('relocated'))?.localPath,
        protected.path,
      );
    },
  );

  test('automatic cleanup limits each pass to 100 orphan files', () async {
    final files = <File>[];
    for (var index = 0; index < 121; index++) {
      files.add(
        await _seedFile(
          manager,
          imageRepository,
          fileAccess: fileAccess,
          key: 'expired-batch-$index',
          touched: DateTime.now().subtract(const Duration(days: 60)),
        ),
      );
    }
    await _runAutomaticCleanup(manager);
    expect(files.where((file) => file.existsSync()), hasLength(21));
    await _runAutomaticCleanup(manager);
    expect(files.any((file) => file.existsSync()), isFalse);
  });

  test('busy orphan prefixes do not consume the deletion batch', () async {
    final busyFiles = <File>[];
    for (var index = 0; index < 101; index++) {
      busyFiles.add(
        await _seedFile(
          manager,
          imageRepository,
          fileAccess: fileAccess,
          key: 'busy-$index',
          touched: DateTime.now().subtract(const Duration(days: 60)),
        ),
      );
    }
    final eligible = await _seedFile(
      manager,
      imageRepository,
      fileAccess: fileAccess,
      key: 'eligible-after-busy-prefix',
      touched: DateTime.now().subtract(const Duration(days: 45)),
    );
    final release = Completer<void>();
    final publications = List.generate(
      busyFiles.length,
      (index) => fileAccess.protect('busy-$index', () => release.future),
    );
    try {
      await _runAutomaticCleanup(manager);
      expect(busyFiles.every((file) => file.existsSync()), isTrue);
      expect(await eligible.exists(), isFalse);
    } finally {
      release.complete();
      await Future.wait(publications);
    }
  });

  test(
    'one failed orphan unlink does not block later eligible files',
    () async {
      final blocked = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'blocked-unlink',
        touched: DateTime.now().subtract(const Duration(days: 60)),
      );
      final eligible = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'after-blocked-unlink',
        touched: DateTime.now().subtract(const Duration(days: 45)),
      );
      final cleanup = AppImageCacheInfoRepository(
        delegate: (manager as CacheManager).config.repo,
        imageRepository: imageRepository,
        fileAccess: fileAccess,
        cacheDirectoryPath: p.join(
          cacheRoot.path,
          ImageCacheManagerFactory.cacheKey,
        ),
        removeFile: (key) async {
          if (key == 'blocked-unlink') {
            throw FileSystemException('Injected unlink failure', blocked.path);
          }
          await manager.removeFile(key);
        },
      );
      await cleanup.getObjectsOverCapacity(200);
      await cleanup.getOldObjects(const Duration(days: 30));

      expect(await blocked.exists(), isTrue);
      expect(await manager.getFileFromCache('blocked-unlink'), isNotNull);
      expect(await eligible.exists(), isFalse);
      expect(await manager.getFileFromCache('after-blocked-unlink'), isNull);
      expect(
        await fileAccess.deleteIfIdle('blocked-unlink', () async {}),
        isTrue,
      );
    },
  );

  test(
    'concurrent cleanup hooks share one scan and a failed scan keeps files',
    () async {
      final file = await _seedFile(
        manager,
        imageRepository,
        fileAccess: fileAccess,
        key: 'cleanup-flight',
        touched: DateTime.now().subtract(const Duration(days: 60)),
      );
      final started = Completer<void>();
      final release = Completer<void>();
      var scans = 0;
      imageRepository.afterLookup = () async {
        scans++;
        started.complete();
        await release.future;
        throw StateError('App index unavailable');
      };
      final first = _runAutomaticCleanup(manager);
      await started.future;
      final second = _runAutomaticCleanup(manager);
      await Future<void>.delayed(Duration.zero);
      expect(scans, 1);
      release.complete();
      await Future.wait([first, second]);
      expect(await file.exists(), isTrue);
      imageRepository.afterLookup = null;
      await _runAutomaticCleanup(manager);
      expect(await file.exists(), isFalse);
    },
  );

  test('ensureCached protects its file through the App index write', () async {
    const key = 'ensure-publishing';
    final file = await _seedFile(
      manager,
      imageRepository,
      fileAccess: fileAccess,
      key: key,
      touched: DateTime.now().subtract(const Duration(days: 60)),
    );
    final started = Completer<void>();
    final release = Completer<void>();
    imageRepository.beforeUpsert = (record) async {
      started.complete();
      await release.future;
    };
    final service = DefaultImageCacheService(
      repository: imageRepository,
      cacheManagerFuture: Future.value(manager),
      directoryResolver: const ImageCacheDirectoryResolver(),
      fileAccess: fileAccess,
    );
    final pending = service.ensureCached(
      const ImageCacheRequest(
        cacheKey: key,
        sourceUrl: 'https://example.invalid/$key.png',
        ownerType: ImageCacheOwnerType.thread,
        ownerId: 'test-thread',
        role: ImageCacheRole.threadInline,
        retentionClass: ImageRetentionClass.sticky,
      ),
    );
    await started.future;
    await _runAutomaticCleanup(manager);
    expect(await file.exists(), isTrue);
    release.complete();
    expect((await pending).success, isTrue);
    imageRepository.beforeUpsert = null;
    await _runAutomaticCleanup(manager);
    expect(await file.exists(), isTrue);
    expect(
      (await imageRepository.getByKey(key))?.retentionClass,
      ImageRetentionClass.sticky,
    );
  });

  test(
    'keeps the original file when it is within the requested width',
    () async {
      const url = 'https://example.invalid/small.png';
      const originalKey = 'small-original';
      const targetWidth = 32;
      final original = await manager.putFile(
        url,
        await _pngBytes(width: 16, height: 12),
        key: originalKey,
        fileExtension: 'png',
      );

      final result = await _lastFileInfo(
        (manager as ImageCacheManager).getImageFile(
          url,
          key: originalKey,
          maxWidth: targetWidth,
        ),
      );

      expect(result.file.path, original.path);
      expect(
        await manager.getFileFromCache('resized_w${targetWidth}_$originalKey'),
        isNull,
      );
    },
  );

  test(
    'creates a bounded copy when the source exceeds the requested width',
    () async {
      const url = 'https://example.invalid/large.png';
      const originalKey = 'large-original';
      const targetWidth = 32;
      final original = await manager.putFile(
        url,
        await _pngBytes(width: 64, height: 40),
        key: originalKey,
        fileExtension: 'png',
      );

      final result = await _lastFileInfo(
        (manager as ImageCacheManager).getImageFile(
          url,
          key: originalKey,
          maxWidth: targetWidth,
        ),
      );
      final dimensions = await _imageDimensions(result.file);

      expect(result.file.path, isNot(original.path));
      expect(dimensions.width, targetWidth);
      expect(dimensions.height, 20);
      expect(
        await manager.getFileFromCache('resized_w${targetWidth}_$originalKey'),
        isNotNull,
      );
      expect(
        p.isWithin(
          p.join(cacheRoot.path, ImageCacheManagerFactory.cacheKey),
          result.file.path,
        ),
        isTrue,
      );
    },
  );
}

final class _HookedImageCacheRepository extends LocalImageCacheRepository {
  _HookedImageCacheRepository(super.database);

  Future<void> Function()? afterLookup;
  Future<void> Function(CachedImageRecord record)? beforeUpsert;

  @override
  Future<void> upsert(CachedImageRecord record) async {
    await beforeUpsert?.call(record);
    await super.upsert(record);
  }

  @override
  Future<Map<String, String>> lookupLocalPaths(
    Iterable<String> cacheKeys,
  ) async {
    final paths = await super.lookupLocalPaths(cacheKeys);
    await afterLookup?.call();
    return paths;
  }
}

Future<void> _runAutomaticCleanup(BaseCacheManager manager) async {
  final repository = (manager as CacheManager).config.repo;
  // Exercise the same public repository hooks used by CacheStore's timer.
  expect(await repository.getObjectsOverCapacity(200), isEmpty);
  expect(await repository.getOldObjects(const Duration(days: 30)), isEmpty);
}

Future<File> _seedFile(
  BaseCacheManager manager,
  LocalImageCacheRepository imageRepository, {
  required ImageCacheFileAccess fileAccess,
  required String key,
  required DateTime touched,
  ImageRetentionClass? retention,
}) => fileAccess.protect(key, () async {
  // Match production publication: aging metadata is not an orphan until the
  // intended App ownership has been written under this same per-key guard.
  final url = 'https://example.invalid/$key.png';
  final file = await manager.putFile(
    url,
    Uint8List.fromList([1, 2, 3]),
    key: key,
    fileExtension: 'png',
  );
  final repository = (manager as CacheManager).config.repo;
  final stored = (await repository.get(key))!;
  await repository.update(
    CacheObject(
      stored.url,
      key: stored.key,
      relativePath: stored.relativePath,
      validTill: stored.validTill,
      id: stored.id,
      touched: touched,
      length: stored.length,
    ),
    setTouchedToNow: false,
  );
  if (retention != null) {
    await imageRepository.upsert(
      _record(key: key, file: file, retention: retention),
    );
  }
  return file;
});

CachedImageRecord _record({
  required String key,
  required File file,
  required ImageRetentionClass retention,
}) {
  final now = DateTime.now();
  return CachedImageRecord(
    cacheKey: key,
    ownerType: ImageCacheOwnerType.thread.dbValue,
    ownerId: 'test-thread',
    role: ImageCacheRole.threadInline.dbValue,
    localPath: file.path,
    bytes: file.lengthSync(),
    protected: retention == ImageRetentionClass.protected,
    retentionClass: retention,
    createdAt: now,
    updatedAt: now,
    lastAccessedAt: now,
  );
}

Future<FileInfo> _lastFileInfo(Stream<FileResponse> responses) async {
  final values = await responses.toList();
  return values.whereType<FileInfo>().last;
}

Future<Uint8List> _pngBytes({required int width, required int height}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) {
    throw StateError('Failed to encode generated PNG fixture.');
  }
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<({int width, int height})> _imageDimensions(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final frame = await codec.getNextFrame();
  final dimensions = (width: frame.image.width, height: frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return dimensions;
}

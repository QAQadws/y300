import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui';

import 'package:file/file.dart' as file;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/services/default_image_cache_service.dart';
import 'package:y300/features/cache/data/providers/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';

void main() {
  test('ensureCached deduplicates concurrent same-key downloads', () async {
    final tempDir = await io.Directory.systemTemp.createTemp(
      'y300-image-cache-dedupe-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final imageFile = io.File('${tempDir.path}/downloaded.jpg');
    await imageFile.writeAsBytes(<int>[1, 2, 3, 4]);
    final downloadCompleter = Completer<String>();
    final downloader = _SpyImageFileDownloader(
      localPath: imageFile.path,
      downloadCompleter: downloadCompleter,
    );
    final service = DefaultImageCacheService(
      repository: _MemoryImageCacheRepository(),
      cacheManagerFuture: Future<BaseCacheManager>.value(_UnusedCacheManager()),
      directoryResolver: const ImageCacheDirectoryResolver(),
      downloader: downloader,
    );
    const request = ImageCacheRequest(
      cacheKey: 'comic-page-dedupe',
      sourceUrl: 'https://bbs.yamibo.com/data/attachment/page.jpg',
      ownerType: ImageCacheOwnerType.comic,
      ownerId: 'yamibo:100',
      role: ImageCacheRole.comicPage,
    );

    final first = service.ensureCached(request);
    final second = service.ensureCached(request);
    await Future<void>.delayed(Duration.zero);

    expect(downloader.downloadCount, 1);
    downloadCompleter.complete(imageFile.path);
    await Future.wait(<Future<CachedImageResult>>[first, second]);
  });

  test('ensureCached passes anti-hotlink headers to downloader', () async {
    final tempDir = await io.Directory.systemTemp.createTemp(
      'y300-image-cache-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final imageFile = io.File('${tempDir.path}/downloaded.jpg');
    await imageFile.writeAsBytes(<int>[1, 2, 3, 4]);
    final downloader = _SpyImageFileDownloader(localPath: imageFile.path);
    final service = DefaultImageCacheService(
      repository: _MemoryImageCacheRepository(),
      cacheManagerFuture: Future<BaseCacheManager>.value(_UnusedCacheManager()),
      directoryResolver: const ImageCacheDirectoryResolver(),
      headerBuilder: const _StaticImageHeaderBuilder(<String, String>{
        'Referer': 'https://bbs.yamibo.com/',
        'Cookie': 'auth=token123',
      }),
      downloader: downloader,
    );

    final result = await service.ensureCached(
      const ImageCacheRequest(
        cacheKey: 'comic-page-1',
        sourceUrl: 'https://bbs.yamibo.com/data/attachment/test.jpg',
        ownerType: ImageCacheOwnerType.comic,
        ownerId: 'yamibo:100',
        role: ImageCacheRole.comicPage,
      ),
    );

    expect(result.success, isTrue);
    expect(downloader.lastHeaders, <String, String>{
      'Referer': 'https://bbs.yamibo.com/',
      'Cookie': 'auth=token123',
    });
  });

  test(
    'ensureCached normalizes relative source url before building headers',
    () async {
      final tempDir = await io.Directory.systemTemp.createTemp(
        'y300-image-cache-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final imageFile = io.File('${tempDir.path}/downloaded.jpg');
      await imageFile.writeAsBytes(<int>[1, 2, 3, 4]);
      final downloader = _SpyImageFileDownloader(localPath: imageFile.path);
      final headerBuilder = _SpyImageHeaderBuilder();
      final repository = _MemoryImageCacheRepository();
      final service = DefaultImageCacheService(
        repository: repository,
        cacheManagerFuture: Future<BaseCacheManager>.value(
          _UnusedCacheManager(),
        ),
        directoryResolver: const ImageCacheDirectoryResolver(),
        headerBuilder: headerBuilder,
        downloader: downloader,
      );

      await service.ensureCached(
        const ImageCacheRequest(
          cacheKey: 'comic-page-1',
          sourceUrl: 'data/attachment/test.jpg',
          ownerType: ImageCacheOwnerType.comic,
          ownerId: 'yamibo:100',
          role: ImageCacheRole.comicPage,
        ),
      );

      expect(
        headerBuilder.lastUrl,
        'https://bbs.yamibo.com/data/attachment/test.jpg',
      );
      expect(
        downloader.lastSourceUrl,
        'https://bbs.yamibo.com/data/attachment/test.jpg',
      );
      expect(
        repository.records['comic-page-1']?.lastSourceUrl,
        'https://bbs.yamibo.com/data/attachment/test.jpg',
      );
    },
  );

  test(
    'ensureCached redownloads when a stable key gets a new source url',
    () async {
      final tempDir = await io.Directory.systemTemp.createTemp(
        'y300-image-cache-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final oldFile = io.File('${tempDir.path}/old.jpg');
      final newFile = io.File('${tempDir.path}/new.jpg');
      await oldFile.writeAsBytes(<int>[1, 2, 3]);
      await newFile.writeAsBytes(<int>[4, 5, 6, 7]);

      final repository = _MemoryImageCacheRepository();
      repository.records['cover/comic/yamibo:100'] = CachedImageRecord(
        cacheKey: 'cover/comic/yamibo:100',
        ownerType: ImageCacheOwnerType.comic.dbValue,
        ownerId: 'yamibo:100',
        role: ImageCacheRole.cover.dbValue,
        lastSourceUrl: 'https://bbs.yamibo.com/data/attachment/old.jpg',
        localPath: oldFile.path,
        bytes: 3,
        protected: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final downloader = _SpyImageFileDownloader(localPath: newFile.path);
      final service = DefaultImageCacheService(
        repository: repository,
        cacheManagerFuture: Future<BaseCacheManager>.value(
          _UnusedCacheManager(),
        ),
        directoryResolver: const ImageCacheDirectoryResolver(),
        downloader: downloader,
      );

      final result = await service.ensureCached(
        const ImageCacheRequest(
          cacheKey: 'cover/comic/yamibo:100',
          sourceUrl: 'https://bbs.yamibo.com/data/attachment/new.jpg',
          ownerType: ImageCacheOwnerType.comic,
          ownerId: 'yamibo:100',
          role: ImageCacheRole.cover,
          protected: true,
        ),
      );

      expect(result.success, isTrue);
      expect(result.localPath, newFile.path);
      expect(result.fromCache, isFalse);
      expect(
        downloader.lastSourceUrl,
        'https://bbs.yamibo.com/data/attachment/new.jpg',
      );
      expect(downloader.lastForce, isTrue);
      expect(
        repository.records['cover/comic/yamibo:100']?.lastSourceUrl,
        'https://bbs.yamibo.com/data/attachment/new.jpg',
      );
    },
  );

  test(
    'deleteByOwner removes all owner records and ignores missing files',
    () async {
      final tempDir = await io.Directory.systemTemp.createTemp(
        'y300-image-cache-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final existingProtected = io.File('${tempDir.path}/protected.jpg');
      final existingPage = io.File('${tempDir.path}/page.jpg');
      await existingProtected.writeAsBytes(<int>[1, 2, 3]);
      await existingPage.writeAsBytes(<int>[4, 5, 6]);

      final repository = _MemoryImageCacheRepository()
        ..records['cover-1'] = CachedImageRecord(
          cacheKey: 'cover-1',
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: 'yamibo:100',
          role: ImageCacheRole.cover.dbValue,
          localPath: existingProtected.path,
          bytes: 3,
          protected: true,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        )
        ..records['page-1'] = CachedImageRecord(
          cacheKey: 'page-1',
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: 'yamibo:100',
          role: ImageCacheRole.comicPage.dbValue,
          localPath: existingPage.path,
          bytes: 3,
          protected: false,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        )
        ..records['missing-1'] = CachedImageRecord(
          cacheKey: 'missing-1',
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: 'yamibo:100',
          role: ImageCacheRole.comicPage.dbValue,
          localPath: '${tempDir.path}/missing.jpg',
          bytes: 0,
          protected: false,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        )
        ..records['other-owner'] = CachedImageRecord(
          cacheKey: 'other-owner',
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: 'yamibo:200',
          role: ImageCacheRole.cover.dbValue,
          localPath: '${tempDir.path}/other.jpg',
          bytes: 0,
          protected: true,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
      final service = DefaultImageCacheService(
        repository: repository,
        cacheManagerFuture: Future<BaseCacheManager>.value(
          _UnusedCacheManager(),
        ),
        directoryResolver: const ImageCacheDirectoryResolver(),
      );

      final deletedCount = await service.deleteByOwner(
        ownerType: ImageCacheOwnerType.comic,
        ownerId: 'yamibo:100',
      );

      expect(deletedCount, 3);
      expect(repository.records.keys, <String>{'other-owner'});
      expect(await existingProtected.exists(), isFalse);
      expect(await existingPage.exists(), isFalse);
    },
  );

  test(
    'clearUnprotectedByRoles deletes only matching unprotected roles',
    () async {
      final tempDir = await io.Directory.systemTemp.createTemp(
        'y300-image-cache-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final comicPageFile = io.File('${tempDir.path}/comic-page.jpg');
      final threadFile = io.File('${tempDir.path}/thread.jpg');
      await comicPageFile.writeAsBytes(<int>[1, 2, 3]);
      await threadFile.writeAsBytes(<int>[4, 5, 6]);

      final repository = _MemoryImageCacheRepository()
        // 命中：漫画页，非保护 -> 删。
        ..records['comic-page-1'] = CachedImageRecord(
          cacheKey: 'comic-page-1',
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: 'yamibo:100',
          role: ImageCacheRole.comicPage.dbValue,
          localPath: comicPageFile.path,
          bytes: 3,
          protected: false,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        )
        // 命中：帖子内联图，非保护 -> 删。
        ..records['thread-1'] = CachedImageRecord(
          cacheKey: 'thread-1',
          ownerType: ImageCacheOwnerType.thread.dbValue,
          ownerId: 'tid-1',
          role: ImageCacheRole.threadInline.dbValue,
          localPath: threadFile.path,
          bytes: 3,
          protected: false,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        )
        // 保留：封面，非保护但 role 不在清理集合。
        ..records['cover-1'] = CachedImageRecord(
          cacheKey: 'cover-1',
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: 'yamibo:100',
          role: ImageCacheRole.cover.dbValue,
          localPath: '${tempDir.path}/cover.jpg',
          bytes: 0,
          protected: false,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        )
        // 保留：漫画页但受保护。
        ..records['protected-page-1'] = CachedImageRecord(
          cacheKey: 'protected-page-1',
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: 'yamibo:100',
          role: ImageCacheRole.comicPage.dbValue,
          localPath: '${tempDir.path}/protected-page.jpg',
          bytes: 0,
          protected: true,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
      final service = DefaultImageCacheService(
        repository: repository,
        cacheManagerFuture: Future<BaseCacheManager>.value(
          _UnusedCacheManager(),
        ),
        directoryResolver: const ImageCacheDirectoryResolver(),
      );

      final deletedCount = await service.clearUnprotectedByRoles(
        roles: const <ImageCacheRole>[
          ImageCacheRole.comicPage,
          ImageCacheRole.threadInline,
        ],
      );

      expect(deletedCount, 2);
      expect(repository.records.keys, <String>{'cover-1', 'protected-page-1'});
      expect(await comicPageFile.exists(), isFalse);
      expect(await threadFile.exists(), isFalse);
    },
  );

  test('clearUnprotectedByRoles with empty roles deletes nothing', () async {
    final repository = _MemoryImageCacheRepository()
      ..records['comic-page-1'] = CachedImageRecord(
        cacheKey: 'comic-page-1',
        ownerType: ImageCacheOwnerType.comic.dbValue,
        ownerId: 'yamibo:100',
        role: ImageCacheRole.comicPage.dbValue,
        bytes: 3,
        protected: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
    final service = DefaultImageCacheService(
      repository: repository,
      cacheManagerFuture: Future<BaseCacheManager>.value(_UnusedCacheManager()),
      directoryResolver: const ImageCacheDirectoryResolver(),
    );

    final deletedCount = await service.clearUnprotectedByRoles(
      roles: const <ImageCacheRole>[],
    );

    expect(deletedCount, 0);
    expect(repository.records.keys, <String>{'comic-page-1'});
  });

  test(
    'recordResolvedDimensions updates existing cache record dimensions',
    () async {
      final repository = _MemoryImageCacheRepository();
      repository.records['page-1'] = CachedImageRecord(
        cacheKey: 'page-1',
        ownerType: ImageCacheOwnerType.thread.dbValue,
        ownerId: 'tid-1',
        role: ImageCacheRole.threadInline.dbValue,
        localPath: '/tmp/page.jpg',
        bytes: 1,
        protected: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final service = DefaultImageCacheService(
        repository: repository,
        cacheManagerFuture: Future<BaseCacheManager>.value(
          _UnusedCacheManager(),
        ),
        directoryResolver: const ImageCacheDirectoryResolver(),
      );

      await service.recordResolvedDimensions(
        cacheKey: 'page-1',
        size: const Size(900, 1200),
      );

      expect(repository.records['page-1']?.width, 900);
      expect(repository.records['page-1']?.height, 1200);
    },
  );

  test('clearUnprotected spares sticky long-term cache', () async {
    final repository = _MemoryImageCacheRepository()
      ..records['thread-1'] = CachedImageRecord(
        cacheKey: 'thread-1',
        ownerType: ImageCacheOwnerType.thread.dbValue,
        ownerId: 'tid-1',
        role: ImageCacheRole.threadInline.dbValue,
        bytes: 3,
        protected: false,
        retentionClass: ImageRetentionClass.ephemeral,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      )
      ..records['smiley-1'] = CachedImageRecord(
        cacheKey: 'smiley-1',
        ownerType: ImageCacheOwnerType.sticker.dbValue,
        ownerId: 'yamibo-smiley-v4',
        role: ImageCacheRole.remoteSmiley.dbValue,
        bytes: 3,
        protected: false,
        retentionClass: ImageRetentionClass.sticky,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      )
      ..records['avatar-1'] = CachedImageRecord(
        cacheKey: 'avatar-1',
        ownerType: ImageCacheOwnerType.profile.dbValue,
        ownerId: 'uid-1',
        role: ImageCacheRole.avatar.dbValue,
        bytes: 3,
        protected: false,
        retentionClass: ImageRetentionClass.recentReader,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
    final service = DefaultImageCacheService(
      repository: repository,
      cacheManagerFuture: Future<BaseCacheManager>.value(_UnusedCacheManager()),
      directoryResolver: const ImageCacheDirectoryResolver(),
    );

    final usage = await service.loadUsage();
    expect(usage.budgetedBytes, 6);
    expect(usage.clearableBytes, 6);
    expect(usage.longTermBytes, 3);

    await service.clearUnprotected();

    // 常规与 recentReader 被清，sticky 保留。
    expect(repository.records.containsKey('thread-1'), isFalse);
    expect(repository.records.containsKey('avatar-1'), isFalse);
    expect(repository.records.containsKey('smiley-1'), isTrue);
  });

  test('pruneToLimit excludes sticky from the regular cache budget', () async {
    final repository = _MemoryImageCacheRepository()
      ..records['smiley-1'] = CachedImageRecord(
        cacheKey: 'smiley-1',
        ownerType: ImageCacheOwnerType.sticker.dbValue,
        ownerId: 'yamibo-smiley-v4',
        role: ImageCacheRole.remoteSmiley.dbValue,
        bytes: 100,
        protected: false,
        retentionClass: ImageRetentionClass.sticky,
        // 更久未访问：若仅按 LRU 会先删它，但 sticky 应后于 ephemeral。
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        lastAccessedAt: DateTime(2026, 1, 1),
      )
      ..records['thread-1'] = CachedImageRecord(
        cacheKey: 'thread-1',
        ownerType: ImageCacheOwnerType.thread.dbValue,
        ownerId: 'tid-1',
        role: ImageCacheRole.threadInline.dbValue,
        bytes: 100,
        protected: false,
        retentionClass: ImageRetentionClass.ephemeral,
        createdAt: DateTime(2026, 2, 1),
        updatedAt: DateTime(2026, 2, 1),
        lastAccessedAt: DateTime(2026, 2, 1),
      );
    final service = DefaultImageCacheService(
      repository: repository,
      cacheManagerFuture: Future<BaseCacheManager>.value(_UnusedCacheManager()),
      directoryResolver: const ImageCacheDirectoryResolver(),
    );

    // 常规缓存 100，长期缓存 100 不计入额度。限额 50 时只删常规缓存。
    await service.pruneToLimit(maxBytes: 50);

    expect(repository.records.containsKey('thread-1'), isFalse);
    expect(repository.records.containsKey('smiley-1'), isTrue);
  });
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder(this.headers);

  final Map<String, String> headers;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async => headers;
}

class _SpyImageHeaderBuilder implements ImageRequestHeaderBuilder {
  String? lastUrl;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    lastUrl = imageUrl;
    return const <String, String>{'Referer': 'https://bbs.yamibo.com/'};
  }
}

class _SpyImageFileDownloader implements ImageFileDownloader {
  _SpyImageFileDownloader({required this.localPath, this.downloadCompleter});

  final String localPath;
  final Completer<String>? downloadCompleter;
  int downloadCount = 0;
  Map<String, String>? lastHeaders;
  String? lastSourceUrl;
  bool? lastForce;

  @override
  Future<String> download({
    required BaseCacheManager cacheManager,
    required String sourceUrl,
    required String cacheKey,
    Map<String, String>? headers,
    bool force = false,
  }) async {
    downloadCount += 1;
    lastSourceUrl = sourceUrl;
    lastHeaders = headers;
    lastForce = force;
    return downloadCompleter?.future ?? localPath;
  }
}

class _MemoryImageCacheRepository implements ImageCacheRepository {
  final Map<String, CachedImageRecord> records = <String, CachedImageRecord>{};

  @override
  Future<int> calculateUsageBytes({required bool includeProtected}) async {
    return records.values
        .where((record) => includeProtected || !record.protected)
        .fold<int>(0, (sum, record) => sum + record.bytes);
  }

  @override
  Future<List<ImageCacheUsageGroup>> calculateUsageGroups() async {
    return records.values
        .map((record) {
          return ImageCacheUsageGroup(
            ownerType: record.ownerType,
            role: record.role,
            retentionClass: record.retentionClass.dbValue,
            protected: record.protected,
            bytes: record.bytes,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> deleteByKey(String cacheKey) async {
    records.remove(cacheKey);
  }

  @override
  Future<CachedImageRecord?> getByKey(String cacheKey) async =>
      records[cacheKey];

  @override
  Future<List<CachedImageRecord>> listByOwner({
    required String ownerType,
    required String ownerId,
  }) async {
    return records.values
        .where(
          (record) =>
              record.ownerType == ownerType && record.ownerId == ownerId,
        )
        .toList(growable: false);
  }

  @override
  Future<List<CachedImageRecord>> listUnprotectedByAccessTime() async {
    final unprotected =
        records.values.where((record) => !record.protected).toList()
          ..sort((a, b) {
            final aTime = a.lastAccessedAt ?? a.updatedAt;
            final bTime = b.lastAccessedAt ?? b.updatedAt;
            return aTime.compareTo(bTime);
          });
    return unprotected;
  }

  @override
  Future<List<CachedImageRecord>> listUnprotectedByRoles({
    required List<String> roles,
  }) async {
    if (roles.isEmpty) {
      return const <CachedImageRecord>[];
    }
    return records.values
        .where((record) => !record.protected && roles.contains(record.role))
        .toList(growable: false);
  }

  @override
  Future<List<CachedImageRecord>> listProtectedCovers() async {
    return records.values
        .where(
          (record) =>
              record.protected &&
              (record.role == ImageCacheRole.cover.dbValue ||
                  record.role == ImageCacheRole.customCover.dbValue),
        )
        .toList(growable: false);
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {}

  @override
  Future<void> updateDimensions({
    required String cacheKey,
    required int width,
    required int height,
    required DateTime updatedAt,
  }) async {
    final record = records[cacheKey];
    if (record == null) {
      return;
    }
    records[cacheKey] = record.copyWith(
      width: width,
      height: height,
      updatedAt: updatedAt,
      lastAccessedAt: updatedAt,
    );
  }

  @override
  Future<void> upsert(CachedImageRecord record) async {
    records[record.cacheKey] = record;
  }
}

class _UnusedCacheManager implements BaseCacheManager {
  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> emptyCache() async {}

  @override
  Stream<FileInfo> getFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {}

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => null;

  @override
  Future<FileInfo?> getFileFromMemory(String key) async => null;

  @override
  Future<file.File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<file.File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<file.File> putFileStream(
    String url,
    Stream<List<int>> source, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeFile(String key) async {}
}

import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui';

import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/cache/data/services/default_image_cache_service.dart';
import 'package:y300/features/cache/data/providers/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/data/services/image_cache_diagnostic_recorder.dart';
import 'package:y300/features/cache/data/services/image_cache_failure_backoff.dart';
import 'package:y300/features/cache/data/services/y300_forum_resource_file_service.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';

void main() {
  group('confirmed missing image cooldown', () {
    test(
      '45 sequential consumers produce one download and diagnostic',
      () async {
        final downloader = _ControlledFailureDownloader();
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final repository = _MemoryImageCacheRepository();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
          repository: repository,
        );

        for (var consumer = 0; consumer < 45; consumer++) {
          final result = await service.ensureCached(_missingImageRequest());
          expect(result.success, isFalse);
        }

        expect(downloader.downloadCount, 1);
        expect(recorder.events, hasLength(1));
        expect(
          recorder.events.single.stage,
          ImageCacheDiagnosticStage.download,
        );
        expect(
          recorder.events.single.failureKind,
          ImageCacheDiagnosticFailureKind.notFound,
        );
        expect(repository.records, isEmpty);
      },
    );

    test(
      'cooldown expires from actual failure and hits do not renew it',
      () async {
        var now = DateTime.utc(2026, 10, 14);
        final downloader = _ControlledFailureDownloader();
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
          failureBackoff: ImageCacheFailureBackoff(now: () => now),
        );

        await service.ensureCached(_missingImageRequest());
        now = now.add(const Duration(seconds: 29));
        await service.ensureCached(_missingImageRequest());
        expect(downloader.downloadCount, 1);
        now = now.add(const Duration(seconds: 1));
        await service.ensureCached(_missingImageRequest());
        expect(downloader.downloadCount, 2);
        expect(recorder.events, hasLength(2));
      },
    );

    test(
      'a slow download starts cooldown when its failure completes',
      () async {
        var now = DateTime.utc(2026, 10, 14);
        final completion = Completer<String>();
        final downloader = _ControlledFailureDownloader(
          onDownload: (call) => call == 1
              ? completion.future
              : Future<String>.error(_confirmedNotFound),
        );
        final service = _missingImageService(
          downloader: downloader,
          failureBackoff: ImageCacheFailureBackoff(now: () => now),
        );
        final request = _missingImageRequest();
        final first = service.ensureCached(request);
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(minutes: 1));
        completion.completeError(_confirmedNotFound);
        await first;

        now = now.add(const Duration(seconds: 29));
        await service.ensureCached(request);
        expect(downloader.downloadCount, 1);
        now = now.add(const Duration(seconds: 1));
        await service.ensureCached(request);
        expect(downloader.downloadCount, 2);
      },
    );

    test(
      'an expired missing resource can recover into the positive cache',
      () async {
        var now = DateTime.utc(2026, 10, 14);
        final imageFile = await _temporaryFailureCacheImage();
        final repository = _MemoryImageCacheRepository();
        final downloader = _ControlledFailureDownloader(
          onDownload: (call) => call == 1
              ? Future<String>.error(_confirmedNotFound)
              : Future<String>.value(imageFile.path),
        );
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final service = _missingImageService(
          downloader: downloader,
          repository: repository,
          recorder: recorder,
          failureBackoff: ImageCacheFailureBackoff(now: () => now),
        );
        final request = _missingImageRequest();
        expect((await service.ensureCached(request)).success, isFalse);
        now = now.add(const Duration(seconds: 30));
        final recovered = await service.ensureCached(request);
        expect(recovered.success, isTrue);
        expect(recovered.fromCache, isFalse);
        expect(recovered.localPath, imageFile.path);
        expect(repository.records[request.cacheKey]?.localPath, imageFile.path);
        expect((await service.ensureCached(request)).fromCache, isTrue);
        expect(downloader.downloadCount, 2);
        expect(recorder.events, hasLength(1));
      },
    );

    test(
      'valid indexed file takes priority and clears remembered failure',
      () async {
        final imageFile = await _temporaryFailureCacheImage();
        final repository = _MemoryImageCacheRepository();
        final downloader = _ControlledFailureDownloader();
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
          repository: repository,
        );
        final request = _missingImageRequest();
        await service.ensureCached(request);
        repository.records[request.cacheKey] = _cachedMissingImageRecord(
          request,
          imageFile.path,
        );

        final cached = await service.ensureCached(request);
        expect(cached.success, isTrue);
        expect(cached.fromCache, isTrue);
        expect(cached.localPath, imageFile.path);
        expect(downloader.downloadCount, 1);
        expect(recorder.events, hasLength(1));

        await imageFile.delete();
        await service.ensureCached(request);
        expect(downloader.downloadCount, 2);
      },
    );

    test(
      'valid cache manager file takes priority over remembered failure',
      () async {
        final imageFile = await _temporaryFailureCacheImage();
        final manager = _MutableFileCacheManager();
        final downloader = _ControlledFailureDownloader();
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
          manager: manager,
        );
        final request = _missingImageRequest();
        await service.ensureCached(request);
        manager.cached = FileInfo(
          const LocalFileSystem().file(imageFile.path),
          FileSource.Cache,
          DateTime.utc(2026, 10, 15),
          request.sourceUrl,
        );

        final result = await service.ensureCached(request);
        expect(result.success, isTrue);
        expect(result.fromCache, isTrue);
        expect(result.localPath, imageFile.path);
        expect(downloader.downloadCount, 1);
        expect(recorder.events, hasLength(1));
      },
    );

    test(
      'source or referer changes can download while the original is cooling',
      () async {
        final downloader = _ControlledFailureDownloader();
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
        );
        final original = _missingImageRequest();

        await service.ensureCached(original);
        await service.ensureCached(
          _missingImageRequest(
            sourceUrl: 'https://bbs.yamibo.com/data/attachment/replaced.jpg',
          ),
        );
        await service.ensureCached(
          _missingImageRequest(
            referer: 'https://bbs.yamibo.com/thread-2-1-1.html',
          ),
        );
        await service.ensureCached(original);

        expect(downloader.downloadCount, 3);
        expect(recorder.events, hasLength(3));
      },
    );

    test(
      'trimmed key referer and resolved relative URL share cooldown',
      () async {
        final downloader = _ControlledFailureDownloader();
        final service = _missingImageService(downloader: downloader);

        await service.ensureCached(_missingImageRequest());
        await service.ensureCached(
          _missingImageRequest(
            cacheKey: ' missing/image ',
            sourceUrl: 'data/attachment/missing.jpg',
            referer: ' https://bbs.yamibo.com/thread-1-1-1.html ',
          ),
        );

        expect(downloader.downloadCount, 1);
      },
    );

    test(
      'concurrent consumers share the same failing download and diagnostic',
      () async {
        final completion = Completer<String>();
        final downloader = _ControlledFailureDownloader(
          onDownload: (_) => completion.future,
        );
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
        );
        final requests = List.generate(
          45,
          (_) => service.ensureCached(_missingImageRequest()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(downloader.downloadCount, 1);
        completion.completeError(_confirmedNotFound);

        final results = await Future.wait(requests);
        expect(results.map((result) => result.success), everyElement(isFalse));
        await service.ensureCached(_missingImageRequest());
        expect(downloader.downloadCount, 1);
        expect(recorder.events, hasLength(1));
      },
    );

    test(
      'shared different referer request only remembers initiating headers',
      () async {
        final completion = Completer<String>();
        final downloader = _ControlledFailureDownloader(
          onDownload: (call) => call == 1
              ? completion.future
              : Future<String>.error(_confirmedNotFound),
        );
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
        );
        final initiatingRequest = _missingImageRequest();
        final otherRefererRequest = _missingImageRequest(
          referer: 'https://bbs.yamibo.com/thread-2-1-1.html',
        );
        final first = service.ensureCached(initiatingRequest);
        await Future<void>.delayed(Duration.zero);
        final shared = service.ensureCached(otherRefererRequest);

        expect(identical(first, shared), isTrue);
        expect(downloader.downloadCount, 1);
        completion.completeError(_confirmedNotFound);
        expect((await first).success, isFalse);
        expect((await shared).success, isFalse);
        expect(recorder.events, hasLength(1));

        expect(
          (await service.ensureCached(otherRefererRequest)).success,
          isFalse,
        );
        expect(downloader.downloadCount, 2);
        expect(
          (await service.ensureCached(initiatingRequest)).success,
          isFalse,
        );
        expect(downloader.downloadCount, 2);
        expect(recorder.events, hasLength(2));
      },
    );

    test('explicit retry only clears the requested missing resource', () async {
      final downloader = _ControlledFailureDownloader();
      final service = _missingImageService(downloader: downloader);
      final first = _missingImageRequest();
      final second = _missingImageRequest(cacheKey: 'other/image');
      await service.ensureCached(first);
      await service.ensureCached(second);

      final ImageCacheFailureControl retryControl = service;
      retryControl.allowRetry(first);
      await service.ensureCached(first);
      await service.ensureCached(second);
      await service.ensureCached(first);

      expect(downloader.downloadCount, 3);
    });

    test(
      'retry during a download shares it and rejects its late cooldown',
      () async {
        final completion = Completer<String>();
        final downloader = _ControlledFailureDownloader(
          onDownload: (call) => call == 1
              ? completion.future
              : Future<String>.error(_confirmedNotFound),
        );
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
        );
        final request = _missingImageRequest();
        final first = service.ensureCached(request);
        await Future<void>.delayed(Duration.zero);
        service.allowRetry(request);
        final retry = service.ensureCached(request);

        expect(identical(first, retry), isTrue);
        expect(downloader.downloadCount, 1);
        completion.completeError(_confirmedNotFound);
        await Future.wait(<Future<CachedImageResult>>[first, retry]);
        await service.ensureCached(request);
        await service.ensureCached(request);

        expect(downloader.downloadCount, 2);
        expect(recorder.events, hasLength(2));
      },
    );

    test(
      'new session clears remembered missing resources including A B A',
      () async {
        var sessionScope = Object();
        final downloader = _ControlledFailureDownloader();
        final service = _missingImageService(
          downloader: downloader,
          failureScopeFor: () => sessionScope,
        );
        final request = _missingImageRequest();
        await service.ensureCached(request);
        await service.ensureCached(request);
        expect(downloader.downloadCount, 1);

        sessionScope = Object();
        await service.ensureCached(request);
        await service.ensureCached(request);
        expect(downloader.downloadCount, 2);

        // Re-entering the same account still creates a new session token.
        sessionScope = Object();
        await service.ensureCached(request);
        await service.ensureCached(request);
        expect(downloader.downloadCount, 3);
      },
    );

    test(
      'session change rejects old failure even before another ensure call',
      () async {
        var sessionScope = Object();
        final completion = Completer<String>();
        final downloader = _ControlledFailureDownloader(
          onDownload: (call) => call == 1
              ? completion.future
              : Future<String>.error(_confirmedNotFound),
        );
        final service = _missingImageService(
          downloader: downloader,
          failureScopeFor: () => sessionScope,
        );
        final request = _missingImageRequest();
        final oldSession = service.ensureCached(request);
        await Future<void>.delayed(Duration.zero);
        sessionScope = Object();
        completion.completeError(_confirmedNotFound);
        expect((await oldSession).success, isFalse);

        await service.ensureCached(request);
        await service.ensureCached(request);
        expect(downloader.downloadCount, 2);
      },
    );

    test(
      'session A B A while an old task is active cannot restore cooldown',
      () async {
        var sessionScope = Object();
        final completion = Completer<String>();
        final downloader = _ControlledFailureDownloader(
          onDownload: (call) => call == 1
              ? completion.future
              : Future<String>.error(_confirmedNotFound),
        );
        final service = _missingImageService(
          downloader: downloader,
          failureScopeFor: () => sessionScope,
        );
        final request = _missingImageRequest();
        final firstSession = service.ensureCached(request);
        await Future<void>.delayed(Duration.zero);
        sessionScope = Object();
        final secondSession = service.ensureCached(request);
        sessionScope = Object();
        final newFirstSession = service.ensureCached(request);
        expect(downloader.downloadCount, 1);
        completion.completeError(_confirmedNotFound);
        await Future.wait(<Future<CachedImageResult>>[
          firstSession,
          secondSession,
          newFirstSession,
        ]);

        await service.ensureCached(request);
        await service.ensureCached(request);
        expect(downloader.downloadCount, 2);
      },
    );

    test('cooldown storage is bounded and preserves recent hits', () async {
      final downloader = _ControlledFailureDownloader();
      final service = _missingImageService(
        downloader: downloader,
        failureBackoff: ImageCacheFailureBackoff(maxEntries: 2),
      );
      final first = _missingImageRequest(cacheKey: 'missing/1');
      final second = _missingImageRequest(cacheKey: 'missing/2');
      final third = _missingImageRequest(cacheKey: 'missing/3');
      await service.ensureCached(first);
      await service.ensureCached(second);
      await service.ensureCached(first);
      await service.ensureCached(third);
      await service.ensureCached(first);
      expect(downloader.downloadCount, 3);
      await service.ensureCached(second);
      expect(downloader.downloadCount, 4);
    });

    test('backward clock changes never extend a remembered failure', () async {
      var now = DateTime.utc(2026, 10, 14);
      final downloader = _ControlledFailureDownloader();
      final service = _missingImageService(
        downloader: downloader,
        failureBackoff: ImageCacheFailureBackoff(now: () => now),
      );
      await service.ensureCached(_missingImageRequest());
      now = now.subtract(const Duration(seconds: 1));
      await service.ensureCached(_missingImageRequest());
      expect(downloader.downloadCount, 2);
    });

    final uncachedFailures = <(String, Object)>[
      (
        'unauthorized 401',
        _resourceFailure(ForumResourceFailureKind.unauthorized, 401),
      ),
      (
        'unauthorized 403',
        _resourceFailure(ForumResourceFailureKind.unauthorized, 403),
      ),
      (
        'WAF challenge',
        _resourceFailure(ForumResourceFailureKind.securityChallenge, 405),
      ),
      ('timeout', _resourceFailure(ForumResourceFailureKind.timeout)),
      ('network', _resourceFailure(ForumResourceFailureKind.network)),
      (
        'not-found without HTTP status',
        _resourceFailure(ForumResourceFailureKind.notFound),
      ),
      (
        'not-found 410',
        _resourceFailure(ForumResourceFailureKind.notFound, 410),
      ),
      ('server 404', _resourceFailure(ForumResourceFailureKind.server, 404)),
      (
        'partial resource stream',
        const ForumResourceStreamException(
          failure: ForumResourceFailure(
            kind: ForumResourceFailureKind.notFound,
            code: 'resource_stream_failed',
            statusCode: 404,
          ),
          bytesReceived: 7,
        ),
      ),
      ('untyped error', StateError('resource_not_found')),
    ];
    for (final (label, error) in uncachedFailures) {
      test('$label does not suppress later download attempts', () async {
        final downloader = _ControlledFailureDownloader(failure: error);
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
        );
        await service.ensureCached(_missingImageRequest());
        await service.ensureCached(_missingImageRequest());
        expect(downloader.downloadCount, 2);
        expect(recorder.events, hasLength(2));
      });
    }

    test(
      'a typed 404 during cache lookup is not remembered as remote absence',
      () async {
        final manager = _MutableFileCacheManager()
          ..lookupFailure = _confirmedNotFound;
        final recorder = _RecordingImageCacheDiagnosticRecorder();
        final downloader = _ControlledFailureDownloader();
        final service = _missingImageService(
          downloader: downloader,
          recorder: recorder,
          manager: manager,
        );
        await service.ensureCached(_missingImageRequest());
        manager.lookupFailure = null;
        await service.ensureCached(_missingImageRequest());

        expect(downloader.downloadCount, 1);
        expect(recorder.events, hasLength(2));
        expect(
          recorder.events.first.stage,
          ImageCacheDiagnosticStage.cacheLookup,
        );
        expect(recorder.events.last.stage, ImageCacheDiagnosticStage.download);
      },
    );
  });

  test(
    'download failures emit one privacy-safe structured diagnostic',
    () async {
      final recorder = _RecordingImageCacheDiagnosticRecorder();
      final service = DefaultImageCacheService(
        repository: _MemoryImageCacheRepository(),
        cacheManagerFuture: Future<BaseCacheManager>.value(
          _UnusedCacheManager(),
        ),
        directoryResolver: const ImageCacheDirectoryResolver(),
        downloader: const _FailingImageFileDownloader(),
        diagnosticRecorder: recorder,
      );
      const cacheKey = 'private/cache/key/123';

      final result = await service.ensureCached(
        const ImageCacheRequest(
          cacheKey: cacheKey,
          sourceUrl:
              'https://bbs.yamibo.com/forum.php?mod=image&aid=123&key=secret',
          referer:
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=private',
          ownerType: ImageCacheOwnerType.composer,
          ownerId: 'private-owner',
          role: ImageCacheRole.composerUnusedAttachment,
        ),
      );

      expect(result.success, isFalse);
      expect(recorder.events, hasLength(1));
      final event = recorder.events.single;
      expect(event.stage, ImageCacheDiagnosticStage.download);
      expect(event.ownerType, ImageCacheOwnerType.composer.dbValue);
      expect(event.role, ImageCacheRole.composerUnusedAttachment.dbValue);
      expect(event.failureKind, ImageCacheDiagnosticFailureKind.invalidContent);
      expect(event.reasonCode, 'resource_is_not_image');
      expect(event.cacheKeyFingerprint, isNot(contains(cacheKey)));
      expect(event.cacheKeyFingerprint, hasLength(16));
    },
  );

  test('diagnostic recorder failures never change cache result', () async {
    final service = DefaultImageCacheService(
      repository: _MemoryImageCacheRepository(),
      cacheManagerFuture: Future<BaseCacheManager>.value(_UnusedCacheManager()),
      directoryResolver: const ImageCacheDirectoryResolver(),
      downloader: const _FailingImageFileDownloader(),
      diagnosticRecorder: const _ThrowingImageCacheDiagnosticRecorder(),
    );

    final result = await service.ensureCached(
      const ImageCacheRequest(
        cacheKey: 'failure-isolation',
        sourceUrl: 'https://bbs.yamibo.com/image.png',
        ownerType: ImageCacheOwnerType.thread,
        ownerId: 'thread-owner',
        role: ImageCacheRole.threadInline,
      ),
    );

    expect(result.success, isFalse);
  });

  test(
    'manager initialization failures are classified and contained',
    () async {
      final recorder = _RecordingImageCacheDiagnosticRecorder();
      final managerCompleter = Completer<BaseCacheManager>();
      final service = DefaultImageCacheService(
        repository: _MemoryImageCacheRepository(),
        cacheManagerFuture: managerCompleter.future,
        directoryResolver: const ImageCacheDirectoryResolver(),
        diagnosticRecorder: recorder,
      );

      final resultFuture = service.ensureCached(
        const ImageCacheRequest(
          cacheKey: 'manager-failure',
          sourceUrl: 'https://bbs.yamibo.com/image.png',
          ownerType: ImageCacheOwnerType.thread,
          ownerId: 'thread-owner',
          role: ImageCacheRole.threadInline,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      managerCompleter.completeError(StateError('manager unavailable'));
      final result = await resultFuture;

      expect(result.success, isFalse);
      expect(
        recorder.events.single.stage,
        ImageCacheDiagnosticStage.managerInitialization,
      );
      expect(
        recorder.events.single.failureKind,
        ImageCacheDiagnosticFailureKind.cacheManager,
      );
    },
  );

  test('typed resource stream diagnostics retain available byte count', () {
    final event = buildImageCacheFailureDiagnostic(
      stage: ImageCacheDiagnosticStage.download,
      cacheKey: 'stream-failure',
      ownerType: ImageCacheOwnerType.comic,
      role: ImageCacheRole.comicPage,
      error: const ForumResourceStreamException(
        failure: ForumResourceFailure(
          kind: ForumResourceFailureKind.network,
          code: 'resource_stream_failed',
        ),
        bytesReceived: 23,
      ),
      elapsed: const Duration(milliseconds: 8),
    );

    expect(event.failureKind, ImageCacheDiagnosticFailureKind.network);
    expect(event.reasonCode, 'resource_stream_failed');
    expect(event.bytesReceived, 23);
  });

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

  test(
    'ensureCached passes only the resource referer to cache manager',
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
      final service = DefaultImageCacheService(
        repository: _MemoryImageCacheRepository(),
        cacheManagerFuture: Future<BaseCacheManager>.value(
          _UnusedCacheManager(),
        ),
        directoryResolver: const ImageCacheDirectoryResolver(),
        downloader: downloader,
      );

      final result = await service.ensureCached(
        const ImageCacheRequest(
          cacheKey: 'comic-page-1',
          sourceUrl: 'https://bbs.yamibo.com/data/attachment/test.jpg',
          referer: 'https://bbs.yamibo.com/thread-1-1-1.html',
          ownerType: ImageCacheOwnerType.comic,
          ownerId: 'yamibo:100',
          role: ImageCacheRole.comicPage,
        ),
      );

      expect(result.success, isTrue);
      expect(downloader.lastHeaders, <String, String>{
        'Referer': 'https://bbs.yamibo.com/thread-1-1-1.html',
      });
    },
  );

  test(
    'ensureCached normalizes relative source url before downloading',
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
      final repository = _MemoryImageCacheRepository();
      final service = DefaultImageCacheService(
        repository: repository,
        cacheManagerFuture: Future<BaseCacheManager>.value(
          _UnusedCacheManager(),
        ),
        directoryResolver: const ImageCacheDirectoryResolver(),
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

  test(
    'dimension single-flight preserves real file and metadata validation',
    () async {
      final tempDir = await io.Directory.systemTemp.createTemp(
        'y300-dimension-index-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final image = io.File('${tempDir.path}/cached.jpg');
      await image.writeAsBytes(<int>[1, 2, 3]);
      const key = 'cover/dimension-test';
      final repository = _MemoryImageCacheRepository()
        ..records[key] = CachedImageRecord(
          cacheKey: key,
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: 'dimension-owner',
          role: ImageCacheRole.cover.dbValue,
          localPath: image.path,
          bytes: 3,
          width: 320,
          height: 200,
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
      final index = CacheRecordForumImageDimensionIndex(
        imageCacheService: service,
        imageRequestResolver: const DefaultForumImageRequestResolver(),
      );
      final spec = ForumImageLoadSpec(
        kind: ForumImageKind.cover,
        url: Uri.parse('https://bbs.yamibo.com/cache-dimension-test.jpg'),
        ownerId: 'dimension-owner',
        cacheKey: key,
      );
      final results = await Future.wait(
        List.generate(10, (_) => index.getBySpec(spec)),
      );
      expect(
        results.map((value) => value?.size),
        everyElement(const Size(320, 200)),
      );
      expect(repository.getByKeyCalls, 1);
      expect(repository.records[key]?.lastAccessedAt, isNull);
      expect(repository.touchCalls, 0);

      await image.delete();
      expect(await index.getBySpec(spec), isNull);
      expect(repository.getByKeyCalls, 2);

      await image.writeAsBytes(<int>[1, 2, 3, 4, 5, 6, 7]);
      expect((await service.peekCached(key))?.bytes, 7);
      await index.recordDecodedDimensions(
        spec: spec,
        size: const Size(640, 400),
      );
      final recordedAccess = repository.records[key]?.lastAccessedAt;
      expect((await index.getBySpec(spec))?.size, const Size(640, 400));
      expect(repository.records[key]?.lastAccessedAt, recordedAccess);
      expect(repository.touchCalls, 0);

      repository.records.remove(key);
      expect(await index.getBySpec(spec), isNull);
    },
  );

  test(
    'last known dimensions prefer current key then newest matching owner',
    () async {
      final repository = _MemoryImageCacheRepository()
        ..records['current-head'] = CachedImageRecord(
          cacheKey: 'current-head',
          ownerType: ImageCacheOwnerType.forum.dbValue,
          ownerId: 'forum:30',
          role: ImageCacheRole.forumHeadImage.dbValue,
          bytes: 1,
          width: 1200,
          height: 300,
          protected: false,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        )
        ..records['newer-head'] = CachedImageRecord(
          cacheKey: 'newer-head',
          ownerType: ImageCacheOwnerType.forum.dbValue,
          ownerId: 'forum:30',
          role: ImageCacheRole.forumHeadImage.dbValue,
          bytes: 1,
          width: 1600,
          height: 500,
          protected: false,
          createdAt: DateTime(2026, 1, 2),
          updatedAt: DateTime(2026, 1, 2),
        )
        ..records['other-forum'] = CachedImageRecord(
          cacheKey: 'other-forum',
          ownerType: ImageCacheOwnerType.forum.dbValue,
          ownerId: 'forum:33',
          role: ImageCacheRole.forumHeadImage.dbValue,
          bytes: 1,
          width: 999,
          height: 111,
          protected: false,
          createdAt: DateTime(2026, 1, 3),
          updatedAt: DateTime(2026, 1, 3),
        );
      final service = DefaultImageCacheService(
        repository: repository,
        cacheManagerFuture: Future<BaseCacheManager>.value(
          _UnusedCacheManager(),
        ),
        directoryResolver: const ImageCacheDirectoryResolver(),
      );

      final current = await service.getLastKnownDimensions(
        ownerType: ImageCacheOwnerType.forum,
        ownerId: 'forum:30',
        role: ImageCacheRole.forumHeadImage,
        preferredCacheKey: 'current-head',
      );
      final latest = await service.getLastKnownDimensions(
        ownerType: ImageCacheOwnerType.forum,
        ownerId: 'forum:30',
        role: ImageCacheRole.forumHeadImage,
        preferredCacheKey: 'missing-head',
      );

      expect(current, const Size(1200, 300));
      expect(latest, const Size(1600, 500));
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

const _confirmedNotFound = ForumResourceFileServiceException(
  ForumResourceFailure(
    kind: ForumResourceFailureKind.notFound,
    code: 'resource_not_found',
    statusCode: 404,
  ),
);

ImageCacheRequest _missingImageRequest({
  String cacheKey = 'missing/image',
  String sourceUrl = 'https://bbs.yamibo.com/data/attachment/missing.jpg',
  String? referer = 'https://bbs.yamibo.com/thread-1-1-1.html',
}) => ImageCacheRequest(
  cacheKey: cacheKey,
  sourceUrl: sourceUrl,
  referer: referer,
  ownerType: ImageCacheOwnerType.thread,
  ownerId: 'thread-owner',
  role: ImageCacheRole.threadInline,
);

DefaultImageCacheService _missingImageService({
  required _ControlledFailureDownloader downloader,
  _MemoryImageCacheRepository? repository,
  _RecordingImageCacheDiagnosticRecorder? recorder,
  BaseCacheManager? manager,
  ImageCacheFailureBackoff? failureBackoff,
  Object? Function()? failureScopeFor,
}) => DefaultImageCacheService(
  repository: repository ?? _MemoryImageCacheRepository(),
  cacheManagerFuture: Future<BaseCacheManager>.value(
    manager ?? _UnusedCacheManager(),
  ),
  directoryResolver: const ImageCacheDirectoryResolver(),
  downloader: downloader,
  diagnosticRecorder: recorder ?? const NoopImageCacheDiagnosticRecorder(),
  failureBackoff: failureBackoff,
  failureScopeFor: failureScopeFor,
);

Future<io.File> _temporaryFailureCacheImage() async {
  final directory = await io.Directory.systemTemp.createTemp(
    'y300-image-failure-cooldown-',
  );
  addTearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  final imageFile = io.File('${directory.path}/valid-cache.jpg');
  await imageFile.writeAsBytes(<int>[1, 2, 3]);
  return imageFile;
}

CachedImageRecord _cachedMissingImageRecord(
  ImageCacheRequest request,
  String path,
) => CachedImageRecord(
  cacheKey: request.cacheKey,
  ownerType: request.ownerType.dbValue,
  ownerId: request.ownerId,
  role: request.role.dbValue,
  lastSourceUrl: request.sourceUrl,
  localPath: path,
  bytes: 3,
  protected: false,
  createdAt: DateTime.utc(2026, 10, 14),
  updatedAt: DateTime.utc(2026, 10, 14),
);

ForumResourceFileServiceException _resourceFailure(
  ForumResourceFailureKind kind, [
  int? statusCode,
]) => ForumResourceFileServiceException(
  ForumResourceFailure(
    kind: kind,
    code: 'resource_failure',
    statusCode: statusCode,
  ),
);

class _ControlledFailureDownloader implements ImageFileDownloader {
  _ControlledFailureDownloader({
    this.failure = _confirmedNotFound,
    this.onDownload,
  });

  final Object failure;
  final Future<String> Function(int call)? onDownload;
  int downloadCount = 0;

  @override
  Future<String> download({
    required BaseCacheManager cacheManager,
    required String sourceUrl,
    required String cacheKey,
    Map<String, String>? headers,
    bool force = false,
  }) async {
    downloadCount++;
    final callback = onDownload;
    if (callback != null) return callback(downloadCount);
    throw failure;
  }
}

class _MutableFileCacheManager extends _UnusedCacheManager {
  FileInfo? cached;
  Object? lookupFailure;

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    final failure = lookupFailure;
    if (failure != null) throw failure;
    return cached;
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

class _FailingImageFileDownloader implements ImageFileDownloader {
  const _FailingImageFileDownloader();

  @override
  Future<String> download({
    required BaseCacheManager cacheManager,
    required String sourceUrl,
    required String cacheKey,
    Map<String, String>? headers,
    bool force = false,
  }) {
    throw const ForumResourceFileServiceException(
      ForumResourceFailure(
        kind: ForumResourceFailureKind.invalidContent,
        code: 'resource_is_not_image',
        statusCode: 200,
      ),
    );
  }
}

class _RecordingImageCacheDiagnosticRecorder
    implements ImageCacheDiagnosticRecorder {
  final List<ImageCacheFailureDiagnostic> events =
      <ImageCacheFailureDiagnostic>[];

  @override
  void recordFailure(ImageCacheFailureDiagnostic event) {
    events.add(event);
  }
}

class _ThrowingImageCacheDiagnosticRecorder
    implements ImageCacheDiagnosticRecorder {
  const _ThrowingImageCacheDiagnosticRecorder();

  @override
  void recordFailure(ImageCacheFailureDiagnostic event) {
    throw StateError('diagnostic recorder failed');
  }
}

class _MemoryImageCacheRepository implements ImageCacheRepository {
  final Map<String, CachedImageRecord> records = <String, CachedImageRecord>{};
  int getByKeyCalls = 0;
  int touchCalls = 0;

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
  Future<CachedImageRecord?> getByKey(String cacheKey) async {
    getByKeyCalls++;
    return records[cacheKey];
  }

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
  Future<void> touch(String cacheKey, DateTime accessedAt) async {
    touchCalls++;
  }

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

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/library_shared/data/services/default_work_purge_service.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  group('DefaultWorkPurgeService', () {
    test('comic purge clears core collaborators before best-effort cleanup', () async {
      final calls = <String>[];
      final service = DefaultWorkPurgeService(
        purgeComicWork: ({required comicId}) async {
          calls.add('comic:$comicId');
        },
        purgeNovelWork: ({required novelId}) async {
          fail('novel purge should not be used');
        },
        purgeLibraryWorkState: ({
          required moduleKey,
          required workId,
        }) async {
          calls.add('state:$moduleKey:$workId');
        },
        markFavoriteRemovedByWorkId: (workId) async {
          calls.add('favorite:$workId');
          return 2;
        },
        deleteCacheByOwner: ({
          required ownerType,
          required ownerId,
        }) async {
          calls.add('cache:$ownerType:$ownerId');
          return 1;
        },
        deleteComicDownloads: ({required workId}) async {
          calls.add('download:$workId');
          return true;
        },
        deleteNovelDownloads: ({required novelId}) async {
          fail('novel download cleanup should not be used');
        },
        deleteComicQueueByComicId: (comicId) async {
          calls.add('queue:$comicId');
        },
      );

      final result = await service.purge(
        workId: ' comic-1 ',
        kind: ThreadContentKind.comic,
      );

      expect(result.workId, 'comic-1');
      expect(result.kind, ThreadContentKind.comic);
      expect(result.purgedCache, isTrue);
      expect(result.purgedDownload, isTrue);
      expect(result.errors, isEmpty);
      expect(
        calls,
        <String>[
          'comic:comic-1',
          'state:${LibraryModuleKey.comic}:comic-1',
          'favorite:comic-1',
          'queue:comic-1',
          'cache:${ImageCacheOwnerType.comic}:comic-1',
          'download:comic-1',
        ],
      );
    });

    test('novel purge uses novel strategy and can return empty best-effort flags', () async {
      final calls = <String>[];
      final service = DefaultWorkPurgeService(
        purgeComicWork: ({required comicId}) async {
          fail('comic purge should not be used');
        },
        purgeNovelWork: ({required novelId}) async {
          calls.add('novel:$novelId');
        },
        purgeLibraryWorkState: ({
          required moduleKey,
          required workId,
        }) async {
          calls.add('state:$moduleKey:$workId');
        },
        markFavoriteRemovedByWorkId: (workId) async {
          calls.add('favorite:$workId');
          return 1;
        },
        deleteCacheByOwner: ({
          required ownerType,
          required ownerId,
        }) async {
          calls.add('cache:$ownerType:$ownerId');
          return 0;
        },
        deleteComicDownloads: ({required workId}) async {
          fail('comic download cleanup should not be used');
        },
        deleteNovelDownloads: ({required novelId}) async {
          calls.add('download:$novelId');
          return false;
        },
        deleteComicQueueByComicId: (comicId) async {
          fail('comic queue cleanup should not be used');
        },
      );

      final result = await service.purge(
        workId: 'novel-1',
        kind: ThreadContentKind.novel,
      );

      expect(result.purgedCache, isFalse);
      expect(result.purgedDownload, isFalse);
      expect(result.errors, isEmpty);
      expect(
        calls,
        <String>[
          'novel:novel-1',
          'state:${LibraryModuleKey.novel}:novel-1',
          'favorite:novel-1',
          'cache:${ImageCacheOwnerType.novel}:novel-1',
          'download:novel-1',
        ],
      );
    });

    test('cache and download failures are reported without rolling back core cleanup', () async {
      final calls = <String>[];
      final service = DefaultWorkPurgeService(
        purgeComicWork: ({required comicId}) async {
          fail('comic purge should not be used');
        },
        purgeNovelWork: ({required novelId}) async {
          calls.add('novel:$novelId');
        },
        purgeLibraryWorkState: ({
          required moduleKey,
          required workId,
        }) async {
          calls.add('state:$moduleKey:$workId');
        },
        markFavoriteRemovedByWorkId: (workId) async {
          calls.add('favorite:$workId');
          return 1;
        },
        deleteCacheByOwner: ({
          required ownerType,
          required ownerId,
        }) async {
          calls.add('cache:$ownerType:$ownerId');
          throw StateError('cache exploded');
        },
        deleteComicDownloads: ({required workId}) async {
          fail('comic download cleanup should not be used');
        },
        deleteNovelDownloads: ({required novelId}) async {
          calls.add('download:$novelId');
          throw StateError('download exploded');
        },
        deleteComicQueueByComicId: (comicId) async {
          fail('comic queue cleanup should not be used');
        },
      );

      final result = await service.purge(
        workId: 'novel-2',
        kind: ThreadContentKind.novel,
      );

      expect(result.purgedCache, isFalse);
      expect(result.purgedDownload, isFalse);
      expect(result.errors, hasLength(2));
      expect(result.errors.join(' '), contains('cache exploded'));
      expect(result.errors.join(' '), contains('download exploded'));
      expect(
        calls,
        <String>[
          'novel:novel-2',
          'state:${LibraryModuleKey.novel}:novel-2',
          'favorite:novel-2',
          'cache:${ImageCacheOwnerType.novel}:novel-2',
          'download:novel-2',
        ],
      );
    });

    test('unsupported kind throws UnsupportedError', () async {
      final service = DefaultWorkPurgeService(
        purgeComicWork: ({required comicId}) async {},
        purgeNovelWork: ({required novelId}) async {},
        purgeLibraryWorkState: ({
          required moduleKey,
          required workId,
        }) async {},
        markFavoriteRemovedByWorkId: (_) async => 0,
        deleteCacheByOwner: ({
          required ownerType,
          required ownerId,
        }) async {
          return 0;
        },
        deleteComicDownloads: ({required workId}) async => false,
        deleteNovelDownloads: ({required novelId}) async => false,
        deleteComicQueueByComicId: (_) async {},
      );

      expect(
        () => service.purge(workId: 'forum-1', kind: ThreadContentKind.forum),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

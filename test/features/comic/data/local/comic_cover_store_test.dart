import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_cover_store.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';
import '../../../../test_support/unavailable_library_cover_store.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ComicCoverStore', () {
    const databaseName = 'comic_cover_store_test.db';

    late Future<Database> dbFuture;
    late LocalComicRepository repository;
    late ComicCoverStore store;

    setUp(() async {
      await deleteDatabase(databaseName);
      dbFuture = ComicLocalDb.open(databaseName: databaseName);
      repository = LocalComicRepository(
        dbFuture,
        libraryCoverStore: const UnavailableLibraryCoverStore(),
      );
      store = ComicCoverStore(dbFuture);
    });

    test(
      'updateCoverCache writes normal and custom local cover paths',
      () async {
        await repository.addToShelf(
          comicId: 'yamibo:cover',
          tid: '100',
          fid: '30',
          title: 'Cover Comic',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>['https://img.test/original.jpg'],
            episodeLinks: <ComicEpisodeLink>[],
            plainTextSummary: 'summary',
          ),
        );

        await store.updateCoverCache(
          comicId: 'yamibo:cover',
          coverImageUrl: 'https://img.test/remote-cover.jpg',
          coverLocalPath: '/cache/remote-cover.jpg',
        );

        var detail = await repository.getComicDetail(comicId: 'yamibo:cover');
        expect(detail?.coverImageUrl, 'https://img.test/remote-cover.jpg');
        expect(detail?.coverLocalPath, '/cache/remote-cover.jpg');
        expect(detail?.customCoverLocalPath, isNull);

        await repository.updateCustomCover(
          comicId: 'yamibo:cover',
          customCoverImageUrl: 'https://img.test/custom-cover.jpg',
        );
        await store.updateCoverCache(
          comicId: 'yamibo:cover',
          customCoverLocalPath: '/cache/custom-cover.jpg',
        );

        detail = await repository.getComicDetail(comicId: 'yamibo:cover');
        expect(
          detail?.customCoverImageUrl,
          'https://img.test/custom-cover.jpg',
        );
        expect(detail?.customCoverLocalPath, '/cache/custom-cover.jpg');
      },
    );

    test(
      'promoteFirstEpisodeCover uses smallest tid and preserves custom cover',
      () async {
        await repository.addToShelf(
          comicId: 'yamibo:700',
          tid: '700',
          fid: '30',
          title: 'Test Comic',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(
                url: 'thread-701-1-1.html',
                rawText: 'later',
                episodeTitle: 'later',
              ),
              ComicEpisodeLink(
                url: 'thread-699-1-1.html',
                rawText: 'first',
                episodeTitle: 'first',
              ),
            ],
            plainTextSummary: 'summary',
          ),
        );

        final laterApplied = await store.promoteFirstEpisodeCover(
          comicId: 'yamibo:700',
          episodeId: 'yamibo:700:701',
          imageUrl: 'https://img.test/701-1.jpg',
        );
        var detail = await repository.getComicDetail(comicId: 'yamibo:700');
        expect(laterApplied, isFalse);
        expect(detail?.coverImageUrl, isNull);

        final firstApplied = await store.promoteFirstEpisodeCover(
          comicId: 'yamibo:700',
          episodeId: 'yamibo:700:699',
          imageUrl: 'https://img.test/699-1.jpg',
        );
        detail = await repository.getComicDetail(comicId: 'yamibo:700');
        expect(firstApplied, isTrue);
        expect(detail?.coverImageUrl, 'https://img.test/699-1.jpg');

        await repository.updateCustomCover(
          comicId: 'yamibo:700',
          customCoverImageUrl: 'https://img.test/custom.jpg',
        );
        final preservedCustom = await store.promoteFirstEpisodeCover(
          comicId: 'yamibo:700',
          episodeId: 'yamibo:700:699',
          imageUrl: 'https://img.test/699-2.jpg',
        );
        detail = await repository.getComicDetail(comicId: 'yamibo:700');
        expect(preservedCustom, isFalse);
        expect(detail?.customCoverImageUrl, 'https://img.test/custom.jpg');
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';

void main() {
  group('ComicFirstEpisodeCoverService', () {
    test('promotes first image from lowest tid episode when images already exist', () async {
      final repository = _FakeComicRepository(
        episodes: const <ComicEpisodeItem>[
          ComicEpisodeItem(
            episodeId: 'comic:1:200',
            comicId: 'comic:1',
            episodeTitle: '第2话',
            sourceTid: '200',
            sourceUrl: 'thread-200-1-1.html',
            orderIndex: 0,
            publishTimeText: null,
          ),
          ComicEpisodeItem(
            episodeId: 'comic:1:100',
            comicId: 'comic:1',
            episodeTitle: '第1话',
            sourceTid: '100',
            sourceUrl: 'thread-100-1-1.html',
            orderIndex: 1,
            publishTimeText: null,
          ),
        ],
        imagesByEpisode: const <String, List<ComicEpisodeImageItem>>{
          'comic:1:100': <ComicEpisodeImageItem>[
            ComicEpisodeImageItem(
              episodeId: 'comic:1:100',
              imageUrl: 'https://img.test/first.jpg',
              imageIndex: 0,
              cacheStatus: 'none',
            ),
          ],
        },
      );
      final service = ComicFirstEpisodeCoverService(
        repository: repository,
        fetchEpisodeImagesByTid: (_) async {
          throw StateError('existing images should not fetch again');
        },
      );

      final promoted = await service.promoteIfPossible(comicId: 'comic:1');

      expect(promoted, isTrue);
      expect(repository.promotedEpisodeId, 'comic:1:100');
      expect(repository.promotedImageUrl, 'https://img.test/first.jpg');
      expect(repository.savedEpisodeId, isNull);
    });

    test('fetches first episode images and saves them when local image rows are missing', () async {
      final repository = _FakeComicRepository(
        episodes: const <ComicEpisodeItem>[
          ComicEpisodeItem(
            episodeId: 'comic:1:100',
            comicId: 'comic:1',
            episodeTitle: '第1话',
            sourceTid: '100',
            sourceUrl: 'thread-100-1-1.html',
            orderIndex: 0,
            publishTimeText: null,
          ),
        ],
      );
      final service = ComicFirstEpisodeCoverService(
        repository: repository,
        fetchEpisodeImagesByTid: (tid) async {
          expect(tid, '100');
          return const <String>[
            'https://img.test/first.jpg',
            'https://img.test/first.jpg',
            '   ',
            'https://img.test/second.jpg',
          ];
        },
      );

      final promoted = await service.promoteIfPossible(comicId: 'comic:1');

      expect(promoted, isTrue);
      expect(repository.savedEpisodeId, 'comic:1:100');
      expect(repository.savedImageUrls, <String>[
        'https://img.test/first.jpg',
        'https://img.test/second.jpg',
      ]);
    });

    test('skips automatic cover promotion when custom cover exists', () async {
      final repository = _FakeComicRepository(
        detail: _detail(customCoverImageUrl: 'https://img.test/custom.jpg'),
        episodes: const <ComicEpisodeItem>[
          ComicEpisodeItem(
            episodeId: 'comic:1:100',
            comicId: 'comic:1',
            episodeTitle: '第1话',
            sourceTid: '100',
            sourceUrl: 'thread-100-1-1.html',
            orderIndex: 0,
            publishTimeText: null,
          ),
        ],
      );
      final service = ComicFirstEpisodeCoverService(
        repository: repository,
        fetchEpisodeImagesByTid: (_) async => const <String>[
          'https://img.test/first.jpg',
        ],
      );

      final promoted = await service.promoteIfPossible(comicId: 'comic:1');

      expect(promoted, isFalse);
      expect(repository.promotedEpisodeId, isNull);
      expect(repository.savedEpisodeId, isNull);
    });
  });
}

class _FakeComicRepository
    implements ComicRepository, ComicFirstEpisodeCoverWriter {
  _FakeComicRepository({
    ComicDetail? detail,
    this.episodes = const <ComicEpisodeItem>[],
    this.imagesByEpisode = const <String, List<ComicEpisodeImageItem>>{},
  }) : detail = detail ?? _detail();

  ComicDetail? detail;
  final List<ComicEpisodeItem> episodes;
  final Map<String, List<ComicEpisodeImageItem>> imagesByEpisode;
  String? promotedEpisodeId;
  String? promotedImageUrl;
  String? savedEpisodeId;
  List<String> savedImageUrls = const <String>[];

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return detail;
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) async {
    return episodes;
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({
    required String episodeId,
  }) async {
    return imagesByEpisode[episodeId] ?? const <ComicEpisodeImageItem>[];
  }

  @override
  Future<bool> promoteFirstEpisodeCover({
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    promotedEpisodeId = episodeId;
    promotedImageUrl = imageUrl;
    return true;
  }

  @override
  Future<void> saveEpisodeImages({
    required String episodeId,
    required List<String> imageUrls,
  }) async {
    savedEpisodeId = episodeId;
    savedImageUrls = imageUrls;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

ComicDetail _detail({
  String? customCoverImageUrl,
  String? customCoverLocalPath,
}) {
  return ComicDetail(
    comicId: 'comic:1',
    sourceTid: '100',
    sourceFid: '30',
    title: 'Test Comic',
    author: null,
    translationGroup: null,
    coverImageUrl: null,
    customCoverImageUrl: customCoverImageUrl,
    customCoverLocalPath: customCoverLocalPath,
    updatedAt: DateTime(2026, 1, 1),
    episodeCount: 1,
  );
}

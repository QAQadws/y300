import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/services/novel_favorite_ingest_service.dart';
import 'package:y300/features/novel/data/services/novel_source_metadata_ingest_service.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_metadata_repository.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_parser.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  test(
    'metadata ingest parses and writes once with the injected clock',
    () async {
      final detail = _detail();
      final parser = _RecordingParser();
      final repository = _RecordingMetadataRepository();
      final now = DateTime(2026, 7, 13, 18);
      final favoriteAddedAt = DateTime(2026, 7, 1, 9);
      final service = DefaultNovelSourceMetadataIngestService(
        parser: parser,
        repository: repository,
        clock: () => now,
      );
      const seed = NovelSourceSeed(fid: '49', tid: '200');

      final result = await service.ingestFromFavoriteDetail(
        seed: seed,
        detail: detail,
        favoriteAddedAt: favoriteAddedAt,
      );

      expect(parser.callCount, 1);
      expect(identical(parser.details.single, detail), isTrue);
      expect(parser.ingestedAts, <DateTime>[now]);
      expect(repository.callCount, 1);
      expect(identical(repository.metadata.single, result), isTrue);
      expect(repository.seeds.single.tid, '200');
      expect(repository.favoriteAddedAts, <DateTime>[favoriteAddedAt]);
    },
  );

  test('parser or repository failures are not retried implicitly', () async {
    final parserFailure = _RecordingParser(error: const FormatException('bad'));
    final parserFailureRepository = _RecordingMetadataRepository();
    final parserFailureService = DefaultNovelSourceMetadataIngestService(
      parser: parserFailure,
      repository: parserFailureRepository,
    );

    await expectLater(
      parserFailureService.ingestFromFavoriteDetail(
        seed: const NovelSourceSeed(fid: '49', tid: '200'),
        detail: _detail(),
        favoriteAddedAt: DateTime(2026, 7, 1),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(parserFailure.callCount, 1);
    expect(parserFailureRepository.callCount, 0);

    final repositoryFailure = _RecordingMetadataRepository(
      error: StateError('write failed'),
    );
    final repositoryFailureService = DefaultNovelSourceMetadataIngestService(
      parser: _RecordingParser(),
      repository: repositoryFailure,
    );
    await expectLater(
      repositoryFailureService.ingestFromFavoriteDetail(
        seed: const NovelSourceSeed(fid: '49', tid: '200'),
        detail: _detail(),
        favoriteAddedAt: DateTime(2026, 7, 1),
      ),
      throwsA(isA<StateError>()),
    );
    expect(repositoryFailure.callCount, 1);
  });

  test(
    'favorite facade only delegates preloaded detail to metadata ingest',
    () async {
      final metadataIngest = _RecordingMetadataIngestService();
      final removed = <String>[];
      final service = RepositoryNovelFavoriteIngestService(
        metadataIngestService: metadataIngest,
        removeFromShelf: ({required workId}) async => removed.add(workId),
      );
      final detail = _detail();
      final favoriteAddedAt = DateTime(2026, 7, 1);

      final workId = await service.upsertFromThreadDetail(
        detail: detail,
        favoriteAddedAt: favoriteAddedAt,
        sourceTagName: '原创',
      );
      await service.removeFromShelf(workId: workId);

      expect(workId, 'novel:49:200');
      expect(metadataIngest.callCount, 1);
      expect(identical(metadataIngest.details.single, detail), isTrue);
      expect(metadataIngest.seeds.single.typeid, '293');
      expect(metadataIngest.seeds.single.tagName, '原创');
      expect(metadataIngest.favoriteAddedAts, <DateTime>[favoriteAddedAt]);
      expect(removed, <String>['novel:49:200']);
    },
  );
}

class _RecordingParser implements NovelSourceMetadataParser {
  _RecordingParser({this.error});

  final Object? error;
  final List<ThreadDetailData> details = <ThreadDetailData>[];
  final List<DateTime> ingestedAts = <DateTime>[];
  int callCount = 0;

  @override
  NovelSourceMetadata parseFirstPost({
    required NovelSourceSeed seed,
    required ThreadDetailData detail,
    required DateTime ingestedAt,
  }) {
    callCount++;
    details.add(detail);
    ingestedAts.add(ingestedAt);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return _metadata(ingestedAt: ingestedAt);
  }
}

class _RecordingMetadataRepository implements NovelSourceMetadataRepository {
  _RecordingMetadataRepository({this.error});

  final Object? error;
  final List<NovelSourceSeed> seeds = <NovelSourceSeed>[];
  final List<NovelSourceMetadata> metadata = <NovelSourceMetadata>[];
  final List<DateTime> favoriteAddedAts = <DateTime>[];
  int callCount = 0;

  @override
  Future<void> saveFromFavoriteDetail({
    required NovelSourceSeed seed,
    required NovelSourceMetadata metadata,
    required DateTime favoriteAddedAt,
  }) async {
    callCount++;
    seeds.add(seed);
    this.metadata.add(metadata);
    favoriteAddedAts.add(favoriteAddedAt);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}

class _RecordingMetadataIngestService
    implements NovelSourceMetadataIngestService {
  final List<NovelSourceSeed> seeds = <NovelSourceSeed>[];
  final List<ThreadDetailData> details = <ThreadDetailData>[];
  final List<DateTime> favoriteAddedAts = <DateTime>[];
  int callCount = 0;

  @override
  Future<NovelSourceMetadata> ingestFromFavoriteDetail({
    required NovelSourceSeed seed,
    required ThreadDetailData detail,
    required DateTime favoriteAddedAt,
  }) async {
    callCount++;
    seeds.add(seed);
    details.add(detail);
    favoriteAddedAts.add(favoriteAddedAt);
    return _metadata();
  }
}

ThreadDetailData _detail() {
  return ThreadDetailData(
    tid: '200',
    fid: '49',
    typeid: '293',
    subject: '测试小说',
    author: '作者',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: <ThreadPost>[
      ThreadPost(
        pid: '11',
        author: '作者',
        authorId: '99',
        message: '<p>简介</p><p>目录</p>',
        number: 1,
        isFirst: true,
        dateline: '2026-07-13',
      ),
    ],
  );
}

NovelSourceMetadata _metadata({DateTime? ingestedAt}) {
  return NovelSourceMetadata(
    novelId: 'novel:49:200',
    tid: '200',
    fid: '49',
    subject: '测试小说',
    publisherName: '作者',
    publisherId: '99',
    firstPostPid: '11',
    catalogEntries: const <NovelSourceCatalogEntry>[],
    sourceIntro: null,
    coverImageUrl: null,
    sourceApiVersion: 4,
    ingestedAt: ingestedAt ?? DateTime(2026, 7, 13),
  );
}

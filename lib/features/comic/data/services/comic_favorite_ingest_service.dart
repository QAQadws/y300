import 'package:y300/features/comic/data/services/comic_parser_service.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

abstract class ComicFavoriteIngestService {
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    required DateTime favoriteAddedAt,
    String? sourceTagName,
    FavoriteSyncExecutionContext? executionContext,
  });

  Future<void> removeFromShelf({required String workId});
}

class RepositoryComicFavoriteIngestService
    implements ComicFavoriteIngestService {
  RepositoryComicFavoriteIngestService({
    required ComicFavoriteIngestRepository repository,
    required ComicParserService parserService,
    required ComicSubjectParser subjectParser,
    required ComicPostAggregationService aggregationService,
  }) : _repository = repository,
       _parserService = parserService,
       _subjectParser = subjectParser,
       _aggregationService = aggregationService;

  final ComicFavoriteIngestRepository _repository;
  final ComicParserService _parserService;
  final ComicSubjectParser _subjectParser;
  final ComicPostAggregationService _aggregationService;

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    required DateTime favoriteAddedAt,
    String? sourceTagName,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final comicId = buildComicWorkId(detail.tid);
    final aggregation = _aggregationService.build(detail.posts);
    if (aggregation.parseMessage.isEmpty &&
        aggregation.attachmentImageUrls.isEmpty) {
      await _repository.addFavoriteToShelf(
        comicId: comicId,
        tid: detail.tid,
        fid: detail.fid,
        sourceTypeId: detail.typeid,
        sourceTagName: sourceTagName,
        title: detail.subject,
        favoriteAddedAt: favoriteAddedAt,
        parsedPost: ParsedComicPost.empty.copyWith(
          subjectMetadata: _subjectParser.parse(detail.subject),
        ),
      );
      return comicId;
    }
    final parsed = _parserService
        .parseInput(
          ComicPostParseInput(
            messageHtml: aggregation.parseMessage,
            attachmentImageUrls: aggregation.attachmentImageUrls,
          ),
        )
        .copyWith(subjectMetadata: _subjectParser.parse(detail.subject));

    await _repository.addFavoriteToShelf(
      comicId: comicId,
      tid: detail.tid,
      fid: detail.fid,
      sourceTypeId: detail.typeid,
      sourceTagName: sourceTagName,
      title: detail.subject,
      favoriteAddedAt: favoriteAddedAt,
      parsedPost: parsed,
    );
    return comicId;
  }

  @override
  Future<void> removeFromShelf({required String workId}) {
    return _repository.removeFromShelf(comicId: workId);
  }

  static String buildComicWorkId(String tid) {
    return 'yamibo:${tid.trim()}';
  }
}

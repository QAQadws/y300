import 'package:y300/features/comic/data/comic_parser_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/favorites/domain/favorite_pipeline_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

abstract class ComicFavoriteIngestService {
  /// 完整摄入：分类 + 解析章节 + 提取封面。
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  });

  /// 轻量摄入：只创建书架条目，不深度解析章节、不提取封面图。
  ///
  /// 执行步骤：
  /// 1. 解析首楼 → 提取 episodelinks + catalogUrl
  /// 2. 如果有 episodelinks（直接链接），直接用它们创建章节
  /// 3. 如果是"長篇連載"且无目录 → 标记为 light，后续由阶段 2 搜索队列补全
  Future<String> lightUpsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  });

  Future<void> removeFromShelf({required String workId});
}

class RepositoryComicFavoriteIngestService implements ComicFavoriteIngestService {
  RepositoryComicFavoriteIngestService({
    required ComicRepository repository,
    required ComicParserService parserService,
    required ComicSubjectParser subjectParser,
    required ComicPostAggregationService aggregationService,
  })  : _repository = repository,
        _parserService = parserService,
        _subjectParser = subjectParser,
        _aggregationService = aggregationService;

  final ComicRepository _repository;
  final ComicParserService _parserService;
  final ComicSubjectParser _subjectParser;
  final ComicPostAggregationService _aggregationService;

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  }) async {
    final comicId = buildComicWorkId(detail.tid);
    final aggregation = _aggregationService.build(detail.posts);
    if (aggregation.parseMessage.isEmpty && aggregation.attachmentImageUrls.isEmpty) {
      await _repository.addToShelf(
        comicId: comicId,
        tid: detail.tid,
        fid: detail.fid,
        sourceTypeId: detail.typeid,
        sourceTagName: sourceTagName,
        title: detail.subject,
        parsedPost: ParsedComicPost.empty.copyWith(
          subjectMetadata: _subjectParser.parse(detail.subject),
        ),
      );
      return comicId;
    }
    final parsed = _parserService.parseInput(
      ComicPostParseInput(
        messageHtml: aggregation.parseMessage,
        attachmentImageUrls: aggregation.attachmentImageUrls,
      ),
    ).copyWith(
          subjectMetadata: _subjectParser.parse(detail.subject),
        );

    await _repository.addToShelf(
      comicId: comicId,
      tid: detail.tid,
      fid: detail.fid,
      sourceTypeId: detail.typeid,
      sourceTagName: sourceTagName,
      title: detail.subject,
      parsedPost: parsed,
    );
    return comicId;
  }

  @override
  Future<String> lightUpsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  }) async {
    final comicId = buildComicWorkId(detail.tid);
    final aggregation = _aggregationService.build(detail.posts);

    // 只解析基本结构，跳过附件图片以加速管道吞吐。
    final parsed = _parserService.parseInput(
      ComicPostParseInput(
        messageHtml: aggregation.parseMessage,
        attachmentImageUrls: const <String>[],
      ),
    ).copyWith(subjectMetadata: _subjectParser.parse(detail.subject));

    // 長篇連載且无目录 → 仅靠直接链接，标记 light 供后续搜索队列补全。
    final isLongSerial = _isLongSerialTag(sourceTagName);
    final hasCatalog = parsed.catalogUrl != null &&
        parsed.catalogUrl!.trim().isNotEmpty;

    await _repository.addToShelfWithLevel(
      comicId: comicId,
      tid: detail.tid,
      fid: detail.fid,
      sourceTypeId: detail.typeid,
      sourceTagName: sourceTagName,
      title: detail.subject,
      parsedPost: parsed,
      processingLevel: isLongSerial && !hasCatalog
          ? FavoriteProcessingLevel.light.name
          : FavoriteProcessingLevel.full.name,
    );

    return comicId;
  }

  @override
  Future<void> removeFromShelf({required String workId}) {
    return _repository.removeFromShelf(comicId: workId);
  }

  /// 判断标签是否指示長篇連載作品。
  bool _isLongSerialTag(String? tagName) {
    if (tagName == null) return false;
    final normalized = tagName.trim();
    return normalized.contains('長篇連載') || normalized.contains('长篇连载');
  }

  static String buildComicWorkId(String tid) {
    return 'yamibo:${tid.trim()}';
  }
}

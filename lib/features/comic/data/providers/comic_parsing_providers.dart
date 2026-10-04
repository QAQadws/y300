import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/domain/services/comic_detector.dart';
import 'package:y300/features/comic/domain/services/comic_parser_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/comic/domain/services/html_comic_parser_service.dart';
import 'package:y300/features/comic/domain/services/rule_based_comic_detector.dart';
import 'package:comic_title_core/comic_title_core.dart';
import 'package:y300/features/thread/data/providers/forum_image_source_pipeline_provider.dart';

final comicDetectorProvider = Provider<ComicDetector>((ref) {
  return RuleBasedComicDetector();
});

final comicParserServiceProvider = Provider<ComicParserService>((ref) {
  return HtmlComicParserService();
});

final comicTitleAnalyzerProvider = Provider<ComicTitleAnalyzer>((ref) {
  return const PetitComicTitleAnalyzer();
});

final comicSubjectParserProvider = Provider<ComicSubjectParser>((ref) {
  return RuleBasedComicSubjectParser(
    analyzer: ref.watch(comicTitleAnalyzerProvider),
  );
});

final comicPostAggregationServiceProvider =
    Provider<ComicPostAggregationService>((ref) {
      return ComicPostAggregationService(
        imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
      );
    });

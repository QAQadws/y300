import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
import 'package:y300/features/comic/domain/services/comic_parser_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';
import 'package:y300/features/thread/domain/services/forum_post_image_source_collector.dart';

class HtmlComicParserService implements ComicParserService {
  static final RegExp _episodeTextPattern = RegExp(
    r'^(\d+(\.\d+)?\s*[\u8bdd\u8a71].*|\d+(\.\d+)?|\u7b2c\s*.+\s*[\u8bdd\u8a71]|.*\u7279\u5178.*)$',
  );
  final ComicPostParsingEngine _engine;
  final ForumPostDomExtractor _domExtractor;
  final ForumPostImageSourceCollector _imageSourceCollector;

  HtmlComicParserService({
    ComicPostParsingEngine? engine,
    ForumPostDomExtractor? domExtractor,
    ForumPostImageSourceCollector imageSourceCollector =
        const ForumPostImageSourceCollector(),
  }) : this._(
         engine: engine,
         domExtractor: domExtractor ?? const ForumPostDomExtractor(),
         imageSourceCollector: imageSourceCollector,
       );

  HtmlComicParserService._({
    required ComicPostParsingEngine? engine,
    required ForumPostDomExtractor domExtractor,
    required ForumPostImageSourceCollector imageSourceCollector,
  }) : _domExtractor = domExtractor,
       _imageSourceCollector = imageSourceCollector,
       _engine = engine ?? ComicPostParsingEngine(domExtractor: domExtractor);

  @override
  ParsedComicPost parse({required String message}) {
    return parseInput(ComicPostParseInput(messageHtml: message));
  }

  @override
  ParsedComicPost parseInput(ComicPostParseInput input) {
    final signals = <ComicParsingSignal>[];
    final domImageUrls = _domExtractor.extractImageSources(input.messageHtml);
    final imageUrls = _imageSourceCollector.merge(
      domImageUrls: domImageUrls,
      attachmentImageUrls: input.attachmentImageUrls,
    );
    signals
      ..add(
        ComicParsingSignal(
          stage: 'image',
          message: 'dom images=${domImageUrls.length}',
        ),
      )
      ..add(
        ComicParsingSignal(
          stage: 'image',
          message: 'attachment images=${input.attachmentImageUrls.length}',
        ),
      )
      ..add(
        ComicParsingSignal(
          stage: 'image',
          message: 'accepted images=${imageUrls.length}',
        ),
      );

    final parsedByEngine = _engine.parse(messageHtml: input.messageHtml);
    final episodeLinks = parsedByEngine.episodes
        .map(
          (episode) => ComicEpisodeLink(
            url: episode.url,
            rawText: episode.titleRaw,
            episodeTitle: _extractEpisodeTitle(episode.titleRaw),
          ),
        )
        .toList(growable: false);
    final catalogUrl = parsedByEngine.catalogLinks.isEmpty
        ? null
        : parsedByEngine.catalogLinks.first;
    signals.addAll(parsedByEngine.debugSignals);

    final plainText = _domExtractor
        .extractPlainText(input.messageHtml)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final debugInfo = ComicParsingDebugInfo(
      signals: signals,
      totalAnchors: _domExtractor.extractAnchors(input.messageHtml).length,
      totalEpisodeLinks: episodeLinks.length,
      catalogUrl: catalogUrl,
    );

    return ParsedComicPost(
      imageUrls: imageUrls,
      episodeLinks: episodeLinks,
      plainTextSummary: plainText,
      catalogUrl: catalogUrl,
      inferredAuthor: _inferAuthor(plainText),
      parsingDebug: debugInfo,
    );
  }

  String? _extractEpisodeTitle(String text) {
    if (text.isEmpty) {
      return null;
    }
    if (_episodeTextPattern.hasMatch(text)) {
      return text;
    }
    return null;
  }

  String? _inferAuthor(String plainText) {
    final authorMatch = RegExp(
      r'(\u4f5c\u8005|\u6c49\u5316|\u7ffb\u8bd1)[\uff1a:]\s*([^\s\uff0c\u3002\uff1b;]+)',
    ).firstMatch(plainText);
    return authorMatch?.group(2);
  }
}

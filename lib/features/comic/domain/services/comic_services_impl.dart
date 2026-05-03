import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/comic/data/comic_parser_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_detector.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/thread/data/thread_repository.dart';

final comicDetectorProvider = Provider<ComicDetector>((ref) {
  return RuleBasedComicDetector();
});

final comicParserServiceProvider = Provider<ComicParserService>((ref) {
  return HtmlComicParserService();
});

final comicSubjectParserProvider = Provider<ComicSubjectParser>((ref) {
  return const RuleBasedComicSubjectParser();
});

abstract class ComicEpisodeRefreshService {
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid);
}

class NetworkComicEpisodeRefreshService implements ComicEpisodeRefreshService {
  NetworkComicEpisodeRefreshService({
    required ComicEpisodeDiscoveryService discoveryService,
  }) : _discoveryService = discoveryService;

  final ComicEpisodeDiscoveryService _discoveryService;

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    final result = await _discoveryService.discoverFromTid(tid);
    return result.episodeLinks;
  }
}

final comicEpisodeDiscoveryServiceProvider = Provider<ComicEpisodeDiscoveryService>((ref) {
  final engine = ComicPostParsingEngine();
  final opPostParser = ComicConsecutiveOpPostParser(engine: engine);
  return ComicEpisodeDiscoveryService(
    fetchThreadDetail: (tid) => ref.read(threadRepositoryProvider).getThreadDetail(tid: tid, page: 1),
    opPostParser: opPostParser,
    catalogHtmlFetcher: DioCatalogHtmlFetcher(),
  );
});

final comicEpisodeRefreshServiceProvider = Provider<ComicEpisodeRefreshService>((ref) {
  return NetworkComicEpisodeRefreshService(
    discoveryService: ref.read(comicEpisodeDiscoveryServiceProvider),
  );
});

abstract class ComicReaderService {
  Future<List<String>> fetchEpisodeImagesByTid(String tid);

  Future<ComicImageCacheResult> cacheImage({required String imageUrl});

  Future<void> prefetchImages({required List<String> imageUrls}) async {
    for (final imageUrl in imageUrls) {
      await cacheImage(imageUrl: imageUrl);
    }
  }
}

class ComicImageCacheResult {
  const ComicImageCacheResult({
    required this.success,
    this.localPath,
  });

  final bool success;
  final String? localPath;
}

class NetworkComicReaderService implements ComicReaderService {
  NetworkComicReaderService({
    required ThreadRepository threadRepository,
    required ComicParserService parserService,
    BaseCacheManager? cacheManager,
  })  : _threadRepository = threadRepository,
        _parserService = parserService,
        _cacheManager = cacheManager ?? DefaultCacheManager();

  final ThreadRepository _threadRepository;
  final ComicParserService _parserService;
  final BaseCacheManager _cacheManager;

  @override
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async {
    final result = await _threadRepository.getThreadDetail(tid: tid, page: 1);
    return result.when(
      success: (data) {
        final firstPost = data.posts.where((post) => post.isFirst).firstOrNull;
        if (firstPost == null) {
          return const <String>[];
        }
        return _parserService.parse(message: firstPost.message).imageUrls;
      },
      failure: (_) => const <String>[],
    );
  }

  @override
  Future<ComicImageCacheResult> cacheImage({required String imageUrl}) async {
    try {
      final fileInfo = await _cacheManager.downloadFile(imageUrl, key: imageUrl);
      return ComicImageCacheResult(
        success: true,
        localPath: fileInfo.file.path,
      );
    } catch (_) {
      return const ComicImageCacheResult(success: false);
    }
  }

  @override
  Future<void> prefetchImages({required List<String> imageUrls}) async {
    for (final imageUrl in imageUrls) {
      await cacheImage(imageUrl: imageUrl);
    }
  }
}

final comicReaderServiceProvider = FutureProvider<ComicReaderService>((ref) async {
  return NetworkComicReaderService(
    threadRepository: ref.read(threadRepositoryProvider),
    parserService: ref.read(comicParserServiceProvider),
    cacheManager: await ref.read(comicCacheManagerProvider.future),
  );
});

class RuleBasedComicDetector implements ComicDetector {
  RuleBasedComicDetector({this.threshold = 60});

  final int threshold;

  static final RegExp _subjectKeyword = RegExp(
    r'(\u7b2c\s*\d+(\.\d+)?\s*\u8bdd|\u6c49\u5316|\[[^\]]*\u7ec4\]|\u3010[^\u3011]*\u7ec4\u3011)',
    caseSensitive: false,
  );

  static final RegExp _episodeLink = RegExp(
    r'thread-\d+-\d+-\d+\.html',
    caseSensitive: false,
  );

  static final RegExp _weakTextKeyword = RegExp(
    r'(\u76ee\u5f55|\u56fe\u6e90|\u5d4c\u5b57|\u6821\u5bf9)',
    caseSensitive: false,
  );

  @override
  ComicCandidateInfo detect({
    required String fid,
    required String subject,
    required String message,
  }) {
    var score = 0;
    final reasons = <String>[];

    if (fid == '30') {
      score += 40;
      reasons.add('fid=30');
    }

    final imageCount = RegExp(r'<img\b', caseSensitive: false).allMatches(message).length;
    if (imageCount >= 2) {
      score += 35;
      reasons.add('\u56fe\u7247\u6570\u91cf>=2');
    }

    if (_subjectKeyword.hasMatch(subject)) {
      score += 20;
      reasons.add('\u6807\u9898\u547d\u4e2d\u6f2b\u753b\u5173\u952e\u8bcd');
    }

    final linkCount = _episodeLink.allMatches(message).length;
    if (linkCount >= 2) {
      score += 15;
      reasons.add('\u7ae0\u8282\u94fe\u63a5\u6570\u91cf>=2');
    }

    if (_weakTextKeyword.hasMatch(message)) {
      score += 10;
      reasons.add('\u6b63\u6587\u547d\u4e2d\u5f31\u5173\u952e\u8bcd');
    }

    return ComicCandidateInfo(
      isCandidate: score >= threshold,
      score: score,
      reasons: reasons,
    );
  }
}

class HtmlComicParserService implements ComicParserService {
  static final RegExp _emojiLikeImage = RegExp(
    r'(smilies|static/image|emotion|avatar)',
    caseSensitive: false,
  );

  static final RegExp _episodeTextPattern = RegExp(
    r'^(\d+(\.\d+)?|\u7b2c\s*.+\s*\u8bdd|.*\u7279\u5178.*)$',
  );
  final ComicPostParsingEngine _engine;

  HtmlComicParserService({
    ComicPostParsingEngine? engine,
  }) : _engine = engine ?? ComicPostParsingEngine();

  @override
  ParsedComicPost parse({required String message}) {
    final signals = <ComicParsingSignal>[];
    final document = html_parser.parseFragment(message);

    final imageUrls = <String>[];
    final seenImages = <String>{};
    for (final node in document.querySelectorAll('img')) {
      final src = (node.attributes['src'] ?? '').trim();
      if (src.isEmpty || _emojiLikeImage.hasMatch(src)) {
        if (src.isNotEmpty) {
          signals.add(ComicParsingSignal(stage: 'image', message: 'ignored image src=$src'));
        }
        continue;
      }
      if (seenImages.add(src)) {
        imageUrls.add(src);
      }
    }
    signals.add(ComicParsingSignal(stage: 'image', message: 'accepted images=${imageUrls.length}'));

    final parsedByEngine = _engine.parse(messageHtml: message);
    final episodeLinks = parsedByEngine.episodes
        .map(
          (episode) => ComicEpisodeLink(
            url: episode.url,
            rawText: episode.titleRaw,
            episodeTitle: _extractEpisodeTitle(episode.titleRaw),
          ),
        )
        .toList(growable: false);
    final catalogUrl = parsedByEngine.catalogLinks.isEmpty ? null : parsedByEngine.catalogLinks.first;
    signals.addAll(parsedByEngine.debugSignals);

    final plainText = (document.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

    final debugInfo = ComicParsingDebugInfo(
      signals: signals,
      totalAnchors: document.querySelectorAll('a').length,
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
    final authorMatch = RegExp(r'(\u4f5c\u8005|\u6c49\u5316|\u7ffb\u8bd1)[\uff1a:]\s*([^\s\uff0c\u3002\uff1b;]+)').firstMatch(plainText);
    return authorMatch?.group(2);
  }
}

extension _FirstOrNullExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

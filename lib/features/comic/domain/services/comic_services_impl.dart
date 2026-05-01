import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/comic/data/comic_parser_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_detector.dart';
import 'package:y300/features/thread/data/thread_repository.dart';

final comicDetectorProvider = Provider<ComicDetector>((ref) {
  return RuleBasedComicDetector();
});

final comicParserServiceProvider = Provider<ComicParserService>((ref) {
  return HtmlComicParserService();
});

/// 章节刷新接口：便于在控制器与测试中替换实现。
abstract class ComicEpisodeRefreshService {
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid);
}

class NetworkComicEpisodeRefreshService implements ComicEpisodeRefreshService {
  NetworkComicEpisodeRefreshService({
    required ThreadRepository threadRepository,
    required ComicParserService parserService,
  })  : _threadRepository = threadRepository,
        _parserService = parserService;

  final ThreadRepository _threadRepository;
  final ComicParserService _parserService;

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    final result = await _threadRepository.getThreadDetail(tid: tid, page: 1);
    return result.when(
      success: (data) {
        final firstPost = data.posts.where((post) => post.isFirst).firstOrNull;
        if (firstPost == null) {
          return const <ComicEpisodeLink>[];
        }
        final parsed = _parserService.parse(message: firstPost.message);
        return parsed.episodeLinks;
      },
      failure: (_) => const <ComicEpisodeLink>[],
    );
  }
}

final comicEpisodeRefreshServiceProvider = Provider<ComicEpisodeRefreshService>((ref) {
  return NetworkComicEpisodeRefreshService(
    threadRepository: ref.read(threadRepositoryProvider),
    parserService: ref.read(comicParserServiceProvider),
  );
});

/// 阅读器接口：负责章节图抓取与图片缓存。
abstract class ComicReaderService {
  Future<List<String>> fetchEpisodeImagesByTid(String tid);

  Future<bool> cacheImage({required String imageUrl});
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
  Future<bool> cacheImage({required String imageUrl}) async {
    try {
      await _cacheManager.downloadFile(imageUrl, key: imageUrl);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final comicReaderServiceProvider = Provider<ComicReaderService>((ref) {
  return NetworkComicReaderService(
    threadRepository: ref.read(threadRepositoryProvider),
    parserService: ref.read(comicParserServiceProvider),
    cacheManager: ref.read(comicCacheManagerProvider),
  );
});

class RuleBasedComicDetector implements ComicDetector {
  RuleBasedComicDetector({this.threshold = 60});

  final int threshold;

  static final RegExp _subjectKeyword = RegExp(
    r'(第\s*\d+(\.\d+)?\s*话|汉化|\[[^\]]*组\]|【[^】]*组】)',
    caseSensitive: false,
  );

  static final RegExp _episodeLink = RegExp(
    r'thread-\d+-\d+-\d+\.html',
    caseSensitive: false,
  );

  static final RegExp _weakTextKeyword = RegExp(
    r'(目录|图源|嵌字|校对)',
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
      reasons.add('图片数量>=2');
    }

    if (_subjectKeyword.hasMatch(subject)) {
      score += 20;
      reasons.add('标题命中漫画关键词');
    }

    final linkCount = _episodeLink.allMatches(message).length;
    if (linkCount >= 2) {
      score += 15;
      reasons.add('章节链接数量>=2');
    }

    if (_weakTextKeyword.hasMatch(message)) {
      score += 10;
      reasons.add('正文命中弱关键词');
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

  static final RegExp _threadIdPattern = RegExp(r'thread-(\d+)-\d+-\d+\.html', caseSensitive: false);

  static final RegExp _episodeTextPattern = RegExp(r'^(\d+(\.\d+)?|第\s*.+\s*话)$');

  @override
  ParsedComicPost parse({required String message}) {
    final document = html_parser.parseFragment(message);

    final imageUrls = <String>[];
    final seenImages = <String>{};
    for (final node in document.querySelectorAll('img')) {
      final src = (node.attributes['src'] ?? '').trim();
      if (src.isEmpty || _emojiLikeImage.hasMatch(src)) {
        continue;
      }
      if (seenImages.add(src)) {
        imageUrls.add(src);
      }
    }

    final episodeLinks = <ComicEpisodeLink>[];
    final seenLinks = <String>{};
    String? catalogUrl;

    for (final node in document.querySelectorAll('a')) {
      final href = (node.attributes['href'] ?? '').trim();
      if (href.isEmpty) {
        continue;
      }
      final normalizedUrl = _normalizeUrl(href);
      if (normalizedUrl == null) {
        continue;
      }
      final text = node.text.trim();

      final isCatalog = text.contains('目录');
      if (isCatalog && catalogUrl == null) {
        catalogUrl = normalizedUrl;
      }

      if (_threadIdPattern.hasMatch(normalizedUrl) && seenLinks.add(normalizedUrl)) {
        final episodeTitle = _extractEpisodeTitle(text);
        episodeLinks.add(
          ComicEpisodeLink(
            url: normalizedUrl,
            rawText: text,
            episodeTitle: episodeTitle,
          ),
        );
      }
    }

    final plainText = (document.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

    return ParsedComicPost(
      imageUrls: imageUrls,
      episodeLinks: episodeLinks,
      plainTextSummary: plainText,
      catalogUrl: catalogUrl,
      inferredAuthor: _inferAuthor(plainText),
    );
  }

  String? _normalizeUrl(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null) {
      return null;
    }

    if (!uri.hasScheme) {
      return href;
    }

    final cleaned = Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    return cleaned.toString();
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
    final authorMatch = RegExp(r'(作者|汉化|翻译)[：:]\s*([^\s，。；;]+)').firstMatch(plainText);
    return authorMatch?.group(2);
  }
}

extension _FirstOrNullExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

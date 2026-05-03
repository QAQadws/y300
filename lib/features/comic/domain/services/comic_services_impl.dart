import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/comic/data/comic_parser_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
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
  static const String _yamiboOrigin = 'https://bbs.yamibo.com/';

  static final RegExp _emojiLikeImage = RegExp(
    r'(smilies|static/image|emotion|avatar)',
    caseSensitive: false,
  );

  static final RegExp _threadIdPattern = RegExp(r'thread-(\d+)-\d+-\d+\.html', caseSensitive: false);
  static final RegExp _forumViewThreadPattern = RegExp(
    r'forum\.php\?[^#]*\bmod=viewthread\b[^#]*\btid=\d+',
    caseSensitive: false,
  );
  static final RegExp _damagedTidPattern = RegExp(r'(^|[?&;])tid=(\d+)(?:[&#]|$)', caseSensitive: false);
  static final RegExp _fromUidPattern = RegExp(r'(^|[?&;])fromuid=([^&#]+)(?:[&#]|$)', caseSensitive: false);

  static final RegExp _episodeTextPattern = RegExp(
    r'^(\d+(\.\d+)?|\u7b2c\s*.+\s*\u8bdd|.*\u7279\u5178.*)$',
  );

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

    final episodeLinks = <ComicEpisodeLink>[];
    final seenLinks = <String>{};
    String? catalogUrl;

    final anchors = document.querySelectorAll('a');
    signals.add(ComicParsingSignal(stage: 'anchor', message: 'raw anchors=${anchors.length}'));

    for (final node in anchors) {
      final href = (node.attributes['href'] ?? '').trim();
      if (href.isEmpty) {
        continue;
      }

      final decodedHref = _decodeHtmlAmp(href);
      final normalizedUrl = _normalizeUrl(decodedHref);
      if (normalizedUrl == null) {
        signals.add(ComicParsingSignal(stage: 'anchor', message: 'reject href=$href'));
        continue;
      }

      final text = node.text.trim();
      final isCatalog = text.contains('\u76ee\u5f55');
      if (isCatalog && catalogUrl == null) {
        catalogUrl = normalizedUrl;
        signals.add(ComicParsingSignal(stage: 'rule', message: 'catalog hit text=$text url=$normalizedUrl'));
      }

      if (_isEpisodeThreadLink(normalizedUrl) && seenLinks.add(normalizedUrl)) {
        final episodeTitle = _extractEpisodeTitle(text);
        episodeLinks.add(
          ComicEpisodeLink(
            url: normalizedUrl,
            rawText: text,
            episodeTitle: episodeTitle,
          ),
        );
        signals.add(ComicParsingSignal(
          stage: 'rule',
          message: 'episode hit text=$text url=$normalizedUrl title=${episodeTitle ?? 'null'}',
        ));
      }
    }

    final plainText = (document.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

    final debugInfo = ComicParsingDebugInfo(
      signals: signals,
      totalAnchors: anchors.length,
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

  String? _normalizeUrl(String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    // Only treat obviously damaged hrefs as tid-only fallback.
    // Example: ";tid=537155&highlight=..." (missing full forum.php path).
    if (trimmed.startsWith(';tid=') || trimmed.startsWith('tid=')) {
      final damagedTid = _extractTidFromDamagedHref(trimmed);
      if (damagedTid != null) {
        return 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$damagedTid';
      }
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return null;
    }

    final effectiveUri = uri.hasScheme ? uri : Uri.parse(_yamiboOrigin).resolveUri(uri);

    final isThreadHtml = _threadIdPattern.hasMatch(effectiveUri.path);
    final isForumViewThread = effectiveUri.path.toLowerCase().endsWith('forum.php') &&
        effectiveUri.queryParameters['mod']?.toLowerCase() == 'viewthread' &&
        (effectiveUri.queryParameters['tid']?.isNotEmpty ?? false);

    String? normalizedQuery;
    if (isForumViewThread) {
      final mod = effectiveUri.queryParameters['mod'];
      final tid = effectiveUri.queryParameters['tid'];
      final fromuid = effectiveUri.queryParameters['fromuid'] ?? _extractFromUid(trimmed);
      final queryPairs = <String>[
        if (mod != null) 'mod=$mod',
        if (tid != null) 'tid=$tid',
        if (fromuid != null && fromuid.isNotEmpty) 'fromuid=$fromuid',
      ];
      normalizedQuery = queryPairs.isEmpty ? null : queryPairs.join('&');
    } else if (isThreadHtml) {
      normalizedQuery = null;
    } else {
      normalizedQuery = effectiveUri.hasQuery ? effectiveUri.query : null;
    }

    final cleaned = Uri(
      scheme: effectiveUri.scheme,
      userInfo: effectiveUri.userInfo,
      host: effectiveUri.host,
      port: effectiveUri.hasPort ? effectiveUri.port : null,
      path: effectiveUri.path,
      query: normalizedQuery,
    );
    final normalized = cleaned.toString();

    // Fallback for malformed hrefs that still contain tid but failed to form
    // a recognizable viewthread/thread URL after normalization.
    if (!_isEpisodeThreadLink(normalized)) {
      final damagedTid = _extractTidFromDamagedHref(trimmed);
      if (damagedTid != null) {
        return 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$damagedTid';
      }
    }

    return normalized;
  }

  String? _extractTidFromDamagedHref(String href) {
    final match = _damagedTidPattern.firstMatch(href);
    return match?.group(2);
  }

  String? _extractFromUid(String href) {
    final match = _fromUidPattern.firstMatch(href);
    return match?.group(2);
  }

  bool _isEpisodeThreadLink(String normalizedUrl) {
    return _threadIdPattern.hasMatch(normalizedUrl) || _forumViewThreadPattern.hasMatch(normalizedUrl);
  }

  String _decodeHtmlAmp(String href) {
    var result = href;
    while (result.contains('&amp;')) {
      result = result.replaceAll('&amp;', '&');
    }
    return result;
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

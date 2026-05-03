import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
import 'package:y300/features/comic/domain/models/comic_post_parsing_models.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

/// Parse consecutive OP posts from floor-1.
///
/// Rule:
/// 1. Start from floor 1.
/// 2. Merge only consecutive posts authored by the OP.
/// 3. Stop when first non-OP post appears.
class ComicConsecutiveOpPostParser {
  ComicConsecutiveOpPostParser({
    required ComicPostParsingEngine engine,
  }) : _engine = engine;

  final ComicPostParsingEngine _engine;

  ParsedComicPost parse({
    required String tid,
    required String fid,
    required String subject,
    required List<ThreadPost> posts,
  }) {
    final first = _findFirstFloor(posts);
    if (first == null) {
      return ParsedComicPost.empty;
    }

    final opAuthorId = first.authorId;
    final consecutive = <ThreadPost>[first];
    final sorted = posts.toList()..sort((a, b) => a.number.compareTo(b.number));

    for (final post in sorted) {
      if (post.number <= 1) {
        continue;
      }
      if (post.authorId != opAuthorId) {
        break;
      }
      consecutive.add(post);
    }

    final allImages = <String>[];
    final imageDedup = <String>{};
    final allEpisodes = <EpisodeLinkCandidate>[];
    final allCatalog = <String>{};
    final allSignals = <ComicParsingSignal>[];

    for (final post in consecutive) {
      final context = ParsedPostContext(
        tid: tid,
        fid: fid,
        subject: subject,
        authorUid: post.authorId,
        isFirst: post.number == 1 || post.isFirst,
        messageHtml: post.message,
        messageText: '',
      );
      final result = _engine.parse(messageHtml: context.messageHtml);
      final images = _extractImages(context.messageHtml);
      for (final image in images) {
        if (imageDedup.add(image)) {
          allImages.add(image);
        }
      }
      allEpisodes.addAll(result.episodes);
      allCatalog.addAll(result.catalogLinks);
      allSignals.addAll(result.debugSignals);
    }

    final episodeLinks = _toEpisodeLinks(allEpisodes);
    return ParsedComicPost(
      imageUrls: allImages,
      episodeLinks: episodeLinks,
      plainTextSummary: '',
      catalogUrl: allCatalog.isEmpty ? null : allCatalog.first,
      parsingDebug: ComicParsingDebugInfo(
        signals: allSignals,
        totalAnchors: 0,
        totalEpisodeLinks: episodeLinks.length,
        catalogUrl: allCatalog.isEmpty ? null : allCatalog.first,
      ),
    );
  }

  ThreadPost? _findFirstFloor(List<ThreadPost> posts) {
    for (final post in posts) {
      if (post.isFirst || post.number == 1) {
        return post;
      }
    }
    return null;
  }

  List<String> _extractImages(String html) {
    final matches = RegExp('<img[^>]*\\ssrc=["\\\']([^"\\\']+)["\\\']', caseSensitive: false).allMatches(html);
    final images = <String>[];
    final seen = <String>{};
    for (final match in matches) {
      final src = (match.group(1) ?? '').trim();
      if (src.isEmpty) {
        continue;
      }
      if (seen.add(src)) {
        images.add(src);
      }
    }
    return images;
  }

  List<ComicEpisodeLink> _toEpisodeLinks(List<EpisodeLinkCandidate> candidates) {
    final bestByTid = <String, EpisodeLinkCandidate>{};
    for (final candidate in candidates) {
      final current = bestByTid[candidate.tid];
      if (current == null ||
          candidate.confidence > current.confidence ||
          (candidate.confidence == current.confidence && candidate.position < current.position)) {
        bestByTid[candidate.tid] = candidate;
      }
    }
    final sorted = bestByTid.values.toList()..sort((a, b) => a.position.compareTo(b.position));
    return sorted
        .map(
          (e) => ComicEpisodeLink(
            url: e.url,
            rawText: e.titleRaw,
            episodeTitle: e.titleNormalized.isEmpty ? null : e.titleNormalized,
          ),
        )
        .toList(growable: false);
  }
}

import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
import 'package:y300/features/comic/domain/models/comic_post_parsing_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';

/// Parse consecutive OP posts from floor-1.
///
/// Rule:
/// 1. Start from floor 1.
/// 2. Merge only consecutive posts authored by the OP.
/// 3. Stop when first non-OP post appears.
class ComicConsecutiveOpPostParser {
  ComicConsecutiveOpPostParser({required ComicPostParsingEngine engine})
    : _engine = engine;

  final ComicPostParsingEngine _engine;

  ParsedComicPost parse({
    required String tid,
    required String fid,
    required String subject,
    required List<ComicThreadDiscoveryPost> posts,
  }) {
    final first = _findFirstFloor(posts);
    if (first == null) {
      return ParsedComicPost.empty;
    }

    final opAuthorId = first.authorId;
    final consecutive = <ComicThreadDiscoveryPost>[first];
    final sorted = posts.toList()
      ..sort((a, b) => a.floorNumber.compareTo(b.floorNumber));

    for (final post in sorted) {
      if (post.floorNumber <= 1) {
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
        isFirst: post.floorNumber == 1 || post.isFirst,
        messageHtml: post.messageHtml,
        messageText: '',
      );
      final result = _engine.parse(messageHtml: context.messageHtml);
      final images = _extractImages(post);
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

  ComicThreadDiscoveryPost? _findFirstFloor(
    List<ComicThreadDiscoveryPost> posts,
  ) {
    for (final post in posts) {
      if (post.isFirst || post.floorNumber == 1) {
        return post;
      }
    }
    return null;
  }

  List<String> _extractImages(ComicThreadDiscoveryPost post) {
    return post.imageReferences
        .map((source) => source.url)
        .toList(growable: false);
  }

  List<ComicEpisodeLink> _toEpisodeLinks(
    List<EpisodeLinkCandidate> candidates,
  ) {
    final bestByTid = <String, EpisodeLinkCandidate>{};
    for (final candidate in candidates) {
      final current = bestByTid[candidate.tid];
      if (current == null ||
          candidate.confidence > current.confidence ||
          (candidate.confidence == current.confidence &&
              candidate.position < current.position)) {
        bestByTid[candidate.tid] = candidate;
      }
    }
    final sorted = bestByTid.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));
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

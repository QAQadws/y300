import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_link_merger.dart';
import 'package:y300/features/comic/domain/services/comic_single_thread_episode_namer.dart';

/// Combines linked chapters with the chapter hosted by the imported thread.
class ComicInitialEpisodeAssembler {
  const ComicInitialEpisodeAssembler({
    required ComicEpisodeLinkMerger linkMerger,
    required ComicSingleThreadEpisodeNamer episodeNamer,
  }) : _linkMerger = linkMerger,
       _episodeNamer = episodeNamer;

  final ComicEpisodeLinkMerger _linkMerger;
  final ComicSingleThreadEpisodeNamer _episodeNamer;

  List<ComicEpisodeLink> assemble({
    required ParsedComicPost parsedPost,
    required ComicSubjectMetadata subjectMetadata,
    required String sourceUrl,
    required String sourceTitle,
  }) {
    // Historical chapter links do not make the source a directory. Only a
    // parsed catalog suppresses the source's own image chapter at initial ingest.
    if ((parsedPost.catalogUrl?.trim().isNotEmpty ?? false) ||
        parsedPost.imageUrls.isEmpty) {
      return parsedPost.episodeLinks;
    }
    return _linkMerger.sort(
      _linkMerger.merge(parsedPost.episodeLinks, [
        ComicEpisodeLink(
          url: sourceUrl,
          rawText: sourceTitle,
          episodeTitle: _episodeNamer.resolve(
            metadata: subjectMetadata,
            fallbackComicTitle: sourceTitle,
          ),
        ),
      ]),
    );
  }
}

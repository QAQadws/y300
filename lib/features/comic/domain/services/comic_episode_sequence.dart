import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/library_shared/domain/services/library_source_id_comparator.dart';

enum ComicEpisodeDirection { previous, next }

enum ComicEpisodeOpenPolicy { resumeIfUnread, startAtBeginning }

/// Owns the canonical order used by comic navigation and lookahead.
///
/// Database order is not a navigation contract: imported catalogs can arrive
/// in a different order, so source TID is the primary sequence key.
class ComicEpisodeSequence {
  const ComicEpisodeSequence();

  List<ComicEpisodeItem> order(Iterable<ComicEpisodeItem> episodes) {
    final ordered = episodes.toList(growable: true)
      ..sort((left, right) {
        var result = compareLibrarySourceIds(left.sourceTid, right.sourceTid);
        if (result == 0) {
          result = left.orderIndex.compareTo(right.orderIndex);
        }
        if (result == 0) {
          result = left.episodeId.compareTo(right.episodeId);
        }
        return result;
      });
    return List<ComicEpisodeItem>.unmodifiable(ordered);
  }

  ComicEpisodeItem? adjacent({
    required Iterable<ComicEpisodeItem> episodes,
    required String episodeId,
    required ComicEpisodeDirection direction,
  }) {
    final ordered = order(episodes);
    final index = ordered.indexWhere(
      (episode) => episode.episodeId == episodeId,
    );
    if (index < 0) {
      return null;
    }
    final targetIndex = direction == ComicEpisodeDirection.previous
        ? index - 1
        : index + 1;
    if (targetIndex < 0 || targetIndex >= ordered.length) {
      return null;
    }
    return ordered[targetIndex];
  }
}

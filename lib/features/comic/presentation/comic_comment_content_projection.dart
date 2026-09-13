import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/presentation/thread_post_text_slots.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projector.dart';
import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

@immutable
final class ComicCommentContentProjection {
  ComicCommentContentProjection({
    required this.sourceResult,
    required List<ComicCommentItemProjection> items,
    required this.mode,
    required this.converterId,
    required this.sourceRevision,
    required this.isConverted,
  }) : items = List<ComicCommentItemProjection>.unmodifiable(items);

  factory ComicCommentContentProjection.raw(
    ComicCommentLoadResult sourceResult, {
    required TextConversionMode mode,
    required String converterId,
    required String sourceRevision,
  }) {
    return ComicCommentContentProjection(
      sourceResult: sourceResult,
      items: [
        for (final item in sourceResult.items)
          ComicCommentItemProjection.raw(item),
      ],
      mode: mode,
      converterId: converterId,
      sourceRevision: sourceRevision,
      isConverted: false,
    );
  }

  final ComicCommentLoadResult sourceResult;
  final List<ComicCommentItemProjection> items;
  final TextConversionMode mode;
  final String converterId;
  final String sourceRevision;
  final bool isConverted;

  String get displayIdentity =>
      '$sourceRevision:${mode.name}:$converterId:$isConverted';

  late final List<int> layoutFingerprints = List.unmodifiable([
    for (final item in items)
      Object.hashAll(
        ThreadDetailContentProjector.postRevisionParts(item.displayPost),
      ),
  ]);
}

/// Only replacing existing displayed content can require scroll restoration.
/// New rows below the existing prefix and metadata/loading changes cannot.
class ComicCommentLayoutRevisionTracker {
  ComicCommentContentProjection? _previous;
  int _revision = 0;

  int update(ComicCommentContentProjection projection) {
    final previous = _previous;
    if (identical(previous, projection)) return _revision;
    if (previous != null) {
      final before = previous.layoutFingerprints;
      final after = projection.layoutFingerprints;
      if (after.length < before.length ||
          !Iterable<int>.generate(
            before.length,
          ).every((i) => before[i] == after[i])) {
        _revision++;
      }
    }
    _previous = projection;
    return _revision;
  }
}

@immutable
final class ComicCommentItemProjection {
  const ComicCommentItemProjection({
    required this.sourceItem,
    required this.displayMessage,
    required this.displayDateline,
    this.projectedPost,
  });

  ComicCommentItemProjection.raw(ComicCommentItem sourceItem)
    : this(
        sourceItem: sourceItem,
        displayMessage: sourceItem.rawMessage,
        displayDateline: sourceItem.dateline,
      );

  final ThreadPost? projectedPost;
  ThreadPost get displayPost {
    if (projectedPost != null) return projectedPost!;
    final collector = ThreadPlainTextCollector();
    final slots = ThreadPostTextSlots.collect(sourceItem.post, collector);
    collector.sources[slots.dateline.index] = displayDateline;
    return slots.build(
      sourceItem.post,
      values: collector.sources,
      displayHtml: displayMessage,
    );
  }

  final ComicCommentItem sourceItem;
  final String displayMessage;
  final String displayDateline;
}

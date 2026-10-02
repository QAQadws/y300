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
    this.bodyRevision = '',
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
  final String bodyRevision;

  String get displayIdentity =>
      '$sourceRevision:${mode.name}:$converterId:$isConverted:$bodyRevision';

  late final List<int> layoutFingerprints = List.unmodifiable([
    for (final item in items)
      Object.hashAll(
        ThreadDetailContentProjector.postRevisionParts(item.renderPost),
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
  ComicCommentItemProjection({
    required this.sourceItem,
    required this.displayMessage,
    required this.displayDateline,
    this.projectedPost,
    this.renderedPost,
  });

  ComicCommentItemProjection.raw(ComicCommentItem sourceItem)
    : this(
        sourceItem: sourceItem,
        displayMessage: sourceItem.rawMessage,
        displayDateline: sourceItem.dateline,
      );

  final ThreadPost? projectedPost;
  final ThreadPost? renderedPost;
  ThreadPost get renderPost => renderedPost ?? displayPost;

  ComicCommentItemProjection projectBody(
    ThreadPost Function(ThreadPost) project,
  ) {
    final completePost = displayPost;
    return ComicCommentItemProjection(
      sourceItem: sourceItem,
      displayMessage: displayMessage,
      displayDateline: displayDateline,
      projectedPost: completePost,
      renderedPost: project(completePost),
    );
  }

  late final ThreadPost displayPost = _buildDisplayPost();

  ThreadPost _buildDisplayPost() {
    if (projectedPost != null) return projectedPost!;
    final post = sourceItem.post;
    if (displayMessage == post.message && displayDateline == post.dateline) {
      return post;
    }
    final collector = ThreadPlainTextCollector();
    final slots = ThreadPostTextSlots.collect(post, collector);
    collector.sources[slots.dateline.index] = displayDateline;
    return slots.build(
      post,
      values: collector.sources,
      displayHtml: displayMessage,
    );
  }

  final ComicCommentItem sourceItem;
  final String displayMessage;
  final String displayDateline;
}

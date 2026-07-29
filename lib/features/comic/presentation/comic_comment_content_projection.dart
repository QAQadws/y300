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
}

@immutable
final class ComicCommentItemProjection {
  const ComicCommentItemProjection({
    required this.sourceItem,
    required this.displayMessage,
    required this.displayDateline,
  });

  ComicCommentItemProjection.raw(ComicCommentItem sourceItem)
    : this(
        sourceItem: sourceItem,
        displayMessage: sourceItem.rawMessage,
        displayDateline: sourceItem.dateline,
      );

  final ComicCommentItem sourceItem;
  final String displayMessage;
  final String displayDateline;
}

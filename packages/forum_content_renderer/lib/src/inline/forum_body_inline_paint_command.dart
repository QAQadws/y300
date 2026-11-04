import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import 'forum_body_inline_paint_row.dart';

/// One borrowed ACTUAL drawable and its pure command. This neither owns the
/// resource nor proves source coverage. Keep its source alive until the common
/// scene worker has adopted dependencies; only that worker takes private aliases.
final class ForumBodyInlinePaintCommand {
  const ForumBodyInlinePaintCommand._(this.command, this.resource, this.row);
  factory ForumBodyInlinePaintCommand.text(
    ForumBodyTextLease text,
    Offset offset,
  ) => ForumBodyInlinePaintCommand._(
    ForumBodyTextPictureCommand.fromText(text, offset),
    text,
    null,
  );
  factory ForumBodyInlinePaintCommand.picture(
    ForumBodyTextPictureLease picture,
    Offset offset,
  ) => ForumBodyInlinePaintCommand._(
    ForumBodyTextPictureCommand.fromPicture(picture, offset),
    picture,
    null,
  );
  factory ForumBodyInlinePaintCommand.parent(
    ForumBodyInlinePaintRowView row,
    Offset offset,
  ) => ForumBodyInlinePaintCommand._(
    ForumBodyTextPictureCommand.fromInlineRow(row, offset),
    row.parent,
    row,
  );
  factory ForumBodyInlinePaintCommand.fill(
    Rect rect,
    Color color,
    Offset offset,
  ) => ForumBodyInlinePaintCommand._(
    ForumBodyTextPictureCommand.fillRect(
      rect: rect,
      color: color,
      offset: offset,
    ),
    null,
    null,
  );
  final ForumBodyTextPictureCommand command;
  final ForumBodyNativeParagraphLease? resource;
  final ForumBodyInlinePaintRowView? row;
  ForumBodyInlinePaintCommand translated(Offset offset) =>
      ForumBodyInlinePaintCommand._(command.translated(offset), resource, row);
  ForumBodyInlinePaintCommand clipped(Rect clip) =>
      ForumBodyInlinePaintCommand._(command.clipped(clip), resource, row);
}

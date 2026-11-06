import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_text_layout.dart';
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

  void replay(Canvas canvas, {ForumBodyTextLayout? textInk}) {
    canvas.save();
    try {
      final offset = command.applyPaintTransform(canvas);
      if (command.fill case final fill?) {
        canvas.drawRect(fill.rect.shift(offset), Paint()..color = fill.color);
      } else if (row case final line?) {
        line.paint(canvas, offset);
      } else {
        switch (resource) {
          case final ForumBodyTextLease text:
            (textInk ?? text.layout).paint(canvas, offset);
          case final ForumBodyDecorationTextLease decoration:
            decoration.layout.paint(canvas, offset);
          case final ForumBodyTextPictureLease picture:
            picture.paint(canvas, offset);
          default:
            throw StateError('Unsupported inline paint resource');
        }
      }
    } finally {
      canvas.restore();
    }
  }
}

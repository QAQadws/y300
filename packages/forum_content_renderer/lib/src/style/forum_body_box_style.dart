import 'forum_body_length.dart';

enum ForumBodyBoxSizing { contentBox, borderBox }

/// Computed CSS lengths; percentages still use the containing block's width.
/// Null width means auto, null maxWidth means none. These values do not inherit
/// implicitly and never include the renderer's text scaling a second time.
final class ForumBodyBoxStyle {
  const ForumBodyBoxStyle({
    this.width,
    this.minWidth = ForumBodyLength.zero,
    this.maxWidth,
    this.sizing = ForumBodyBoxSizing.contentBox,
  });
  final ForumBodyLength? width;
  final ForumBodyLength minWidth;
  final ForumBodyLength? maxWidth;
  final ForumBodyBoxSizing sizing;
}

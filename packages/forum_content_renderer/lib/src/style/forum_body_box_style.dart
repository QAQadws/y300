import 'forum_body_length.dart';

enum ForumBodyBoxSizing { contentBox, borderBox }

/// Computed CSS lengths; percentages still use the containing block's width.
/// Null width/height mean unspecified, null maxWidth means none. An image
/// can have explicit auto to override an HTML sizing attribute. These values
/// do not inherit implicitly or include the renderer's text scaling.
final class ForumBodyBoxStyle {
  const ForumBodyBoxStyle({
    this.width,
    this.height,
    this.minWidth = ForumBodyLength.zero,
    this.maxWidth,
    this.sizing = ForumBodyBoxSizing.contentBox,
  });
  final ForumBodyLength? width;
  final ForumBodyLength? height;
  final ForumBodyLength minWidth;
  final ForumBodyLength? maxWidth;
  final ForumBodyBoxSizing sizing;
}

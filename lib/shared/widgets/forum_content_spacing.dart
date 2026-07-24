/// Horizontal spacing used by the native forum content surfaces.
abstract final class ForumContentSpacing {
  /// Space between the viewport edge and the post card.
  static const double pageHorizontal = 12;

  /// Space between a post card edge and its readable body.
  static const double postBodyHorizontal = 10;

  /// Final horizontal inset of readable post text.
  static const double readableBodyHorizontal =
      pageHorizontal + postBodyHorizontal;

  /// Internal horizontal padding supplied by QuillEditorConfig.
  static const double quillInnerHorizontal = 12;

  /// Additional surface padding required to align Quill text with post text.
  static const double composerQuillSurfaceHorizontal =
      readableBodyHorizontal - quillInnerHorizontal;

  /// Existing horizontal padding of composer page lists.
  static const double composerPageHorizontal = 16;

  /// Additional source-editor padding required to align with post text.
  static const double composerSourceEditorHorizontal =
      readableBodyHorizontal - composerPageHorizontal;
}

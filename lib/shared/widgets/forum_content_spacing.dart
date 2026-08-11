/// Spacing used by the native forum content surfaces and the composers that
/// must visually match them.
///
/// Tuning guide: only the values in the "knobs" section are meant to be edited.
/// Everything below `readableBodyHorizontal` is derived, so the composer text
/// keeps landing on the same horizontal inset as post text. The derived values
/// must stay >= 0; `forum_content_spacing_test.dart` locks that down.
abstract final class ForumContentSpacing {
  // --- Horizontal knobs ---

  /// Space between the viewport edge and the post card.
  static const double pageHorizontal = 6;

  /// Space between a post card edge and its readable body.
  static const double postBodyHorizontal = 6;

  /// Internal horizontal padding supplied by QuillEditorConfig.
  ///
  /// Not a knob: it mirrors a flutter_quill default, so changing it here only
  /// makes the composer misalign.
  static const double quillInnerHorizontal = 12;

  /// Horizontal padding of the composer pages' own scroll views.
  ///
  /// Source-mode alignment depends on this matching the pages' actual list
  /// padding, so both read this token instead of repeating a literal.
  static const double composerPageHorizontal = 12;

  /// Vertical padding of the composer pages' own scroll views.
  static const double composerPageVertical = 16;

  // --- Vertical knobs ---

  /// Outer vertical padding of the thread detail list.
  static const double listTop = 8;
  static const double listBottom = 12;

  /// Gap between two adjacent post cards.
  static const double postCardGap = 8;

  /// Top inset of a post card's header segment (avatar + meta row).
  static const double postCardHeaderTop = 8;

  /// Top inset of a post card's body segment (the readable HTML).
  static const double postCardBodyTop = 6;

  /// Insets of a post card's footer segment (poll / comments / ratings).
  static const double postCardFooterTop = 8;
  static const double postCardFooterBottom = 8;

  /// Bottom inset of the single-container post card variant, which carries
  /// header, body and footer in one box instead of three segments.
  static const double postCardSingleBottom = 9;

  /// Bottom inset of the composer body. Larger than [postCardBodyTop]'s
  /// counterpart on purpose: it is scroll slack under the caret, not visual
  /// symmetry with a post card.
  static const double composerBodyBottom = 16;

  // --- Derived: keep composer text aligned with post text ---

  /// Final horizontal inset of readable post text.
  static const double readableBodyHorizontal =
      pageHorizontal + postBodyHorizontal;

  /// Additional surface padding required to align Quill text with post text.
  static const double composerQuillSurfaceHorizontal =
      readableBodyHorizontal - quillInnerHorizontal;

  /// Additional source-editor padding required to align with post text.
  static const double composerSourceEditorHorizontal =
      readableBodyHorizontal - composerPageHorizontal;

  /// Top inset of the composer body, matched to the post body segment so the
  /// first line starts at the same offset in both surfaces.
  static const double composerBodyTop = postCardBodyTop;
}

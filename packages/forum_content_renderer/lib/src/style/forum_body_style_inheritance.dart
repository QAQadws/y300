import 'forum_body_style_options.dart';

/// When a body-only override ends at a semantic role, restore that property's
/// author parent value before resolving the child. Other computed inheritance
/// (including lengths depending on an effective parent font) remains intact.
final class ForumBodyStyleInheritance {
  const ForumBodyStyleInheritance(this.policy);
  final ForumBodyStylePolicy policy;

  ForumBodyResolvedStyle parentFor({
    required ForumBodyTextRole role,
    required ForumBodyResolvedStyle author,
    required ForumBodyResolvedStyle effective,
  }) {
    bool restore(ForumBodyStyleProperty property) =>
        policy.overrides(property, effective.role) &&
        !policy.overrides(property, role);
    if (!ForumBodyStyleProperty.values.any(restore)) return effective;
    return ForumBodyResolvedStyle(
      textStyle: effective.textStyle.copyWith(
        fontSize: restore(ForumBodyStyleProperty.fontSize)
            ? author.textStyle.fontSize
            : effective.textStyle.fontSize,
        fontWeight: restore(ForumBodyStyleProperty.fontWeight)
            ? author.textStyle.fontWeight
            : effective.textStyle.fontWeight,
        letterSpacing: restore(ForumBodyStyleProperty.letterSpacing)
            ? author.textStyle.letterSpacing
            : effective.textStyle.letterSpacing,
        wordSpacing: restore(ForumBodyStyleProperty.wordSpacing)
            ? author.textStyle.wordSpacing
            : effective.textStyle.wordSpacing,
        color: restore(ForumBodyStyleProperty.foreground)
            ? author.textStyle.color
            : effective.textStyle.color,
        backgroundColor: restore(ForumBodyStyleProperty.background)
            ? author.textStyle.backgroundColor
            : effective.textStyle.backgroundColor,
      ),
      role: effective.role,
      textAlign: restore(ForumBodyStyleProperty.textAlign)
          ? author.textAlign
          : effective.textAlign,
      alignmentFromReader: restore(ForumBodyStyleProperty.textAlign)
          ? author.alignmentFromReader
          : effective.alignmentFromReader,
      textDirection: effective.textDirection,
      whiteSpace: effective.whiteSpace,
      rubyPosition: effective.rubyPosition,
      textEmphasis: restore(ForumBodyStyleProperty.foreground)
          ? effective.textEmphasis.withColor(author.textEmphasis.color)
          : effective.textEmphasis,
      indent: restore(ForumBodyStyleProperty.textIndent)
          ? author.indent
          : effective.indent,
      indentFromReader: restore(ForumBodyStyleProperty.textIndent)
          ? author.indentFromReader
          : effective.indentFromReader,
      margin: restore(ForumBodyStyleProperty.paragraphSpacing)
          ? author.margin
          : effective.margin,
      padding: effective.padding,
      box: effective.box,
      lineHeight: restore(ForumBodyStyleProperty.lineHeight)
          ? author.lineHeight
          : effective.lineHeight,
      hidden: effective.hidden,
      strong: effective.strong,
      ownDecoration: effective.ownDecoration,
      linkTarget: effective.linkTarget,
      boxBackground: restore(ForumBodyStyleProperty.background)
          ? author.boxBackground
          : effective.boxBackground,
      ownBackground: restore(ForumBodyStyleProperty.background)
          ? author.ownBackground
          : effective.ownBackground,
      display: effective.display,
      visibilityHidden: effective.visibilityHidden,
    );
  }
}

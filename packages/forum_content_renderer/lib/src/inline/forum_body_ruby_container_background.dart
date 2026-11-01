import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_ruby_content.dart';

/// Pure container paint input, separate from its base and annotation glyphs.
/// The source-free natural font box does not become text/source coverage.
final class ForumBodyRubyContainerBackground {
  ForumBodyRubyContainerBackground({
    required this.rootPath,
    required this.fontStrut,
    required Color color,
  }) : color = _snapshotColor(color) {
    if (rootPath.isEmpty ||
        !fontStrut.isSourceFree ||
        fontStrut.projection.text.isNotEmpty ||
        fontStrut.layoutMode !=
            ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
        fontStrut.style.textStyle.height != kTextHeightNone) {
      throw ArgumentError('Invalid ruby container background');
    }
  }

  static ForumBodyRubyContainerBackground? fromGroup(
    ForumBodyRubyGroupContent group,
  ) {
    final color = group.style.boxBackground;
    if (color == null) return null;
    final frozen = _snapshotColor(color);
    if (frozen.a <= 0) return null;
    final style = group.style;
    return ForumBodyRubyContainerBackground(
      rootPath: group.rootPath,
      color: frozen,
      fontStrut: ForumBodyParagraphContent.anonymousInline(
        identity: group.identity,
        fontRevision: group.fontRevision,
        styleRevision: group.styleRevision,
        style: ForumBodyResolvedStyle(
          // Inline backgrounds use the container's own natural font box, not
          // author line-height or the tallest of its independently sized RBs.
          textStyle: style.textStyle.copyWith(height: kTextHeightNone),
          role: style.role,
          textAlign: style.textAlign,
          textDirection: style.textDirection,
        ),
      ),
    );
  }

  final String rootPath;
  final Color color;
  final ForumBodyParagraphContent fontStrut;

  void validateScope(ForumBodyParagraphContent content) {
    if (fontStrut.identity != content.identity ||
        fontStrut.fontRevision != content.fontRevision ||
        fontStrut.styleRevision != content.styleRevision) {
      throw ArgumentError('Ruby container background scope mismatch');
    }
  }
}

/// Qualified numeric font geometry. No lease, cache or owner survives capture.
final class ForumBodyRubyContainerFontBox {
  ForumBodyRubyContainerFontBox({
    required this.background,
    required this.height,
    required this.alphabeticBaseline,
  }) {
    if (!height.isFinite || height < 0 || !alphabeticBaseline.isFinite) {
      throw ArgumentError('Invalid ruby container font geometry');
    }
  }
  final ForumBodyRubyContainerBackground background;
  final double height;
  final double alphabeticBaseline;
}

Color _snapshotColor(Color color) {
  final alpha = color.a, red = color.r, green = color.g, blue = color.b;
  if (!alpha.isFinite || !red.isFinite || !green.isFinite || !blue.isFinite) {
    throw ArgumentError('Nonfinite ruby container background');
  }
  return Color.from(
    alpha: alpha,
    red: red,
    green: green,
    blue: blue,
    colorSpace: color.colorSpace,
  );
}

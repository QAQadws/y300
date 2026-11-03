import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_ruby_content.dart';
import 'forum_body_ruby_container_background.dart';

/// The root's own line-box font, independent of its children's glyph boxes and
/// of whether a background is painted. It never contributes source or text.
final class ForumBodyRubyRootBoxInput {
  ForumBodyRubyRootBoxInput({required this.rootPath, required this.fontStrut}) {
    if (rootPath.isEmpty ||
        !fontStrut.isSourceFree ||
        fontStrut.projection.text.isNotEmpty ||
        fontStrut.layoutMode !=
            ForumBodyParagraphLayoutMode.intrinsicSingleLine) {
      throw ArgumentError('Invalid ruby root font input');
    }
  }

  factory ForumBodyRubyRootBoxInput.fromGroup(
    ForumBodyRubyGroupContent group,
  ) => ForumBodyRubyRootBoxInput(
    rootPath: group.rootPath,
    fontStrut: ForumBodyParagraphContent.anonymousInline(
      identity: group.identity,
      fontRevision: group.fontRevision,
      styleRevision: group.styleRevision,
      style: group.style,
    ),
  );

  final String rootPath;
  final ForumBodyParagraphContent fontStrut;

  void validateScope(
    ForumBodyParagraphContent content, {
    ForumBodyRubyContainerBackground? background,
  }) {
    if (fontStrut.identity != content.identity ||
        fontStrut.fontRevision != content.fontRevision ||
        fontStrut.styleRevision != content.styleRevision) {
      throw ArgumentError('Ruby root font scope mismatch');
    }
    if (background != null &&
        (background.rootPath != rootPath ||
            background.fontStrut.style.textStyle !=
                fontStrut.style.textStyle.copyWith(height: kTextHeightNone))) {
      throw ArgumentError('Ruby root font differs from background font');
    }
  }
}

/// Actual empty native font geometry, captured through the reading cache. Only
/// numbers survive capture; the native resource is released before publication.
final class ForumBodyRubyRootFontBox {
  ForumBodyRubyRootFontBox({
    required this.input,
    required this.height,
    required this.alphabeticBaseline,
  }) {
    if (!height.isFinite || height < 0 || !alphabeticBaseline.isFinite) {
      throw ArgumentError('Invalid ruby root font geometry');
    }
  }
  final ForumBodyRubyRootBoxInput input;
  final double height;
  final double alphabeticBaseline;

  ForumBodyRubyAtomFrame enclose({
    required Size childSize,
    required double childBaseline,
  }) => encloseBounds(
    childBounds: Offset.zero & childSize,
    childBaseline: childBaseline,
  );

  /// Reserve the actual child's complete envelope without changing its local
  /// origin. Decorations can extend on either side of its original ruby box;
  /// moving those extents into the base band would also move the annotations.
  ForumBodyRubyAtomFrame encloseBounds({
    required Rect childBounds,
    required double childBaseline,
  }) {
    if (!childBounds.left.isFinite ||
        !childBounds.top.isFinite ||
        !childBounds.right.isFinite ||
        !childBounds.bottom.isFinite ||
        !childBounds.width.isFinite ||
        childBounds.width > 16384 ||
        childBounds.width < 0 ||
        !childBounds.height.isFinite ||
        childBounds.height <= 0 ||
        !childBaseline.isFinite ||
        childBaseline < childBounds.top ||
        childBaseline > childBounds.bottom) {
      throw ArgumentError('Invalid ruby child frame');
    }
    final ascent = math.max(
      childBaseline - childBounds.top,
      alphabeticBaseline,
    );
    final descent = math.max(
      childBounds.bottom - childBaseline,
      height - alphabeticBaseline,
    );
    final frameHeight = ascent + descent;
    if (!frameHeight.isFinite || frameHeight > 16384) {
      throw ArgumentError('Ruby root frame exceeds layout bounds');
    }
    return ForumBodyRubyAtomFrame._(
      Size(childBounds.width, frameHeight),
      ascent,
      Offset(-childBounds.left, ascent - childBaseline),
      childBounds,
    );
  }
}

/// Parent allocation and one translation of the unchanged child layout. Root
/// leading must not be folded into the base band and move its annotations.
final class ForumBodyRubyAtomFrame {
  const ForumBodyRubyAtomFrame._(
    this.size,
    this.baseline,
    this.childOffset,
    this.childBounds,
  );
  final Size size;
  final double baseline;

  /// The original child's coordinates stay intact for paint, hit and selection.
  final Offset childOffset;
  final Rect childBounds;
  double get childTop => childOffset.dy;
  PlaceholderDimensions get dimensions => PlaceholderDimensions(
    size: size,
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: baseline,
  );
}

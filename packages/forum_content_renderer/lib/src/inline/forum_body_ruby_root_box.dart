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
  }) {
    if (!childSize.width.isFinite ||
        childSize.width > 16384 ||
        childSize.width < 0 ||
        !childSize.height.isFinite ||
        childSize.height <= 0 ||
        !childBaseline.isFinite ||
        childBaseline < 0 ||
        childBaseline > childSize.height) {
      throw ArgumentError('Invalid ruby child frame');
    }
    final ascent = math.max(childBaseline, alphabeticBaseline);
    final descent = math.max(
      childSize.height - childBaseline,
      height - alphabeticBaseline,
    );
    final frameHeight = ascent + descent;
    if (!frameHeight.isFinite || frameHeight > 16384) {
      throw ArgumentError('Ruby root frame exceeds layout bounds');
    }
    return ForumBodyRubyAtomFrame._(
      Size(childSize.width, frameHeight),
      ascent,
      ascent - childBaseline,
    );
  }
}

/// Parent allocation and one translation of the unchanged child layout. Root
/// leading must not be folded into the base band and move its annotations.
final class ForumBodyRubyAtomFrame {
  const ForumBodyRubyAtomFrame._(this.size, this.baseline, this.childTop);
  final Size size;
  final double baseline;
  final double childTop;
  PlaceholderDimensions get dimensions => PlaceholderDimensions(
    size: size,
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: baseline,
  );
}

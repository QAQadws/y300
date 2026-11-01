import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Engine-only advance, already measured/scaled. SPACE remains collapsible;
/// NBSP plus WORD JOINER keeps first-line indentation attached to text.
/// The private font has no ascent/descent/ink. Real base/annotation glyphs keep
/// their original fonts, sources and native owners.
final class ForumBodyNativeSpaceSpan extends TextSpan {
  ForumBodyNativeSpaceSpan(double advance) : this._(advance, ' ');
  ForumBodyNativeSpaceSpan.nonBreaking(double advance)
    : this._(advance, nonBreakingText);
  ForumBodyNativeSpaceSpan._(this.advance, String text) : super(text: text) {
    if (!advance.isFinite || advance < 0 || advance > 16384) {
      throw ArgumentError.value(advance, 'advance');
    }
  }

  static const fontFamily =
      'packages/forum_content_renderer/ForumBodyInlineSpace';
  static const unitsPerEm = 1024;
  static const nonBreakingText = '\u00A0\u2060';
  final double advance;

  @override
  RenderComparison compareTo(InlineSpan other) =>
      other is ForumBodyNativeSpaceSpan &&
          other.advance == advance &&
          other.text == text
      ? RenderComparison.identical
      : RenderComparison.layout;

  @override
  bool operator ==(Object other) =>
      other is ForumBodyNativeSpaceSpan &&
      other.advance == advance &&
      other.text == text;

  @override
  int get hashCode => Object.hash(runtimeType, advance, text);

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    builder.pushStyle(
      ui.TextStyle(
        fontFamily: fontFamily,
        // The font's advance is 1/1024 em. This preserves actual system-font
        // subpixel widths through Android's native font-size quantization;
        // it is an internal font-unit conversion, not another reader scale.
        fontSize: advance * unitsPerEm,
        height: 0,
        fontWeight: FontWeight.normal,
        fontStyle: FontStyle.normal,
        letterSpacing: 0,
        wordSpacing: 0,
        foreground: ui.Paint()..color = const Color(0x00000000),
        background: ui.Paint()..color = const Color(0x00000000),
        shadows: const [],
        decoration: TextDecoration.none,
        fontFeatures: const [],
        fontVariations: const [],
      ),
    );
    builder.addText(text!);
    builder.pop();
  }
}

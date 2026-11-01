import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Engine-only collapsible glue: its advance is already measured/scaled.
/// The private blank font has one-em SPACE and zero ascent/descent/ink. Actual
/// base/annotation glyphs keep their original fonts, sources and native owners.
final class ForumBodyNativeSpaceSpan extends TextSpan {
  ForumBodyNativeSpaceSpan(this.advance) : super(text: ' ') {
    if (!advance.isFinite || advance < 0 || advance > 16384) {
      throw ArgumentError.value(advance, 'advance');
    }
  }

  static const fontFamily =
      'packages/forum_content_renderer/ForumBodyInlineSpace';
  final double advance;

  @override
  RenderComparison compareTo(InlineSpan other) =>
      other is ForumBodyNativeSpaceSpan && other.advance == advance
      ? RenderComparison.identical
      : RenderComparison.layout;

  @override
  bool operator ==(Object other) =>
      other is ForumBodyNativeSpaceSpan && other.advance == advance;

  @override
  int get hashCode => Object.hash(runtimeType, advance);

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    builder.pushStyle(
      ui.TextStyle(
        fontFamily: fontFamily,
        fontSize: advance,
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
    builder.addText(' ');
    builder.pop();
  }
}

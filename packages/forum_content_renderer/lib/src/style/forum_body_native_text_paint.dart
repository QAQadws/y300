import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';

import 'forum_body_paint_text_style.dart';
import 'forum_body_style_options.dart';

/// Native row order is background, shadows/glyphs, then decorations. Each
/// consumer must retain physical row order and the appropriate paint offsets.
enum ForumBodyParagraphPaintLayer { all, background, foreground, decoration }

/// Shared native span derivation. Font inputs and text seams remain intact;
/// invisible paints have stable source/layer equality for cache admission.
TextSpan forumBodyNativePaintSpan({
  required TextStyle style,
  required ForumBodyParagraphPaintLayer layer,
  String? text,
  List<InlineSpan>? children,
  ForumBodyResolvedStyle? resolved,
}) {
  final visible = resolved == null ? style : forumBodyPaintTextStyle(resolved);
  final hidden = resolved?.visibilityHidden ?? false;
  if (layer == ForumBodyParagraphPaintLayer.all && !hidden) {
    return TextSpan(style: visible, text: text, children: children);
  }
  return _LayerSpan(
    sourceStyle: style,
    layer: layer,
    hidden: hidden,
    style: switch (layer) {
      ForumBodyParagraphPaintLayer.all => visible,
      ForumBodyParagraphPaintLayer.background => visible.copyWith(
        foreground: Paint()..color = const Color(0x00000000),
        shadows: const [],
        decoration: TextDecoration.none,
      ),
      ForumBodyParagraphPaintLayer.foreground => visible.copyWith(
        background: Paint()..color = const Color(0x00000000),
        decoration: TextDecoration.none,
      ),
      ForumBodyParagraphPaintLayer.decoration => visible.copyWith(
        foreground: Paint()..color = const Color(0x00000000),
        background: Paint()..color = const Color(0x00000000),
        shadows: const [],
      ),
    },
    text: text,
    children: children,
  );
}

final class _LayerSpan extends _DecorationSpan {
  _LayerSpan({
    required this.sourceStyle,
    required this.layer,
    required this.hidden,
    required super.style,
    super.text,
    super.children,
  }) : super(
         sourceColor: layer == ForumBodyParagraphPaintLayer.decoration
             ? sourceStyle.color
             : null,
       );
  final TextStyle sourceStyle;
  final ForumBodyParagraphPaintLayer layer;
  final bool hidden;
  @override
  RenderComparison compareTo(InlineSpan other) =>
      this == other ? RenderComparison.identical : super.compareTo(other);
  @override
  bool operator ==(Object other) =>
      other is _LayerSpan &&
      sourceStyle == other.sourceStyle &&
      layer == other.layer &&
      hidden == other.hidden &&
      text == other.text &&
      listEquals(children, other.children);
  @override
  int get hashCode => Object.hash(
    sourceStyle,
    layer,
    hidden,
    text,
    Object.hashAll(children ?? const []),
  );
}

/// Preserve native color below the transparent foreground override. Replacing
/// decorationColor changes inheritance, transparent sentinels and native run
/// coalescing. No additional text boundary is introduced here.
final class _DecorationSpan extends TextSpan {
  const _DecorationSpan({
    required this.sourceColor,
    required super.style,
    super.text,
    super.children,
  });
  final Color? sourceColor;
  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    final color = sourceColor;
    if (color != null) builder.pushStyle(ui.TextStyle(color: color));
    try {
      super.build(builder, textScaler: textScaler, dimensions: dimensions);
    } finally {
      if (color != null) builder.pop();
    }
  }

  @override
  RenderComparison compareTo(InlineSpan other) {
    if (other is! _DecorationSpan) return RenderComparison.layout;
    final comparison = super.compareTo(other);
    return sourceColor != other.sourceColor &&
            comparison.index < RenderComparison.paint.index
        ? RenderComparison.paint
        : comparison;
  }

  @override
  bool operator ==(Object other) =>
      other is _DecorationSpan &&
      sourceColor == other.sourceColor &&
      super == other;
  @override
  int get hashCode => Object.hash(super.hashCode, sourceColor);
}

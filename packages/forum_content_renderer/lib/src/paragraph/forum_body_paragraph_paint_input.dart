part of 'forum_body_paragraph_content.dart';

/// Native per-row phases: background, shadows/glyphs, then decorations. Their
/// paint coordinates may differ; composition must retain physical row order.
enum ForumBodyParagraphPaintLayer { all, background, foreground, decoration }

/// Whole-context paint derivation; no text/style seam or font input is changed.
/// These inputs have distinct native identities and use the existing cache and
/// admission. They do not acquire resources or authorize current source hits.
final class ForumBodyParagraphPaintInput {
  ForumBodyParagraphPaintInput(ForumBodyParagraphContent original)
    : original = original,
      background = _derive(original, ForumBodyParagraphPaintLayer.background),
      foreground = _derive(original, ForumBodyParagraphPaintLayer.foreground),
      decoration = _derive(original, ForumBodyParagraphPaintLayer.decoration);

  static const revision = 3;
  final ForumBodyParagraphContent original, background, foreground, decoration;

  static ForumBodyParagraphContent _derive(
    ForumBodyParagraphContent original,
    ForumBodyParagraphPaintLayer layer,
  ) {
    if (original.isSourceFree ||
        original.paintLayer != ForumBodyParagraphPaintLayer.all) {
      throw ArgumentError('Paint layers require an original text context');
    }
    return ForumBodyParagraphContent._paintLayer(original, layer);
  }
}

// Generated transparent Paints have identity equality. Compare the original
// style plus the explicit derivation instead, so rebuilding an equal input
// doesn't miss every native phase. Caller-provided Paints keep their original
// TextStyle identity semantics; native building still uses the derived style.
final class _ForumBodyLayerSpan extends _ForumBodyDecorationSpan {
  _ForumBodyLayerSpan({
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
      other is _ForumBodyLayerSpan &&
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

/// Preserve native color below the transparent foreground override. An explicit
/// replacement decorationColor would change inheritance, transparent sentinel
/// semantics and native decoration-run coalescing. No text boundary is added.
final class _ForumBodyDecorationSpan extends TextSpan {
  const _ForumBodyDecorationSpan({
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
    if (other is! _ForumBodyDecorationSpan) return RenderComparison.layout;
    final comparison = super.compareTo(other);
    return sourceColor != other.sourceColor &&
            comparison.index < RenderComparison.paint.index
        ? RenderComparison.paint
        : comparison;
  }

  @override
  bool operator ==(Object other) =>
      other is _ForumBodyDecorationSpan &&
      sourceColor == other.sourceColor &&
      super == other;
  @override
  int get hashCode => Object.hash(super.hashCode, sourceColor);
}

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_native_paragraph_layout.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../style/forum_body_style_options.dart';

/// Source-free single-line font input; no DOM/display projection or caret.
final class ForumBodyDecorationTextInput {
  ForumBodyDecorationTextInput._({
    required this.text,
    required this.textStyle,
    required this.textDirection,
    required this.fontRevision,
    required this.styleRevision,
  });

  /// Full-size, bounded decoration text, for example a list's `12.` label.
  factory ForumBodyDecorationTextInput.label({
    required String text,
    required ForumBodyResolvedStyle style,
    required String fontRevision,
    required int styleRevision,
  }) {
    final source = style.textStyle;
    final size = source.fontSize;
    final settings =
        (source.fontFamilyFallback?.length ?? 0) +
        (source.fontFeatures?.length ?? 0) +
        (source.fontVariations?.length ?? 0) +
        (source.shadows?.length ?? 0);
    if (text.isEmpty ||
        text.length > 64 ||
        text.runes.any(
          (unit) =>
              forumBodyIsDisplayLineBreak(unit) || unit < 0x20 || unit == 0x85,
        ) ||
        size == null ||
        !size.isFinite ||
        size <= 0 ||
        size > 512 ||
        source.foreground != null ||
        source.background != null ||
        settings > 512 ||
        !(source.letterSpacing ?? 0).isFinite ||
        !(source.wordSpacing ?? 0).isFinite) {
      throw ArgumentError('Invalid source-free decoration text');
    }
    // The core validates Unicode/whitespace without assigning the resulting
    // temporary zero-based projection any source or reading authority.
    final validation = HtmlDisplayTextProjection.build([
      HtmlDisplayTextRun(
        text: text,
        sourceRuneStart: 0,
        whiteSpace: HtmlDisplayWhiteSpace.pre,
      ),
    ]);
    if (validation.text != text) throw ArgumentError('Invalid decoration text');
    return ForumBodyDecorationTextInput._(
      text: text,
      fontRevision: fontRevision,
      styleRevision: styleRevision,
      textDirection: style.textDirection,
      textStyle: TextStyle(
        inherit: false,
        color: style.visibilityHidden
            ? const Color(0x00000000)
            : source.color ?? const Color(0xff000000),
        fontFamily: source.fontFamily,
        fontFamilyFallback: source.fontFamilyFallback == null
            ? null
            : List.unmodifiable(source.fontFamilyFallback!),
        fontSize: size,
        fontWeight: source.fontWeight,
        fontStyle: source.fontStyle,
        locale: source.locale,
        textBaseline: source.textBaseline,
        height: kTextHeightNone,
        letterSpacing: source.letterSpacing,
        wordSpacing: source.wordSpacing,
        decoration: TextDecoration.none,
        fontFeatures: source.fontFeatures == null
            ? null
            : List.unmodifiable(source.fontFeatures!),
        fontVariations: source.fontVariations == null
            ? null
            : List.unmodifiable(source.fontVariations!),
        shadows: style.visibilityHidden
            ? const []
            : source.shadows == null
            ? null
            : List.unmodifiable(source.shadows!),
      ),
    );
  }
  static const revision = 1;
  final String text;
  final TextStyle textStyle;
  final TextDirection textDirection;
  final String fontRevision;
  final int styleRevision;
  late final estimatedInputBytes =
      4096 +
      text.length * 96 +
      256 +
      fontRevision.length * 2 +
      (textStyle.fontFamily?.length ?? 0) * 2 +
      (textStyle.fontFamilyFallback?.fold<int>(
            0,
            (sum, value) => sum + 16 + value.length * 2,
          ) ??
          0) +
      (textStyle.fontFeatures?.length ?? 0) * 24 +
      (textStyle.fontVariations?.length ?? 0) * 24 +
      (textStyle.shadows?.length ?? 0) * 48;
  late final int _hash = Object.hash(
    revision,
    text,
    textStyle,
    textDirection,
    fontRevision,
    styleRevision,
  );
  @override
  int get hashCode => _hash;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumBodyDecorationTextInput &&
          text == other.text &&
          textStyle == other.textStyle &&
          textDirection == other.textDirection &&
          fontRevision == other.fontRevision &&
          styleRevision == other.styleRevision;
}

/// Native font metrics/paint only; this resource cannot masquerade as a text
/// lease or answer source hits and selection requests. Owned by the same cache.
final class ForumBodyDecorationTextLayout
    implements ForumBodyNativeParagraphLayout {
  ForumBodyDecorationTextLayout._(
    this._painter,
    this.width,
    this.height,
    this.alphabeticBaseline,
    this.fontBounds,
  );
  static const revision = 2;
  static double resolveScale(
    ForumBodyDecorationTextInput input,
    TextScaler textScaler,
  ) {
    final scaled = textScaler.scale(input.textStyle.fontSize!);
    if (!scaled.isFinite || scaled <= 0 || scaled > 4096) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.scale,
      );
    }
    return scaled;
  }

  factory ForumBodyDecorationTextLayout.create({
    required ForumBodyDecorationTextInput input,
    required double scaledFontSize,
  }) {
    if (!scaledFontSize.isFinite ||
        scaledFontSize <= 0 ||
        scaledFontSize > 4096) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.scale,
      );
    }
    final painter = TextPainter(
      text: TextSpan(text: input.text, style: input.textStyle),
      textDirection: input.textDirection,
      locale: input.textStyle.locale,
      textScaler: _DecorationScaler(input.textStyle.fontSize!, scaledFontSize),
    );
    try {
      painter.layout(maxWidth: double.infinity);
      final lines = painter.computeLineMetrics();
      if (lines.length != 1) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.singleLine,
        );
      }
      if (!painter.width.isFinite || painter.width > 16384) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.width,
        );
      }
      var bounds = Rect.fromLTWH(0, 0, painter.width, painter.height);
      for (final box in painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: input.text.length),
      )) {
        bounds = bounds.expandToInclude(box.toRect());
      }
      return ForumBodyDecorationTextLayout._(
        painter,
        painter.width,
        painter.height,
        lines.single.baseline,
        bounds,
      );
    } catch (_) {
      painter.dispose();
      rethrow;
    }
  }
  final TextPainter _painter;
  final double width;
  final double height;
  final double alphabeticBaseline;

  /// Native row plus complete label font selection.
  final Rect fontBounds;
  @override
  int get lineCount => 1;
  @override
  bool get isDisposed => _disposed;
  bool _disposed = false;
  void paint(Canvas canvas, Offset offset) {
    if (_disposed) throw StateError('Decoration text is disposed');
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    _painter.paint(canvas, offset);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _painter.dispose();
  }
}

final class _DecorationScaler extends TextScaler {
  const _DecorationScaler(this.size, this.scaled);
  final double size, scaled;
  @override
  double scale(double fontSize) => fontSize == size
      ? scaled
      : throw StateError('Decoration font size was not captured');
  @override
  double get textScaleFactor => scaled / size;
}

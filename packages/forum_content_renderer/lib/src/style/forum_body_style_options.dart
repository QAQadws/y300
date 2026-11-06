import 'package:flutter/painting.dart';

import 'forum_body_length.dart';
import 'forum_body_box_style.dart';
import 'forum_body_ruby_position.dart';
import 'forum_body_text_emphasis.dart';
import 'forum_body_quote_decoration.dart';
import 'forum_body_list_style.dart';
import 'forum_body_baseline_shift.dart';
import '../html_rendering/theme/forum_html_theme_context.dart';
import '../document/forum_body_document.dart';

export 'forum_body_ruby_position.dart';
export 'forum_body_text_emphasis.dart';
export 'forum_body_quote_decoration.dart';
export 'forum_body_list_style.dart';
export 'forum_body_baseline_shift.dart';

enum ForumBodyStyleScope { asDefault, forceBody, forceAll }

enum ForumBodyStyleProperty {
  fontSize,
  fontWeight,
  lineHeight,
  letterSpacing,
  wordSpacing,
  textAlign,
  textIndent,
  paragraphSpacing,
  foreground,
  background,
}

enum ForumBodyTextRole { body, heading, quote, code, list, table, ruby, notice }

typedef ForumBodyRoleFontScales = ({double heading, double quote, double code});

enum ForumBodyFloatSide { none, left, right, unsupported }

enum ForumBodyClear { none, left, right, both, unsupported }

enum ForumBodyWhiteSpace { normal, pre, preWrap, preLine }

enum ForumBodyDisplay {
  inline,
  block,
  listItem,
  inlineBlock,
  table,
  tableRow,
  tableCell,
  none,
}

final class ForumBodyStylePolicy {
  ForumBodyStylePolicy([
    Map<ForumBodyStyleProperty, ForumBodyStyleScope> values = const {},
  ]) : values = Map.unmodifiable(values);
  final Map<ForumBodyStyleProperty, ForumBodyStyleScope> values;

  bool overrides(ForumBodyStyleProperty property, ForumBodyTextRole role) =>
      switch (values[property] ?? ForumBodyStyleScope.asDefault) {
        ForumBodyStyleScope.asDefault => false,
        ForumBodyStyleScope.forceBody => role == ForumBodyTextRole.body,
        ForumBodyStyleScope.forceAll => true,
      };
}

/// Inputs are unscaled; one renderer TextScaler owns the final scaling.
/// The resolved Host font family is always used, except semantic code fonts.
final class ForumBodyReaderStyle {
  static const ForumBodyRoleFontScales defaultRoleFontScales = (
    heading: 1,
    quote: 1,
    code: 1,
  );

  ForumBodyReaderStyle({
    required this.textStyle,
    required this.fontRevision,
    required this.linkColor,
    this.textAlign = TextAlign.start,
    this.textDirection = TextDirection.ltr,
    this.paragraphBefore = 0,
    this.paragraphAfter = 10,
    this.firstLineIndent = ForumBodyLength.zero,
    this.compressBlankLines = false,
    this.removeSourceIndent = false,
    this.roleFontScales = defaultRoleFontScales,
    this.theme,
    ForumBodyStylePolicy? policy,
  }) : policy = policy ?? ForumBodyStylePolicy() {
    final size = textStyle.fontSize;
    if (size == null ||
        !size.isFinite ||
        size <= 0 ||
        size > 512 ||
        !(textStyle.height ?? 1).isFinite ||
        (textStyle.height ?? 1) < 0 ||
        (textStyle.height ?? 1) > 64 ||
        !(textStyle.letterSpacing ?? 0).isFinite ||
        !(textStyle.wordSpacing ?? 0).isFinite ||
        !paragraphBefore.isFinite ||
        paragraphBefore < 0 ||
        !paragraphAfter.isFinite ||
        paragraphAfter < 0 ||
        !firstLineIndent.value.isFinite ||
        firstLineIndent.unit == ForumBodyLengthUnit.auto ||
        !_validScale(roleFontScales.heading) ||
        !_validScale(roleFontScales.quote) ||
        !_validScale(roleFontScales.code)) {
      throw ArgumentError('Invalid body typography');
    }
  }
  static bool _validScale(double scale) =>
      scale.isFinite && scale >= .75 && scale <= 1.5;

  final TextStyle textStyle;
  final String fontRevision;
  final Color linkColor;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final double paragraphBefore;
  final double paragraphAfter;
  final ForumBodyLength firstLineIndent;
  final bool compressBlankLines;
  final bool removeSourceIndent;
  final ForumBodyRoleFontScales roleFontScales;
  final ForumBodyStylePolicy policy;

  /// The same immutable semantic palette used by the HTML renderer.
  final ForumHtmlThemeContext? theme;
}

final class ForumBodyResolvedStyle {
  const ForumBodyResolvedStyle({
    required this.textStyle,
    required this.role,
    required this.textAlign,
    required this.textDirection,
    this.whiteSpace = ForumBodyWhiteSpace.normal,
    this.rubyPosition = ForumBodyRubyPosition.alternate,
    this.textEmphasis = const ForumBodyTextEmphasis(),
    this.baselineAlignment = ForumBodyBaselineAlignment.baseline,
    this.baselineShift = const ForumBodyBaselineShift.none(),
    this.indent = ForumBodyLength.zero,
    this.margin = const ForumBodyInsets(),
    this.padding = const ForumBodyInsets(),
    this.box = const ForumBodyBoxStyle(),
    this.floatSide = ForumBodyFloatSide.none,
    this.clear = ForumBodyClear.none,
    this.lineHeight = const ForumBodyLineHeight.natural(),
    this.hidden = false,
    this.strong = false,
    this.ownDecoration = TextDecoration.none,
    this.ownBackground,
    this.linkTarget,
    this.linkPath,
    this.boxBackground,
    this.display = ForumBodyDisplay.inline,
    this.visibilityHidden = false,
    this.indentFromReader = true,
    this.alignmentFromReader = true,
    this.quoteDecoration,
    this.insideQuoteContainer = false,
    this.listStyle = const ForumBodyListStyle(),
  });
  final TextStyle textStyle;
  final ForumBodyTextRole role;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final ForumBodyWhiteSpace whiteSpace;
  final ForumBodyRubyPosition rubyPosition;
  final ForumBodyTextEmphasis textEmphasis;
  final ForumBodyBaselineAlignment baselineAlignment;
  final ForumBodyBaselineShift baselineShift;
  final ForumBodyLength indent;
  final ForumBodyInsets margin;
  final ForumBodyInsets padding;
  final ForumBodyBoxStyle box;
  final ForumBodyFloatSide floatSide;
  final ForumBodyClear clear;
  final ForumBodyLineHeight lineHeight;
  final bool hidden;
  final bool strong;
  final TextDecoration ownDecoration;
  final Color? ownBackground;
  final String? linkTarget;

  /// Original anchor occurrence, shared by its styled descendants.
  final String? linkPath;
  final Color? boxBackground;
  final ForumBodyDisplay display;
  final bool visibilityHidden;
  final bool indentFromReader;
  final bool alignmentFromReader;
  final ForumBodyQuoteDecoration? quoteDecoration;
  final bool insideQuoteContainer;
  final ForumBodyListStyle listStyle;

  ForumBodyResolvedStyle withTextEmphasis(ForumBodyTextEmphasis value) =>
      _copy(textStyle, value);

  ForumBodyResolvedStyle withTextStyle(TextStyle value) =>
      _copy(value, textEmphasis);

  ForumBodyResolvedStyle withReaderIndent(ForumBodyLength value) =>
      _copy(textStyle, textEmphasis, readerIndent: value);

  ForumBodyResolvedStyle _copy(
    TextStyle nextText,
    ForumBodyTextEmphasis value, {
    ForumBodyLength? readerIndent,
  }) => readerIndent == null && value == textEmphasis && nextText == textStyle
      ? this
      : ForumBodyResolvedStyle(
          textStyle: nextText,
          role: role,
          textAlign: textAlign,
          textDirection: textDirection,
          whiteSpace: whiteSpace,
          rubyPosition: rubyPosition,
          textEmphasis: value,
          baselineAlignment: baselineAlignment,
          baselineShift: baselineShift,
          indent: readerIndent ?? indent,
          margin: margin,
          padding: padding,
          box: box,
          floatSide: floatSide,
          clear: clear,
          lineHeight: lineHeight,
          hidden: hidden,
          strong: strong,
          ownDecoration: ownDecoration,
          ownBackground: ownBackground,
          linkTarget: linkTarget,
          linkPath: linkPath,
          boxBackground: boxBackground,
          display: display,
          visibilityHidden: visibilityHidden,
          indentFromReader: readerIndent != null || indentFromReader,
          alignmentFromReader: alignmentFromReader,
          quoteDecoration: quoteDecoration,
          insideQuoteContainer: insideQuoteContainer,
          listStyle: listStyle,
        );
}

/// CSS numeric line-height inherits as a factor; length/percentage computes
/// to an absolute value before inheritance, even when a child changes size.
final class ForumBodyLineHeight {
  const ForumBodyLineHeight.natural() : factor = null, pixels = null;
  const ForumBodyLineHeight.factor(this.factor) : pixels = null;
  const ForumBodyLineHeight.pixels(this.pixels) : factor = null;
  final double? factor;
  final double? pixels;

  double textStyleHeight(double fontSize) =>
      factor ?? (pixels == null ? kTextHeightNone : pixels! / fontSize);
}

final class ForumBodyStyleIssue {
  const ForumBodyStyleIssue(this.path, this.property, this.value);
  final String path;
  final String property;
  final String value;
}

final class ForumBodyStyleResult {
  ForumBodyStyleResult({
    required this.identity,
    required this.fontRevision,
    required this.root,
    required this.resolverRevision,
    required Map<String, ForumBodyResolvedStyle> byPath,
    required Iterable<ForumBodyStyleIssue> issues,
  }) : byPath = Map.unmodifiable(byPath),
       issues = List.unmodifiable(issues);
  final ForumBodyResolvedStyle root;
  final ForumBodyIdentity identity;
  final String fontRevision;
  final int resolverRevision;
  final Map<String, ForumBodyResolvedStyle> byPath;
  final List<ForumBodyStyleIssue> issues;
}

import 'package:flutter/painting.dart';

import 'forum_body_length.dart';
import 'forum_body_box_style.dart';
import 'forum_body_ruby_position.dart';
import 'forum_body_text_emphasis.dart';
import 'forum_body_quote_decoration.dart';
import '../html_rendering/theme/forum_html_theme_context.dart';
import '../document/forum_body_document.dart';

export 'forum_body_ruby_position.dart';
export 'forum_body_text_emphasis.dart';
export 'forum_body_quote_decoration.dart';

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

enum ForumBodyWhiteSpace { normal, pre, preWrap, preLine }

enum ForumBodyDisplay {
  inline,
  block,
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
  ForumBodyReaderStyle({
    required this.textStyle,
    required this.fontRevision,
    required this.linkColor,
    this.textAlign = TextAlign.start,
    this.textDirection = TextDirection.ltr,
    this.paragraphBefore = 0,
    this.paragraphAfter = 10,
    this.firstLineIndent = ForumBodyLength.zero,
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
        firstLineIndent.unit == ForumBodyLengthUnit.auto) {
      throw ArgumentError('Invalid body typography');
    }
  }
  final TextStyle textStyle;
  final String fontRevision;
  final Color linkColor;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final double paragraphBefore;
  final double paragraphAfter;
  final ForumBodyLength firstLineIndent;
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
    this.indent = ForumBodyLength.zero,
    this.margin = const ForumBodyInsets(),
    this.padding = const ForumBodyInsets(),
    this.box = const ForumBodyBoxStyle(),
    this.lineHeight = const ForumBodyLineHeight.natural(),
    this.hidden = false,
    this.strong = false,
    this.ownDecoration = TextDecoration.none,
    this.ownBackground,
    this.linkTarget,
    this.boxBackground,
    this.display = ForumBodyDisplay.inline,
    this.visibilityHidden = false,
    this.indentFromReader = true,
    this.alignmentFromReader = true,
    this.quoteDecoration,
    this.insideQuoteContainer = false,
  });
  final TextStyle textStyle;
  final ForumBodyTextRole role;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final ForumBodyWhiteSpace whiteSpace;
  final ForumBodyRubyPosition rubyPosition;
  final ForumBodyTextEmphasis textEmphasis;
  final ForumBodyLength indent;
  final ForumBodyInsets margin;
  final ForumBodyInsets padding;
  final ForumBodyBoxStyle box;
  final ForumBodyLineHeight lineHeight;
  final bool hidden;
  final bool strong;
  final TextDecoration ownDecoration;
  final Color? ownBackground;
  final String? linkTarget;
  final Color? boxBackground;
  final ForumBodyDisplay display;
  final bool visibilityHidden;
  final bool indentFromReader;
  final bool alignmentFromReader;
  final ForumBodyQuoteDecoration? quoteDecoration;
  final bool insideQuoteContainer;

  ForumBodyResolvedStyle withTextEmphasis(ForumBodyTextEmphasis value) =>
      value == textEmphasis
      ? this
      : ForumBodyResolvedStyle(
          textStyle: textStyle,
          role: role,
          textAlign: textAlign,
          textDirection: textDirection,
          whiteSpace: whiteSpace,
          rubyPosition: rubyPosition,
          textEmphasis: value,
          indent: indent,
          margin: margin,
          padding: padding,
          box: box,
          lineHeight: lineHeight,
          hidden: hidden,
          strong: strong,
          ownDecoration: ownDecoration,
          ownBackground: ownBackground,
          linkTarget: linkTarget,
          boxBackground: boxBackground,
          display: display,
          visibilityHidden: visibilityHidden,
          indentFromReader: indentFromReader,
          alignmentFromReader: alignmentFromReader,
          quoteDecoration: quoteDecoration,
          insideQuoteContainer: insideQuoteContainer,
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

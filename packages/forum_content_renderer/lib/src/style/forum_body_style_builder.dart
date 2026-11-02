import 'package:flutter/painting.dart';

import '../document/forum_body_document.dart';
import '../helpers/discuz_font_size_policy.dart';
import '../html_rendering/theme/css_author_color_parser.dart';
import 'forum_body_length.dart';
import 'forum_body_language.dart';
import 'forum_body_box_resolver.dart';
import 'forum_body_style_options.dart';
import 'forum_body_text_emphasis_resolver.dart';

const forumBodyStyleRevision = 13;
ForumBodyLength forumBodyReaderIndent(
  ForumBodyReaderStyle reader,
  double size,
) => reader.firstLineIndent.unit == ForumBodyLengthUnit.em
    ? reader.firstLineIndent
    : reader.firstLineIndent.computed(
        fontSize: size,
        rootFontSize: reader.textStyle.fontSize!,
      );
ForumBodyLineHeight forumBodyReaderHeight(ForumBodyReaderStyle reader) {
  final height = reader.textStyle.height;
  return height == null || height == kTextHeightNone
      ? const ForumBodyLineHeight.natural()
      : ForumBodyLineHeight.factor(height);
}

final class ForumBodyStyleBuilder {
  ForumBodyStyleBuilder(this.reader, {this.applyPolicy = true});
  final ForumBodyReaderStyle reader;
  final bool applyPolicy;
  final issues = <ForumBodyStyleIssue>[];
  List<ForumBodyStyleIssue> takeIssues() {
    if (issues.isEmpty) return const [];
    final result = List<ForumBodyStyleIssue>.of(issues);
    issues.clear();
    return result;
  }

  void clear() {
    issues.clear();
    _colors.clear();
  }

  final _colors =
      <String, ({Color? color, bool unsupported, bool transparent})>{};
  final _colorParser = CsslibAuthorColorParser();
  static const _handled = {
    'font-size',
    'font-family',
    'font-weight',
    'font-style',
    'line-height',
    'letter-spacing',
    'word-spacing',
    'text-decoration',
    'text-decoration-line',
    'text-emphasis',
    'text-emphasis-style',
    'text-emphasis-color',
    'text-emphasis-position',
    'color',
    'background',
    'background-color',
    'text-align',
    'direction',
    'white-space',
    'ruby-position',
    'text-indent',
    'display',
    'visibility',
    'width',
    'min-width',
    'max-width',
    'box-sizing',
    'margin',
    'margin-top',
    'margin-right',
    'margin-bottom',
    'margin-left',
    'padding',
    'padding-top',
    'padding-right',
    'padding-bottom',
    'padding-left',
  };

  ForumBodyResolvedStyle resolve(
    ForumBodyElement node,
    ForumBodyResolvedStyle parent, {
    ForumBodyElementKind? parentKind,
  }) {
    final role = _role(node.kind, parent.role);
    final declarations = node.style;
    if (!declarations.isValid) {
      _issue(node, 'style', 'malformed');
    }
    for (final declaration in declarations.declarations) {
      if (!_handled.contains(declaration.property)) {
        _issue(node, declaration.property, declaration.value);
      }
    }
    final baseSize = reader.textStyle.fontSize!;
    var style = parent.textStyle;
    var size = style.fontSize ?? baseSize;
    final heading = RegExp(r'^h([1-6])$').firstMatch(node.tag);
    if (heading != null) {
      const factors = [2.0, 1.5, 1.25, 1.0, 0.875, 0.75];
      size *= factors[int.parse(heading[1]!) - 1];
    } else if (node.tag == 'small') {
      size *= .85;
    } else if (node.kind == ForumBodyElementKind.editStatus) {
      size = baseSize * .88;
    } else if (node.kind == ForumBodyElementKind.rubyAnnotationContainer ||
        (node.kind == ForumBodyElementKind.rubyText &&
            parentKind != ForumBodyElementKind.rubyAnnotationContainer)) {
      // The level owns the UA half-size. A real RT inside RTC inherits it,
      // as does anonymous annotation text; neither is reduced a second time.
      size *= .5;
    }
    String? value(String property) =>
        declarations.value(property)?.toLowerCase();
    final authorSize = value('font-size');
    if (authorSize != null) {
      size =
          _fontSize(node, authorSize, parent.textStyle.fontSize ?? baseSize) ??
          size;
    } else if (node.tag == 'font' && node.attributes['size'] != null) {
      size =
          DiscuzFontSizePolicy.fontSizeForBase(
            node.attributes['size'],
            baseFontSize: baseSize,
          ) ??
          size;
    }
    if (_force(ForumBodyStyleProperty.fontSize, role)) {
      size = baseSize;
    }

    final strong =
        parent.strong ||
        node.tag == 'b' ||
        node.tag == 'strong' ||
        role == ForumBodyTextRole.heading;
    final parentWeight = style.fontWeight ?? FontWeight.w400;
    var weight = heading != null
        ? FontWeight.w700
        : node.tag == 'b' || node.tag == 'strong'
        ? _weight('bolder', parentWeight)!
        : parentWeight;
    final rawWeight = value('font-weight');
    if (rawWeight != null) {
      weight = rawWeight == 'inherit' || rawWeight == 'unset'
          ? parentWeight
          : _weight(rawWeight, parentWeight) ??
                _unsupported(node, 'font-weight', rawWeight, weight);
    }
    if (_force(ForumBodyStyleProperty.fontWeight, role)) {
      final baseWeight = reader.textStyle.fontWeight ?? FontWeight.w400;
      // A fixed 700 would erase emphasis when the reader also requests 700.
      weight = strong ? _weight('bolder', baseWeight)! : baseWeight;
    }
    var italic =
        node.kind == ForumBodyElementKind.editStatus ||
            node.tag == 'i' ||
            node.tag == 'em'
        ? FontStyle.italic
        : style.fontStyle;
    final rawItalic = value('font-style');
    if (rawItalic != null) {
      italic = switch (rawItalic) {
        'normal' || 'initial' => FontStyle.normal,
        'italic' || 'oblique' => FontStyle.italic,
        'inherit' || 'unset' => parent.textStyle.fontStyle,
        _ => _unsupported(node, 'font-style', rawItalic, italic),
      };
    }

    var height =
        node.kind == ForumBodyElementKind.rubyText ||
            node.kind == ForumBodyElementKind.rubyAnnotationContainer
        ? const ForumBodyLineHeight.factor(1)
        : parent.lineHeight;
    final rawHeight = value('line-height');
    if (rawHeight != null) {
      height = _lineHeight(
        node,
        rawHeight,
        size,
        height,
        inherited: parent.lineHeight,
      );
    }
    if (_force(ForumBodyStyleProperty.lineHeight, role)) {
      height = forumBodyReaderHeight(reader);
    }

    var ownDecoration = TextDecoration.none;
    if (node.tag == 'a' || node.tag == 'u') {
      ownDecoration = TextDecoration.underline;
    }
    if (const {'s', 'strike', 'del'}.contains(node.tag)) {
      ownDecoration = TextDecoration.lineThrough;
    }
    final rawDecoration = declarations
        .effectiveDeclaration({'text-decoration-line', 'text-decoration'})
        ?.value
        .toLowerCase();
    if (rawDecoration != null) {
      final parts = rawDecoration.split(RegExp(r'\s+'));
      if (parts.any(
        (part) => !const {
          'none',
          'underline',
          'line-through',
          'overline',
          'inherit',
          'initial',
          'unset',
        }.contains(part),
      )) {
        _issue(node, 'text-decoration', rawDecoration);
      } else {
        ownDecoration = parts.contains('inherit')
            ? parent.ownDecoration
            : TextDecoration.combine([
                if (parts.contains('underline')) TextDecoration.underline,
                if (parts.contains('line-through')) TextDecoration.lineThrough,
                if (parts.contains('overline')) TextDecoration.overline,
              ]);
      }
    }
    // Decorations drawn by an ancestor continue through nested inline text.
    final decoration = TextDecoration.combine([
      style.decoration ?? TextDecoration.none,
      ownDecoration,
    ]);

    final linkTarget = node.tag == 'a'
        ? node.attributes['href']
        : parent.linkTarget;
    var foreground = node.tag == 'a' ? reader.linkColor : style.color;
    if (node.kind == ForumBodyElementKind.editStatus) {
      foreground = (reader.textStyle.color ?? foreground)?.withValues(
        alpha: .62,
      );
    }
    final rawForeground =
        value('color') ??
        (node.tag == 'font' ? node.attributes['color'] : null);
    if (rawForeground != null &&
        rawForeground != 'inherit' &&
        rawForeground != 'currentcolor' &&
        rawForeground != 'unset') {
      foreground = rawForeground == 'initial'
          ? reader.textStyle.color
          : _color(node, 'color', rawForeground, foreground);
    } else if (rawForeground != null) {
      foreground = parent.textStyle.color;
    }
    if (_force(ForumBodyStyleProperty.foreground, role) && linkTarget == null) {
      foreground = reader.textStyle.color;
    }
    Color? boxBackground;
    Color? ownBackground;
    var inlineBackground = style.backgroundColor;
    final rawBackground = declarations
        .effectiveDeclaration({'background-color', 'background'})
        ?.value
        .toLowerCase();
    if (rawBackground != null) {
      final color = switch (rawBackground) {
        'inherit' => parent.ownBackground ?? const Color(0x00000000),
        'initial' || 'unset' => const Color(0x00000000),
        'currentcolor' => foreground,
        _ => _color(
          node,
          'background-color',
          rawBackground,
          const Color(0x00000000),
        ),
      };
      ownBackground = color;
      // RB/RT own inline text contexts. Highlights must reach native text
      // paint rather than remaining on metadata for an unpainted block box.
      if (node.kind == ForumBodyElementKind.inline ||
          node.kind == ForumBodyElementKind.rubyBase ||
          node.kind == ForumBodyElementKind.rubyText) {
        inlineBackground = color == null
            ? inlineBackground
            : Color.alphaBlend(
                color,
                inlineBackground ?? const Color(0x00000000),
              );
      } else {
        boxBackground = color;
      }
    }
    if (_force(ForumBodyStyleProperty.background, role)) {
      inlineBackground =
          reader.textStyle.backgroundColor ?? const Color(0x00000000);
      boxBackground = null;
      ownBackground = reader.textStyle.backgroundColor;
    }
    // Start from the Host font so a null system family can leave a code block.
    // Inherited author values are supplied explicitly, never via copyWith(null).
    style = reader.textStyle.copyWith(
      locale: resolveForumBodyLanguage(
        attributes: node.attributes,
        inherited: parent.textStyle.locale,
        onUnsupported: (value) => _issue(node, 'lang', value),
      ),
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic,
      height: height.textStyleHeight(size),
      decoration: decoration,
      color: foreground,
      backgroundColor: inlineBackground,
      fontFamily: role == ForumBodyTextRole.code
          ? 'monospace'
          : reader.textStyle.fontFamily,
      letterSpacing: _spacing(
        node,
        'letter-spacing',
        size,
        parent.textStyle.letterSpacing ?? 0,
        ForumBodyStyleProperty.letterSpacing,
        role,
      ),
      wordSpacing: _spacing(
        node,
        'word-spacing',
        size,
        parent.textStyle.wordSpacing ?? 0,
        ForumBodyStyleProperty.wordSpacing,
        role,
      ),
    );

    final rawAlign =
        value('text-align') ?? node.attributes['align']?.toLowerCase();
    var alignment = parent.textAlign;
    var alignmentFromReader = parent.alignmentFromReader;
    if (heading != null && alignmentFromReader) {
      alignment = TextAlign.start;
      alignmentFromReader = false;
    }
    if (rawAlign != null) {
      if (rawAlign == 'inherit' || rawAlign == 'unset') {
        alignment = parent.textAlign;
        alignmentFromReader = parent.alignmentFromReader;
      } else {
        final parsed = _alignment(rawAlign);
        if (parsed == null) {
          _issue(node, 'text-align', rawAlign);
        } else {
          alignment = parsed;
          alignmentFromReader = false;
        }
      }
    }
    if (_force(ForumBodyStyleProperty.textAlign, role)) {
      alignment = reader.textAlign;
      alignmentFromReader = true;
    }
    final rawDirection =
        value('direction') ?? node.attributes['dir']?.toLowerCase();
    var direction = parent.textDirection;
    if (rawDirection != null) {
      direction = switch (rawDirection) {
        'ltr' => TextDirection.ltr,
        'rtl' => TextDirection.rtl,
        'initial' => TextDirection.ltr,
        'inherit' || 'unset' => direction,
        _ => _unsupported(node, 'direction', rawDirection, direction),
      };
    }
    var whiteSpace = role == ForumBodyTextRole.code
        ? ForumBodyWhiteSpace.preWrap
        : parent.whiteSpace;
    final rawWhiteSpace = value('white-space');
    if (rawWhiteSpace != null) {
      whiteSpace = switch (rawWhiteSpace) {
        'normal' || 'initial' => ForumBodyWhiteSpace.normal,
        'pre' => ForumBodyWhiteSpace.pre,
        'pre-wrap' => ForumBodyWhiteSpace.preWrap,
        'pre-line' => ForumBodyWhiteSpace.preLine,
        'inherit' || 'unset' => whiteSpace,
        _ => _unsupported(node, 'white-space', rawWhiteSpace, whiteSpace),
      };
    }
    var indent = parent.indentFromReader && role != ForumBodyTextRole.body
        ? ForumBodyLength.zero
        : parent.indent;
    var indentFromReader = parent.indentFromReader;
    final rawIndent = value('text-indent');
    if (rawIndent != null && rawIndent != 'inherit' && rawIndent != 'unset') {
      final length = rawIndent == 'initial'
          ? ForumBodyLength.zero
          : ForumBodyLength.tryParse(rawIndent);
      final computed = length?.unit == ForumBodyLengthUnit.auto
          ? null
          : length?.computed(fontSize: size, rootFontSize: baseSize);
      indent = computed == null || !computed.value.isFinite
          ? _unsupported(node, 'text-indent', rawIndent, indent)
          : computed;
      if (computed != null && computed.value.isFinite) {
        indentFromReader = false;
      }
    }
    if (_force(ForumBodyStyleProperty.textIndent, role)) {
      indent = forumBodyReaderIndent(reader, size);
      indentFromReader = true;
    }
    var display = switch (node.kind) {
      ForumBodyElementKind.inline ||
      ForumBodyElementKind.hardBreak ||
      ForumBodyElementKind.image ||
      ForumBodyElementKind.ruby ||
      ForumBodyElementKind.rubyBase ||
      ForumBodyElementKind.rubyText ||
      ForumBodyElementKind.rubyAnnotationContainer ||
      ForumBodyElementKind.rubyFallback ||
      ForumBodyElementKind.unknown => ForumBodyDisplay.inline,
      ForumBodyElementKind.table => ForumBodyDisplay.table,
      ForumBodyElementKind.tableRow => ForumBodyDisplay.tableRow,
      ForumBodyElementKind.tableCell => ForumBodyDisplay.tableCell,
      ForumBodyElementKind.media => ForumBodyDisplay.inlineBlock,
      _ => ForumBodyDisplay.block,
    };
    if (node.tag == 'code') {
      display = ForumBodyDisplay.inline;
    }
    final rawDisplay = value('display');
    if (rawDisplay != null) {
      display = switch (rawDisplay) {
        'inline' => ForumBodyDisplay.inline,
        'block' => ForumBodyDisplay.block,
        'inline-block' => ForumBodyDisplay.inlineBlock,
        'none' => ForumBodyDisplay.none,
        'table' => ForumBodyDisplay.table,
        'table-row' => ForumBodyDisplay.tableRow,
        'table-cell' => ForumBodyDisplay.tableCell,
        'initial' || 'unset' => ForumBodyDisplay.inline,
        'inherit' => parent.display,
        _ => _unsupported(node, 'display', rawDisplay, display),
      };
    }
    // Native folds own expansion; their web-only display:none is mechanical.
    if (node.kind == ForumBodyElementKind.collapseContent &&
        display == ForumBodyDisplay.none) {
      display = ForumBodyDisplay.block;
    }
    var visibilityHidden = parent.visibilityHidden;
    final rawVisibility = value('visibility');
    if (rawVisibility != null) {
      visibilityHidden = switch (rawVisibility) {
        'visible' || 'initial' => false,
        'hidden' || 'collapse' => true,
        'inherit' || 'unset' => visibilityHidden,
        _ => _unsupported(node, 'visibility', rawVisibility, visibilityHidden),
      };
    }
    final rawRubyPosition = value('ruby-position');
    final ForumBodyRubyPosition rubyPosition = switch (rawRubyPosition) {
      null || 'inherit' || 'unset' => parent.rubyPosition,
      'initial' => ForumBodyRubyPosition.alternate,
      _ =>
        ForumBodyRubyPosition.tryParse(rawRubyPosition) ??
            _unsupported(
              node,
              'ruby-position',
              rawRubyPosition,
              parent.rubyPosition,
            ),
    };
    return ForumBodyResolvedStyle(
      textStyle: style,
      role: role,
      textAlign: alignment,
      textDirection: direction,
      whiteSpace: whiteSpace,
      rubyPosition: rubyPosition,
      textEmphasis: resolveForumBodyTextEmphasis(
        declarations: declarations,
        inherited: parent.textEmphasis,
        parseColor: (raw) =>
            _colors.putIfAbsent(raw, () => _colorParser.parseValue(raw)),
        onUnsupported: (property, value) => _issue(node, property, value),
      ),
      indent: indent,
      margin: _insets(node, 'margin', size, role, parent.margin),
      padding: _insets(node, 'padding', size, role, parent.padding),
      box: const ForumBodyBoxResolver().resolveBoxStyle(
        node: node,
        parent: parent.box,
        fontSize: size,
        rootFontSize: reader.textStyle.fontSize!,
        onUnsupported: (property, value) => _issue(node, property, value),
      ),
      lineHeight: height,
      hidden:
          parent.hidden ||
          node.kind == ForumBodyElementKind.hidden ||
          (node.attributes['class']
                  ?.split(RegExp(r'\s+'))
                  .contains('showcollapse_gather') ??
              false) ||
          display == ForumBodyDisplay.none ||
          node.attributes.containsKey('hidden'),
      strong: strong,
      ownDecoration: ownDecoration,
      ownBackground: ownBackground,
      linkTarget: linkTarget,
      boxBackground: boxBackground,
      indentFromReader: indentFromReader,
      alignmentFromReader: alignmentFromReader,
      display: display,
      visibilityHidden: visibilityHidden,
    );
  }

  bool _force(ForumBodyStyleProperty property, ForumBodyTextRole role) =>
      applyPolicy && reader.policy.overrides(property, role);

  void _issue(ForumBodyElement node, String property, String value) =>
      issues.add(ForumBodyStyleIssue(node.path, property, value));
  T _unsupported<T>(
    ForumBodyElement node,
    String property,
    String value,
    T fallback,
  ) {
    _issue(node, property, value);
    return fallback;
  }

  ForumBodyTextRole _role(
    ForumBodyElementKind kind,
    ForumBodyTextRole parent,
  ) => switch (kind) {
    ForumBodyElementKind.heading => ForumBodyTextRole.heading,
    ForumBodyElementKind.quote => ForumBodyTextRole.quote,
    ForumBodyElementKind.code => ForumBodyTextRole.code,
    ForumBodyElementKind.list ||
    ForumBodyElementKind.listItem => ForumBodyTextRole.list,
    ForumBodyElementKind.table ||
    ForumBodyElementKind.tableCell => ForumBodyTextRole.table,
    ForumBodyElementKind.rubyText ||
    ForumBodyElementKind.rubyAnnotationContainer => ForumBodyTextRole.ruby,
    ForumBodyElementKind.editStatus ||
    ForumBodyElementKind.locked => ForumBodyTextRole.notice,
    _ => parent,
  };

  double? _fontSize(ForumBodyElement node, String value, double parent) {
    if (value == 'inherit' || value == 'unset') return parent;
    if (value == 'initial') return reader.textStyle.fontSize;
    final factor = const {
      'xx-small': .6,
      'x-small': .75,
      'small': .89,
      'medium': 1.0,
      'large': 1.2,
      'x-large': 1.5,
      'xx-large': 2.0,
      'xxx-large': 3.0,
    }[value];
    final length = ForumBodyLength.tryParse(value);
    final size = factor != null
        ? reader.textStyle.fontSize! * factor
        : value == 'larger'
        ? parent * 1.2
        : value == 'smaller'
        ? parent / 1.2
        : length == null || length.unit == ForumBodyLengthUnit.auto
        ? null
        : length.resolve(
            fontSize: parent,
            rootFontSize: reader.textStyle.fontSize!,
            reference: parent,
          );
    if (size == null || size <= 0 || size > 512) {
      _issue(node, 'font-size', value);
      return null;
    }
    return size;
  }

  FontWeight? _weight(String value, FontWeight parent) {
    if (value == 'normal' || value == 'initial') return FontWeight.w400;
    if (value == 'bold') return FontWeight.w700;
    if (value == 'bolder') {
      return parent.value < 400
          ? FontWeight.w400
          : parent.value < 600
          ? FontWeight.w700
          : FontWeight.w900;
    }
    if (value == 'lighter') {
      return parent.value <= 500
          ? FontWeight.w100
          : parent.value <= 700
          ? FontWeight.w400
          : FontWeight.w700;
    }
    final number = int.tryParse(value);
    if (number == null || number < 100 || number > 900 || number % 100 != 0) {
      return null;
    }
    return FontWeight.values[number ~/ 100 - 1];
  }

  ForumBodyLineHeight _lineHeight(
    ForumBodyElement node,
    String raw,
    double size,
    ForumBodyLineHeight fallback, {
    required ForumBodyLineHeight inherited,
  }) {
    if (raw == 'inherit' || raw == 'unset') return inherited;
    if (raw == 'normal' || raw == 'initial') {
      return const ForumBodyLineHeight.natural();
    }
    final factor = double.tryParse(raw);
    if (factor != null && factor.isFinite && factor > 0 && factor <= 64) {
      return ForumBodyLineHeight.factor(factor);
    }
    final length = ForumBodyLength.tryParse(raw);
    if (length != null && length.unit != ForumBodyLengthUnit.auto) {
      final pixels = length.resolve(
        fontSize: size,
        rootFontSize: reader.textStyle.fontSize!,
        reference: size,
      );
      if (pixels > 0 && pixels <= 32768) {
        return ForumBodyLineHeight.pixels(pixels);
      }
    }
    return _unsupported(node, 'line-height', raw, fallback);
  }

  double _spacing(
    ForumBodyElement node,
    String property,
    double size,
    double parent,
    ForumBodyStyleProperty setting,
    ForumBodyTextRole role,
  ) {
    if (_force(setting, role)) {
      return setting == ForumBodyStyleProperty.letterSpacing
          ? reader.textStyle.letterSpacing ?? 0
          : reader.textStyle.wordSpacing ?? 0;
    }
    final raw = node.style.value(property)?.toLowerCase();
    if (raw == null || raw == 'inherit' || raw == 'unset') return parent;
    if (raw == 'normal' || raw == 'initial') return 0;
    final length = ForumBodyLength.tryParse(raw);
    if (length == null ||
        length.unit == ForumBodyLengthUnit.auto ||
        length.unit == ForumBodyLengthUnit.percent) {
      return _unsupported(node, property, raw, parent);
    }
    final spacing = length.resolve(
      fontSize: size,
      rootFontSize: reader.textStyle.fontSize!,
      reference: 0,
    );
    return spacing.abs() > 512
        ? _unsupported(node, property, raw, parent)
        : spacing;
  }

  TextAlign? _alignment(String raw) => switch (raw) {
    'start' || 'initial' => TextAlign.start,
    'end' => TextAlign.end,
    'left' => TextAlign.left,
    'right' => TextAlign.right,
    'center' => TextAlign.center,
    'justify' => TextAlign.justify,
    _ => null,
  };

  Color? _color(
    ForumBodyElement node,
    String property,
    String raw,
    Color? parent,
  ) {
    final parsed = _colors.putIfAbsent(raw, () => _colorParser.parseValue(raw));
    if (parsed.unsupported) return _unsupported(node, property, raw, parent);
    return parsed.transparent
        ? const Color(0x00000000)
        : parsed.color ?? parent;
  }

  ForumBodyInsets _insets(
    ForumBodyElement node,
    String property,
    double size,
    ForumBodyTextRole role,
    ForumBodyInsets parent,
  ) {
    final isParagraph =
        node.kind == ForumBodyElementKind.paragraph ||
        node.kind == ForumBodyElementKind.heading;
    final defaults = property == 'margin' && isParagraph
        ? ForumBodyInsets(
            top: ForumBodyLength(reader.paragraphBefore),
            bottom: ForumBodyLength(reader.paragraphAfter),
          )
        : property == 'padding' && node.kind == ForumBodyElementKind.editStatus
        ? const ForumBodyInsets(bottom: ForumBodyLength(8))
        : const ForumBodyInsets();
    final resolved = const ForumBodyBoxResolver().resolve(
      node: node,
      property: property,
      defaults: defaults,
      parent: parent,
      fontSize: size,
      rootFontSize: reader.textStyle.fontSize!,
      onUnsupported: (property, value) => _issue(node, property, value),
    );
    return property == 'margin' &&
            isParagraph &&
            _force(ForumBodyStyleProperty.paragraphSpacing, role)
        ? ForumBodyInsets(
            top: defaults.top,
            bottom: defaults.bottom,
            left: resolved.left,
            right: resolved.right,
          )
        : resolved;
  }
}

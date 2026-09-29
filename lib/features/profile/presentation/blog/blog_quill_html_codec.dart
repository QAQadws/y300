import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_size_mapping.dart';
import 'package:y300/features/profile/presentation/blog/blog_body_text_codec.dart';

const blogQuillImageEmbedType = 'blogImage';
const blogQuillHtmlEmbedType = 'blogHtml';

/// New images and the home editor's smileys are HTML images, not forum AIDs.
Embeddable blogQuillImageEmbed(String src, {String? originalHtml}) {
  if (!_isImageUrl(src)) throw ArgumentError.value(src, 'src');
  return Embeddable(blogQuillImageEmbedType, <String, String>{
    'src': src,
    'html': originalHtml ?? '<img src="${_escapeAttribute(src)}">',
  });
}

Map<String, String>? blogQuillImagePayload(Object? data) {
  final payload = _embedPayload(data, blogQuillImageEmbedType);
  if (payload is! Map) return null;
  final src = payload['src'];
  final source = payload['html'];
  if (src is! String || source is! String) return null;
  return {'src': src, 'html': source};
}

String? blogQuillHtmlSource(Object? data) {
  final payload = _embedPayload(data, blogQuillHtmlEmbedType);
  return payload is String ? payload : null;
}

Object? _embedPayload(Object? data, String type) {
  if (data is Embeddable) return data.type == type ? data.data : null;
  if (data is Map && data.containsKey(type)) return data[type];
  // EmbedBuilder receives the payload; a codec receives the complete embed.
  return data;
}

/// The editable HTML subset deliberately matches Discuz's ordinary-user tags.
/// Unknown markup is a preview embed, so editing nearby text cannot erase it.
/// Callers retain the original source until an actual document edit occurs.
class BlogQuillHtmlCodec {
  const BlogQuillHtmlCodec();

  Document decodeDocument(String source) =>
      Document.fromDelta(decodeDelta(source));

  Delta decodeDelta(String source) {
    final plain = BlogBodyTextCodec.decode(source);
    if (plain != null) return Delta()..insert('$plain\n');
    final decoder = _HtmlDeltaDecoder();
    for (final node in html.parseFragment(source).nodes) {
      decoder.append(node, const {}, const {}, 0);
    }
    return decoder.finish();
  }

  String encodeDocument(Document document) => encodeDelta(document.toDelta());

  String encodeDelta(Delta delta) {
    final lines = <_HtmlLine>[];
    var content = StringBuffer();
    for (final operation in delta.toList()) {
      if (!operation.isInsert) continue;
      final attributes = operation.attributes ?? const <String, dynamic>{};
      final data = operation.data;
      if (data is String) {
        final pieces = data.split('\n');
        for (var i = 0; i < pieces.length; i++) {
          if (pieces[i].isNotEmpty) {
            content.write(
              _wrapInline(BlogBodyTextCodec.encode(pieces[i]), attributes),
            );
          }
          if (i < pieces.length - 1) {
            lines.add(_HtmlLine(content.toString(), attributes));
            content = StringBuffer();
          }
        }
      } else if (blogQuillImagePayload(data) case final image?) {
        content.write(_wrapInline(image['html']!, attributes));
      } else if (blogQuillHtmlSource(data) case final source?) {
        content.write(source);
      } else {
        // Never silently drop a future embed introduced by another surface.
        throw const FormatException('Unsupported blog document embed');
      }
    }
    if (content.isNotEmpty) lines.add(_HtmlLine(content.toString(), const {}));
    if (lines.isEmpty || (lines.length == 1 && lines.single.html.isEmpty)) {
      return '';
    }
    final output = StringBuffer();
    String? activeList;
    for (final line in lines) {
      final list = switch (line.attributes[Attribute.list.key]) {
        'ordered' => 'ol',
        'bullet' => 'ul',
        _ => null,
      };
      if (list != activeList) {
        if (activeList != null) output.write('</$activeList>');
        if (list != null) output.write('<$list>');
        activeList = list;
      }
      var value = line.html.isEmpty ? '<br>' : line.html;
      if (list != null) {
        value = '<li>$value</li>';
      } else {
        final align = line.attributes[Attribute.align.key];
        final alignment =
            const {'left', 'center', 'right', 'justify'}.contains(align)
            ? ' align="$align"'
            : '';
        value = '<div$alignment>$value</div>';
      }
      if (line.attributes[Attribute.blockQuote.key] == true) {
        value = '<blockquote>$value</blockquote>';
      }
      output.write(value);
    }
    if (activeList != null) output.write('</$activeList>');
    return output.toString();
  }
}

String _wrapInline(String text, Map<String, dynamic> attributes) {
  var result = text;
  if (attributes[Attribute.underline.key] == true) result = '<u>$result</u>';
  if (attributes[Attribute.italic.key] == true) result = '<i>$result</i>';
  if (attributes[Attribute.bold.key] == true) result = '<b>$result</b>';
  final size = composerDiscuzSizeForQuillSize(attributes[Attribute.size.key]);
  final color = _normalizeColor(attributes[Attribute.color.key]);
  final font = attributes[Attribute.font.key];
  final fontAttributes = [
    if (size != null) 'size="$size"',
    if (color != null) 'color="$color"',
    if (font is String && font.isNotEmpty) 'face="${_escapeAttribute(font)}"',
  ];
  if (fontAttributes.isNotEmpty) {
    result = '<font ${fontAttributes.join(' ')}>$result</font>';
  }
  final link = attributes[Attribute.link.key];
  if (link is String && _isLinkUrl(link)) {
    result = '<a href="${_escapeAttribute(link)}">$result</a>';
  }
  return result;
}

class _HtmlLine {
  const _HtmlLine(this.html, this.attributes);
  final String html;
  final Map<String, dynamic> attributes;
}

class _HtmlDeltaDecoder {
  final Delta _delta = Delta();
  bool _hasLineContent = false;
  bool _afterBreak = false;
  int _revision = 0;

  void append(
    dom.Node node,
    Map<String, dynamic> inline,
    Map<String, dynamic> block,
    int depth,
  ) {
    if (node is dom.Text) {
      var text = node.text;
      if (_afterBreak) text = text.replaceFirst(RegExp(r'^\r?\n'), '');
      if (!_hasLineContent && text.trim().isEmpty && text.contains('\n')) {
        return;
      }
      text = text
          .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
          .replaceAll('\u00a0', ' ');
      if (text.isNotEmpty) {
        _delta.insert(text, inline.isEmpty ? null : inline);
        _revision++;
        _hasLineContent = true;
        _afterBreak = false;
      }
      return;
    }
    if (node is dom.Comment) {
      _insertRaw('<!--${node.data}-->');
      return;
    }
    if (node is! dom.Element) return;
    if (depth >= 64) {
      _insertRaw(_wrapInline(node.outerHtml, inline));
      return;
    }
    if (node.localName == 'img' && _isImageUrl(node.attributes['src'] ?? '')) {
      _delta.insert(
        blogQuillImageEmbed(
          node.attributes['src']!,
          originalHtml: node.outerHtml,
        ).toJson(),
        inline.isEmpty ? null : inline,
      );
      _revision++;
      _hasLineContent = true;
      _afterBreak = false;
      return;
    }
    final attributes = _readAttributes(node, inline, block);
    if (attributes == null) {
      _insertRaw(_wrapInline(node.outerHtml, inline));
      return;
    }
    final (nextInline, nextBlock) = attributes;
    final name = node.localName;
    if (name == 'br') {
      _newLine(nextBlock);
      _afterBreak = true;
      return;
    }
    final isList = name == 'ol' || name == 'ul';
    final isBlock =
        isList || const {'p', 'div', 'blockquote', 'li'}.contains(name);
    if (isBlock && _hasLineContent) _newLine(block);
    final revisionBefore = _revision;
    for (final child in node.nodes) {
      append(child, nextInline, nextBlock, depth + 1);
    }
    if (isBlock &&
        (_hasLineContent || (_revision == revisionBefore && !isList))) {
      _newLine(nextBlock);
    }
  }

  void _insertRaw(String source) {
    _delta.insert({blogQuillHtmlEmbedType: source});
    _revision++;
    _hasLineContent = true;
    _afterBreak = false;
  }

  void _newLine(Map<String, dynamic> attributes) {
    _delta.insert('\n', attributes.isEmpty ? null : attributes);
    _revision++;
    _hasLineContent = false;
  }

  Delta finish() {
    if (_delta.isEmpty || _hasLineContent) _delta.insert('\n');
    return _delta;
  }
}

(Map<String, dynamic>, Map<String, dynamic>)? _readAttributes(
  dom.Element element,
  Map<String, dynamic> inheritedInline,
  Map<String, dynamic> inheritedBlock,
) {
  final name = element.localName;
  if (!const {
    'b',
    'strong',
    'i',
    'em',
    'u',
    'span',
    'font',
    'a',
    'br',
    'p',
    'div',
    'blockquote',
    'ol',
    'ul',
    'li',
  }.contains(name)) {
    return null;
  }
  final inline = <String, dynamic>{...inheritedInline};
  final block = <String, dynamic>{...inheritedBlock};
  switch (name) {
    case 'b' || 'strong':
      inline[Attribute.bold.key] = true;
    case 'i' || 'em':
      inline[Attribute.italic.key] = true;
    case 'u':
      inline[Attribute.underline.key] = true;
    case 'blockquote':
      block[Attribute.blockQuote.key] = true;
    case 'ol':
      block[Attribute.list.key] = 'ordered';
    case 'ul':
      block[Attribute.list.key] = 'bullet';
  }
  // Complex/nested lists stay a single preserved HTML fragment.
  if ((name == 'ol' || name == 'ul') &&
      (element.querySelector('ol, ul') != null ||
          element.children.any((child) => child.localName != 'li'))) {
    return null;
  }
  if (name == 'blockquote' &&
      element.querySelector('blockquote, ol, ul') != null) {
    return null;
  }
  for (final entry in element.attributes.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    if (key == 'style') {
      if (!_readStyle(value, inline, block)) return null;
    } else if (key == 'align' &&
        const {'p', 'div', 'blockquote'}.contains(name)) {
      if (!const {'left', 'center', 'right', 'justify'}.contains(value)) {
        return null;
      }
      block[Attribute.align.key] = value;
    } else if (name == 'font' && key == 'size') {
      final size = int.tryParse(value);
      final mapped = size == null ? null : composerQuillSizeForDiscuzSize(size);
      if (mapped == null) return null;
      inline[Attribute.size.key] = mapped;
    } else if (name == 'font' && key == 'color') {
      final color = _normalizeColor(value);
      if (color == null) return null;
      inline[Attribute.color.key] = color;
    } else if (name == 'font' && key == 'face' && value.isNotEmpty) {
      inline[Attribute.font.key] = value;
    } else if (name == 'a' && key == 'href' && _isLinkUrl(value)) {
      inline[Attribute.link.key] = value;
    } else {
      return null;
    }
  }
  return (inline, block);
}

bool _readStyle(
  String source,
  Map<String, dynamic> inline,
  Map<String, dynamic> block,
) {
  for (final declaration in source.split(';')) {
    if (declaration.trim().isEmpty) continue;
    final separator = declaration.indexOf(':');
    if (separator < 0) return false;
    final key = declaration.substring(0, separator).trim().toLowerCase();
    final value = declaration.substring(separator + 1).trim().toLowerCase();
    switch (key) {
      case 'font-weight':
        if (value == 'bold' || value == '700') {
          inline[Attribute.bold.key] = true;
        } else if (value == 'normal' || value == '400') {
          inline.remove(Attribute.bold.key);
        } else {
          return false;
        }
      case 'font-style':
        if (value == 'italic') {
          inline[Attribute.italic.key] = true;
        } else if (value == 'normal') {
          inline.remove(Attribute.italic.key);
        } else {
          return false;
        }
      case 'text-decoration':
        if (value == 'underline') {
          inline[Attribute.underline.key] = true;
        } else {
          return false;
        }
      case 'font-size':
        if (!value.endsWith('px')) return false;
        final size = double.tryParse(value.substring(0, value.length - 2));
        final supported = composerDiscuzSizeToQuillSize.values.where(
          (entry) => double.parse(entry) == size,
        );
        if (supported.isEmpty) return false;
        inline[Attribute.size.key] = supported.first;
      case 'color':
        final color = _normalizeColor(value);
        if (color == null) return false;
        inline[Attribute.color.key] = color;
      case 'text-align':
        if (!const {'left', 'center', 'right', 'justify'}.contains(value)) {
          return false;
        }
        block[Attribute.align.key] = value;
      default:
        return false;
    }
  }
  return true;
}

String? _normalizeColor(Object? value) {
  if (value is! String) return null;
  final normalized = value.toLowerCase();
  if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(normalized)) return normalized;
  if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(normalized)) {
    return '#${normalized.substring(1).split('').map((digit) => '$digit$digit').join()}';
  }
  return const {
    'black': '#000000',
    'silver': '#c0c0c0',
    'gray': '#808080',
    'white': '#ffffff',
    'maroon': '#800000',
    'red': '#ff0000',
    'purple': '#800080',
    'fuchsia': '#ff00ff',
    'green': '#008000',
    'lime': '#00ff00',
    'olive': '#808000',
    'yellow': '#ffff00',
    'navy': '#000080',
    'blue': '#0000ff',
    'teal': '#008080',
    'aqua': '#00ffff',
    'orange': '#ffa500',
  }[normalized];
}

bool _isImageUrl(String value) => _isUrl(value, allowMail: false);
bool _isLinkUrl(String value) => _isUrl(value, allowMail: true);

bool _isUrl(String value, {required bool allowMail}) {
  if (value.trim().isEmpty || RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null &&
      (!uri.hasScheme ||
          const {'http', 'https'}.contains(uri.scheme) ||
          (allowMail && uri.scheme == 'mailto'));
}

String _escapeAttribute(String value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

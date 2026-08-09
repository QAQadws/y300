import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/domain/models/composer_collapse_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/domain/services/composer_collapse_document_parser.dart';
import 'package:y300/features/composer_shared/domain/services/composer_collapse_serializer.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_size_mapping.dart';

const _attachGrammar = ComposerAttachBbCodeGrammar();
const _collapseParser = ComposerCollapseDocumentParser();
const _collapseSerializer = ComposerCollapseSerializer();

class ComposerQuillBbCodeCodec {
  const ComposerQuillBbCodeCodec();

  String encodeDocument(Document document) {
    return encodeDelta(document.toDelta());
  }

  String encodeDelta(Delta delta) {
    final lines = <_EncodedLine>[];
    final currentLine = _EncodedLineBuffer();

    for (final operation in delta.toList()) {
      if (!operation.isInsert) {
        continue;
      }
      final attributes = operation.attributes ?? const <String, dynamic>{};
      final data = operation.data;
      if (data is String) {
        _appendText(
          text: data,
          attributes: attributes,
          currentLine: currentLine,
          lines: lines,
        );
        continue;
      }
      final collapseText = _encodeCollapseEmbed(data);
      if (collapseText != null) {
        currentLine.writeCollapse(collapseText);
        continue;
      }
      final embedText = _encodeInlineEmbed(data);
      if (embedText.isNotEmpty) {
        currentLine.writeText(_wrapInline(embedText, attributes));
      }
    }

    if (currentLine.isNotEmpty) {
      lines.addAll(currentLine.takeLines(const _BlockSignature()));
    }
    return _renderLines(lines);
  }

  Document decodeDocument(String bbCode) {
    return Document.fromDelta(decodeDelta(bbCode));
  }

  Delta decodeDelta(String bbCode) {
    final parsed = _collapseParser.parse(bbCode);
    final placeholders = <String, ComposerCollapseBlock>{};
    final source = parsed.hasCollapse
        ? _replaceCollapseBlocks(parsed, placeholders)
        : bbCode;
    final placeholderPattern = placeholders.isEmpty
        ? ''
        : '|${placeholders.keys.map(RegExp.escape).join('|')}';
    final builder = _DeltaBbCodeBuilder(collapseBlocks: placeholders);
    final tagPattern = RegExp(
      // 只有合法（纯数字 aid）的 attach 代码才是原子节点，
      // 非法写法保持为可编辑文本，用户还能改回来。
      '${ComposerAttachBbCodeGrammar.tokenPatternSource}|'
      r'\{:[^}]+:\}'
      r'|\[/?(?:b|i|u|s|quote)\]'
      r'|\[/?(?:color|backcolor|size|url|align)(?:=[^\]]+)?\]'
      '$placeholderPattern',
      caseSensitive: false,
    );
    var offset = 0;
    for (final match in tagPattern.allMatches(source)) {
      if (match.start > offset) {
        builder.appendText(source.substring(offset, match.start));
      }
      builder.appendToken(match.group(0)!);
      offset = match.end;
    }
    if (offset < source.length) {
      builder.appendText(source.substring(offset));
    }
    return builder.finish();
  }

  String _replaceCollapseBlocks(
    ComposerCollapseDocument document,
    Map<String, ComposerCollapseBlock> placeholders,
  ) {
    final buffer = StringBuffer();
    var placeholderIndex = 0;
    for (final part in document.parts) {
      switch (part) {
        case ComposerCollapseText(:final value):
          buffer.write(value);
        case ComposerCollapseBlock block:
          String placeholder;
          do {
            placeholder = '\uE000collapse-$placeholderIndex\uE001';
            placeholderIndex += 1;
          } while (document.source.contains(placeholder) ||
              placeholders.containsKey(placeholder));
          placeholders[placeholder] = block;
          buffer.write(placeholder);
      }
    }
    return buffer.toString();
  }

  void _appendText({
    required String text,
    required Map<String, dynamic> attributes,
    required _EncodedLineBuffer currentLine,
    required List<_EncodedLine> lines,
  }) {
    final parts = text.split('\n');
    for (var index = 0; index < parts.length; index += 1) {
      final part = parts[index];
      if (part.isNotEmpty) {
        currentLine.writeText(_wrapInline(part, attributes));
      }
      if (index < parts.length - 1) {
        lines.addAll(
          currentLine.takeLines(_BlockSignature.fromAttributes(attributes)),
        );
      }
    }
  }

  String _renderLines(List<_EncodedLine> lines) {
    final rendered = <String>[];
    var index = 0;
    while (index < lines.length) {
      if (_isQuoteBoundaryLine(lines, index)) {
        index += 1;
        continue;
      }
      final line = lines[index];
      if (line.isAtomicCollapse) {
        rendered.add(line.content);
        index += 1;
        continue;
      }
      if (!line.block.hasBlockFormat) {
        rendered.add(line.content);
        index += 1;
        continue;
      }

      final group = <String>[line.content];
      index += 1;
      while (index < lines.length && lines[index].block == line.block) {
        group.add(lines[index].content);
        index += 1;
      }
      rendered.add(_wrapBlock(group.join('\n'), line.block));
    }
    return rendered.join('\n');
  }

  bool _isQuoteBoundaryLine(List<_EncodedLine> lines, int index) {
    final line = lines[index];
    if (!line.isBlank || line.block.hasBlockFormat) {
      return false;
    }
    final previousQuoteIndex = _previousContentLineIndex(lines, index);
    final nextQuoteIndex = _nextContentLineIndex(lines, index);
    if (previousQuoteIndex == null || nextQuoteIndex == null) {
      return false;
    }
    return lines[previousQuoteIndex].block.isQuote &&
        lines[nextQuoteIndex].block.isQuote;
  }

  int? _previousContentLineIndex(List<_EncodedLine> lines, int startIndex) {
    for (var index = startIndex - 1; index >= 0; index -= 1) {
      if (lines[index].isBlank) {
        continue;
      }
      return index;
    }
    return null;
  }

  int? _nextContentLineIndex(List<_EncodedLine> lines, int startIndex) {
    for (var index = startIndex + 1; index < lines.length; index += 1) {
      if (lines[index].isBlank) {
        continue;
      }
      return index;
    }
    return null;
  }

  String _wrapInline(String source, Map<String, dynamic> attributes) {
    if (source.isEmpty) {
      return source;
    }
    final tags = <_BbCodeTag>[
      if (attributes[Attribute.bold.key] == true)
        const _BbCodeTag('[b]', '[/b]'),
      if (attributes[Attribute.italic.key] == true)
        const _BbCodeTag('[i]', '[/i]'),
      if (attributes[Attribute.underline.key] == true)
        const _BbCodeTag('[u]', '[/u]'),
      if (attributes[Attribute.strikeThrough.key] == true)
        const _BbCodeTag('[s]', '[/s]'),
      if (composerDiscuzSizeForQuillSize(attributes[Attribute.size.key])
          case final size?)
        _BbCodeTag('[size=$size]', '[/size]'),
      if (_normalizeHexColor(attributes[Attribute.color.key]) case final color?)
        _BbCodeTag('[color=$color]', '[/color]'),
      if (_normalizeHexColor(attributes[Attribute.background.key])
          case final background?)
        _BbCodeTag('[backcolor=$background]', '[/backcolor]'),
      if (_normalizeUrl(attributes[Attribute.link.key]) case final url?)
        _BbCodeTag('[url=$url]', '[/url]'),
    ];
    if (tags.isEmpty) {
      return source;
    }
    final buffer = StringBuffer();
    for (final tag in tags) {
      buffer.write(tag.opening);
    }
    buffer.write(source);
    for (final tag in tags.reversed) {
      buffer.write(tag.closing);
    }
    return buffer.toString();
  }

  String _wrapBlock(String source, _BlockSignature block) {
    var result = source;
    if (block.isQuote) {
      result = '[quote]$result[/quote]';
    }
    if (block.align != null) {
      result = '[align=${block.align}]$result[/align]';
    }
    return result;
  }

  String? _encodeCollapseEmbed(Object? data) {
    final collapse = composerQuillCollapseEmbedPayload(data);
    if (collapse != null) {
      final title = collapse['title']?.toString() ?? '';
      final body = collapse['body']?.toString() ?? '';
      return _collapseSerializer.serializeBlock(
        title: title,
        bodyBbCode: body,
        rawOpeningLine: collapse['rawOpeningLine'] as String?,
        rawClosing: collapse['rawClosing'] as String?,
      );
    }
    return null;
  }

  String _encodeInlineEmbed(Object? data) {
    final stickerCode = composerQuillEmbedData(
      data,
      composerQuillStickerEmbedType,
    );
    if (stickerCode != null && stickerCode.trim().isNotEmpty) {
      return stickerCode.trim();
    }
    final attachAid = composerQuillAttachEmbedAid(data);
    if (attachAid != null && attachAid.trim().isNotEmpty) {
      return _attachGrammar.codeFor(
        attachAid,
        composerQuillAttachEmbedTagKind(data),
      );
    }
    return '';
  }
}

class _DeltaBbCodeBuilder {
  _DeltaBbCodeBuilder({Map<String, ComposerCollapseBlock>? collapseBlocks})
    : _collapseBlocks =
          collapseBlocks ?? const <String, ComposerCollapseBlock>{};

  final Delta _delta = Delta();
  final Map<String, ComposerCollapseBlock> _collapseBlocks;
  final List<_ActiveBbCodeTag> _activeTags = <_ActiveBbCodeTag>[];
  bool _lineHasContent = false;
  bool _lineContainsCollapse = false;
  bool _skipNextLeadingNewline = false;

  void appendToken(String token) {
    final collapse = _collapseBlocks[token];
    if (collapse != null) {
      _delta.insert(
        composerQuillCollapseEmbedData(
          id: collapse.id,
          title: collapse.title,
          body: _collapseSerializer.serialize(collapse.body),
          rawOpeningLine: collapse.rawOpeningLine,
          rawClosing: collapse.rawClosing,
        ),
      );
      _lineHasContent = true;
      _lineContainsCollapse = true;
      return;
    }
    final lower = token.toLowerCase();
    final attachmentTokens = _attachGrammar.scan(token);
    if (attachmentTokens.length == 1 &&
        attachmentTokens.single.rawCode.length == token.length) {
      final attachment = attachmentTokens.single;
      _delta.insert(
        composerQuillAttachEmbedData(attachment.aid, attachment.kind),
        _inlineAttributes(),
      );
      _lineHasContent = true;
      return;
    }
    if (token.startsWith('{:') && token.endsWith(':}')) {
      _delta.insert(composerQuillStickerEmbedData(token), _inlineAttributes());
      _lineHasContent = true;
      return;
    }
    if (lower.startsWith('[/')) {
      _closeTag(lower.substring(2, lower.length - 1));
      return;
    }
    final tag = _parseOpeningTag(token);
    if (tag != null) {
      _activeTags.add(tag);
      return;
    }
    appendText(token);
  }

  void appendText(String text) {
    if (text.isEmpty) {
      return;
    }
    final parts = text.split('\n');
    for (var index = 0; index < parts.length; index += 1) {
      final part = parts[index];
      if (part.isNotEmpty) {
        _delta.insert(part, _inlineAttributes());
        _lineHasContent = true;
      }
      if (index < parts.length - 1) {
        if (_skipNextLeadingNewline) {
          _skipNextLeadingNewline = false;
          continue;
        }
        _appendLineBreak();
      }
    }
  }

  Delta finish() {
    final operations = _delta.toList();
    final endsWithNewline =
        operations.isNotEmpty &&
        operations.last.data is String &&
        (operations.last.data as String).endsWith('\n');
    if (!endsWithNewline) {
      _appendLineBreak();
    }
    return _delta;
  }

  Map<String, dynamic>? _inlineAttributes() {
    final attributes = <String, dynamic>{};
    for (final tag in _activeTags) {
      switch (tag.name) {
        case 'b':
          attributes[Attribute.bold.key] = true;
          break;
        case 'i':
          attributes[Attribute.italic.key] = true;
          break;
        case 'u':
          attributes[Attribute.underline.key] = true;
          break;
        case 's':
          attributes[Attribute.strikeThrough.key] = true;
          break;
        case 'size':
          final size = _normalizeDiscuzSize(tag.value);
          if (size != null) {
            attributes[Attribute.size.key] = composerQuillSizeForDiscuzSize(
              int.parse(size),
            );
          }
          break;
        case 'color':
          final color = _normalizeHexColor(tag.value);
          if (color != null) {
            attributes[Attribute.color.key] = color;
          }
          break;
        case 'backcolor':
          final background = _normalizeHexColor(tag.value);
          if (background != null) {
            attributes[Attribute.background.key] = background;
          }
          break;
        case 'url':
          final url = _normalizeUrl(tag.value);
          if (url != null) {
            attributes[Attribute.link.key] = url;
          }
          break;
      }
    }
    return attributes.isEmpty ? null : attributes;
  }

  Map<String, dynamic>? _blockAttributes() {
    final attributes = <String, dynamic>{};
    for (final tag in _activeTags) {
      switch (tag.name) {
        case 'quote':
          attributes[Attribute.blockQuote.key] = true;
          break;
        case 'align':
          final align = _normalizeAlign(tag.value);
          if (align != null) {
            attributes[Attribute.align.key] = align;
          }
          break;
      }
    }
    return attributes.isEmpty ? null : attributes;
  }

  void _closeTag(String name) {
    final normalized = name.toLowerCase();
    for (var index = _activeTags.length - 1; index >= 0; index -= 1) {
      if (_activeTags[index].name == normalized) {
        if (_isBlockTag(normalized) && _lineHasContent) {
          _appendLineBreak();
          _skipNextLeadingNewline = true;
        }
        _activeTags.removeAt(index);
        return;
      }
    }
  }

  void _appendLineBreak() {
    _delta.insert('\n', _lineContainsCollapse ? null : _blockAttributes());
    _lineHasContent = false;
    _lineContainsCollapse = false;
  }

  _ActiveBbCodeTag? _parseOpeningTag(String token) {
    if (!token.startsWith('[') || !token.endsWith(']')) {
      return null;
    }
    final body = token.substring(1, token.length - 1);
    final separator = body.indexOf('=');
    final name = (separator < 0 ? body : body.substring(0, separator))
        .trim()
        .toLowerCase();
    final value = separator < 0 ? null : body.substring(separator + 1).trim();
    return switch (name) {
      'b' ||
      'i' ||
      'u' ||
      's' ||
      'quote' ||
      'color' ||
      'backcolor' ||
      'size' ||
      'url' ||
      'align' => _ActiveBbCodeTag(name: name, value: value),
      _ => null,
    };
  }
}

bool _isBlockTag(String name) {
  return name == 'quote' || name == 'align';
}

class _BbCodeTag {
  const _BbCodeTag(this.opening, this.closing);

  final String opening;
  final String closing;
}

class _EncodedLine {
  const _EncodedLine({
    required this.content,
    required this.block,
    this.isAtomicCollapse = false,
  });

  final String content;
  final _BlockSignature block;
  final bool isAtomicCollapse;

  bool get isBlank => content.trim().isEmpty;
}

final class _EncodedLineBuffer {
  final List<_EncodedSegment> _segments = <_EncodedSegment>[];

  bool get isNotEmpty => _segments.isNotEmpty;

  void writeText(String source) {
    if (source.isEmpty) {
      return;
    }
    if (_segments.isNotEmpty && !_segments.last.isCollapse) {
      final last = _segments.last;
      _segments[_segments.length - 1] = _EncodedSegment(
        source: '${last.source}$source',
      );
      return;
    }
    _segments.add(_EncodedSegment(source: source));
  }

  void writeCollapse(String source) {
    _segments.add(_EncodedSegment(source: source, isCollapse: true));
  }

  List<_EncodedLine> takeLines(_BlockSignature block) {
    if (_segments.isEmpty) {
      return <_EncodedLine>[_EncodedLine(content: '', block: block)];
    }
    final lines = <_EncodedLine>[];
    final text = StringBuffer();

    void flushText() {
      if (text.isEmpty) {
        return;
      }
      lines.add(_EncodedLine(content: text.toString(), block: block));
      text.clear();
    }

    for (final segment in _segments) {
      if (segment.isCollapse) {
        flushText();
        lines.add(
          _EncodedLine(
            content: segment.source,
            block: const _BlockSignature(),
            isAtomicCollapse: true,
          ),
        );
      } else {
        text.write(segment.source);
      }
    }
    flushText();
    _segments.clear();
    return lines;
  }
}

final class _EncodedSegment {
  const _EncodedSegment({required this.source, this.isCollapse = false});

  final String source;
  final bool isCollapse;
}

class _BlockSignature {
  const _BlockSignature({this.isQuote = false, this.align});

  factory _BlockSignature.fromAttributes(Map<String, dynamic> attributes) {
    return _BlockSignature(
      isQuote: attributes[Attribute.blockQuote.key] == true,
      align: _normalizeAlign(attributes[Attribute.align.key]),
    );
  }

  final bool isQuote;
  final String? align;

  bool get hasBlockFormat => isQuote || align != null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _BlockSignature &&
            other.isQuote == isQuote &&
            other.align == align;
  }

  @override
  int get hashCode => Object.hash(isQuote, align);
}

class _ActiveBbCodeTag {
  const _ActiveBbCodeTag({required this.name, required this.value});

  final String name;
  final String? value;
}

String? _normalizeDiscuzSize(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 1 || parsed > 7) {
    return null;
  }
  return parsed.toString();
}

String? _normalizeHexColor(Object? value) {
  final raw = value?.toString().trim().toLowerCase();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final hex = raw.startsWith('#') ? raw.substring(1) : raw;
  if (RegExp(r'^[0-9a-f]{3}$').hasMatch(hex)) {
    final expanded = hex.split('').map((part) => '$part$part').join();
    return '#$expanded';
  }
  if (RegExp(r'^[0-9a-f]{6}$').hasMatch(hex)) {
    return '#$hex';
  }
  return null;
}

String? _normalizeAlign(Object? value) {
  final raw = value?.toString().trim().toLowerCase();
  return switch (raw) {
    'left' || 'center' || 'right' => raw,
    _ => null,
  };
}

String? _normalizeUrl(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw;
}

import 'package:y300/features/novel/domain/models/novel_reader_document.dart';

class NovelReaderInlineStyleDto {
  const NovelReaderInlineStyleDto({
    this.bold = false,
    this.italic = false,
    this.color,
  });

  final bool bold;
  final bool italic;
  final String? color;

  factory NovelReaderInlineStyleDto.fromStyle(NovelReaderInlineStyle style) {
    return NovelReaderInlineStyleDto(
      bold: style.bold,
      italic: style.italic,
      color: style.color,
    );
  }

  factory NovelReaderInlineStyleDto.fromMap(Map<String, Object?> map) {
    return NovelReaderInlineStyleDto(
      bold: map['bold'] as bool? ?? false,
      italic: map['italic'] as bool? ?? false,
      color: map['color'] as String?,
    );
  }

  NovelReaderInlineStyle toStyle() {
    return NovelReaderInlineStyle(
      bold: bold,
      italic: italic,
      color: color,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'bold': bold,
      'italic': italic,
      'color': color,
    };
  }
}

class NovelReaderImageDto {
  const NovelReaderImageDto({
    required this.url,
    this.altText,
  });

  final String url;
  final String? altText;

  factory NovelReaderImageDto.fromImage(NovelReaderImage image) {
    return NovelReaderImageDto(
      url: image.url,
      altText: image.altText,
    );
  }

  factory NovelReaderImageDto.fromMap(Map<String, Object?> map) {
    return NovelReaderImageDto(
      url: map['url'] as String? ?? '',
      altText: map['altText'] as String?,
    );
  }

  NovelReaderImage toImage() {
    return NovelReaderImage(
      url: url,
      altText: altText,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'url': url,
      'altText': altText,
    };
  }
}

class NovelReaderLinkDto {
  const NovelReaderLinkDto({
    required this.url,
    required this.text,
    this.tid,
  });

  final String url;
  final String text;
  final String? tid;

  factory NovelReaderLinkDto.fromLink(NovelReaderLink link) {
    return NovelReaderLinkDto(
      url: link.url,
      text: link.text,
      tid: link.tid,
    );
  }

  factory NovelReaderLinkDto.fromMap(Map<String, Object?> map) {
    return NovelReaderLinkDto(
      url: map['url'] as String? ?? '',
      text: map['text'] as String? ?? '',
      tid: map['tid'] as String?,
    );
  }

  NovelReaderLink toLink() {
    return NovelReaderLink(
      url: url,
      text: text,
      tid: tid,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'url': url,
      'text': text,
      'tid': tid,
    };
  }
}

class NovelReaderNodeDto {
  const NovelReaderNodeDto({
    required this.id,
    required this.type,
    this.text,
    this.children = const <NovelReaderNodeDto>[],
    this.image,
    this.link,
    this.style = const NovelReaderInlineStyleDto(),
  });

  final String id;
  final String type;
  final String? text;
  final List<NovelReaderNodeDto> children;
  final NovelReaderImageDto? image;
  final NovelReaderLinkDto? link;
  final NovelReaderInlineStyleDto style;

  factory NovelReaderNodeDto.fromNode(NovelReaderNode node) {
    return NovelReaderNodeDto(
      id: node.id,
      type: _encodeNodeType(node.type),
      text: node.text,
      children: node.children
          .map(NovelReaderNodeDto.fromNode)
          .toList(growable: false),
      image: node.image == null ? null : NovelReaderImageDto.fromImage(node.image!),
      link: node.link == null ? null : NovelReaderLinkDto.fromLink(node.link!),
      style: NovelReaderInlineStyleDto.fromStyle(node.style),
    );
  }

  factory NovelReaderNodeDto.fromMap(Map<String, Object?> map) {
    final rawChildren = map['children'] as List<Object?>? ?? const <Object?>[];
    final imageMap = _mapValue(map['image']);
    final linkMap = _mapValue(map['link']);
    final styleMap = _mapValue(map['style']);
    return NovelReaderNodeDto(
      id: map['id'] as String? ?? '',
      type: map['type'] as String? ?? _encodeNodeType(NovelReaderNodeType.paragraph),
      text: map['text'] as String?,
      children: rawChildren
          .whereType<Map<Object?, Object?>>()
          .map((child) => NovelReaderNodeDto.fromMap(_castMap(child)))
          .toList(growable: false),
      image: imageMap == null ? null : NovelReaderImageDto.fromMap(imageMap),
      link: linkMap == null ? null : NovelReaderLinkDto.fromMap(linkMap),
      style: styleMap == null
          ? const NovelReaderInlineStyleDto()
          : NovelReaderInlineStyleDto.fromMap(styleMap),
    );
  }

  NovelReaderNode toNode() {
    return NovelReaderNode(
      id: id,
      type: _decodeNodeType(type),
      text: text,
      children: children.map((child) => child.toNode()).toList(growable: false),
      image: image?.toImage(),
      link: link?.toLink(),
      style: style.toStyle(),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'type': type,
      'text': text,
      'children': children.map((child) => child.toMap()).toList(growable: false),
      'image': image?.toMap(),
      'link': link?.toMap(),
      'style': style.toMap(),
    };
  }
}

class NovelReaderDocumentDto {
  const NovelReaderDocumentDto({
    required this.episodeId,
    required this.rawHtmlHash,
    required this.nodes,
    required this.plainText,
    required this.wordCount,
  });

  final String episodeId;
  final String rawHtmlHash;
  final List<NovelReaderNodeDto> nodes;
  final String plainText;
  final int wordCount;

  factory NovelReaderDocumentDto.fromDocument(NovelReaderDocument document) {
    return NovelReaderDocumentDto(
      episodeId: document.episodeId,
      rawHtmlHash: document.rawHtmlHash,
      nodes: document.nodes
          .map(NovelReaderNodeDto.fromNode)
          .toList(growable: false),
      plainText: document.plainText,
      wordCount: document.wordCount,
    );
  }

  factory NovelReaderDocumentDto.fromMap(Map<String, Object?> map) {
    final rawNodes = map['nodes'] as List<Object?>? ?? const <Object?>[];
    return NovelReaderDocumentDto(
      episodeId: map['episodeId'] as String? ?? '',
      rawHtmlHash: map['rawHtmlHash'] as String? ?? '',
      nodes: rawNodes
          .whereType<Map<Object?, Object?>>()
          .map((node) => NovelReaderNodeDto.fromMap(_castMap(node)))
          .toList(growable: false),
      plainText: map['plainText'] as String? ?? '',
      wordCount: map['wordCount'] as int? ?? 0,
    );
  }

  NovelReaderDocument toDocument() {
    return NovelReaderDocument(
      episodeId: episodeId,
      rawHtmlHash: rawHtmlHash,
      nodes: nodes.map((node) => node.toNode()).toList(growable: false),
      plainText: plainText,
      wordCount: wordCount,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'episodeId': episodeId,
      'rawHtmlHash': rawHtmlHash,
      'nodes': nodes.map((node) => node.toMap()).toList(growable: false),
      'plainText': plainText,
      'wordCount': wordCount,
    };
  }
}

String _encodeNodeType(NovelReaderNodeType type) {
  return switch (type) {
    NovelReaderNodeType.paragraph => 'paragraph',
    NovelReaderNodeType.heading => 'heading',
    NovelReaderNodeType.quote => 'quote',
    NovelReaderNodeType.image => 'image',
    NovelReaderNodeType.link => 'link',
    NovelReaderNodeType.divider => 'divider',
    NovelReaderNodeType.spacer => 'spacer',
  };
}

NovelReaderNodeType _decodeNodeType(String type) {
  return switch (type) {
    'paragraph' => NovelReaderNodeType.paragraph,
    'heading' => NovelReaderNodeType.heading,
    'quote' => NovelReaderNodeType.quote,
    'image' => NovelReaderNodeType.image,
    'link' => NovelReaderNodeType.link,
    'divider' => NovelReaderNodeType.divider,
    'spacer' => NovelReaderNodeType.spacer,
    _ => NovelReaderNodeType.paragraph,
  };
}

Map<String, Object?> _castMap(Map<Object?, Object?> raw) {
  return raw.map(
    (key, value) => MapEntry(key.toString(), value),
  );
}

Map<String, Object?>? _mapValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    return _castMap(value);
  }
  return null;
}

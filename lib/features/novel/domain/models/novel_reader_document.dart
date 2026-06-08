enum NovelReaderNodeType {
  paragraph,
  heading,
  quote,
  image,
  link,
  divider,
  spacer,
}

class NovelReaderInlineStyle {
  const NovelReaderInlineStyle({
    this.bold = false,
    this.italic = false,
    this.color,
  });

  final bool bold;
  final bool italic;
  final String? color;
}

class NovelReaderImage {
  const NovelReaderImage({
    required this.url,
    this.altText,
  });

  final String url;
  final String? altText;
}

class NovelReaderLink {
  const NovelReaderLink({
    required this.url,
    required this.text,
    this.tid,
  });

  final String url;
  final String text;
  final String? tid;
}

class NovelReaderNode {
  const NovelReaderNode({
    required this.id,
    required this.type,
    this.text,
    this.children = const <NovelReaderNode>[],
    this.image,
    this.link,
    this.style = const NovelReaderInlineStyle(),
  });

  final String id;
  final NovelReaderNodeType type;
  final String? text;
  final List<NovelReaderNode> children;
  final NovelReaderImage? image;
  final NovelReaderLink? link;
  final NovelReaderInlineStyle style;
}

class NovelReaderDocument {
  const NovelReaderDocument({
    required this.episodeId,
    required this.rawHtmlHash,
    required this.nodes,
    required this.plainText,
    required this.wordCount,
  });

  final String episodeId;
  final String rawHtmlHash;
  final List<NovelReaderNode> nodes;
  final String plainText;
  final int wordCount;
}

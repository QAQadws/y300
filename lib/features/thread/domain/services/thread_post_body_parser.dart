import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

class ThreadPostBodyParser {
  const ThreadPostBodyParser({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  static const Set<String> _blockTags = <String>{
    'p',
    'div',
    'section',
    'article',
    'blockquote',
    'li',
    'tr',
  };

  ThreadPostBodyDocument parse(String html) {
    final fragment = html_parser.parseFragment(html);
    final buildContext = _ThreadPostBodyBuildContext(parser: this);
    buildContext.visitChildren(fragment, const _InlineStyle());
    buildContext.flushText();

    return ThreadPostBodyDocument(
      blocks: List<ThreadPostBodyBlock>.unmodifiable(buildContext.blocks),
    );
  }

  ThreadPostImageBlock? _parseImage(html_dom.Element image, int index) {
    final rawUrl =
        DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(
          image,
          domAttributes: const <String>[
            'zoomfile',
            'file',
            'data-original',
            'data-src',
            'src',
          ],
        );
    if (rawUrl == null || rawUrl.isEmpty) {
      return null;
    }
    final normalized = DefaultForumImageSourcePipeline.normalizeImageSource(
      rawUrl,
      urlResolver: _urlResolver,
    );
    if (normalized == null ||
        !DefaultForumImageSourcePipeline.isHttpImageUrl(normalized) ||
        DefaultForumImageSourcePipeline.isForumChromeImage(normalized)) {
      return null;
    }
    return ThreadPostImageBlock(
      url: normalized,
      rawUrl: rawUrl,
      index: index,
      aid: image.attributes['aid']?.trim(),
      originalWidth: _parseDimension(image.attributes['width']),
      originalHeight: _parseDimension(image.attributes['height']),
    );
  }

  ThreadPostInlineImage? _parseInlineSmiley(html_dom.Element image) {
    final rawUrl =
        DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(
          image,
          domAttributes: const <String>['src', 'data-src', 'data-original'],
        );
    if (rawUrl == null || rawUrl.isEmpty) {
      return null;
    }
    final normalized = DefaultForumImageSourcePipeline.normalizeImageSource(
      rawUrl,
      urlResolver: _urlResolver,
    );
    if (normalized == null ||
        !DefaultForumImageSourcePipeline.isHttpImageUrl(normalized) ||
        !normalized.toLowerCase().contains('/static/image/smiley/')) {
      return null;
    }
    return ThreadPostInlineImage(
      url: normalized,
      rawUrl: rawUrl,
      altText: image.attributes['alt']?.trim(),
      originalWidth: _parseDimension(image.attributes['width']),
      originalHeight: _parseDimension(image.attributes['height']),
    );
  }

  String? _resolve(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty || value.startsWith('javascript:')) {
      return null;
    }
    return _urlResolver.resolve(value);
  }

  double? _parseDimension(String? raw) {
    final value = double.tryParse(raw?.trim() ?? '');
    return value == null || value <= 0 ? null : value;
  }
}

class _ThreadPostBodyBuildContext {
  _ThreadPostBodyBuildContext({required this.parser});

  final ThreadPostBodyParser parser;
  final List<ThreadPostBodyBlock> blocks = <ThreadPostBodyBlock>[];
  final _TextBlockBuffer textBuffer = _TextBlockBuffer();
  var imageIndex = 0;

  void flushText() {
    final block = textBuffer.takeBlock();
    if (block != null) {
      blocks.add(block);
    }
  }

  void visitChildren(html_dom.Node node, _InlineStyle style) {
    for (final child in node.nodes) {
      visit(child, style);
    }
  }

  void visit(html_dom.Node node, _InlineStyle style) {
    if (node is html_dom.Text) {
      textBuffer.addText(node.text, style);
      return;
    }
    if (node is! html_dom.Element) {
      return;
    }

    final tag = (node.localName ?? '').toLowerCase();
    if (tag == 'script' || tag == 'style') {
      return;
    }
    if (node.classes.contains('aimg_tip')) {
      return;
    }
    if (tag == 'br') {
      flushText();
      return;
    }
    if (tag == 'img') {
      final smiley = parser._parseInlineSmiley(node);
      if (smiley != null) {
        textBuffer.addInlineImage(smiley, style);
        return;
      }
      final image = parser._parseImage(node, imageIndex);
      if (image != null) {
        flushText();
        blocks.add(image);
        imageIndex += 1;
      }
      return;
    }
    if (node.classes.contains('quote') || tag == 'blockquote') {
      flushText();
      final quoteRoot = tag == 'blockquote'
          ? node
          : node.querySelector('blockquote') ?? node;
      final quoteContext = _ThreadPostBodyBuildContext(parser: parser);
      quoteContext.imageIndex = imageIndex;
      quoteContext.visitChildren(quoteRoot, style);
      quoteContext.flushText();
      imageIndex = quoteContext.imageIndex;
      if (quoteContext.blocks.isNotEmpty) {
        blocks.add(
          ThreadPostQuoteBlock(
            blocks: List<ThreadPostBodyBlock>.unmodifiable(quoteContext.blocks),
          ),
        );
      }
      return;
    }

    final nextStyle = style.merge(
      linkUrl: tag == 'a' ? parser._resolve(node.attributes['href']) : null,
      isBold: tag == 'b' || tag == 'strong' ? true : null,
      isItalic: tag == 'i' || tag == 'em' ? true : null,
      isUnderline: tag == 'u' ? true : null,
    );
    final isBlock = ThreadPostBodyParser._blockTags.contains(tag);
    if (isBlock && textBuffer.hasContent) {
      flushText();
    }
    visitChildren(node, nextStyle);
    if (isBlock && textBuffer.hasContent) {
      flushText();
    }
  }
}

class _TextBlockBuffer {
  final List<ThreadPostTextRun> _runs = <ThreadPostTextRun>[];

  bool get hasContent =>
      _runs.any((run) => run.inlineImage != null || run.text.trim().isNotEmpty);

  void addText(String raw, _InlineStyle style) {
    final text = _normalizeInlineText(raw);
    if (text.isEmpty) {
      return;
    }
    _runs.add(
      ThreadPostTextRun(
        text: text,
        linkUrl: style.linkUrl,
        isBold: style.isBold,
        isItalic: style.isItalic,
        isUnderline: style.isUnderline,
      ),
    );
  }

  void addInlineImage(ThreadPostInlineImage image, _InlineStyle style) {
    _runs.add(
      ThreadPostTextRun(
        text: image.altText?.isNotEmpty == true ? image.altText! : '',
        linkUrl: style.linkUrl,
        isBold: style.isBold,
        isItalic: style.isItalic,
        isUnderline: style.isUnderline,
        inlineImage: image,
      ),
    );
  }

  ThreadPostTextBlock? takeBlock() {
    if (!hasContent) {
      _runs.clear();
      return null;
    }
    final normalized = _mergeAdjacentRuns(_runs)
        .where((run) => run.inlineImage != null || run.text.trim().isNotEmpty)
        .toList(growable: false);
    _runs.clear();
    if (normalized.isEmpty) {
      return null;
    }
    return ThreadPostTextBlock(runs: normalized);
  }

  List<ThreadPostTextRun> _mergeAdjacentRuns(List<ThreadPostTextRun> runs) {
    final output = <ThreadPostTextRun>[];
    for (final run in runs) {
      if (output.isNotEmpty && _sameStyle(output.last, run)) {
        final previous = output.removeLast();
        output.add(
          ThreadPostTextRun(
            text: '${previous.text}${run.text}',
            linkUrl: previous.linkUrl,
            isBold: previous.isBold,
            isItalic: previous.isItalic,
            isUnderline: previous.isUnderline,
          ),
        );
      } else {
        output.add(run);
      }
    }
    return output;
  }

  bool _sameStyle(ThreadPostTextRun a, ThreadPostTextRun b) {
    return a.inlineImage == null &&
        b.inlineImage == null &&
        a.linkUrl == b.linkUrl &&
        a.isBold == b.isBold &&
        a.isItalic == b.isItalic &&
        a.isUnderline == b.isUnderline;
  }

  String _normalizeInlineText(String raw) {
    return raw.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _InlineStyle {
  const _InlineStyle({
    this.linkUrl,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
  });

  final String? linkUrl;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;

  _InlineStyle merge({
    String? linkUrl,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
  }) {
    return _InlineStyle(
      linkUrl: linkUrl ?? this.linkUrl,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
    );
  }
}

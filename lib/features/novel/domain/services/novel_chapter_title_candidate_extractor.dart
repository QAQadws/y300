import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

abstract interface class NovelChapterTitleCandidateExtractor {
  List<String> extractTextUnits(String rawHtml);
}

/// Builds title candidates from author-owned prose without changing the
/// chapter HTML that is persisted and displayed by the reader.
class DiscuzNovelChapterTitleCandidateExtractor
    implements NovelChapterTitleCandidateExtractor {
  const DiscuzNovelChapterTitleCandidateExtractor();

  static const String _excludedSelector =
      'blockquote, .quote, .pstatus, .postedit, .post-edit, '
      '.post-signature, .signature, .showcollapse_gather';
  static final RegExp _leadingEditNotice = RegExp(
    r'^(?:本帖最后由|本帖最後由).+?(?:编辑|編輯)\s*',
  );
  static const Set<String> _skipTags = <String>{
    'script',
    'style',
    'form',
    'input',
    'button',
    'select',
    'textarea',
    'iframe',
    'noscript',
    'img',
  };
  static const Set<String> _blockTags = <String>{
    'address',
    'article',
    'aside',
    'blockquote',
    'dd',
    'div',
    'dl',
    'dt',
    'figcaption',
    'figure',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'li',
    'main',
    'nav',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'tr',
    'ul',
  };

  @override
  List<String> extractTextUnits(String rawHtml) {
    final normalizedHtml = rawHtml.trim();
    if (normalizedHtml.isEmpty) {
      return const <String>[];
    }

    final fragment = html_parser.parseFragment(normalizedHtml);
    for (final element in fragment.querySelectorAll(_excludedSelector)) {
      element.remove();
    }
    final collector = _DocumentOrderTextCollector(
      blockTags: _blockTags,
      skipTags: _skipTags,
      normalize: _stripNonProsePrefix,
    );
    for (final node in fragment.nodes) {
      collector.visit(node);
    }
    return collector.finish();
  }

  String _stripNonProsePrefix(String value) {
    return value
        .replaceAll('\u00A0', ' ')
        .replaceFirst(_leadingEditNotice, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _DocumentOrderTextCollector {
  _DocumentOrderTextCollector({
    required this.blockTags,
    required this.skipTags,
    required this.normalize,
  });

  final Set<String> blockTags;
  final Set<String> skipTags;
  final String Function(String value) normalize;
  final List<String> _units = <String>[];
  final StringBuffer _buffer = StringBuffer();

  void visit(html_dom.Node node) {
    if (node is html_dom.Text) {
      _buffer.write(node.data);
      return;
    }
    if (node is! html_dom.Element) {
      return;
    }
    final tag = node.localName?.toLowerCase() ?? '';
    if (skipTags.contains(tag)) {
      return;
    }
    if (tag == 'br' || tag == 'hr') {
      _flush();
      return;
    }
    final isBlock = blockTags.contains(tag);
    if (isBlock) {
      _flush();
    }
    for (final child in node.nodes) {
      visit(child);
    }
    if (isBlock) {
      _flush();
    }
  }

  List<String> finish() {
    _flush();
    return List<String>.unmodifiable(_units);
  }

  void _flush() {
    if (_buffer.isEmpty) {
      return;
    }
    final unit = normalize(_buffer.toString());
    _buffer.clear();
    if (unit.isNotEmpty) {
      _units.add(unit);
    }
  }
}

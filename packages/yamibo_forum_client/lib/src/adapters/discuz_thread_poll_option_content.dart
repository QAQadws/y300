import 'package:html/dom.dart' as dom;

/// Consumes an already sanitized, detached option container. Template labels
/// and cells retain their author styles but cannot act as voting controls.
({String html, String text, bool hasImage}) readDiscuzThreadPollOptionContent(
  dom.Element root,
) {
  final label = root.querySelector('label');
  if (label != null) {
    var remaining = RegExp(r'^\s*\d+\.\s*').firstMatch(label.text)?.end ?? 0;
    final pending = label.nodes.reversed.toList();
    while (pending.isNotEmpty && remaining > 0) {
      final node = pending.removeLast();
      if (node is dom.Text) {
        final removed = remaining < node.data.length
            ? remaining
            : node.data.length;
        node.data = node.data.substring(removed);
        remaining -= removed;
      } else {
        pending.addAll(node.nodes.reversed);
      }
    }
  }
  for (final label in root.querySelectorAll('label')) {
    final span = dom.Element.tag('span')
      ..attributes.addAll(label.attributes)
      ..nodes.addAll(label.nodes.toList());
    span.attributes.remove('for');
    span.attributes.remove('id');
    label.replaceWith(span);
  }
  final content = dom.Element.tag('div');
  for (final node in root.nodes.toList()) {
    if (root.localName == 'tr' &&
        node is dom.Element &&
        (node.localName == 'td' || node.localName == 'th')) {
      final cell = dom.Element.tag('div')
        ..attributes.addAll(node.attributes)
        ..nodes.addAll(node.nodes.toList());
      content.nodes.add(cell);
    } else {
      content.nodes.add(node);
    }
  }
  var text = content.text;
  if (text.trim().isEmpty) {
    text = content
        .querySelectorAll('img')
        .map((image) {
          final alt = image.attributes['alt']?.trim() ?? '';
          return alt.isNotEmpty ? alt : image.attributes['title']?.trim() ?? '';
        })
        .where((label) => label.isNotEmpty)
        .join(' ');
  }
  return (
    html: content.innerHtml.trim(),
    text: text,
    hasImage: content.querySelector('img') != null,
  );
}

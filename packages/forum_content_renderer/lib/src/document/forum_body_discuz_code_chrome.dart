import 'package:html/dom.dart' as dom;

/// Recognizes only the verified X3.5 code toolbar, never caption text itself.
/// The caller supplies the preceding element during its existing sibling walk.
bool forumBodyIsDiscuzCodeCopyControl(
  dom.Element element,
  dom.Element? preceding,
) {
  if (element.localName != 'em' || preceding?.localName != 'div') return false;
  final parent = element.parentNode;
  if (parent is! dom.Element ||
      parent.localName != 'div' ||
      !parent.classes.contains('blockcode')) {
    return false;
  }
  final command = _copyCommand.firstMatch(element.attributes['onclick'] ?? '');
  if (command == null || preceding!.attributes['id'] != command.group(2)) {
    return false;
  }
  var hasList = false;
  for (final child in preceding.nodes) {
    if (child is dom.Element) {
      if (hasList || child.localName != 'ol') return false;
      hasList = true;
    } else if (child is dom.Text && child.data.trim().isNotEmpty) {
      return false;
    }
  }
  return hasList;
}

final _copyCommand = RegExp(
  r'''^\s*copycode\(\s*\$\(\s*(['"])(code_[a-zA-Z0-9]{3})\1\s*\)\s*\)\s*;?\s*$''',
);

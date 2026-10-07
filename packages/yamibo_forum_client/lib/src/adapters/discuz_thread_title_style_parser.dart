import 'package:html/dom.dart' as dom;

import '../contracts/user_thread_directory.dart';

/// Reads the title emphasis emitted by Discuz's `procthread` highlight field.
final class DiscuzThreadTitleStyleParser {
  /// Parses only supported declarations on the title element itself.
  static UserThreadTitleStyle fromHtml(dom.Element title) {
    final declarations = <String, String>{};
    for (final declaration in (title.attributes['style'] ?? '').split(';')) {
      final separator = declaration.indexOf(':');
      if (separator < 0) continue;
      final name = declaration.substring(0, separator).trim().toLowerCase();
      final value = declaration
          .substring(separator + 1)
          .replaceFirst(RegExp(r'\s*!important\s*$', caseSensitive: false), '')
          .trim()
          .toLowerCase();
      declarations[name] = value;
    }
    final weight = declarations['font-weight'];
    return UserThreadTitleStyle(
      colorHex: _color(declarations['color']),
      bold: weight == 'bold' || RegExp(r'^[6-9]00$').hasMatch(weight ?? ''),
      italic: declarations['font-style'] == 'italic',
      underline: (declarations['text-decoration'] ?? '')
          .split(RegExp(r'\s+'))
          .contains('underline'),
    );
  }

  static String? _color(String? value) {
    if (value == null ||
        !RegExp(r'^#(?:[0-9a-f]{3}|[0-9a-f]{6})$').hasMatch(value)) {
      return null;
    }
    if (value.length == 4) {
      return '#${value.substring(1).split('').map((digit) => '$digit$digit').join()}'
          .toUpperCase();
    }
    return value.toUpperCase();
  }
}

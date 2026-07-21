import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/import_novel_pagination_html_fixture.dart '
      '<escaped-html> <output-html>',
    );
    exitCode = 64;
    return;
  }

  final source = File(arguments[0]);
  final output = File(arguments[1]);
  final escaped = (await source.readAsString(encoding: utf8)).trim();
  final decoded = jsonDecode('"$escaped"');
  if (decoded is! String) {
    throw const FormatException(
      'Fixture source must decode to an HTML string.',
    );
  }
  for (final forbidden in const <String>[
    'cookiepre',
    'formhash',
    'member_uid',
    'member_username',
  ]) {
    if (decoded.toLowerCase().contains(forbidden)) {
      throw StateError('Decoded fixture contains forbidden field $forbidden.');
    }
  }
  await output.parent.create(recursive: true);
  await output.writeAsString('$decoded\n', encoding: utf8);
  stdout.writeln('Wrote decoded HTML fixture (${decoded.length} chars).');
}

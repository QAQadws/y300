import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/import_novel_pagination_api_fixture.dart '
      '<captured-json> <output-json> <pid>',
    );
    exitCode = 64;
    return;
  }

  final source = File(arguments[0]);
  final output = File(arguments[1]);
  final targetPid = arguments[2].trim();
  final decoded = jsonDecode(await source.readAsString(encoding: utf8));
  final root = _stringMap(decoded, label: 'root');
  final variables = _stringMap(root['Variables'], label: 'Variables');
  final thread = _stringMap(variables['thread'], label: 'thread');
  final posts = _mapList(variables['postlist'], label: 'postlist');
  final matching = posts
      .where((post) => '${post['pid']}' == targetPid)
      .toList();
  if (matching.length != 1) {
    throw FormatException(
      'Expected exactly one post with pid=$targetPid, found ${matching.length}.',
    );
  }
  final post = matching.single;
  final sanitized = <String, Object?>{
    'Version': '${root['Version'] ?? '1'}',
    'Charset': '${root['Charset'] ?? 'UTF-8'}',
    'FixtureMetadata': <String, Object?>{
      'kind': 'novelPaginationPost',
      'source': 'sanitized structural excerpt from a user-provided capture',
      'requestedPage': 1,
      'originalPostCount': posts.length,
      'sanitizedExcerpt': true,
      'targetPid': targetPid,
      'requestVersion': '1',
    },
    'Variables': <String, Object?>{
      'fid': '${variables['fid'] ?? thread['fid'] ?? ''}',
      'ppp': '${variables['ppp'] ?? '20'}',
      'thread': _pick(thread, const <String>[
        'tid',
        'fid',
        'typeid',
        'subject',
        'author',
        'authorid',
        'replies',
        'allreplies',
        'maxposition',
        'views',
      ]),
      'postlist': <Map<String, Object?>>[
        _pick(post, const <String>[
          'pid',
          'tid',
          'first',
          'author',
          'authorid',
          'dateline',
          'message',
          'anonymous',
          'attachment',
          'status',
          'number',
        ]),
      ],
      'imagelist': const <String>[''],
    },
  };

  final encoded = const JsonEncoder.withIndent('  ').convert(sanitized);
  for (final forbidden in const <String>[
    '"auth"',
    '"saltkey"',
    '"formhash"',
    '"cookiepre"',
    '"member_uid"',
    '"member_username"',
    '"member_avatar"',
  ]) {
    if (encoded.contains(forbidden)) {
      throw StateError('Sanitized fixture still contains $forbidden.');
    }
  }
  await output.parent.create(recursive: true);
  await output.writeAsString('$encoded\n', encoding: utf8);
  stdout.writeln(
    'Wrote sanitized pid=$targetPid fixture (${encoded.length} chars).',
  );
}

Map<String, dynamic> _stringMap(Object? value, {required String label}) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object.');
  }
  return value.map(
    (key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
  );
}

List<Map<String, dynamic>> _mapList(Object? value, {required String label}) {
  if (value is! List) {
    throw FormatException('$label must be a JSON array.');
  }
  return value
      .map((item) => _stringMap(item, label: '$label item'))
      .toList(growable: false);
}

Map<String, Object?> _pick(Map<String, dynamic> source, List<String> keys) {
  return <String, Object?>{
    for (final key in keys)
      if (source.containsKey(key)) key: source[key],
  };
}

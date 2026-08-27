import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test_support/utf8_test_fixture.dart';

const _thisTest = 'test/architecture/test_fixture_boundary_test.dart';

const _metadataOnlyTests = <String>{
  'test/features/thread/domain/html_rendering/'
      'forum_html_sample_document_test.dart',
  'test/features/thread/presentation/html_rendering/'
      'forum_html_renderer_prototype_page_test.dart',
};

void main() {
  test('standard tests never read ignored private forum documents', () {
    final violations = <String>[];
    for (final file in _dartFiles(<String>['test'])) {
      final path = _normalized(file.path);
      if (path == _thisTest) continue;
      final source = file.readAsStringSync();
      if (!_mentionsPrivateDocs(source)) continue;

      if (!_metadataOnlyTests.contains(path)) {
        violations.add('$path references docs outside the metadata allowlist');
        continue;
      }
      if (source.contains("import 'dart:io';") ||
          source.contains('rootBundle.') ||
          source.contains('File(') ||
          source.contains('Directory(')) {
        violations.add('$path reads a metadata-only private source');
      }
    }

    for (final file in _dartFiles(<String>[
      'packages/yamibo_forum_client/test',
    ])) {
      if (_mentionsPrivateDocs(file.readAsStringSync())) {
        violations.add('${_normalized(file.path)} references App-private docs');
      }
    }

    expect(violations, isEmpty);
  });

  test('standard tests never skip because a private fixture is missing', () {
    const forbiddenMarkers = <String>[
      'Local Phase 0 HTML fixture is unavailable',
      'Local prototype asset',
      'skip: fixtureExists',
    ];
    final violations = _dartFiles(<String>['test'])
        .where((file) => _normalized(file.path) != _thisTest)
        .where((file) {
          final source = file.readAsStringSync();
          return forbiddenMarkers.any(source.contains) ||
              (source.contains('markTestSkipped(') &&
                  (source.contains('docs/') ||
                      source.contains('assets/prototypes/forum_html')));
        })
        .map((file) => _normalized(file.path))
        .toList();

    expect(violations, isEmpty);
  });

  test('committed payload fixtures contain no authentication material', () {
    final violations = <String>[];
    for (final file in _payloadFixtureFiles()) {
      final path = _normalized(file.path);
      final source = file.readAsStringSync();
      final lowerSource = source.toLowerCase();

      for (final marker in const <String>[
        'discuz_auth',
        'discuz_uid',
        'cookiepre',
        'reporturl',
      ]) {
        if (lowerSource.contains(marker)) {
          violations.add('$path contains forbidden marker $marker');
        }
      }
      if (RegExp(
        r'^\s*(cookie|set-cookie)\s*:',
        caseSensitive: false,
        multiLine: true,
      ).hasMatch(source)) {
        violations.add('$path contains a Cookie header');
      }
      if (_mentionsPrivateDocs(source)) {
        violations.add('$path contains a private docs path');
      }
      if (_containsNonFixtureFormhash(source)) {
        violations.add('$path contains a non-fixture formhash');
      }
      if (_containsPasswordValue(source)) {
        violations.add('$path contains a non-empty password value');
      }
    }

    expect(violations, isEmpty);
  });

  test('UTF-8 fixture reader stays inside the committed fixture root', () {
    expect(
      readUtf8TestFixture('thread/actions/rate_form.html'),
      contains('fixture-formhash'),
    );
    expect(() => readUtf8TestFixture('../pubspec.yaml'), throwsArgumentError);
    expect(
      () => readUtf8TestFixture('thread/actions/missing.html'),
      throwsStateError,
    );
  });
}

bool _mentionsPrivateDocs(String source) =>
    source.contains('docs/') || source.contains(r'docs\');

bool _containsNonFixtureFormhash(String source) {
  final inputPattern = RegExp(r'<input\b[^>]*>', caseSensitive: false);
  final formhashNamePattern = RegExp(
    r'''\bname\s*=\s*["']formhash["']''',
    caseSensitive: false,
  );
  final valuePattern = RegExp(
    r'''\bvalue\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  );
  for (final match in inputPattern.allMatches(source)) {
    final tag = match.group(0)!;
    if (!formhashNamePattern.hasMatch(tag)) continue;
    final value = valuePattern.firstMatch(tag)?.group(1) ?? '';
    if (!_isFixtureSecret(value)) return true;
  }

  final jsonPattern = RegExp(
    r'''["']formhash["']\s*:\s*["']([^"']*)["']''',
    caseSensitive: false,
  );
  return jsonPattern
      .allMatches(source)
      .any((match) => !_isFixtureSecret(match.group(1) ?? ''));
}

bool _containsPasswordValue(String source) {
  final inputPattern = RegExp(r'<input\b[^>]*>', caseSensitive: false);
  final passwordNamePattern = RegExp(
    r'''\bname\s*=\s*["'][^"']*pass(?:word|wd)[^"']*["']''',
    caseSensitive: false,
  );
  final valuePattern = RegExp(
    r'''\bvalue\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  );
  for (final match in inputPattern.allMatches(source)) {
    final tag = match.group(0)!;
    if (!passwordNamePattern.hasMatch(tag)) continue;
    if ((valuePattern.firstMatch(tag)?.group(1) ?? '').isNotEmpty) return true;
  }

  final jsonPattern = RegExp(
    r'''["'][^"']*pass(?:word|wd)[^"']*["']\s*:\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  return jsonPattern.hasMatch(source);
}

bool _isFixtureSecret(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('fixture-') || normalized.startsWith('test-');
}

Iterable<File> _payloadFixtureFiles() sync* {
  final root = Directory('test/fixtures');
  if (!root.existsSync()) return;
  for (final file
      in root.listSync(recursive: true, followLinks: false).whereType<File>()) {
    final name = file.uri.pathSegments.last.toLowerCase();
    if (name == 'manifest.json') continue;
    if (name.endsWith('.html') ||
        name.endsWith('.xml') ||
        name.endsWith('.json')) {
      yield file;
    }
  }
}

Iterable<File> _dartFiles(Iterable<String> roots) sync* {
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    yield* directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
  }
}

String _normalized(String path) => path.replaceAll('\\', '/');

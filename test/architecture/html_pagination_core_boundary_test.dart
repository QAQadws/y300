import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _root = 'packages/html_pagination_core';
const _lib = '$_root/lib/';
const _entry = 'package:html_pagination_core/html_pagination_core.dart';
const _barrel = '${_lib}html_pagination_core.dart';
const _retiredDomIndex =
    'lib/features/novel/presentation/services/novel_reader_html_dom_text_index.dart';
const _temporaryRoots = {
  'lib/core/html_pagination_core',
  'lib/features/novel/presentation/pagination_core',
};
const _pureSdk = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};
const _runtimeEntries = {
  'package:characters/characters.dart',
  'package:html/dom.dart',
  'package:html/parser.dart',
};

enum _Scope { app, library, consumer }

void main() {
  test('App uses one public pagination entry and retires temporary cores', () {
    expect(_violations(['lib', 'test'], _Scope.app), isEmpty);
    expect(File(_retiredDomIndex).existsSync(), isFalse);
    expect(
      _temporaryRoots.where((root) => Directory(root).existsSync()),
      isEmpty,
    );
  });

  test('pagination library stays pure with one explicit public barrel', () {
    expect(_violations(['$_root/lib'], _Scope.library), isEmpty);
    expect(
      _files('$_root/lib')
          .map((file) => normalizeDartSourcePath(file.path))
          .where((path) => !path.startsWith('${_lib}src/')),
      [_barrel],
    );
    final source = File(_barrel).readAsStringSync(encoding: utf8);
    final shows = dartExportShowLists(source).toList();
    expect(shows, isNotEmpty);
    expect(shows, everyElement(isNotNull));
    expect(shows, everyElement(isNotEmpty));
    for (final uri in dartDependencyDirectiveUris(source)) {
      final target = _target(_barrel, uri);
      expect(target, startsWith('${_lib}src/'));
      expect(File(target).existsSync(), isTrue, reason: target);
    }
  });

  test(
    'manifest keeps only the two pure runtime dependencies and no Flutter',
    () {
      expect(
        _manifestViolations(
          File('$_root/pubspec.yaml').readAsStringSync(encoding: utf8),
        ),
        isEmpty,
      );
    },
  );

  test('package tests and example use public API and own pure fixtures', () {
    expect(
      _violations(['$_root/test', '$_root/example'], _Scope.consumer),
      isEmpty,
    );
  });

  test('boundary rules reject bypasses while preserving Host adapters', () {
    expect(
      _forbidden('lib/new_adapter.dart', '''
import '$_entry' if (dart.library.io == 'true') 'package:html_pagination_core/src/private.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_fit_searcher.dart';
export 'core/temporary/../html_pagination_core/model.dart';
import '../packages/html_pagination_core/test/fixture.dart';
''', _Scope.app),
      {
        '${_lib}src/private.dart',
        'lib/core/html_pagination_core/model.dart',
        '$_root/test/fixture.dart',
      },
    );
    expect(
      _forbidden('${_lib}src/new_policy.dart', '''
import 'package:html/dom.dart';
export 'dart:collection' if (dart.library.ui) 'dart:ui';
part '../../test/host.dart';
import 'package:y300/app.dart';
import 'package:characters/src/characters_impl.dart';
''', _Scope.library),
      {
        'dart:ui',
        '$_root/test/host.dart',
        'lib/app.dart',
        'package:characters/src/characters_impl.dart',
      },
    );
    expect(
      _forbidden('$_root/test/new_test.dart', '''
import '$_entry';
import 'package:test/test.dart';
import 'fixtures/input.dart';
import '../lib/html_pagination_core.dart';
import '../../../test/root_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
''', _Scope.consumer),
      {
        _barrel,
        'test/root_fixture.dart',
        'package:flutter_test/flutter_test.dart',
        'dart:io',
      },
    );
    expect(
      _manifestViolations(
        'dependencies: {characters: any, html: any}\ndev_dependencies:\n  test: any',
      ),
      isEmpty,
    );
    for (final manifest in [
      'dependencies: {characters: any, html: any, http: any}',
      'dependencies:\n  characters: any\n  html: any\n  local:\n    path: ../app',
      'dependencies: {characters: any, html: any}\ndev_dependencies:\n  flutter_test:\n    sdk: flutter',
    ]) {
      expect(_manifestViolations(manifest), isNotEmpty);
    }
  });
}

Iterable<File> _files(String root) {
  final files = Directory(root)
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
  expect(files, isNotEmpty, reason: 'Missing Dart sources: $root');
  return files;
}

Iterable<String> _violations(List<String> roots, _Scope scope) sync* {
  for (final root in roots) {
    for (final file in _files(root)) {
      final source = normalizeDartSourcePath(file.path);
      for (final target in _forbidden(
        source,
        file.readAsStringSync(encoding: utf8),
        scope,
      )) {
        yield '$source -> $target';
      }
    }
  }
}

Set<String> _forbidden(String source, String text, _Scope scope) => {
  for (final uri in dartDependencyDirectiveUris(text))
    if (!_allowed(uri, _target(source, uri), scope)) _target(source, uri),
};

String _target(String source, String uri) =>
    uri.startsWith('package:html_pagination_core/')
    ? normalizeDartSourcePath(
        '$_lib${uri.substring('package:html_pagination_core/'.length)}',
      )
    : resolveDartDependencyTarget(source, uri);

bool _allowed(String uri, String target, _Scope scope) {
  if (scope == _Scope.library) {
    return _pureSdk.contains(target) ||
        _runtimeEntries.contains(target) ||
        target.startsWith(_lib);
  }
  if (uri == 'package:html_pagination_core' ||
      uri.startsWith('package:html_pagination_core/')) {
    return uri == _entry;
  }
  if (scope == _Scope.app) {
    return target != _retiredDomIndex &&
        !target.startsWith('$_root/') &&
        !_temporaryRoots.any(
          (root) => target == root || target.startsWith('$root/'),
        );
  }
  // Pure synthetic fixtures need no file I/O; this also prevents runtime reads
  // of App fixtures that an import-only boundary could not detect.
  return _pureSdk.contains(target) ||
      _runtimeEntries.contains(target) ||
      target == 'package:test/test.dart' ||
      target.startsWith('$_root/test/') ||
      target.startsWith('$_root/example/');
}

List<String> _manifestViolations(String source) {
  final violations = <String>[];
  final dependencies = <String>{};
  var runtime = false;
  for (final raw in source.split('\n')) {
    final line = raw.split('#').first.trimRight();
    if (line.trim().isEmpty) continue;
    final indented = line.startsWith(' ') || line.startsWith('\t');
    if (!indented) runtime = line.startsWith('dependencies:');
    if (runtime) {
      final entries = indented ? line : line.substring('dependencies:'.length);
      for (final match in RegExp(r'([a-zA-Z_]\w*)\s*:').allMatches(entries)) {
        final name = match.group(1)!;
        dependencies.add(name);
        if (!{'characters', 'html'}.contains(name)) violations.add(line);
      }
    }
    if (RegExp(r'^\s*flutter:|\bsdk:\s*flutter\b').hasMatch(line)) {
      violations.add(line);
    }
  }
  if (!dependencies.containsAll({'characters', 'html'})) {
    violations.add('Missing pure runtime dependencies');
  }
  return violations;
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _packageRoot = 'packages/comic_title_core';
const _packageLib = '$_packageRoot/lib/';
const _publicEntry = 'package:comic_title_core/comic_title_core.dart';
const _publicSource = '${_packageLib}comic_title_core.dart';
const _parserEntry = 'package:petitparser/petitparser.dart';
const _pureSdkLibraries = <String>{
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};
const _retiredCorePaths = <String>{
  'lib/features/comic/domain/services/title/comic_title_analysis.dart',
  'lib/features/comic/domain/services/title/comic_title_analyzer.dart',
  'lib/features/comic/domain/services/title/comic_title_grammar.dart',
  'lib/features/comic/domain/services/title/comic_title_number_parser.dart',
  'lib/features/comic/domain/services/title/comic_title_rules.dart',
};

enum _Scope { app, packageLibrary, packageConsumer }

void main() {
  test('App and App tests use the sole title package entry', () {
    expect(_violations(['lib', 'test'], _Scope.app), isEmpty);
  });

  test('the five retired App title core files are not reintroduced', () {
    expect(
      _retiredCorePaths.where((path) => File(path).existsSync()),
      isEmpty,
      reason: 'The package owns the only title core definitions.',
    );
  });

  test(
    'title production depends only on pure Dart, its lib and petitparser',
    () {
      expect(
        _violations(['$_packageRoot/lib'], _Scope.packageLibrary),
        isEmpty,
      );
    },
  );

  test('the title package has one public barrel outside src', () {
    final entries =
        _dartFiles('$_packageRoot/lib')
            .map((file) => normalizeDartSourcePath(file.path))
            .where((path) => !path.startsWith('${_packageLib}src/'))
            .toList()
          ..sort();
    expect(entries, [_publicSource]);
  });

  test('package tests and example do not depend on App or root fixtures', () {
    expect(
      _violations([
        '$_packageRoot/test',
        '$_packageRoot/example',
      ], _Scope.packageConsumer),
      isEmpty,
    );
  });

  test('conditional URIs cannot hide private or impure dependencies', () {
    expect(
      _forbiddenTargets('lib/new_adapter.dart', '''
import '$_publicEntry'
  if (dart.library.io == 'true')
    'package:comic_title_core/src/comic_title_analyzer.dart';
export '$_publicEntry'
  if (dart.library.html) 'package:comic_title_core/other_entry.dart';
''', _Scope.app),
      {
        '${_packageLib}src/comic_title_analyzer.dart',
        '${_packageLib}other_entry.dart',
      },
    );
    expect(
      _forbiddenTargets('${_packageLib}src/new_grammar.dart', '''
import '$_parserEntry'
  if (dart.library.io == 'true') 'dart:io'
  if (dart.library.ui) 'package:flutter/widgets.dart';
export 'dart:collection'
  if (dart.library.html) 'package:y300/core/config/app_config.dart';
import 'package:dio/dio.dart';
import 'package:petitparser/src/parser/parser.dart';
''', _Scope.packageLibrary),
      {
        'dart:io',
        'package:flutter/widgets.dart',
        'lib/core/config/app_config.dart',
        'package:dio/dio.dart',
        'package:petitparser/src/parser/parser.dart',
      },
    );
  });

  test('relative paths enforce ownership and standalone package fixtures', () {
    expect(
      _forbiddenTargets(
        'lib/features/comic/domain/services/new_policy.dart',
        '''
import 'title/comic_title_rules.dart';
export 'package:y300/features/comic/domain/services/title/comic_title_rules.dart';
import '../../../../../packages/comic_title_core/lib/comic_title_core.dart';
import '../../../../../packages/comic_title_core/lib/src/comic_title_rules.dart';
''',
        _Scope.app,
      ),
      {
        'lib/features/comic/domain/services/title/comic_title_rules.dart',
        _publicSource,
        '${_packageLib}src/comic_title_rules.dart',
      },
    );
    expect(
      _forbiddenTargets('${_packageLib}src/new_grammar.dart', '''
import './comic_title_rules.dart';
export 'package:comic_title_core/src/comic_title_analysis.dart';
import '../../test/support.dart';
import '../../../../lib/features/comic/domain/models/comic_models.dart';
''', _Scope.packageLibrary),
      {
        '$_packageRoot/test/support.dart',
        'lib/features/comic/domain/models/comic_models.dart',
      },
    );
    expect(
      _forbiddenTargets('$_packageRoot/test/core_test.dart', '''
import '$_publicEntry';
import 'package:test/test.dart';
import 'fixtures/generated_cases.dart';
import '../../../test/features/comic/domain/services/comic_title_parser_cases.dart';
export 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:flutter_test/flutter_test.dart';
''', _Scope.packageConsumer),
      {
        'test/features/comic/domain/services/comic_title_parser_cases.dart',
        'lib/features/comic/domain/models/comic_models.dart',
        'package:flutter_test/flutter_test.dart',
      },
    );
  });

  test(
    'comments and source strings are ignored while legal URIs remain allowed',
    () {
      const example = '''
// import 'package:flutter/widgets.dart';
/* outer /* inner */ import 'dart:io'; */
const sample = """
export 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';
""";
const rawSample = r"import 'package:comic_title_core/src/private.dart';";
''';
      expect(
        _forbiddenTargets('lib/new_adapter.dart', '''
$example
import '$_publicEntry' show ComicTitleAnalyzer;
import 'package:y300/features/comic/domain/models/comic_models.dart';
''', _Scope.app),
        isEmpty,
      );
      expect(
        _forbiddenTargets('${_packageLib}src/new_grammar.dart', '''
$example
import 'dart:collection';
import '$_parserEntry';
export 'comic_title_rules.dart';
''', _Scope.packageLibrary),
        isEmpty,
      );
    },
  );
}

Iterable<File> _dartFiles(String root) {
  final directory = Directory(root);
  expect(directory.existsSync(), isTrue, reason: 'Missing source root: $root');
  final files = directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  expect(files, isNotEmpty, reason: 'No Dart source in $root');
  return files;
}

List<String> _violations(List<String> roots, _Scope scope) {
  final violations = <String>[];
  for (final root in roots) {
    for (final file in _dartFiles(root)) {
      final source = normalizeDartSourcePath(file.path);
      for (final target in _forbiddenTargets(
        source,
        file.readAsStringSync(encoding: utf8),
        scope,
      )) {
        violations.add('$source -> $target');
      }
    }
  }
  return violations..sort();
}

Set<String> _forbiddenTargets(String source, String text, _Scope scope) => {
  for (final uri in dartDependencyDirectiveUris(text))
    if (!_isAllowed(uri, _resolveTarget(source, uri), scope))
      _resolveTarget(source, uri),
};

String _resolveTarget(String source, String uri) {
  const ownPackage = 'package:comic_title_core/';
  if (uri.startsWith(ownPackage)) {
    return normalizeDartSourcePath(
      '$_packageLib${uri.substring(ownPackage.length)}',
    );
  }
  return resolveDartDependencyTarget(source, uri);
}

bool _isAllowed(String uri, String target, _Scope scope) {
  if (scope == _Scope.app) {
    if (_retiredCorePaths.contains(target)) return false;
    if (uri == 'package:comic_title_core' ||
        uri.startsWith('package:comic_title_core/')) {
      return uri == _publicEntry;
    }
    // Require the canonical package URI even for relative barrel imports.
    return !target.startsWith(_packageLib);
  }
  if (scope == _Scope.packageLibrary) {
    return _pureSdkLibraries.contains(target) ||
        target == _parserEntry ||
        target.startsWith(_packageLib);
  }
  return (target.startsWith('dart:') && target != 'dart:ui') ||
      target == 'package:test/test.dart' ||
      target == _parserEntry ||
      target.startsWith('$_packageRoot/');
}

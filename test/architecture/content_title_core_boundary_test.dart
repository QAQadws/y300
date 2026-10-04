import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _packageRoot = 'packages/content_title_core';
const _packageLib = '$_packageRoot/lib/';
const _publicEntry = 'package:content_title_core/content_title_core.dart';
const _publicSource = '${_packageLib}content_title_core.dart';
const _retiredPackageRoot = 'packages/comic_title_core';
const _runtimePackageEntries = <String>{
  'package:petitparser/petitparser.dart',
  'package:characters/characters.dart',
};
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
  'lib/features/novel/domain/services/novel_title_sanitizer.dart',
  'lib/features/novel/domain/services/novel_chapter_title_policy.dart',
};

// The existing novel fixture facade forwards this exact source. Production and
// other App tests must not depend directly on the package's test directory.
const _fixtureBridgeTargets = <String, String>{
  'test/features/novel/test_support/novel_title_fixtures.dart':
      '$_packageRoot/test/fixtures/novel_title_fixtures.dart',
};

enum _Scope { appProduction, appTest, packageLibrary, packageConsumer }

void main() {
  test('App production uses the sole title package entry', () {
    expect(_violations(['lib'], _Scope.appProduction), isEmpty);
  });

  test('App tests use the public entry or exact fixture bridges', () {
    expect(_violations(['test'], _Scope.appTest), isEmpty);
  });

  test('retired title files and the renamed package are not reintroduced', () {
    expect(
      _retiredCorePaths.where((path) => File(path).existsSync()),
      isEmpty,
      reason: 'The package owns the only title core definitions.',
    );
    expect(Directory(_retiredPackageRoot).existsSync(), isFalse);
  });

  test(
    'title production depends only on pure Dart, its lib and allowed packages',
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
    'package:content_title_core/src/comic/comic_title_analyzer.dart';
export '$_publicEntry'
  if (dart.library.html) 'package:content_title_core/other_entry.dart';
''', _Scope.appProduction),
      {
        '${_packageLib}src/comic/comic_title_analyzer.dart',
        '${_packageLib}other_entry.dart',
      },
    );
    expect(
      _forbiddenTargets('${_packageLib}src/new_grammar.dart', '''
import 'package:petitparser/petitparser.dart'
  if (dart.library.io == 'true') 'dart:io'
  if (dart.library.ui) 'package:flutter/widgets.dart';
export 'dart:collection'
  if (dart.library.html) 'package:y300/core/config/app_config.dart';
import 'package:dio/dio.dart';
import 'package:petitparser/src/parser/parser.dart';
import 'package:characters/src/characters_impl.dart';
''', _Scope.packageLibrary),
      {
        'dart:io',
        'package:flutter/widgets.dart',
        'lib/core/config/app_config.dart',
        'package:dio/dio.dart',
        'package:petitparser/src/parser/parser.dart',
        'package:characters/src/characters_impl.dart',
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
import 'package:y300/features/novel/domain/services/novel_title_sanitizer.dart';
export 'package:y300/features/novel/domain/services/novel_chapter_title_policy.dart';
import '../../../../../packages/content_title_core/lib/content_title_core.dart';
import '../../../../../packages/content_title_core/lib/src/comic_title_rules.dart';
''',
        _Scope.appProduction,
      ),
      {
        'lib/features/comic/domain/services/title/comic_title_rules.dart',
        'lib/features/novel/domain/services/novel_title_sanitizer.dart',
        'lib/features/novel/domain/services/novel_chapter_title_policy.dart',
        _publicSource,
        '${_packageLib}src/comic_title_rules.dart',
      },
    );
    expect(
      _forbiddenTargets('${_packageLib}src/new_grammar.dart', '''
import './comic_title_rules.dart';
export 'package:content_title_core/src/comic_title_analysis.dart';
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

  test('only the exact App novel fixture bridge may enter package tests', () {
    for (final bridge in _fixtureBridgeTargets.entries) {
      final targetUri = '../../../../${bridge.value}';
      expect(
        _forbiddenTargets(bridge.key, "export '$targetUri';", _Scope.appTest),
        isEmpty,
      );
      expect(
        _forbiddenTargets(
          bridge.key,
          "export '${targetUri.replaceFirst('fixtures/', 'other_fixtures/')}';",
          _Scope.appTest,
        ),
        {bridge.value.replaceFirst('fixtures/', 'other_fixtures/')},
      );
      expect(
        _forbiddenTargets(
          'lib/new_adapter.dart',
          "import '../${bridge.value}';",
          _Scope.appProduction,
        ),
        {bridge.value},
      );
      expect(
        _forbiddenTargets(
          'test/new_test.dart',
          "import '../${bridge.value}';",
          _Scope.appTest,
        ),
        {bridge.value},
      );
    }
    expect(
      _forbiddenTargets(
        'test/features/comic/domain/services/comic_title_parser_cases.dart',
        "export '../../../../../$_packageRoot/test/fixtures/comic_title_fixtures.dart';",
        _Scope.appTest,
      ),
      {'$_packageRoot/test/fixtures/comic_title_fixtures.dart'},
    );
  });

  test('old package URIs and relative paths are rejected in every scope', () {
    for (final scope in _Scope.values) {
      expect(
        _forbiddenTargets('$_packageRoot/test/new_test.dart', '''
import 'package:comic_title_core/comic_title_core.dart';
export 'package:comic_title_core/src/comic_title_analysis.dart';
import '../../comic_title_core/lib/comic_title_core.dart';
import 'package:comic_title_core';
''', scope),
        {
          '$_retiredPackageRoot/lib/comic_title_core.dart',
          '$_retiredPackageRoot/lib/src/comic_title_analysis.dart',
          'package:comic_title_core',
        },
      );
    }
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
''', _Scope.appProduction),
        isEmpty,
      );
      expect(
        _forbiddenTargets('${_packageLib}src/new_grammar.dart', '''
$example
import 'dart:collection';
import 'package:petitparser/petitparser.dart';
import 'package:characters/characters.dart';
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
    if (!_isAllowed(source, uri, _resolveTarget(source, uri), scope))
      _resolveTarget(source, uri),
};

String _resolveTarget(String source, String uri) {
  const ownPackage = 'package:content_title_core/';
  if (uri.startsWith(ownPackage)) {
    return normalizeDartSourcePath(
      '$_packageLib${uri.substring(ownPackage.length)}',
    );
  }
  const retiredPackage = 'package:comic_title_core/';
  if (uri.startsWith(retiredPackage)) {
    return normalizeDartSourcePath(
      '$_retiredPackageRoot/lib/${uri.substring(retiredPackage.length)}',
    );
  }
  return resolveDartDependencyTarget(source, uri);
}

bool _isAllowed(String source, String uri, String target, _Scope scope) {
  if (uri == 'package:comic_title_core' ||
      uri.startsWith('package:comic_title_core/') ||
      target == _retiredPackageRoot ||
      target.startsWith('$_retiredPackageRoot/')) {
    return false;
  }
  if (scope == _Scope.appProduction || scope == _Scope.appTest) {
    if (_retiredCorePaths.contains(target)) return false;
    if (uri == 'package:content_title_core' ||
        uri.startsWith('package:content_title_core/')) {
      return uri == _publicEntry;
    }
    // Require the canonical package URI even for relative barrel imports.
    if (target.startsWith('$_packageRoot/')) {
      return scope == _Scope.appTest && _fixtureBridgeTargets[source] == target;
    }
    return true;
  }
  if (scope == _Scope.packageLibrary) {
    return _pureSdkLibraries.contains(target) ||
        _runtimePackageEntries.contains(target) ||
        target.startsWith(_packageLib);
  }
  return (target.startsWith('dart:') && target != 'dart:ui') ||
      target == 'package:test/test.dart' ||
      _runtimePackageEntries.contains(target) ||
      target.startsWith('$_packageRoot/');
}

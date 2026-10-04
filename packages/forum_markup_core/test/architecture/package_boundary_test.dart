import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _publicEntry = 'lib/forum_markup_core.dart';
const _sdkLibraries = <String>{
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};

void main() {
  test('production markup depends only on pure Dart and its own source', () {
    final files = _libraryFiles();
    expect(files, isNotEmpty, reason: 'The package lib root must exist.');
    final violations = <String>[];
    for (final file in files) {
      final source = _normalizePath(file.path);
      for (final target in _forbiddenTargets(
        source,
        file.readAsStringSync(encoding: utf8),
      )) {
        violations.add('$source -> $target');
      }
    }
    expect(violations..sort(), isEmpty);
  });

  test('only one Dart entrypoint is exposed outside src', () {
    final publicFiles =
        _libraryFiles()
            .map((file) => _normalizePath(file.path))
            .where((path) => !path.startsWith('lib/src/'))
            .toList()
          ..sort();
    expect(publicFiles, [_publicEntry]);
  });

  test('the public barrel points to existing internal source', () {
    final targets = _dependencyUris(
      File(_publicEntry).readAsStringSync(encoding: utf8),
    ).map((uri) => _resolveTarget(_publicEntry, uri)).toList();
    expect(targets, isNotEmpty);
    for (final target in targets) {
      expect(target, startsWith('lib/src/'));
      expect(File(target).existsSync(), isTrue, reason: target);
    }
  });

  test('the manifest has no runtime dependencies or Flutter SDK', () {
    expect(
      _manifestViolations(
        File('pubspec.yaml').readAsStringSync(encoding: utf8),
      ),
      isEmpty,
    );
  });

  test('conditional directives cannot hide platform or network imports', () {
    expect(
      _forbiddenTargets('lib/src/new_grammar.dart', '''
import 'dart:collection'
  if (dart.library.io == 'true') 'dart:io'
  if (dart.library.html) 'dart:html';
export 'composer_collapse_models.dart'
  if (dart.library.ui) 'package:flutter/widgets.dart';
import 'package:dio/dio.dart';
import 'package:y300/features/composer_shared/domain/models/app_model.dart';
'''),
      {
        'dart:io',
        'dart:html',
        'package:flutter/widgets.dart',
        'package:dio/dio.dart',
        'package:y300/features/composer_shared/domain/models/app_model.dart',
      },
    );
  });

  test('relative source cannot escape the package lib boundary', () {
    expect(
      _forbiddenTargets('lib/src/new_grammar.dart', r'''
import '../src/composer_collapse_models.dart';
import 'package:forum_markup_core/src/composer_collapse_models.dart';
import '../../test/support.dart';
export '../../../../lib/features/composer_shared/domain/models/app_model.dart';
import '\u002e\u002e/escaped_source.dart';
'''),
      {
        'test/support.dart',
        '../../lib/features/composer_shared/domain/models/app_model.dart',
        r'\u002e\u002e/escaped_source.dart',
      },
    );
  });

  test('comments and quoted examples are not runtime dependencies', () {
    expect(
      _forbiddenTargets('lib/src/new_grammar.dart', '''
// import 'dart:io';
/* export 'package:flutter/widgets.dart'; */
/* outer /* inner */ import 'dart:io'; */
import 'dart:collection';
import 'composer_collapse_models.dart';
const example = """import 'package:y300/app.dart';""";
const rawExample = r"export 'package:dio/dio.dart';";
'''),
      isEmpty,
    );
  });

  test('runtime manifest constraints reject block and inline dependencies', () {
    for (final source in [
      'dependencies:\n  http: ^1.0.0\n',
      'dependencies: {http: ^1.0.0}\n',
      'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n',
    ]) {
      expect(_manifestViolations(source), isNotEmpty, reason: source);
    }
    expect(
      _manifestViolations('''
dependencies: {}
dev_dependencies:
  test: ^1.26.0
  lints: ^6.0.0
'''),
      isEmpty,
    );
  });
}

List<File> _libraryFiles() => Directory('lib')
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .toList();

Set<String> _forbiddenTargets(String sourcePath, String source) => {
  for (final uri in _dependencyUris(source))
    if (!_isAllowed(_resolveTarget(sourcePath, uri)))
      _resolveTarget(sourcePath, uri),
};

bool _isAllowed(String target) =>
    _sdkLibraries.contains(target) || target.startsWith('lib/');

String _resolveTarget(String source, String target) {
  // Require plain URI spellings instead of partially interpreting Dart escapes.
  if (target.contains('\\')) return target;
  const ownPackage = 'package:forum_markup_core/';
  if (target.startsWith(ownPackage)) {
    return _normalizePath('lib/${target.substring(ownPackage.length)}');
  }
  if (Uri.parse(target).hasScheme || target.startsWith('/')) return target;
  final normalizedSource = _normalizePath(source);
  final directory = normalizedSource.substring(
    0,
    normalizedSource.lastIndexOf('/') + 1,
  );
  return _normalizePath('$directory$target');
}

String _normalizePath(String path) {
  final segments = <String>[];
  for (final segment in path.replaceAll('\\', '/').split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..' && segments.isNotEmpty && segments.last != '..') {
      segments.removeLast();
    } else {
      segments.add(segment);
    }
  }
  return segments.join('/');
}

List<String> _manifestViolations(String source) {
  final violations = <String>[];
  var inRuntimeDependencies = false;
  for (final rawLine in source.split('\n')) {
    final line = rawLine.split('#').first.trimRight();
    if (line.trim().isEmpty) continue;
    if (line.startsWith('dependencies:')) {
      final inline = line.substring('dependencies:'.length).trim();
      inRuntimeDependencies = inline.isEmpty;
      if (inline.isNotEmpty && inline != '{}') violations.add(line);
    } else if (!line.startsWith(' ') && !line.startsWith('\t')) {
      inRuntimeDependencies = false;
    } else if (inRuntimeDependencies) {
      violations.add(line.trim());
    }
    if (line.trimLeft().startsWith('flutter:') ||
        RegExp(r'^\s*sdk:\s*flutter\b').hasMatch(line)) {
      violations.add(line.trim());
    }
  }
  return violations;
}

// Tokenize only what URI directives need; examples remain one string token.
// This package test is self-contained and never reads Y300's test helpers.
Iterable<String> _dependencyUris(String source) sync* {
  final tokenPattern = RegExp(
    r'//[^\r\n]*|'
    'r?"""[\\s\\S]*?"""|'
    "r?'''[\\s\\S]*?'''|"
    r'''r?"(?:\\.|[^"\\])*"|'''
    r"r?'(?:\\.|[^'\\])*'|"
    r'[A-Za-z_$][A-Za-z0-9_$]*|[();]',
  );
  final tokens = <String>[];
  var cursor = 0;
  while (cursor < source.length) {
    if (source.startsWith('/*', cursor)) {
      var depth = 1;
      cursor += 2;
      // Quotes have no special meaning inside a Dart block comment.
      while (cursor < source.length && depth > 0) {
        if (source.startsWith('/*', cursor)) {
          depth++;
          cursor += 2;
        } else if (source.startsWith('*/', cursor)) {
          depth--;
          cursor += 2;
        } else {
          cursor++;
        }
      }
      continue;
    }
    final match = tokenPattern.matchAsPrefix(source, cursor);
    if (match == null) {
      cursor++;
      continue;
    }
    final token = match[0]!;
    cursor = match.end;
    if (!token.startsWith('//')) tokens.add(token);
  }
  for (var index = 0; index < tokens.length; index++) {
    if (!{'import', 'export', 'part'}.contains(tokens[index])) continue;
    var parentheses = 0;
    while (++index < tokens.length && tokens[index] != ';') {
      final token = tokens[index];
      if (token == '(') {
        parentheses++;
      } else if (token == ')') {
        parentheses--;
      } else if (parentheses == 0) {
        final quoteIndex = token.startsWith('r') ? 1 : 0;
        if (token.length <= quoteIndex ||
            (token[quoteIndex] != '"' && token[quoteIndex] != "'")) {
          continue;
        }
        final quote = token[quoteIndex];
        final delimiterLength = token.startsWith(quote * 3, quoteIndex) ? 3 : 1;
        yield token.substring(
          quoteIndex + delimiterLength,
          token.length - delimiterLength,
        );
      }
    }
  }
}

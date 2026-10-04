import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _publicEntry = 'lib/continuous_image_geometry.dart';
const _sdkLibraries = <String>{
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};
const _publicGeometryTypes = <String>{
  'ContinuousImageDimensionSource',
  'ContinuousImageDimensions',
  'ContinuousImageExtent',
  'ContinuousImageLayoutHint',
  'ContinuousImageLayoutItem',
  'ContinuousImageScrollDirection',
  'ContinuousImageViewportState',
  'ContinuousImageExtentRegistry',
  'InMemoryContinuousImageExtentRegistry',
  'ContinuousImageLayoutIndex',
  'ContinuousImageDimensionCandidate',
  'ContinuousImageLayoutResolver',
  'ContinuousImageScrollAnchorCoordinator',
  'ContinuousImageScrollAnchorMetrics',
  'ContinuousImageScrollCompensationPlan',
  'ContinuousImageScrollCompensationTiming',
};

void main() {
  test('production geometry depends only on pure Dart and its own source', () {
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

  test('the public barrel exports only the agreed geometry contracts', () {
    final source = File(_publicEntry).readAsStringSync(encoding: utf8);
    final targets = _dependencyUris(
      source,
    ).map((uri) => _resolveTarget(_publicEntry, uri)).toList();
    expect(targets, isNotEmpty);
    for (final target in targets) {
      expect(target, startsWith('lib/src/'));
      expect(File(target).existsSync(), isTrue, reason: target);
    }
    expect(_publicApiViolations(source), isEmpty);
  });

  test('the manifest has no runtime dependencies or Flutter SDK', () {
    expect(
      _manifestViolations(
        File('pubspec.yaml').readAsStringSync(encoding: utf8),
      ),
      isEmpty,
    );
  });

  test('platform imports and relative paths cannot escape pure lib', () {
    expect(
      _forbiddenTargets('lib/src/new_geometry.dart', r'''
import 'dart:collection'
  if (dart.library.io == 'true') 'dart:io'
  if (dart.library.html) 'dart:html';
export 'continuous_image_geometry_models.dart'
  if (dart.library.ui) 'package:flutter/widgets.dart';
import 'package:dio/dio.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image_models.dart';
import '../../test/support.dart';
import '\u002e\u002e/escaped_source.dart';
'''),
      {
        'dart:io',
        'dart:html',
        'package:flutter/widgets.dart',
        'package:dio/dio.dart',
        'package:y300/features/reader_shared/domain/continuous_image/continuous_image_models.dart',
        'test/support.dart',
        r'\u002e\u002e/escaped_source.dart',
      },
    );
  });

  test(
    'host metadata and reader orchestration cannot enter the public API',
    () {
      const hostTypes = <String>[
        'ContinuousImageItem',
        'ContinuousImageSourceKind',
        'ContinuousImageFlowPolicy',
        'ContinuousImageDimensionSink',
        'ReaderSequencePosition',
        'TallImagePolicy',
        'TallImageSliceManifest',
        'ContinuousImagePrefetchCoordinator',
        'ContinuousImageDiagnosticRecorder',
        'ReaderImageSessionCoordinator',
      ];
      expect(
        _publicApiViolations(
          "export 'src/host.dart' show ${hostTypes.join(', ')};",
        ),
        hostTypes.toSet(),
      );
      expect(_publicApiViolations("export 'src/host.dart';"), {
        'export without an explicit show list',
      });
      expect(
        _publicApiViolations('''
export 'src/geometry.dart'
  show ContinuousImageDimensionSource, ContinuousImageLayoutItem;
'''),
        isEmpty,
      );
    },
  );

  test('comments and quoted examples do not create boundary violations', () {
    const source = '''
// import 'dart:io';
/* outer /* inner */ export 'package:flutter/widgets.dart'; */
import 'dart:collection';
import 'continuous_image_geometry_models.dart';
const example = """export 'src/host.dart' show ContinuousImageItem;""";
const rawExample = r"import 'package:y300/app.dart';";
''';
    expect(_forbiddenTargets('lib/src/new_geometry.dart', source), isEmpty);
    expect(_publicApiViolations(source), isEmpty);
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
  const ownPackage = 'package:continuous_image_geometry/';
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

// Guard the explicit API rather than searching geometry variables for host
// keywords: opaque IDs and physical dimension provenance belong in this core.
Set<String> _publicApiViolations(String source) {
  final violations = <String>{};
  final tokens = _sourceTokens(source).toList();
  for (var index = 0; index < tokens.length; index++) {
    if (tokens[index] != 'export') continue;
    var showing = false;
    var hasShow = false;
    while (++index < tokens.length && tokens[index] != ';') {
      final token = tokens[index];
      if (token == 'show') {
        showing = true;
        hasShow = true;
      } else if (token == 'hide') {
        showing = false;
      } else if (showing && !_publicGeometryTypes.contains(token)) {
        violations.add(token);
      }
    }
    if (!hasShow) violations.add('export without an explicit show list');
  }
  return violations;
}

// Self-contained tokenization keeps the package independent of App test helpers.
Iterable<String> _sourceTokens(String source) sync* {
  final tokenPattern = RegExp(
    r'//[^\r\n]*|'
    'r?"""[\\s\\S]*?"""|'
    "r?'''[\\s\\S]*?'''|"
    r'''r?"(?:\\.|[^"\\])*"|'''
    r"r?'(?:\\.|[^'\\])*'|"
    r'[A-Za-z_$][A-Za-z0-9_$]*|[();]',
  );
  var cursor = 0;
  while (cursor < source.length) {
    if (source.startsWith('/*', cursor)) {
      var depth = 1;
      cursor += 2;
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
    if (!token.startsWith('//')) yield token;
  }
}

Iterable<String> _dependencyUris(String source) sync* {
  final tokens = _sourceTokens(source).toList();
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

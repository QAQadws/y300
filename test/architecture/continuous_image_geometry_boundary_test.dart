import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _root = 'packages/continuous_image_geometry';
const _lib = '$_root/lib/';
const _entry =
    'package:continuous_image_geometry/continuous_image_geometry.dart';
const _barrel = '${_lib}continuous_image_geometry.dart';
const _pureSdk = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};
const _publicTypes = {
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
final _retired = {
  for (final name in [
    'layout_resolver',
    'layout_index',
    'extent_registry',
    'scroll_anchor_coordinator',
  ])
    'lib/features/reader_shared/domain/continuous_image/continuous_image_$name.dart',
};

enum _Scope { app, library, consumer }

void main() {
  test(
    'App uses the public entry and keeps the four old algorithms retired',
    () {
      expect(_violations(['lib', 'test'], _Scope.app), isEmpty);
      expect(_retired.where((path) => File(path).existsSync()), isEmpty);
    },
  );

  test('the library is pure Dart with one explicit geometry API', () {
    expect(_violations(['$_root/lib'], _Scope.library), isEmpty);
    expect(
      _files('$_root/lib')
          .map((file) => normalizeDartSourcePath(file.path))
          .where((path) => !path.startsWith('${_lib}src/')),
      [_barrel],
    );
    final source = File(_barrel).readAsStringSync(encoding: utf8);
    final showLists = dartExportShowLists(source).toList();
    expect(showLists, isNotEmpty);
    expect(showLists, everyElement(isNotNull));
    expect(
      showLists.expand((names) => names ?? const <String>[]).toSet(),
      _publicTypes,
    );
    for (final uri in dartDependencyDirectiveUris(source)) {
      final target = _target(_barrel, uri);
      expect(target, startsWith('${_lib}src/'));
      expect(File(target).existsSync(), isTrue, reason: target);
    }
  });

  test('the manifest has no runtime dependencies or Flutter SDK', () {
    expect(
      _manifestViolations(
        File('$_root/pubspec.yaml').readAsStringSync(encoding: utf8),
      ),
      isEmpty,
    );
  });

  test('package tests and example stay independent of the App', () {
    expect(
      _violations(['$_root/test', '$_root/example'], _Scope.consumer),
      isEmpty,
    );
  });

  test('boundary rules reject bypasses without rejecting valid directives', () {
    expect(
      _forbidden('lib/new_adapter.dart', r'''
import 'package:continuous_image_geometry/continuous_image_geometry.dart'
  if (dart.library.io == 'true') 'package:continuous_image_geometry/\x73rc/private.dart';
export 'features/reader_shared/domain/continuous_image/./temporary/../continuous_image_layout_index.dart';
''', _Scope.app),
      {
        '${_lib}src/private.dart',
        _retired.firstWhere((path) => path.endsWith('layout_index.dart')),
      },
    );
    expect(
      _forbidden('${_lib}src/new_geometry.dart', '''
import 'dart:math';
import 'continuous_image_geometry_models.dart';
export 'dart:collection' if (dart.library.ui) 'dart:ui';
part '../../test/host.dart';
''', _Scope.library),
      {'dart:ui', '$_root/test/host.dart'},
    );
    expect(
      _forbidden('$_root/test/new_test.dart', '''
import 'package:test/test.dart';
import '$_entry';
import 'fixtures/input.dart';
import '../../../test/root_fixture.dart';
import 'package:y300/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:continuous_image_geometry/../test/fixture.dart';
''', _Scope.consumer),
      {
        'test/root_fixture.dart',
        'lib/app.dart',
        'package:flutter_test/flutter_test.dart',
        '$_root/test/fixture.dart',
      },
    );
    expect(
      dartExportShowLists('''
// export 'src/ignored.dart';
const example = "export 'src/ignored.dart' show Host;";
export 'src/geometry.dart' if (dart.library.io == 'true') 'src/other.dart'
  show ContinuousImageLayoutItem, ContinuousImageExtent;
export 'src/host.dart';
'''),
      [
        ['ContinuousImageLayoutItem', 'ContinuousImageExtent'],
        null,
      ],
    );
    for (final manifest in [
      'dependencies: {http: any}',
      'dependencies:\n  http: any',
      'dev_dependencies:\n  flutter_test:\n    sdk: flutter',
      'dev_dependencies: {flutter_test: {sdk: flutter}}',
    ]) {
      expect(_manifestViolations(manifest), isNotEmpty);
    }
    expect(
      _manifestViolations('dependencies: {}\ndev_dependencies:\n  test: any'),
      isEmpty,
    );
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
    uri.startsWith('package:continuous_image_geometry/')
    ? normalizeDartSourcePath(
        '$_lib${uri.substring('package:continuous_image_geometry/'.length)}',
      )
    : resolveDartDependencyTarget(source, uri);

bool _allowed(String uri, String target, _Scope scope) {
  if (scope == _Scope.library) {
    return _pureSdk.contains(target) || target.startsWith(_lib);
  }
  if (uri == 'package:continuous_image_geometry' ||
      uri.startsWith('package:continuous_image_geometry/')) {
    return uri == _entry;
  }
  if (scope == _Scope.app) {
    return !_retired.contains(target) && !target.startsWith('$_root/');
  }
  return (target.startsWith('dart:') && target != 'dart:ui') ||
      target == 'package:test/test.dart' ||
      target.startsWith('$_root/test/') ||
      target.startsWith('$_root/example/');
}

List<String> _manifestViolations(String source) {
  final violations = <String>[];
  var runtime = false;
  for (final raw in source.split('\n')) {
    final line = raw.split('#').first.trimRight();
    if (line.trim().isEmpty) continue;
    final indented = line.startsWith(' ') || line.startsWith('\t');
    if (!indented) runtime = line.startsWith('dependencies:');
    if (runtime &&
        (indented || !{'dependencies:', 'dependencies: {}'}.contains(line))) {
      violations.add(line);
    }
    if (RegExp(r'^\s*flutter:|\bsdk:\s*flutter\b').hasMatch(line)) {
      violations.add(line);
    }
  }
  return violations;
}

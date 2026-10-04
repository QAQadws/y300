import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _readerRoot = 'lib/features/reader_shared/';
const _engineRoot = '${_readerRoot}presentation/engine/';
const _publicEngine = '${_engineRoot}engine.dart';
const _internalImageCoordinators = <String>{
  '${_engineRoot}reader_image_session_coordinator.dart',
  '${_engineRoot}reader_restore_coordinator.dart',
  '${_engineRoot}reader_seek_coordinator.dart',
};
const _pureImageHelpers = <String>{
  '${_engineRoot}reader_position_state.dart',
  '${_engineRoot}reader_vertical_position_driver.dart',
};
const _novelApplicationRoot = 'lib/features/novel/application/';
const _pureNovelCoordinators = <String>{
  '${_novelApplicationRoot}novel_reader_display_preferences_coordinator.dart',
};

void main() {
  test(
    'reader coordination stays internal and independent of UI/storage assembly',
    () {
      final violations = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true, followLinks: false).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = normalizeDartSourcePath(file.path);
        violations.addAll(
          _violations(source, file.readAsStringSync(encoding: utf8)),
        );
      }
      for (final path in _internalImageCoordinators) {
        expect(File(path).existsSync(), isTrue);
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test(
    'pure image coordination rejects widget/provider/data and other feature edges',
    () {
      for (final source in _internalImageCoordinators) {
        expect(
          _violations(source, '''
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../../data/new_store.dart';
import '../reader_preferences/reader_preferences_provider.dart';
import 'reader_capability.dart';
import 'package:y300/app/startup/new_provider.dart';
import 'package:y300/features/novel/domain/new_model.dart';
'''),
          hasLength(8),
        );
        expect(
          _violations(source, '''
import 'dart:async';
import 'reader_position_state.dart';
import 'reader_seek_coordinator.dart';
import '../../domain/continuous_image/continuous_image_models.dart';
/* outer /* nested */ import 'package:flutter/widgets.dart'; */
'''),
          isEmpty,
        );
      }
    },
  );

  test(
    'external consumers and public barrel cannot expose internal coordinators',
    () {
      expect(
        _violations('lib/features/comic/presentation/new_reader.dart', '''
import 'package:y300/features/reader_shared/presentation/engine/reader_image_session_coordinator.dart';
import '../../reader_shared/presentation/engine/reader_restore_coordinator.dart'
  if (dart.library.io) 'package:y300/features/reader_shared/presentation/engine/reader_seek_coordinator.dart';
'''),
        hasLength(3),
      );
      expect(
        _violations(_publicEngine, '''
export 'reader_image_session_coordinator.dart';
export 'reader_restore_coordinator.dart';
export 'reader_seek_coordinator.dart';
'''),
        hasLength(3),
      );
      expect(
        _violations('lib/features/comic/presentation/new_reader.dart', '''
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart';
'''),
        isEmpty,
      );
    },
  );

  test(
    'pure novel coordination rejects adapters without restricting application hosts',
    () {
      for (final source in _pureNovelCoordinators) {
        expect(
          _violations(source, '''
import '../data/preferences/new_repository.dart';
import '../presentation/controllers/novel_reader_controller.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
'''),
          hasLength(6),
        );
        expect(
          _violations(source, '''
import 'dart:async';
import '../domain/models/novel_reader_preferences.dart';
import '../domain/repositories/novel_reader_preferences_repository.dart';
import 'future_session.dart';
'''),
          isEmpty,
        );
      }
      expect(
        _violations('${_novelApplicationRoot}future_startup_host.dart', '''
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/preferences/new_repository.dart';
'''),
        isEmpty,
      );
    },
  );
}

List<String> _violations(String source, String contents) => [
  for (final uri in dartDependencyDirectiveUris(contents))
    if (_forbidden(source, resolveDartDependencyTarget(source, uri)))
      '$source -> ${resolveDartDependencyTarget(source, uri)}',
];

bool _forbidden(String source, String target) {
  if (_internalImageCoordinators.contains(target) &&
      (!source.startsWith(_readerRoot) || source == _publicEngine)) {
    return true;
  }
  final imageCoordinator = _internalImageCoordinators.contains(source);
  final novelCoordinator = _pureNovelCoordinators.contains(source);
  if (!imageCoordinator && !novelCoordinator) return false;
  if (target.startsWith('package:flutter') ||
      target == 'dart:ui' ||
      target.startsWith('lib/app/') ||
      target.contains('/data/') ||
      target.contains('/providers/')) {
    return true;
  }
  if (novelCoordinator) return target.contains('/presentation/');
  return (target.startsWith('lib/features/') &&
          !target.startsWith(_readerRoot)) ||
      (target.startsWith('${_readerRoot}presentation/') &&
          !_internalImageCoordinators.contains(target) &&
          !_pureImageHelpers.contains(target));
}

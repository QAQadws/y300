import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _threadRoot = 'lib/features/thread/';
const _sourceContext =
    'lib/features/novel/domain/models/novel_source_reading_context.dart';
const _bodyContract =
    '${_threadRoot}domain/contracts/thread_body_reading_observer.dart';
const _sourceAdapter =
    'lib/features/novel/presentation/adapters/novel_source_reading_adapter.dart';

void main() {
  test('native thread reading stays independent of novel persistence', () {
    final violations = <String>[];
    for (final file in Directory(
      _threadRoot,
    ).listSync(recursive: true, followLinks: false).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      violations.addAll(
        _violations(
          normalizeDartSourcePath(file.path),
          file.readAsStringSync(encoding: utf8),
        ),
      );
    }
    for (final source in [_sourceContext, _bodyContract, _sourceAdapter]) {
      violations.addAll(
        _violations(source, File(source).readAsStringSync(encoding: utf8)),
      );
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('reading contracts reject UI, storage and adapter dependencies', () {
    for (final source in [_sourceContext, _bodyContract]) {
      expect(
        _violations(source, '''
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'package:y300/core/database/app_database.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/presentation/adapters/novel_source_reading_adapter.dart';
'''),
        hasLength(6),
      );
    }
  });

  test('thread and novel producer communicate through domain contracts', () {
    expect(
      _violations('${_threadRoot}presentation/new_body.dart', '''
import 'package:y300/features/novel/domain/models/novel_source_reading_context.dart';
import 'package:y300/features/novel/presentation/adapters/novel_source_reading_adapter.dart';
import 'package:sqflite/sqflite.dart';
'''),
      hasLength(3),
    );
    expect(
      _violations(_sourceAdapter, '''
import 'package:y300/core/database/app_database.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
'''),
      hasLength(3),
    );
    expect(
      _violations(_sourceAdapter, '''
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';
'''),
      isEmpty,
    );
  });
}

List<String> _violations(String source, String contents) => [
  for (final uri in dartDependencyDirectiveUris(contents))
    if (_forbidden(source, resolveDartDependencyTarget(source, uri)))
      '$source -> ${resolveDartDependencyTarget(source, uri)}',
];

bool _forbidden(String source, String target) {
  final storage =
      target.startsWith('package:sqflite') ||
      target.startsWith('package:sqlite') ||
      target.startsWith('lib/core/database/');
  if (source.startsWith(_threadRoot)) {
    if (target.startsWith('lib/features/novel/') || storage) return true;
  }
  if (source == _sourceContext || source == _bodyContract) {
    return storage ||
        target.startsWith('package:flutter') ||
        target == 'dart:ui' ||
        target.contains('/data/') ||
        target.contains('/presentation/');
  }
  if (source == _sourceAdapter) {
    return storage ||
        target.contains('/data/') ||
        target.startsWith('${_threadRoot}presentation/');
  }
  return false;
}

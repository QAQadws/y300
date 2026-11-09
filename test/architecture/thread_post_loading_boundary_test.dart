import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _threadRoot = 'lib/features/thread/';
const _loaders = {
  '${_threadRoot}presentation/services/thread_post_ratings_loader.dart',
  '${_threadRoot}presentation/services/thread_post_comments_loader.dart',
};
const _models = {
  '${_threadRoot}presentation/models/thread_post_load_state.dart',
  '${_threadRoot}presentation/models/thread_post_loading_content.dart',
};

void main() {
  test(
    'post loaders stay internal and independent of controller, UI and data',
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
      for (final path in {..._loaders, ..._models}) {
        expect(File(path).existsSync(), isTrue);
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test(
    'load orchestration cannot acquire transport, providers or page state',
    () {
      for (final source in _loaders) {
        expect(
          _violations(source, '''
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../../data/repositories/thread_post_ratings_repository.dart';
import '../thread_detail_controller.dart';
import '../thread_detail_state.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/auth/application/auth_session_controller.dart';
'''),
          hasLength(8),
        );
        expect(
          _violations(source, '''
import 'dart:async';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import '../models/thread_post_load_state.dart';
import '../../domain/models/thread_post_rating_details.dart';
'''),
          isEmpty,
        );
      }
    },
  );

  test('other features cannot import private loading objects', () {
    expect(
      _violations('lib/features/novel/presentation/future_page.dart', '''
import 'package:y300/features/thread/presentation/services/thread_post_ratings_loader.dart';
import 'package:y300/features/thread/presentation/services/thread_post_comments_loader.dart';
'''),
      hasLength(2),
    );
  });
}

List<String> _violations(String source, String contents) => [
  for (final uri in dartDependencyDirectiveUris(contents))
    if (_forbidden(source, resolveDartDependencyTarget(source, uri)))
      '$source -> $uri',
];

bool _forbidden(String source, String target) {
  if (_loaders.contains(target) && !source.startsWith(_threadRoot)) return true;
  if (!_loaders.contains(source) && !_models.contains(source)) return false;
  if (target.startsWith('dart:')) return target == 'dart:ui';
  return target !=
          'package:yamibo_forum_client/yamibo_forum_client_contracts.dart' &&
      target != 'lib/core/network/api_result.dart' &&
      !target.startsWith('${_threadRoot}domain/') &&
      !_models.contains(target);
}

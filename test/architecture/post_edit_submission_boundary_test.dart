import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _root = 'lib/features/thread/';
const _flow = '${_root}application/post_edit_submission_coordinator.dart';
const _attempt = '${_root}domain/models/post_edit_submission_attempt.dart';
const _controller = '${_root}presentation/post_edit_composer_controller.dart';

void main() {
  test('submission orchestration depends only on neutral contracts and domain policy', () {
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
    expect(File(_flow).existsSync(), isTrue);
    expect(File(_attempt).existsSync(), isTrue);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('flow rejects provider, widgets, transport, persistence and presentation state', () {
    expect(
      _violations(_flow, '''
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/providers/post_edit_providers.dart';
import '../presentation/post_edit_composer_state.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:dio/dio.dart';
import 'dart:io';
'''),
      hasLength(7),
    );
    expect(
      _violations(_flow, '''
import 'dart:async';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../domain/models/post_edit_submission_attempt.dart';
import '../domain/services/post_edit_submit_verification_service.dart';
'''),
      isEmpty,
    );
  });

  test('attempt stays a protocol-neutral value and coordinator stays internal', () {
    expect(
      _violations(_attempt, '''
import '../../application/post_edit_submission_coordinator.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
'''),
      hasLength(3),
    );
    const edge =
        "import 'package:y300/features/thread/application/post_edit_submission_coordinator.dart';";
    expect(_violations(_controller, edge), isEmpty);
    expect(
      _violations('lib/features/reply/presentation/page.dart', edge),
      hasLength(1),
    );
  });
}

List<String> _violations(String source, String contents) => [
  for (final uri in dartDependencyDirectiveUris(contents))
    if (_forbidden(source, uri)) '$source -> $uri',
];

bool _forbidden(String source, String uri) {
  final target = resolveDartDependencyTarget(source, uri);
  if (target == _flow && source != _controller) return true;
  if (source != _flow && source != _attempt) return false;
  if (uri == 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart') {
    return false;
  }
  if (source == _attempt) return true;
  return uri != 'dart:async' && !target.startsWith('${_root}domain/');
}

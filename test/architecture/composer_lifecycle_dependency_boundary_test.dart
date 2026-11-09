import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _retiredDraftContract =
    'lib/features/composer_shared/data/repositories/composer_draft_repository.dart';
const _draftContract =
    'lib/features/composer_shared/domain/repositories/composer_draft_repository.dart';
const _draftCoordinator =
    'lib/features/composer_shared/application/composer_draft_coordinator.dart';
const _applicationRoot = 'lib/features/composer_shared/application/';
const _uploadSession = '${_applicationRoot}composer_upload_session.dart';
const _uploadBatch = '${_applicationRoot}composer_upload_batch.dart';
const _composerRoot = 'lib/features/composer_shared/';
const _quillRoot = '${_composerRoot}presentation/quill/';
const _documentSync =
    '${_quillRoot}composer_quill_document_sync_coordinator.dart';

void main() {
  test(
    'composer lifecycle and contracts stay independent of implementations and UI',
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
      expect(File(_draftContract).existsSync(), isTrue);
      expect(File(_draftCoordinator).existsSync(), isTrue);
      expect(File(_uploadSession).existsSync(), isTrue);
      expect(File(_uploadBatch).existsSync(), isTrue);
      expect(File(_documentSync).existsSync(), isTrue);
      expect(File(_retiredDraftContract).existsSync(), isFalse);
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test(
    'Quill document sync is internal and independent of widgets and storage',
    () {
      expect(
        _violations(_documentSync, '''
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/composer_quill_prototype_editor.dart';
import '../../data/providers/composer_providers.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/thread/domain/new_model.dart';
'''),
        hasLength(7),
      );
      expect(
        _violations(_documentSync, '''
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'composer_quill_bbcode_codec.dart';
import '../../domain/models/composer_insertion_models.dart';
'''),
        isEmpty,
      );
      expect(
        _violations('lib/features/reply/presentation/new_controller.dart', '''
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_document_sync_coordinator.dart';
'''),
        hasLength(1),
      );
    },
  );

  test('new lifecycle implementation and UI dependencies are rejected', () {
    expect(
      _violations(_draftCoordinator, '''
import '../data/repositories/new_repository.dart';
export 'package:y300/features/composer_shared/presentation/controllers/new_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
'''),
      hasLength(3),
    );
    expect(
      _violations('lib/features/reply/presentation/new_controller.dart', '''
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
'''),
      hasLength(1),
    );
    expect(
      _violations(_draftCoordinator, '''
import 'dart:async';
import '../domain/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
// import 'package:flutter/widgets.dart';
'''),
      isEmpty,
    );
  });

  test(
    'new application sessions and batches cannot depend on widget or storage adapters',
    () {
      for (final source in [
        _uploadSession,
        _uploadBatch,
        '${_applicationRoot}future_session.dart',
      ]) {
        expect(
          _violations(source, '''
import '../data/services/new_upload_adapter.dart';
export 'package:y300/features/composer_shared/presentation/controllers/new_controller.dart';
import 'package:flutter/widgets.dart';
import 'dart:ui';
'''),
          hasLength(4),
        );
        expect(
          _violations(source, '''
import 'dart:async';
import 'composer_upload_batch.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
'''),
          isEmpty,
        );
      }
    },
  );
}

List<String> _violations(String source, String contents) => [
  for (final uri in dartDependencyDirectiveUris(contents))
    if (_forbidden(source, resolveDartDependencyTarget(source, uri)))
      '$source -> ${resolveDartDependencyTarget(source, uri)}',
];

bool _forbidden(String source, String target) {
  if (target == _retiredDraftContract) return true;
  if (target == _documentSync && !source.startsWith(_composerRoot)) return true;
  if (source == _documentSync) {
    return target.contains('/data/') ||
        target.startsWith('lib/app/') ||
        target.startsWith('package:flutter_riverpod/') ||
        (target.startsWith('package:flutter/') &&
            target != 'package:flutter/services.dart') ||
        (target.startsWith('lib/features/') &&
            !target.startsWith('${_composerRoot}domain/') &&
            !target.startsWith(_quillRoot));
  }
  if (source != _draftContract && !source.startsWith(_applicationRoot)) {
    return false;
  }
  return target.contains('/data/') ||
      target.contains('/presentation/') ||
      target.startsWith('lib/app/') ||
      target.startsWith('package:flutter') ||
      target == 'dart:ui';
}

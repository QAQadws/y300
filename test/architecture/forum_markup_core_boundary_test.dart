import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_dependency_directives.dart';

const _publicEntry = 'package:forum_markup_core/forum_markup_core.dart';
const _packageLib = 'packages/forum_markup_core/lib/';
const _retiredCorePaths = <String>{
  'lib/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart',
  'lib/features/composer_shared/domain/services/composer_collapse_bbcode_grammar.dart',
  'lib/features/composer_shared/domain/services/composer_collapse_document_parser.dart',
  'lib/features/composer_shared/domain/services/composer_collapse_serializer.dart',
  'lib/features/composer_shared/domain/models/composer_collapse_models.dart',
};

void main() {
  test('App and App tests use the sole public markup package entry', () {
    final violations = <String>[];
    for (final root in ['lib', 'test']) {
      final files = Directory(root)
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      expect(files, isNotEmpty, reason: 'The $root source root must exist.');
      for (final file in files) {
        final source = normalizeDartSourcePath(file.path);
        for (final target in _forbiddenTargets(
          source,
          file.readAsStringSync(encoding: utf8),
        )) {
          violations.add('$source -> $target');
        }
      }
    }
    expect(
      violations..sort(),
      isEmpty,
      reason: 'Use $_publicEntry; keep one grammar and AST type identity.',
    );
  });

  test('the five retired App core definitions are not reintroduced', () {
    expect(
      _retiredCorePaths.where((path) => File(path).existsSync()),
      isEmpty,
      reason: 'The pure core is owned by forum_markup_core.',
    );
  });

  test(
    'ordinary domain imports and the public package entry remain allowed',
    () {
      expect(
        _forbiddenTargets(
          'lib/features/thread/presentation/new_adapter.dart',
          '''
import '$_publicEntry' show ComposerCollapseDocumentParser;
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
export '../controllers/thread_detail_state.dart';
''',
        ),
        isEmpty,
      );
    },
  );

  test('conditional imports and exports inspect every package entry', () {
    expect(
      _forbiddenTargets('lib/features/thread/presentation/new_adapter.dart', '''
import
  '$_publicEntry'
  if (dart.library.io == 'true')
    'package:forum_markup_core/src/composer_attach_bbcode_grammar.dart';
export '$_publicEntry'
  if (dart.library.html) 'package:forum_markup_core/other_entry.dart';
'''),
      {
        'package:forum_markup_core/src/composer_attach_bbcode_grammar.dart',
        'package:forum_markup_core/other_entry.dart',
      },
    );
  });

  test('relative and package paths cannot bypass retired core ownership', () {
    const source =
        'lib/features/composer_shared/domain/services/new_policy.dart';
    expect(
      _forbiddenTargets(source, '''
import './composer_attach_bbcode_grammar.dart';
export 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import '../models/composer_collapse_models.dart';
import '../../../../../packages/forum_markup_core/lib/src/composer_collapse_models.dart';
export '../../../../../packages/forum_markup_core/lib/forum_markup_core.dart';
'''),
      {
        'lib/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart',
        'lib/features/composer_shared/domain/models/composer_collapse_models.dart',
        'packages/forum_markup_core/lib/src/composer_collapse_models.dart',
        'packages/forum_markup_core/lib/forum_markup_core.dart',
      },
    );
  });

  test('comments and quoted source examples do not create dependencies', () {
    expect(
      _forbiddenTargets('lib/example.dart', '''
// import 'package:forum_markup_core/src/private.dart';
/* nested /* export 'package:forum_markup_core/other.dart'; */ comment */
import '$_publicEntry';
const example = """
import 'package:y300/features/composer_shared/domain/models/composer_collapse_models.dart';
""";
const rawExample = r"export 'package:forum_markup_core/src/private.dart';";
'''),
      isEmpty,
    );
  });
}

Set<String> _forbiddenTargets(String sourcePath, String source) => {
  for (final uri in dartDependencyDirectiveUris(source))
    if (_isForbidden(uri, resolveDartDependencyTarget(sourcePath, uri)))
      resolveDartDependencyTarget(sourcePath, uri),
};

bool _isForbidden(String uri, String target) {
  if (_retiredCorePaths.contains(target)) return true;
  if (uri == 'package:forum_markup_core' ||
      uri.startsWith('package:forum_markup_core/')) {
    return uri != _publicEntry;
  }
  // Relative imports of even the barrel bypass the canonical package URI.
  return target.startsWith(_packageLib);
}

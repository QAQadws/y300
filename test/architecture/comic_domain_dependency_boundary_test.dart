import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'dart_dependency_directives.dart';

const _domainRoot = 'lib/features/comic/domain';

// Existing source-to-target debt only. Remove each entry when its dependency
// moves behind a domain contract; never exempt an entire file or directory.
const _existingDebt = <String, Set<String>>{};

typedef _Dependency = ({String source, String target});

void main() {
  test('comic domain dependencies cannot expand the existing debt', () {
    final actual = <_Dependency>{};
    final files = Directory(_domainRoot)
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    expect(files, isNotEmpty, reason: 'The domain source root must exist.');
    for (final file in files) {
      actual.addAll(
        _forbiddenDependencies(
          normalizeDartSourcePath(file.path),
          file.readAsStringSync(encoding: utf8),
        ),
      );
    }
    final allowed = <_Dependency>{
      for (final entry in _existingDebt.entries)
        for (final target in entry.value)
          (source: '$_domainRoot/${entry.key}', target: target),
    };

    expect(
      _describe(actual.difference(allowed)),
      isEmpty,
      reason:
          'New reverse dependencies need a domain contract or host adapter.',
    );
    expect(
      _describe(allowed.difference(actual)),
      isEmpty,
      reason: 'Dependency debt was removed; shrink its exact allowlist entry.',
    );
  });

  test('new dependencies in an already indebted source are still rejected', () {
    const source = '$_domainRoot/services/comic_services_impl.dart';
    const fixtureDebt = {
      'lib/features/comic/data/providers/comic_providers.dart',
    };
    final actual = _forbiddenDependencies(source, '''
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/services/new_storage_adapter.dart';
export
  'package:y300/features/comic/presentation/comic_reader_page.dart';
import 'package:flutter/widgets.dart';
import 'package:y300/app/navigation/reader_routes.dart';
''');
    final newTargets = actual
        .map((edge) => edge.target)
        .toSet()
        .difference(fixtureDebt);

    expect(newTargets, {
      'lib/features/comic/data/services/new_storage_adapter.dart',
      'lib/features/comic/presentation/comic_reader_page.dart',
      'package:flutter/widgets.dart',
      'lib/app/navigation/reader_routes.dart',
    });
  });

  test('relative and package URIs identify the same dependency', () {
    const source = '$_domainRoot/services/new_policy.dart';
    final actual = _forbiddenDependencies(source, '''
import '../../data/repositories/comic_repository.dart';
export 'package:y300/features/comic/data/repositories/comic_repository.dart';
export '../services/comic_services_impl.dart';
''');

    expect(actual, {
      (
        source: source,
        target: 'lib/features/comic/data/repositories/comic_repository.dart',
      ),
      (
        source: source,
        target: 'lib/features/comic/domain/services/comic_services_impl.dart',
      ),
    });
  });

  test('multi-line conditional directives inspect every target URI', () {
    const source = '$_domainRoot/services/new_policy.dart';
    final actual = _forbiddenDependencies(source, '''
import
  '../models/comic_models.dart'
  if (dart.library.io == 'true')
    '../../data/services/native_adapter.dart'
  if (dart.library.html)
    '../../presentation/web_adapter.dart';
export /* explanatory comment */
  'package:y300/core/network/new_provider.dart';
''');

    expect(actual.map((edge) => edge.target).toSet(), {
      'lib/features/comic/data/services/native_adapter.dart',
      'lib/features/comic/presentation/web_adapter.dart',
      'lib/core/network/new_provider.dart',
    });
  });

  test('comments and string contents cannot create dependency edges', () {
    const source = '$_domainRoot/services/new_policy.dart';
    const text = '''
// import 'package:flutter/widgets.dart';
/* nested /* import 'package:flutter/material.dart'; */ comment */
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../models/comic_models.dart';
import '../services/comic_post_aggregation_service.dart';
import '../services/comic_reader_service.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/core/config/app_config.dart';
const example = """
import 'package:y300/features/comic/data/services/example.dart';
""";
const rawExample = r"export 'package:flutter/widgets.dart';";
''';

    expect(_forbiddenDependencies(source, text), isEmpty);
  });
}

Set<_Dependency> _forbiddenDependencies(String sourcePath, String source) => {
  for (final uri in dartDependencyDirectiveUris(source))
    if (_isForbidden(resolveDartDependencyTarget(sourcePath, uri)))
      (
        source: sourcePath,
        target: resolveDartDependencyTarget(sourcePath, uri),
      ),
};

bool _isForbidden(String target) {
  // Foundation supports the current listenable contracts without Widgets.
  if (target.startsWith('package:flutter/')) {
    return target != 'package:flutter/foundation.dart';
  }
  if (target == 'dart:ui' || target.startsWith('package:flutter_')) {
    return true;
  }
  if (!target.startsWith('lib/')) return false;
  return target.contains('/data/') ||
      target.contains('/presentation/') ||
      target.startsWith('lib/app/') ||
      target.startsWith('lib/shared/widgets/') ||
      target.startsWith('lib/l10n/') ||
      target.contains('/providers/') ||
      target.endsWith('_provider.dart') ||
      target.endsWith('_providers.dart') ||
      // Keep the retired umbrella path forbidden if it is ever reintroduced.
      target == '$_domainRoot/services/comic_services_impl.dart';
}

List<String> _describe(Set<_Dependency> edges) =>
    edges.map((edge) => '${edge.source} -> ${edge.target}').toList()..sort();

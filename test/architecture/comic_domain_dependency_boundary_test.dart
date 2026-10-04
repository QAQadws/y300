import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
          _normalize(file.path),
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
  for (final uri in _directiveUris(source))
    if (_isForbidden(_resolveTarget(sourcePath, uri)))
      (source: sourcePath, target: _resolveTarget(sourcePath, uri)),
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

String _resolveTarget(String source, String target) {
  if (target.startsWith('package:y300/')) {
    return p.posix.normalize('lib/${target.substring('package:y300/'.length)}');
  }
  if (Uri.parse(target).hasScheme) return target;
  return p.posix.normalize(p.posix.join(p.posix.dirname(source), target));
}

String _normalize(String path) => p.posix.normalize(path.replaceAll('\\', '/'));

List<String> _describe(Set<_Dependency> edges) =>
    edges.map((edge) => '${edge.source} -> ${edge.target}').toList()..sort();

Iterable<String> _directiveUris(String source) sync* {
  final tokens = _sourceTokens(source).toList();
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (token.isString || (token.text != 'import' && token.text != 'export')) {
      continue;
    }
    var expectsUri = true;
    var parentheses = 0;
    while (++index < tokens.length && tokens[index].text != ';') {
      final next = tokens[index];
      if (next.isString) {
        if (expectsUri && parentheses == 0) yield next.text;
        expectsUri = false;
      } else if (next.text == '(') {
        parentheses++;
      } else if (next.text == ')') {
        parentheses--;
        // A conditional directive's URI follows its closing parenthesis;
        // string values inside the condition are configuration, not imports.
        if (parentheses == 0) expectsUri = true;
      }
    }
  }
}

class _SourceToken {
  const _SourceToken(this.text, {this.isString = false});

  final String text;
  final bool isString;
}

// A small lexer keeps quoted examples and nested comments out of the guard
// without adding an analyzer dependency just to inspect URI directives.
Iterable<_SourceToken> _sourceTokens(String source) sync* {
  var index = 0;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      final end = source.indexOf('\n', index + 2);
      index = end < 0 ? source.length : end + 1;
      continue;
    }
    if (source.startsWith('/*', index)) {
      var depth = 1;
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) {
          depth++;
          index += 2;
        } else if (source.startsWith('*/', index)) {
          depth--;
          index += 2;
        } else {
          index++;
        }
      }
      continue;
    }
    final raw =
        source[index] == 'r' &&
        index + 1 < source.length &&
        (source[index + 1] == "'" || source[index + 1] == '"');
    final quoteIndex = raw ? index + 1 : index;
    final quote = source[quoteIndex];
    if (quote == "'" || quote == '"') {
      final delimiter = source.startsWith(quote * 3, quoteIndex)
          ? quote * 3
          : quote;
      final start = quoteIndex + delimiter.length;
      index = start;
      while (index < source.length && !source.startsWith(delimiter, index)) {
        if (!raw && source[index] == '\\') {
          index += 2;
        } else {
          index++;
        }
      }
      final value = source.substring(
        start,
        index < source.length ? index : source.length,
      );
      yield _SourceToken(raw ? value : _unescape(value), isString: true);
      index += delimiter.length;
      continue;
    }
    if (_isIdentifierCode(source.codeUnitAt(index))) {
      final start = index++;
      while (index < source.length &&
          _isIdentifierCode(source.codeUnitAt(index))) {
        index++;
      }
      yield _SourceToken(source.substring(start, index));
    } else {
      if (source[index].trim().isNotEmpty) yield _SourceToken(source[index]);
      index++;
    }
  }
}

bool _isIdentifierCode(int code) =>
    (code >= 65 && code <= 90) ||
    (code >= 97 && code <= 122) ||
    (code >= 48 && code <= 57) ||
    code == 95 ||
    code == 36;

String _unescape(String value) => value.replaceAllMapped(
  RegExp(r'\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)'),
  (match) {
    final escape = match[1]!;
    if (escape.startsWith('u{')) {
      return String.fromCharCode(
        int.parse(escape.substring(2, escape.length - 1), radix: 16),
      );
    }
    if (escape.startsWith('u') || escape.startsWith('x')) {
      return String.fromCharCode(int.parse(escape.substring(1), radix: 16));
    }
    return switch (escape) {
      'n' => '\n',
      'r' => '\r',
      't' => '\t',
      _ => escape,
    };
  },
);

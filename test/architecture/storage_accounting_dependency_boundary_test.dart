import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _cacheRoot = 'lib/features/cache/';
const _cacheAdapters = '${_cacheRoot}data/services/storage_usage_adapters.dart';
const _neutralAdapters = <String>{
  'lib/features/storage/data/composite_storage_accounting_adapter.dart',
  'lib/features/storage/data/sqlite_metadata_storage_accounting_adapter.dart',
  'lib/features/storage/data/shared_library_database_storage_accounting_adapter.dart',
};
const _businessOwners = <String>[
  'comic',
  'novel',
  'favorites',
  'composer_shared',
  'profile',
  'history',
  'library_shared',
];

void main() {
  test('cache and neutral accounting do not own business assembly', () {
    final violations = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true, followLinks: false).whereType<File>()) {
      final path = file.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart')) continue;
      violations.addAll(
        _violations(path, file.readAsStringSync(encoding: utf8)),
      );
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Business statistics belong to their owners; only the app assembles the report.',
    );
  });

  test('reverse assembly and business imports are rejected', () {
    expect(
      _violations(_cacheAdapters, '''
import 'package:y300/features/profile/domain/repositories/blog_draft_repository.dart';
export '../../../../app/storage/storage_accounting_providers.dart';
final storageAccountingServiceProvider = Provider(create);
'''),
      hasLength(3),
    );
    expect(
      _violations(_neutralAdapters.first, '''
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
'''),
      hasLength(1),
    );
  });

  test('owner adapters and app assembly remain valid', () {
    expect(
      _violations('lib/app/storage/accounting.dart', '''
import 'package:y300/features/comic/data/services/comic_metadata_storage_accounting_adapter.dart';
final storageAccountingServiceProvider = Provider(create);
'''),
      isEmpty,
    );
    expect(
      _violations('lib/features/novel/data/services/accounting.dart', '''
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/storage/data/sqlite_metadata_storage_accounting_adapter.dart';
'''),
      isEmpty,
    );
    expect(
      _violations(_cacheAdapters, '''
/* migration example /* nested note */
import 'package:y300/features/profile/data/providers/blog_draft_providers.dart';
*/
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
const example = """
final storageAccountingServiceProvider = Provider(create);
import 'package:y300/app/storage/storage_accounting_providers.dart';
""";
'''),
      isEmpty,
    );
  });
}

List<String> _violations(String path, String source) {
  final tokens = _directivesAndCode(source);
  final result = <String>[];
  for (final uri in tokens.uris) {
    final target = uri.startsWith('package:y300/')
        ? 'lib/${uri.substring('package:y300/'.length)}'
        : p.posix.normalize(p.posix.join(p.posix.dirname(path), uri));
    if (path.startsWith(_cacheRoot) && target.startsWith('lib/app/')) {
      result.add('$path -> $target');
    } else if ((path == _cacheAdapters || _neutralAdapters.contains(path)) &&
        _businessOwners.any(
          (owner) => target.startsWith('lib/features/$owner/'),
        )) {
      result.add('$path -> $target');
    }
  }
  if (path.startsWith(_cacheRoot)) {
    for (final provider in <String>[
      'storageAccountingServiceProvider',
      'cacheMaintenanceServiceProvider',
    ]) {
      if (RegExp('\\bfinal\\s+$provider\\s*=').hasMatch(tokens.code)) {
        result.add('$path: $provider');
      }
    }
  }
  return result;
}

// Keep URI directives, while excluding quoted examples and nested comments.
({List<String> uris, String code}) _directivesAndCode(String source) {
  final uris = <String>[];
  final code = StringBuffer();
  var index = 0;
  var inDirective = false;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      final end = source.indexOf('\n', index + 2);
      index = end < 0 ? source.length : end;
      code.write(' ');
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
      code.write(' ');
      continue;
    }
    final raw =
        source.startsWith("r'", index) || source.startsWith('r"', index);
    final quoteIndex = index + (raw ? 1 : 0);
    final quote = source[quoteIndex];
    if (quote == "'" || quote == '"') {
      final delimiter = source.startsWith(quote * 3, quoteIndex)
          ? quote * 3
          : quote;
      final start = quoteIndex + delimiter.length;
      index = start;
      while (index < source.length && !source.startsWith(delimiter, index)) {
        index += !raw && source[index] == r'\' ? 2 : 1;
      }
      final value = source.substring(
        start,
        index < source.length ? index : source.length,
      );
      if (inDirective && value.endsWith('.dart')) uris.add(value);
      if (index < source.length) index += delimiter.length;
      code.write(' ');
    } else if (_isIdentifier(source.codeUnitAt(index))) {
      final start = index++;
      while (index < source.length && _isIdentifier(source.codeUnitAt(index))) {
        index++;
      }
      final token = source.substring(start, index);
      if (token == 'import' || token == 'export') inDirective = true;
      code.write(token);
    } else {
      if (source[index] == ';') inDirective = false;
      code.write(source[index++]);
    }
  }
  return (uris: uris, code: code.toString());
}

bool _isIdentifier(int code) =>
    (code >= 65 && code <= 90) ||
    (code >= 97 && code <= 122) ||
    (code >= 48 && code <= 57) ||
    code == 95 ||
    code == 36;

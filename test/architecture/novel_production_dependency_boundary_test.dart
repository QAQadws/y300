import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Fixtures seed current storage contracts directly. No production declaration
// or repository retains an exception for the retired discovery/update chain.
const _retiredIdentifiers = <String>[
  'LegacyNovelThreadGateway',
  'NovelEpisodeDiscoveryService',
  'NovelRefreshSeed',
  'NovelEpisodeRefreshResult',
  'NovelRefreshPlan',
  'NovelEpisodeRefreshMode',
  'NovelDiscoveryOptions',
  'NovelSameThreadCatalogExtractor',
  'NovelParsingRule',
  'NovelParsingContext',
  'NovelParsingDebugInfo',
  'NovelSyncLogger',
  'upsertNovelBySeed',
];

void main() {
  test('production code cannot enable fixture-only novel dependencies', () {
    final violations = <String>[];
    for (final file in _productionFiles()) {
      final path = file.path.replaceAll('\\', '/');
      violations.addAll(
        _dependencyViolations(path, file.readAsStringSync(encoding: utf8)),
      );
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Production ingest and updates must use source metadata and chapter '
          'sync services; fixtures must not restore retired production APIs.',
    );
  });

  test('boundary detects calls and injection without matching documentation', () {
    const nestedDocumentation = '''
/* Outer migration note.
   /* Inner note. */
   repository.upsertNovelBySeed(seed: seed);
   repository.refreshEpisodes(novelId: id);
   LegacyNovelThreadGateway and NovelEpisodeDiscoveryService.
   LocalNovelRepository(database, threadGateway: gateway);
*/
final rawLabel = r"/* upsertNovelBySeed refreshEpisodes */";
''';
    const productionPath =
        'lib/features/favorites/data/services/production_ingest.dart';
    expect(_dependencyViolations(productionPath, nestedDocumentation), isEmpty);
    expect(
      _dependencyViolations(
        productionPath,
        '$nestedDocumentation\nrepository.upsertNovelBySeed(seed: seed);',
      ).map((violation) => violation.substring(violation.indexOf(': ') + 2)),
      <String>['upsertNovelBySeed'],
    );
    const source = '''
// LegacyNovelThreadGateway and repository.upsertNovelBySeed(seed: seed).
/* NovelEpisodeDiscoveryService; repository.refreshEpisodes(novelId: id). */
final label = 'upsertNovelBySeed refreshEpisodes LegacyNovelThreadGateway';
final LegacyNovelThreadGateway gateway;
final discovery = NovelEpisodeDiscoveryService();
final repository = LocalNovelRepository(
  database,
  threadGateway: gateway,
  discoveryService: discovery,
);
repository
  ..upsertNovelBySeed(seed: seed)
  ..refreshEpisodes(novelId: id);
''';

    final violations = _dependencyViolations(productionPath, source);

    expect(
      violations.map(
        (violation) => violation.substring(violation.indexOf(': ') + 2),
      ),
      unorderedEquals(<String>[
        'LegacyNovelThreadGateway',
        'NovelEpisodeDiscoveryService',
        'upsertNovelBySeed',
        'refreshEpisodes(novelId: ...)',
        'LocalNovelRepository(threadGateway: ...)',
        'LocalNovelRepository(discoveryService: ...)',
      ]),
    );
    expect(
      _dependencyViolations(
        'lib/features/comic/presentation/controllers/comic_detail_controller.dart',
        'Future<void> refreshEpisodes() async {}',
      ),
      isEmpty,
    );
    const repositoryPath =
        'lib/features/novel/data/repositories/local_novel_repository.dart';
    expect(
      _dependencyViolations(repositoryPath, '''
final repository = LocalNovelRepository(database, stateRepository: state);
final metadata = DefaultNovelSourceMetadataParser();
final sync = DefaultNovelChapterSyncService(threadGateway: gateway);
'''),
      isEmpty,
    );
    expect(
      _dependencyViolations(repositoryPath, '''
class LocalNovelRepository {
  LocalNovelRepository(database, {
    LegacyNovelThreadGateway? threadGateway,
    NovelEpisodeDiscoveryService? discoveryService,
  });
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {}
  Future<void> refreshEpisodes({required String novelId}) async {}
}
''').map((violation) => violation.substring(violation.indexOf(': ') + 2)),
      unorderedEquals(<String>[
        'LegacyNovelThreadGateway',
        'NovelEpisodeDiscoveryService',
        'NovelRefreshSeed',
        'upsertNovelBySeed',
        'refreshEpisodes(novelId: ...)',
      ]),
    );
  });

  test(
    'retired DTOs and services cannot return as production declarations',
    () {
      for (final identifier in _retiredIdentifiers) {
        final violations = _dependencyViolations(
          'lib/features/novel/domain/retired.dart',
          'class $identifier {}',
        );
        expect(violations, <String>[
          'lib/features/novel/domain/retired.dart: $identifier',
        ]);
      }
    },
  );
}

List<String> _dependencyViolations(String path, String source) {
  final code = _maskCommentsAndStrings(source);
  final violations = <String>[];
  void report(String edge) => violations.add('$path: $edge');

  for (final identifier in _retiredIdentifiers) {
    if (_identifier(identifier).hasMatch(code)) {
      report(identifier);
    }
  }

  // Comic detail has a different refreshEpisodes API. The legacy novel method
  // requires novelId; also reject novel-local tear-offs before they can escape.
  final novelLocalReference =
      path.startsWith('lib/features/novel/') &&
      _identifier('refreshEpisodes').hasMatch(code);
  final novelRefreshCall = _invocationArguments(
    code,
    'refreshEpisodes',
  ).any((arguments) => RegExp(r'\bnovelId\s*:').hasMatch(arguments));
  if (novelLocalReference || novelRefreshCall) {
    report('refreshEpisodes(novelId: ...)');
  }

  for (final arguments in _invocationArguments(code, 'LocalNovelRepository')) {
    for (final dependency in <String>['threadGateway', 'discoveryService']) {
      if (RegExp('\\b$dependency\\s*:').hasMatch(arguments)) {
        report('LocalNovelRepository($dependency: ...)');
      }
    }
  }
  return violations;
}

// This is a small source-edge guard, not a Dart resolver. Ignore literals and
// documentation so migration notes cannot accidentally become dependency edges.
String _maskCommentsAndStrings(String source) {
  final code = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final raw =
        source.startsWith("r'", index) || source.startsWith('r"', index);
    final quoteIndex = index + (raw ? 1 : 0);
    final quote = source[quoteIndex];
    if (quote == "'" || quote == '"') {
      final tripleQuote = '$quote$quote$quote';
      final delimiter = source.startsWith(tripleQuote, quoteIndex)
          ? tripleQuote
          : quote;
      index = quoteIndex + delimiter.length;
      while (index < source.length && !source.startsWith(delimiter, index)) {
        if (!raw && source[index] == r'\') {
          index += 2;
        } else {
          index += 1;
        }
      }
      if (index < source.length) index += delimiter.length;
      code.write(' ');
    } else if (source.startsWith('//', index)) {
      final end = source.indexOf('\n', index + 2);
      index = end < 0 ? source.length : end;
      code.write(' ');
    } else if (source.startsWith('/*', index)) {
      var depth = 1;
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) {
          depth += 1;
          index += 2;
        } else if (source.startsWith('*/', index)) {
          depth -= 1;
          index += 2;
        } else {
          index += 1;
        }
      }
      code.write(' ');
    } else {
      code.write(source[index]);
      index += 1;
    }
  }
  return code.toString();
}

RegExp _identifier(String value) => RegExp('\\b${RegExp.escape(value)}\\b');

Iterable<String> _invocationArguments(String code, String method) sync* {
  final calls = RegExp('\\b${RegExp.escape(method)}\\s*\\(');
  for (final call in calls.allMatches(code)) {
    var depth = 1;
    for (var index = call.end; index < code.length; index += 1) {
      if (code[index] == '(') depth += 1;
      if (code[index] == ')') depth -= 1;
      if (depth == 0) {
        yield code.substring(call.end, index);
        break;
      }
    }
  }
}

Iterable<File> _productionFiles() => Directory('lib')
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

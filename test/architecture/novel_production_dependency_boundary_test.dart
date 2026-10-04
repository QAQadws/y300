import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _legacyRepository =
    'lib/features/novel/data/repositories/local_novel_repository.dart';

// These declarations and the fixture repository remain explicit migration debt.
// They need not keep existing, but new production consumers must not be added.
const _legacyDeclarationOwners = <String, String>{
  'LegacyNovelThreadGateway':
      'lib/features/novel/domain/models/novel_thread_models.dart',
  'NovelEpisodeDiscoveryService':
      'lib/features/novel/domain/services/novel_episode_discovery_service.dart',
};

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
          'sync services; legacy fixture APIs may remain in their current owner.',
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
    expect(
      _dependencyViolations(_legacyRepository, '''
class LocalNovelRepository {
  LocalNovelRepository(database, {
    LegacyNovelThreadGateway? threadGateway,
    NovelEpisodeDiscoveryService? discoveryService,
  });
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {}
  Future<void> refreshEpisodes({required String novelId}) async {}
}
'''),
      isEmpty,
    );
    expect(
      _dependencyViolations(
        _legacyRepository,
        'upsertNovelBySeed(seed: seed); refreshEpisodes(novelId: id);',
      ),
      hasLength(2),
    );
  });
}

List<String> _dependencyViolations(String path, String source) {
  final isLegacyRepository = path == _legacyRepository;
  final code = _maskCommentsAndStrings(source);
  final violations = <String>[];
  void report(String edge) => violations.add('$path: $edge');

  for (final entry in _legacyDeclarationOwners.entries) {
    if (!isLegacyRepository &&
        path != entry.value &&
        _identifier(entry.key).hasMatch(code)) {
      report(entry.key);
    }
  }
  final seedCall = _invocationArguments(
    code,
    'upsertNovelBySeed',
  ).any((arguments) => RegExp(r'\bseed\s*:').hasMatch(arguments));
  if ((!isLegacyRepository &&
          _identifier('upsertNovelBySeed').hasMatch(code)) ||
      seedCall) {
    report('upsertNovelBySeed');
  }

  // Comic detail has a different refreshEpisodes API. The legacy novel method
  // requires novelId; also reject novel-local tear-offs before they can escape.
  final novelLocalReference =
      !isLegacyRepository &&
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

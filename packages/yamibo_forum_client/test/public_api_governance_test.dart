import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('public API governance', () {
    test('package license matches the repository GPL license', () {
      final packageLicense = _normalizeNewlines(
        File('LICENSE').readAsStringSync(),
      );
      final repositoryLicense = _normalizeNewlines(
        File('../../LICENSE').readAsStringSync(),
      );

      expect(packageLicense, repositoryLicense);
      expect(packageLicense, contains('GNU GENERAL PUBLIC LICENSE'));
      expect(packageLicense, contains('Version 3, 29 June 2007'));
    });

    test('governance documents describe version 0.5.0 consistently', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final changelog = File('CHANGELOG.md').readAsStringSync();
      final versioning = File('VERSIONING.md').readAsStringSync();
      final migration = File('MIGRATION.md').readAsStringSync();
      final stability = File('API_STABILITY.md').readAsStringSync();

      expect(pubspec, contains('version: 0.5.0'));
      expect(pubspec, contains('publish_to: none'));
      expect(changelog, contains('## 0.5.0'));
      expect(versioning, contains('Semantic Versioning'));
      expect(migration, contains('## 0.4.x to 0.5.0'));
      expect(stability, contains('## Supported within 0.x'));
      expect(stability, contains('## Experimental'));
      expect(stability, contains('## Internal'));
    });

    test('all three public entry points have library documentation', () {
      for (final path in const <String>[
        'lib/yamibo_forum_client.dart',
        'lib/yamibo_forum_client_contracts.dart',
        'lib/yamibo_forum_client_adapters.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source.trimLeft(), startsWith('///'), reason: path);
        expect(source, contains('library;'), reason: path);
      }
      final adapters = File(
        'lib/yamibo_forum_client_adapters.dart',
      ).readAsStringSync();
      expect(adapters, contains('Experimental'));
    });

    test('README states migrated and application-owned boundaries', () {
      final readme = File('README.md').readAsStringSync();

      expect(readme, contains('GPL-3.0-only'));
      expect(readme, contains('Y300 parity and unmigrated APIs'));
      expect(
        readme,
        contains('Forum and thread favorite target-state commands'),
      );
      expect(readme, isNot(contains('favorite/unfavorite mutations')));
      expect(readme, contains('Post rating/comment preparation and commands'));
      expect(readme, contains('WebView login/browsing/fallback'));
      expect(readme, contains('ForumClientCachePorts'));
    });
  });
}

String _normalizeNewlines(String value) =>
    value.replaceAll('\r\n', '\n').trimRight();

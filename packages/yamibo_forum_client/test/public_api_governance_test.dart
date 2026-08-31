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

    test('governance documents describe the pubspec version consistently', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final currentVersion = RegExp(
        r'^version:\s*([^\s]+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1)!;
      final changelog = File('CHANGELOG.md').readAsStringSync();
      final versioning = File('VERSIONING.md').readAsStringSync();
      final migration = File('MIGRATION.md').readAsStringSync();
      final stability = File('API_STABILITY.md').readAsStringSync();
      final readme = File('README.md').readAsStringSync();
      final chineseReadme = File('README.zh-CN.md').readAsStringSync();

      expect(currentVersion, '0.10.0');
      expect(pubspec, contains('publish_to: none'));
      expect(changelog, contains('## $currentVersion'));
      expect(versioning, contains('Semantic Versioning'));
      expect(migration, contains('## 0.9.x to $currentVersion'));
      expect(stability, contains('## Supported within 0.x'));
      expect(stability, contains('## Experimental'));
      expect(stability, contains('## Internal'));
      expect(readme, contains('`0.10.x`'));
      expect(chineseReadme, contains('`$currentVersion`'));
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

    test('experimental adapter exports stay on the explicit allowlist', () {
      final source = File(
        'lib/yamibo_forum_client_adapters.dart',
      ).readAsStringSync();
      final exports = RegExp(
        "export '([^']+)';",
      ).allMatches(source).map((match) => match.group(1)).toList()..sort();

      expect(
        exports,
        <String>[
          'src/adapters/forum_client_adapter_factory.dart',
          'src/adapters/thread_detail_api_mapper.dart',
          'src/adapters/thread_detail_html_parser.dart',
          'src/parsing/data_parse_exception.dart',
        ]..sort(),
      );
      for (final path in exports) {
        final exportedSource = File('lib/$path').readAsStringSync();
        expect(
          exportedSource,
          isNot(contains('ignore_for_file: public_member_api_docs')),
          reason: path,
        );
      }
    });

    test('documentation lint ignores remain internal and allowlisted', () {
      final ignored =
          Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .where(
                (file) => file.readAsStringSync().contains(
                  'ignore_for_file: public_member_api_docs',
                ),
              )
              .map((file) => file.path.replaceAll('\\', '/'))
              .toList()
            ..sort();

      expect(ignored, <String>[
        'lib/src/adapters/discuz_api_client.dart',
        'lib/src/adapters/discuz_comic_read_adapters.dart',
        'lib/src/adapters/discuz_directory_adapters.dart',
        'lib/src/adapters/discuz_forum_directory_html_repository.dart',
        'lib/src/adapters/discuz_forum_display_repositories.dart',
        'lib/src/adapters/discuz_forum_home_html_repository.dart',
        'lib/src/adapters/discuz_forum_search_repository.dart',
        'lib/src/adapters/discuz_forum_tag_directory_repository.dart',
        'lib/src/adapters/discuz_image_attachment_adapters.dart',
        'lib/src/adapters/discuz_profile_html_adapters.dart',
        'lib/src/adapters/discuz_profile_html_parsers.dart',
        'lib/src/adapters/discuz_search_context_validator.dart',
        'lib/src/adapters/discuz_search_html_parser.dart',
        'lib/src/adapters/discuz_supplemental_read_adapters.dart',
        'lib/src/adapters/discuz_tag_directory_html_parser.dart',
        'lib/src/adapters/discuz_thread_repositories.dart',
        'lib/src/adapters/forum_directory_html_parser.dart',
        'lib/src/adapters/forum_directory_snapshot_codec.dart',
        'lib/src/adapters/forum_display_api_mapper.dart',
        'lib/src/adapters/forum_display_html_parser.dart',
        'lib/src/adapters/forum_display_snapshot_codec.dart',
        'lib/src/adapters/forum_home_html_parser.dart',
        'lib/src/adapters/forum_home_snapshot_codec.dart',
        'lib/src/adapters/tag_page_parsing.dart',
        'lib/src/adapters/thread_detail_snapshot_codec.dart',
        'lib/src/parsing/loose_json.dart',
        'lib/src/parsing/strict_json.dart',
        'lib/src/url/forum_uri_resolver.dart',
      ]);
    });

    test('completed deprecations do not remain in the package', () {
      final source = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(source, isNot(contains('buildStandardReads')));
      expect(source, isNot(contains('pollVoteAction')));
      expect(source, isNot(contains('this.actionUrl')));
      expect(source, isNot(contains('this.formHash')));
      expect(source, isNot(contains('@Deprecated')));
    });

    test('generated placeholder Dartdoc does not enter the public package', () {
      final source = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(source, isNot(contains('/// Performs ')));
      expect(source, isNot(contains('/// Returns capabilities.')));
      expect(source, isNot(contains('/// Id.')));
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
      expect(readme, contains('Thread poll-vote command'));
      expect(readme, contains('Image attachments use a separate'));
      expect(readme, contains('WebView login/browsing/fallback'));
      expect(readme, contains('ForumClientCachePorts'));
      expect(readme, contains('ephemeralDio'));
      expect(readme, contains('sourceOverrides'));
      expect(File('README.zh-CN.md').readAsStringSync(), contains('生产装配'));
      expect(File('CONTRIBUTING.md').existsSync(), isTrue);
      expect(File('RELEASING.md').existsSync(), isTrue);
    });
  });
}

String _normalizeNewlines(String value) =>
    value.replaceAll('\r\n', '\n').trimRight();

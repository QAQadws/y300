import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App never imports package internals', () {
    final violations = _dartFiles(<String>['lib', 'test'])
        .where(
          (file) => file.readAsStringSync().contains(
            'package:yamibo_forum_client/'
            'src/',
          ),
        )
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });

  test('adapter construction stays at composition-root wiring boundaries', () {
    const allowed = <String>{
      'lib/core/network/yamibo_forum_client_provider.dart',
      'test/features/forum/data/forum_display_provider_wiring_test.dart',
      'test/features/forum/data/forum_home_repository_test.dart',
      'test/features/tags/data/tag_provider_wiring_test.dart',
      'test/features/thread/data/thread_repository_provider_wiring_test.dart',
    };
    final violations = _dartFiles(<String>['lib', 'test'])
        .where(
          (file) => file.readAsStringSync().contains(
            'yamibo_forum_client_'
            'adapters.dart',
          ),
        )
        .map((file) => _normalized(file.path))
        .where((path) => !allowed.contains(path))
        .toList();

    expect(violations, isEmpty);
  });

  test('migrated compatibility shims and duplicate adapters stay removed', () {
    const removedPaths = <String>[
      'lib/core/data_source/data_read_contract.dart',
      'lib/features/cache/domain/services/cache_load_policy.dart',
      'lib/features/thread/data/repositories/thread_repository.dart',
      'lib/features/thread/data/services/thread_detail_html_parser.dart',
      'lib/features/forum/data/repositories/forum_display_repository.dart',
      'lib/features/comic/data/repositories/discuz_api_comic_episode_catalog_repository.dart',
      'lib/features/favorites/data/repositories/favorite_directory_repositories.dart',
      'lib/features/search/data/repositories/discuz_forum_search_repository.dart',
      'lib/features/tags/data/repositories/forum_tag_directory_repository.dart',
      'lib/features/profile/data/repositories/forum_user_profile_repository.dart',
      'packages/yamibo_forum_client/lib/yamibo_forum_client_parsers.dart',
    ];

    expect(
      removedPaths.where((path) => File(path).existsSync()).toList(),
      isEmpty,
    );
  });
}

Iterable<File> _dartFiles(Iterable<String> roots) sync* {
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    yield* directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
  }
}

String _normalized(String path) => path.replaceAll('\\', '/');

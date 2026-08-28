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

  test('presentation never performs source-specific forum reads', () {
    const forbidden = <String>[
      'yamiboApiClientProvider',
      'apiClientProvider',
      '.getDiscuz(',
    ];
    final violations = _dartFiles(<String>['lib/features'])
        .where((file) => _normalized(file.path).contains('/presentation/'))
        .where((file) {
          final source = file.readAsStringSync();
          return forbidden.any(source.contains);
        })
        .map((file) => file.path)
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
      'lib/features/forum/domain/services/forum_webview_cookie_bootstrapper.dart',
      'lib/features/forum/data/repositories/forum_home_chrome_repository.dart',
      'lib/features/forum/data/models/forum_home_html_models.dart',
      'lib/features/forum/data/services/forum_home_html_parser.dart',
      'lib/features/forum/data/services/forum_home_chrome_parser.dart',
      'lib/features/forum/data/services/forum_home_snapshot_codec.dart',
      'lib/features/profile/data/services/my_message_parser.dart',
      'packages/yamibo_forum_client/lib/yamibo_forum_client_parsers.dart',
      'lib/core/network/image_request_headers.dart',
      'lib/features/auth/data/repositories/auth_repository.dart',
      'lib/features/auth/data/services/auth_remote_data_source.dart',
      'lib/features/auth/data/services/session_verifier.dart',
      'lib/features/auth/data/models/auth_session_models.dart',
      'lib/features/forum/data/repositories/forum_favorite_repository.dart',
      'lib/features/forum/domain/models/forum_favorite_models.dart',
      'lib/features/thread/data/repositories/thread_favorite_repository.dart',
      'lib/features/thread/data/repositories/discuz_thread_favorite_api_repository.dart',
      'lib/features/thread/data/repositories/thread_post_rate_repository.dart',
      'lib/features/thread/data/repositories/thread_post_comment_repository.dart',
    ];

    expect(
      removedPaths.where((path) => File(path).existsSync()).toList(),
      isEmpty,
    );
  });

  test('auth feature cannot restore source-specific authentication calls', () {
    const forbidden = <String>[
      "module: 'login'",
      "module: 'profile'",
      "module: 'forumindex'",
      "'mlogout'",
      '.getDiscuz(',
      'ApiAuthRepository',
      'DiscuzMobileAuthApi',
      'ApiSessionVerifier',
      'ApiFormhashProvider',
    ];
    final violations = _dartFiles(<String>['lib/features/auth'])
        .where((file) {
          final source = file.readAsStringSync();
          return forbidden.any(source.contains);
        })
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });

  test('forum images cannot restore an independent transport bypass', () {
    const forbidden = <String>[
      'ImageRequestHeaderBuilder',
      'DiscuzImageRequestHeaderBuilder',
      'DefaultCacheManager(',
      'HttpFileService(',
    ];
    final violations = _dartFiles(<String>['lib'])
        .where((file) {
          final source = file.readAsStringSync();
          return forbidden.any(source.contains);
        })
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });

  test('migrated read endpoints stay behind the package facade', () {
    const allowedReferenceBuilders = <String>{
      'lib/features/novel/data/services/thread_post_locator_novel_chapter_source_route_resolver.dart',
      'lib/features/thread/domain/services/thread_floor_link_builder.dart',
    };
    const forbidden = <String>[
      "module: 'mynotelist'",
      "module: 'mypm'",
      "module: 'smiley'",
      "'action': 'viewratings'",
      "'goto': 'findpost'",
    ];
    final violations = _dartFiles(<String>['lib'])
        .where((file) {
          final source = file.readAsStringSync();
          return forbidden.any(source.contains);
        })
        .map((file) => _normalized(file.path))
        .where((path) => !allowedReferenceBuilders.contains(path))
        .toList();

    expect(violations, isEmpty);
  });

  test('favorite mutations stay behind package commands', () {
    const forbidden = <String>[
      "module: 'favforum'",
      "module: 'favthread'",
      'ForumFavoriteMutationResult',
      'ThreadUnfavoriteResult',
    ];
    final violations = _dartFiles(<String>['lib'])
        .where((file) {
          final source = file.readAsStringSync();
          return forbidden.any(source.contains);
        })
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });

  test('rating and comment mutations stay behind package commands', () {
    const forbidden = <String>[
      'DiscuzThreadPostRateRepository',
      'DiscuzThreadPostCommentRepository',
      'ThreadPostRateFormFallbackBuilder',
      'threadPostRateRepositoryProvider',
      'threadPostCommentRepositoryProvider',
    ];
    final violations = _dartFiles(<String>['lib'])
        .where((file) {
          final source = file.readAsStringSync();
          return forbidden.any(source.contains);
        })
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });

  test('novel reads cannot reconstruct the version 1 transport', () {
    final violations = _dartFiles(<String>['lib/features/novel'])
        .where((file) {
          final source = file.readAsStringSync();
          return source.contains("module: 'viewthread'") ||
              source.contains("'version': 1") ||
              source.contains("'version': '1'");
        })
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
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

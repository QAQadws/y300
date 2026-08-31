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

  test('Gateway stays transport-only and cannot parse forum sessions', () {
    final source = File(
      'lib/core/network/yamibo/yamibo_http_gateway.dart',
    ).readAsStringSync();
    const forbidden = <String>[
      'YamiboSessionExtractor',
      'YamiboSessionStore',
      'YamiboSessionSnapshot',
      '_saveExtractedSession',
      'saveExtracted(',
    ];

    expect(
      forbidden.where(source.contains).toList(),
      isEmpty,
      reason: 'Gateway must remain transport/Cookie/WAF-only.',
    );
  });

  test('only the package Host adapter writes the App session projection', () {
    const allowed = <String>{
      'lib/core/network/yamibo/yamibo_session_store.dart',
      'lib/core/network/yamibo_forum_client_host_adapters.dart',
    };
    final violations = _dartFiles(<String>['lib'])
        .where((file) => file.readAsStringSync().contains('saveExtracted('))
        .map((file) => _normalized(file.path))
        .where((path) => !allowed.contains(path))
        .toList();

    expect(violations, isEmpty);
  });

  test('migrated compatibility shims and duplicate adapters stay removed', () {
    const removedPaths = <String>[
      'lib/core/data_source/data_read_contract.dart',
      'lib/core/network/api_client.dart',
      'lib/core/network/yamibo/yamibo_api_client.dart',
      'lib/core/network/yamibo/yamibo_html_client.dart',
      'lib/core/network/yamibo/yamibo_resource_client.dart',
      'lib/core/network/yamibo/yamibo_session_extractor.dart',
      'lib/core/network/discuz_response.dart',
      'lib/core/network/discuz_ajax_cdata_parser.dart',
      'lib/core/network/yamibo/yamibo.dart',
      'lib/features/reader_shared/domain/export/export.dart',
      'lib/features/reader_shared/data/export/export.dart',
      'lib/features/reader_shared/domain/metrics/metrics.dart',
      'lib/features/reader_shared/domain/continuous_image/tall_image/tall_image.dart',
      'lib/features/reader_shared/domain/continuous_image/diagnostics/continuous_image_diagnostics.dart',
      'lib/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart',
      'lib/features/comic/data/providers/comic_refresh_outcome_providers.dart',
      'lib/features/comic/data/providers/comic_search_refresh_queue_providers.dart',
      'lib/features/profile/data/services/discuz_profile_auth_page_detector.dart',
      'lib/features/more/presentation/cache_settings_page.dart',
      'lib/features/more/presentation/cache_settings_controller.dart',
      'lib/features/more/data/more_settings_repository.dart',
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
      'lib/features/auth/data/providers/auth_formhash_provider.dart',
      'lib/features/auth/domain/services/formhash_provider.dart',
      'lib/features/posting/data/repositories/new_thread_repository.dart',
      'lib/features/posting/data/repositories/posting_form_metadata_repository.dart',
      'lib/features/posting/data/services/new_thread_remote_data_source.dart',
      'lib/features/posting/domain/services/new_thread_payload_builder.dart',
      'lib/features/posting/domain/services/new_thread_response_parser.dart',
      'lib/features/posting/domain/services/posting_form_metadata_parser.dart',
      'lib/features/reply/data/repositories/reply_repository.dart',
      'lib/features/reply/data/repositories/discuz_reply_api_repository.dart',
      'lib/features/reply/data/services/discuz_reply_remote_data_source.dart',
      'lib/features/reply/data/services/reply_form_preparation_data_source.dart',
      'lib/features/reply/domain/services/reply_form_parser.dart',
      'lib/features/composer_shared/data/repositories/discuz_composer_attachment_repository.dart',
      'lib/features/composer_shared/data/repositories/discuz_composer_unused_image_repository.dart',
      'lib/features/composer_shared/data/services/composer_attachment_remote_data_source.dart',
      'lib/features/composer_shared/data/services/composer_unused_image_parser.dart',
      'lib/features/composer_shared/data/services/composer_unused_image_remote_data_source.dart',
      'lib/features/thread/data/services/discuz_post_edit_delete_response_parser.dart',
      'lib/features/thread/domain/services/post_edit_attachment_delete_uri_builder.dart',
      'lib/features/thread/data/repositories/thread_poll_vote_repository.dart',
      'lib/features/thread/data/repositories/discuz_post_edit_repository.dart',
      'lib/features/thread/data/services/discuz_successful_control_extractor.dart',
      'lib/features/thread/data/services/post_edit_form_parser.dart',
      'lib/features/thread/data/services/post_edit_remote_data_source.dart',
      'lib/features/thread/data/services/post_edit_submit_response_parser.dart',
      'lib/features/thread/domain/repositories/post_edit_repository.dart',
      'lib/features/thread/domain/services/post_edit_baseline_fingerprint_service.dart',
      'lib/features/thread/domain/services/post_edit_native_capability_classifier.dart',
      'lib/features/thread/domain/services/post_edit_submit_payload_builder.dart',
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

  test('poll mutations stay behind the package command', () {
    const forbidden = <String>[
      "module: 'pollvote'",
      "'action': 'votepoll'",
      'ThreadPollVoteRepository',
      'threadPollVoteRepositoryProvider',
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

  test('post-edit protocols stay behind package contracts', () {
    const forbidden = <String>[
      'editsubmit',
      'DiscuzPostEditRepository',
      'PostEditRemoteDataSource',
      'PostEditFormParser',
      'PostEditSubmitResponseParser',
      'YamiboHttpGateway',
      'package:dio',
    ];
    final violations = _dartFiles(<String>['lib/features/thread'])
        .where((file) {
          final source = file.readAsStringSync();
          return forbidden.any(source.contains);
        })
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });

  test('thread creation and replies stay behind package commands', () {
    const forbidden = <String>[
      "module: 'newthread'",
      "module: 'sendreply'",
      'PackageBackedFormhashProvider',
      'PostingFormMetadataRepository',
      'NewThreadRepository',
      'ReplyRepository',
      'ReplyFormParser',
    ];
    final violations =
        _dartFiles(<String>['lib/features/posting', 'lib/features/reply'])
            .where((file) {
              final source = file.readAsStringSync();
              return forbidden.any(source.contains) ||
                  source.contains('YamiboHttpGateway') ||
                  source.contains('package:dio');
            })
            .map((file) => file.path)
            .toList();

    expect(violations, isEmpty);
  });

  test('image attachment protocols stay behind package contracts', () {
    const forbidden = <String>[
      "module: 'checkpost'",
      "module: 'forumupload'",
      "'action': 'imagelist'",
      "'action': 'deleteattach'",
      'ComposerAttachmentRemoteDataSource',
      'ComposerUnusedImageParser',
      'PostEditAttachmentDeleteUriBuilder',
      'DiscuzPostEditDeleteResponseParser',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    hide ForumHomeRepository, ForumHomeFavoriteForum;
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/services/forum_home_request_profile_resolver.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/forum/presentation/forum_shell_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../support/forum_auth_test_support.dart';
import '../../../support/forum_home_test_support.dart';
import '../../../test_support/localized_test_app.dart';

void main() {
  for (final previousMode in <String?>[null, 'native', 'webview', 'invalid']) {
    testWidgets(
      'old display preference $previousMode opens the shared forum UI',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'forum_shell_mode': ?previousMode,
          'unrelated_preference': 'preserve',
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...forumAuthOverrides(_GuestAuthRepository()),
              forumHomeRepositoryProvider.overrideWithValue(_HomeRepository()),
              forumHomeRequestProfileResolverProvider.overrideWithValue(
                const _AnonymousProfileResolver(),
              ),
              forumWebViewDriverFactoryProvider.overrideWithValue(
                () => throw StateError(
                  'The forum entry must not mount a WebView',
                ),
              ),
            ],
            child: const LocalizedTestApp(
              home: ForumShellPage(isActive: false),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(ForumHomePage)),
        );
        expect(find.text(l10n.forumHomeTitle), findsOneWidget);
        expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
        expect(find.byKey(const Key('forum-webview-page')), findsNothing);
        expect(
          tester.widget<ForumHomePage>(find.byType(ForumHomePage)).isActive,
          isFalse,
        );
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString('forum_shell_mode'), previousMode);
        expect(preferences.getString('unrelated_preference'), 'preserve');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _HomeRepository implements ForumHomeRepository {
  @override
  Future<ForumHomeCacheEntry?> readCachedPayload({
    required DocumentRequestProfile requestProfile,
  }) async => null;

  @override
  Future<ForumHomeReadResult> getForumHomePayload({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  }) async => forumHomeReadSuccess(
    ForumHomePayload(
      directory: const ForumDirectoryData(sections: []),
      isLoggedIn: false,
      favoriteForums: [],
    ),
  );
}

class _AnonymousProfileResolver implements ForumHomeRequestProfileResolver {
  const _AnonymousProfileResolver();

  @override
  Future<DocumentRequestProfile> resolve() async =>
      DocumentRequestProfile.anonymous;
}

class _GuestAuthRepository implements AuthRepository {
  @override
  Future<ApiResult<SessionInfo>> refreshSession() async => const ApiSuccess(
    SessionInfo(uid: '0', username: '', formhash: '', isLoggedIn: false),
  );

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async =>
      const ApiSuccess(false);

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) => throw StateError('Unexpected login');

  @override
  Future<void> logout() async {}
}

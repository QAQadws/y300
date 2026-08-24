import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';

import '../../../support/forum_home_test_support.dart';

void main() {
  testWidgets(
    'ForumHomePage app bar does not contain login entry after migration',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumHomeRepositoryProvider.overrideWithValue(
              _FakeForumHomeRepository(),
            ),
            authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          ],
          child: const LocalizedTestApp(home: ForumHomePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.login), findsNothing);
      expect(find.text('登录'), findsNothing);
    },
  );
}

class _FakeForumHomeRepository implements ForumHomeRepository {
  @override
  Future<ForumHomeCacheEntry?> readCachedPayload({
    required DocumentRequestProfile requestProfile,
  }) async {
    return null;
  }

  @override
  Future<ForumHomeReadResult> getForumHomePayload({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  }) async {
    return forumHomeReadSuccess(
      ForumHomePayload(
        directory: const ForumDirectoryData(
          sections: [
            ForumDirectorySection(
              identity: '1',
              title: '综合区',
              forums: [
                ForumDirectoryForum(
                  fid: '2',
                  title: '公告区',
                  description: '',
                  todayPosts: null,
                ),
              ],
            ),
          ],
        ),
        isLoggedIn: false,
        favoriteForums: const [],
      ),
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    return ApiSuccess(
      SessionInfo(uid: '0', username: '', formhash: '', isLoggedIn: false),
    );
  }

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    throw StateError('login is not part of this test');
  }

  @override
  Future<void> logout() async {
    throw StateError('logout is not part of this test');
  }

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    throw StateError('verifyAuthByForumIndex is not part of this test');
  }
}

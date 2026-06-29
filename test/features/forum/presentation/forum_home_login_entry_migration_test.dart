import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';

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
          child: const MaterialApp(home: ForumHomePage()),
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
  Future<ApiResult<ForumHomePayload>> getForumHomePayload({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  }) async {
    return ApiSuccess(
      ForumHomePayload(
        forumIndex: ForumIndexData(
          categories: [
            ForumCategory(fid: '1', name: '综合区', forums: const ['2']),
          ],
          forums: [
            ForumItem(
              fid: '2',
              name: '公告区',
              threads: 1,
              posts: 1,
              todayPosts: 0,
              description: '',
              icon: '',
              subForums: [],
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/forum/data/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';

void main() {
  testWidgets('ForumHomePage app bar does not contain login entry after migration', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumHomeRepositoryProvider.overrideWithValue(_FakeForumHomeRepository()),
        ],
        child: const MaterialApp(home: ForumHomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.login), findsNothing);
    expect(find.text('登录'), findsNothing);
  });
}

class _FakeForumHomeRepository implements ForumHomeRepository {
  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload() async {
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

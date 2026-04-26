import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/forum/data/forum_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';

void main() {
  group('ForumHomePage', () {
    testWidgets('shows loading skeleton before data returns', (tester) async {
      final completer = Completer<ApiResult<ForumIndexData>>();
      final repository = _FakeForumRepository(() => completer.future);

      await tester.pumpWidget(_buildTestApp(repository));

      expect(find.byKey(const Key('forum-home-skeleton')), findsOneWidget);

      completer.complete(ApiSuccess(_sampleData()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      expect(find.text('综合区'), findsOneWidget);
      expect(find.text('公告区'), findsOneWidget);
    });

    testWidgets('renders grouped forum data after successful load', (tester) async {
      final repository = _FakeForumRepository(
        () async => ApiSuccess(_sampleData()),
      );

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      expect(find.text('共 1 个分组，1 个版块'), findsOneWidget);
      expect(find.text('综合区'), findsOneWidget);
      expect(find.text('公告区'), findsOneWidget);
      expect(find.byKey(const Key('forum-card-2')), findsOneWidget);
    });
  });
}

Widget _buildTestApp(ForumRepository repository) {
  return ProviderScope(
    overrides: [forumRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: ForumHomePage()),
  );
}

ForumIndexData _sampleData() {
  return ForumIndexData(
    categories: [
      ForumCategory(fid: '1', name: '综合区', forums: ['2']),
    ],
    forums: [
      ForumItem(
        fid: '2',
        name: '公告区',
        threads: 12,
        posts: 34,
        todayPosts: 2,
        description: '站点公告与维护信息',
        icon: '',
        subForums: const [],
      ),
    ],
  );
}

class _FakeForumRepository implements ForumRepository {
  _FakeForumRepository(this._loader);

  final Future<ApiResult<ForumIndexData>> Function() _loader;

  @override
  Future<ApiResult<ForumIndexData>> getForumIndex() {
    return _loader();
  }
}

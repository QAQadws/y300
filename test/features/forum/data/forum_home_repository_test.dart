import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';

void main() {
  group('DiscuzForumHomeRepository', () {
    test('returns failure when forumindex request fails', () async {
      final repository = DiscuzForumHomeRepository(
        loadForumIndex: () async => const ApiFailure(
          ApiError(type: ApiErrorType.server, message: 'boom'),
        ),
        refreshSession: () async => ApiSuccess(_loggedOutSession()),
      );

      final result = await repository.getForumHomePayload();

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, 'boom');
    });

    test('degrades to logged-out payload when session refresh fails', () async {
      final repository = DiscuzForumHomeRepository(
        loadForumIndex: () async => ApiSuccess(_sampleForumIndexData()),
        refreshSession: () async => const ApiFailure(
          ApiError(type: ApiErrorType.network, message: 'offline'),
        ),
      );

      final result = await repository.getForumHomePayload();

      expect(result.isSuccess, isTrue);
      final payload = result.dataOrNull!;
      expect(payload.isLoggedIn, isFalse);
      expect(payload.favoriteForums, isEmpty);
    });

    test('loads favorite forum payload after login', () async {
      final repository = DiscuzForumHomeRepository(
        loadForumIndex: () async => ApiSuccess(_sampleForumIndexData()),
        refreshSession: () async => ApiSuccess(_loggedInSession()),
        loadFavoriteForums: () async => ApiSuccess(<FavoriteForum>[
          FavoriteForum(
            favid: '1',
            fid: '30',
            title: '我收藏的版块',
            description: '',
            threads: 1,
            posts: 2,
            todayPosts: 0,
          ),
        ]),
      );

      final result = await repository.getForumHomePayload();

      expect(result.isSuccess, isTrue);
      final payload = result.dataOrNull!;
      expect(payload.isLoggedIn, isTrue);
      expect(payload.favoriteForums.single.fid, '30');
    });
  });
}

ForumIndexData _sampleForumIndexData() {
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

SessionInfo _loggedInSession() {
  return SessionInfo(
    uid: '597454',
    username: 'tester',
    formhash: '14502ecf',
    isLoggedIn: true,
  );
}

SessionInfo _loggedOutSession() {
  return SessionInfo(uid: '0', username: '', formhash: '', isLoggedIn: false);
}

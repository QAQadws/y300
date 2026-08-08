import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/data/services/forum_favorite_action_service.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';

void main() {
  group('ForumFavoriteActionService', () {
    test('favorites the server-declared forum directly', () async {
      final repository = _FakeForumFavoriteRepository();
      final service = ForumFavoriteActionService(repository);

      final result = await service.apply(
        fid: ' 33 ',
        action: ForumDisplayFavoriteAction.favorite,
      );

      expect(result.isSuccess, isTrue);
      expect(repository.favoriteFids, <String>['33']);
      expect(repository.loadCallCount, 0);
    });

    test('resolves favid before canceling a favorited forum', () async {
      final repository = _FakeForumFavoriteRepository(
        favoriteForums: <FavoriteForum>[
          _favoriteForum(fid: '33', favid: 'fav-33'),
        ],
      );
      final service = ForumFavoriteActionService(repository);

      final result = await service.apply(
        fid: '33',
        action: ForumDisplayFavoriteAction.unfavorite,
      );

      expect(result.isSuccess, isTrue);
      expect(repository.loadCallCount, 1);
      expect(repository.unfavoriteFavids, <String>['fav-33']);
    });

    test('fails closed when the forum favorite action is unknown', () async {
      final repository = _FakeForumFavoriteRepository();
      final service = ForumFavoriteActionService(repository);

      final result = await service.apply(
        fid: '33',
        action: ForumDisplayFavoriteAction.unknown,
      );

      expect(result, isA<ApiFailure<ForumFavoriteMutationResult>>());
      expect(repository.favoriteFids, isEmpty);
      expect(repository.unfavoriteFavids, isEmpty);
      expect(repository.loadCallCount, 0);
    });

    test('fails closed when the server list has no matching favid', () async {
      final repository = _FakeForumFavoriteRepository();
      final service = ForumFavoriteActionService(repository);

      final result = await service.apply(
        fid: '33',
        action: ForumDisplayFavoriteAction.unfavorite,
      );

      expect(result, isA<ApiFailure<ForumFavoriteMutationResult>>());
      expect(repository.loadCallCount, 1);
      expect(repository.unfavoriteFavids, isEmpty);
    });
  });
}

FavoriteForum _favoriteForum({required String fid, required String favid}) {
  return FavoriteForum(
    favid: favid,
    fid: fid,
    title: '版块 $fid',
    description: '',
    threads: 0,
    posts: 0,
    todayPosts: 0,
  );
}

class _FakeForumFavoriteRepository implements ForumFavoriteRepository {
  _FakeForumFavoriteRepository({List<FavoriteForum>? favoriteForums})
    : favoriteForums = favoriteForums ?? <FavoriteForum>[];

  final List<FavoriteForum> favoriteForums;
  final favoriteFids = <String>[];
  final unfavoriteFavids = <String>[];
  int loadCallCount = 0;

  @override
  Future<ApiResult<List<FavoriteForum>>> loadFavoriteForums() async {
    loadCallCount += 1;
    return ApiSuccess<List<FavoriteForum>>(favoriteForums);
  }

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> favoriteForum({
    required String fid,
  }) async {
    favoriteFids.add(fid);
    return const ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(),
    );
  }

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> unfavoriteForum({
    required String favid,
  }) async {
    unfavoriteFavids.add(favid);
    return const ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(),
    );
  }
}

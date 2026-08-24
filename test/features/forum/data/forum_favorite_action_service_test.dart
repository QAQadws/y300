import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/data/services/forum_favorite_action_service.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';

void main() {
  group('ForumFavoriteActionService', () {
    test('favorites the server-declared forum directly', () async {
      final repository = _FakeForumFavoriteRepository();
      final service = _service(repository);

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
        favoriteForums: <FavoriteForumEntry>[
          _favoriteForum(fid: '33', favid: 'fav-33'),
        ],
      );
      final service = _service(repository);

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
      final service = _service(repository);

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
      final service = _service(repository);

      final result = await service.apply(
        fid: '33',
        action: ForumDisplayFavoriteAction.unfavorite,
      );

      expect(result, isA<ApiFailure<ForumFavoriteMutationResult>>());
      expect(repository.loadCallCount, 1);
      expect(repository.unfavoriteFavids, isEmpty);
    });

    test('fails closed when remote favorite identity is unsupported', () async {
      final repository = _FakeForumFavoriteRepository(
        favoriteForums: <FavoriteForumEntry>[
          _favoriteForum(fid: '33', favid: 'fav-33'),
        ],
        sourceCapabilities: _unsupportedRemoteIdentityCapabilities,
      );
      final service = _service(repository);

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

ForumFavoriteActionService _service(_FakeForumFavoriteRepository repository) {
  return ForumFavoriteActionService(
    mutationRepository: repository,
    directoryRepository: repository,
  );
}

FavoriteForumEntry _favoriteForum({
  required String fid,
  required String favid,
}) {
  return FavoriteForumEntry(
    fid: fid,
    title: '版块 $fid',
    remoteFavoriteId: favid,
    description: '',
    threadCount: 0,
    postCount: 0,
    todayPostCount: 0,
  );
}

class _FakeForumFavoriteRepository
    implements ForumFavoriteRepository, FavoriteForumDirectoryRepository {
  _FakeForumFavoriteRepository({
    List<FavoriteForumEntry>? favoriteForums,
    FavoriteForumDirectorySourceCapabilities? sourceCapabilities,
  }) : favoriteForums = favoriteForums ?? <FavoriteForumEntry>[],
       _capabilities = sourceCapabilities ?? _sourceCapabilities;

  final List<FavoriteForumEntry> favoriteForums;
  final FavoriteForumDirectorySourceCapabilities _capabilities;
  final favoriteFids = <String>[];
  final unfavoriteFavids = <String>[];
  int loadCallCount = 0;

  @override
  FavoriteForumDirectorySourceCapabilities get capabilities => _capabilities;

  @override
  Future<
    DataReadResult<
      FavoriteForumDirectoryData,
      FavoriteForumDirectoryReadCapabilities
    >
  >
  load(
    FavoriteForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    loadCallCount += 1;
    return DataReadSuccess(
      data: FavoriteForumDirectoryData(items: favoriteForums),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
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

final _sourceCapabilities = FavoriteForumDirectorySourceCapabilities(
  values: DataCapabilitySet<FavoriteForumDirectoryCapability>.supported(
    FavoriteForumDirectoryCapability.values,
  ),
);

final _unsupportedRemoteIdentityCapabilities =
    FavoriteForumDirectorySourceCapabilities(
      values: DataCapabilitySet<FavoriteForumDirectoryCapability>.from(
        supported: FavoriteForumDirectoryCapability.values.where(
          (capability) =>
              capability !=
              FavoriteForumDirectoryCapability.stableRemoteFavoriteIdentity,
        ),
        unsupported: const <FavoriteForumDirectoryCapability>[
          FavoriteForumDirectoryCapability.stableRemoteFavoriteIdentity,
        ],
      ),
    );

import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_favorite_repository.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/tags/data/forum_tag_repository.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';

void main() {
  test('build defaults to home loading state', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    final state = await container.read(forumWebViewControllerProvider.future);

    expect(
      state.currentUri.toString(),
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    expect(state.pageKind, ForumWebViewPageKind.home);
    expect(state.fid, isNull);
    expect(state.tid, isNull);
    expect(state.boardName, isNull);
    expect(state.pageTitle, isNull);
    expect(state.canGoBack, isFalse);
    expect(state.favoriteForums, isEmpty);
    expect(state.currentFavoriteForum, isNull);
    expect(state.isFavoriteMutationLoading, isFalse);
    expect(state.isLoading, isTrue);
    expect(state.loadingProgress, 0);
  });

  test('onPageStarted updates current uri and page kind', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    container
        .read(forumWebViewControllerProvider.notifier)
        .onPageStarted(
          'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
        );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.forumDisplay);
    expect(state.fid, '55');
    expect(state.isLoading, isTrue);
    expect(state.loadingProgress, 0);
  });

  test('onProgress updates loading progress while keeping loading state', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    container.read(forumWebViewControllerProvider.notifier).onProgress(42);

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.loadingProgress, 42);
    expect(state.isLoading, isTrue);
  });

  test('onPageFinished resolves board name and canGoBack', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    await container.read(forumWebViewControllerProvider.notifier).onPageFinished(
          rawUrl:
              'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
          pageTitle: '页面标题',
          canGoBack: true,
        );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.forumDisplay);
    expect(state.fid, '55');
    expect(state.boardName, '综合区');
    expect(state.pageTitle, '页面标题');
    expect(state.canGoBack, isTrue);
    expect(state.isLoading, isFalse);
    expect(state.loadingProgress, 100);
  });

  test('forum display completion refreshes favorite forums and matches current forum', () async {
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: <FavoriteForum>[
        _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
        _favoriteForum(fid: '66', favid: 'fav-66', title: '讨论区'),
      ],
    );
    final container = _createContainer(
      favoriteRepository: favoriteRepository,
    );
    addTearDown(container.dispose);

    await container.read(forumWebViewControllerProvider.notifier).onPageFinished(
          rawUrl:
              'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
          pageTitle: '页面标题',
          canGoBack: true,
        );
    await pumpEventQueue();

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(favoriteRepository.loadCallCount, 1);
    expect(state.favoriteForums.length, 2);
    expect(state.currentFavoriteForum?.fid, '55');
  });

  test('thread detail keeps previous fid when url does not carry it', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    controller.onPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );
    await controller.onPageFinished(
      rawUrl: 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      pageTitle: '综合区页面',
      canGoBack: true,
    );
    await pumpEventQueue();
    controller.onPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    await controller.onPageFinished(
      rawUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      pageTitle: '主题标题',
      canGoBack: true,
    );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.threadDetail);
    expect(state.fid, '55');
    expect(state.tid, '123');
    expect(state.boardName, '综合区');
    expect(state.isLoading, isFalse);
    expect(state.loadingProgress, 100);
  });

  test('board name falls back to page title when tag lookup misses fid', () async {
    final container = _createContainer(
      repository: _FakeForumTagRepository(const <ForumBoardTagSet>[]),
    );
    addTearDown(container.dispose);

    await container.read(forumWebViewControllerProvider.notifier).onPageFinished(
          rawUrl:
              'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=66&mobile=2',
          pageTitle: '回退标题',
          canGoBack: false,
        );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.boardName, '回退标题');
    expect(state.canGoBack, isFalse);
  });

  test('favoriteCurrentForum refreshes favorite state after success', () async {
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: const <FavoriteForum>[],
      onFavorite: (fid) => _favoriteForum(
        fid: fid,
        favid: 'fav-$fid',
        title: '版块$fid',
      ),
    );
    final container = _createContainer(
      favoriteRepository: favoriteRepository,
    );
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    controller.onPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );

    final result = await controller.favoriteCurrentForum();

    expect(result.isSuccess, isTrue);
    expect(favoriteRepository.favoriteCalls, <String>['55']);
    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.currentFavoriteForum?.fid, '55');
    expect(state.isFavoriteMutationLoading, isFalse);
  });

  test('unfavoriteCurrentForum refreshes favorite state after success', () async {
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: <FavoriteForum>[
        _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
      ],
    );
    final container = _createContainer(
      favoriteRepository: favoriteRepository,
    );
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    await controller.onPageFinished(
      rawUrl: 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      pageTitle: '综合区页面',
      canGoBack: true,
    );
    await pumpEventQueue();

    final result = await controller.unfavoriteCurrentForum();

    expect(result.isSuccess, isTrue);
    expect(favoriteRepository.unfavoriteCalls, <String>['fav-55']);
    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.currentFavoriteForum, isNull);
    expect(state.favoriteForums, isEmpty);
  });

  test('unfavoriteForumByFavid refreshes cached favorite forums', () async {
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: <FavoriteForum>[
        _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
        _favoriteForum(fid: '66', favid: 'fav-66', title: '讨论区'),
      ],
    );
    final container = _createContainer(
      favoriteRepository: favoriteRepository,
    );
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    final preload = await controller.loadFavoriteForums();
    expect(preload.isSuccess, isTrue);

    final result = await controller.unfavoriteForumByFavid(favid: 'fav-55');

    expect(result.isSuccess, isTrue);
    expect(favoriteRepository.unfavoriteCalls, <String>['fav-55']);
    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.favoriteForums.map((item) => item.fid), <String>['66']);
  });
}

ProviderContainer _createContainer({
  ForumTagRepository? repository,
  ForumFavoriteRepository? favoriteRepository,
}) {
  final container = ProviderContainer(
    overrides: [
      forumTagRepositoryProvider.overrideWithValue(
        repository ?? _FakeForumTagRepository(_defaultBoards),
      ),
      forumFavoriteRepositoryProvider.overrideWithValue(
        favoriteRepository ?? _FakeForumFavoriteRepository(),
      ),
    ],
  );
  container.listen(
    forumWebViewControllerProvider,
    (_, _) {},
  );
  return container;
}

const List<ForumBoardTagSet> _defaultBoards = <ForumBoardTagSet>[
  ForumBoardTagSet(
    fid: '55',
    name: '综合区',
    tags: <ForumTagDefinition>[],
  ),
];

class _FakeForumTagRepository implements ForumTagRepository {
  const _FakeForumTagRepository(this.boards);

  final List<ForumBoardTagSet> boards;

  @override
  Future<ForumTagLookup> loadLookup() async {
    return ForumTagLookup(boards);
  }
}

FavoriteForum _favoriteForum({
  required String fid,
  required String favid,
  required String title,
}) {
  return FavoriteForum(
    favid: favid,
    fid: fid,
    title: title,
    description: '',
    threads: 0,
    posts: 0,
    todayPosts: 0,
  );
}

class _FakeForumFavoriteRepository implements ForumFavoriteRepository {
  _FakeForumFavoriteRepository({
    List<FavoriteForum>? favoriteForums,
    this.onFavorite,
  }) : favoriteForums =
           List<FavoriteForum>.from(favoriteForums ?? const <FavoriteForum>[]);

  List<FavoriteForum> favoriteForums;
  final FavoriteForum Function(String fid)? onFavorite;

  final List<String> favoriteCalls = <String>[];
  final List<String> unfavoriteCalls = <String>[];
  int loadCallCount = 0;

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> favoriteForum({
    required String fid,
  }) async {
    favoriteCalls.add(fid);
    const result = ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(message: '收藏成功'),
    );
    if (result.isSuccess) {
      final forum =
          onFavorite?.call(fid) ??
          _favoriteForum(fid: fid, favid: 'fav-$fid', title: '版块$fid');
      favoriteForums = <FavoriteForum>[
        ...favoriteForums.where((item) => item.fid != forum.fid),
        forum,
      ];
    }
    return result;
  }

  @override
  Future<ApiResult<List<FavoriteForum>>> loadFavoriteForums() async {
    loadCallCount += 1;
    return ApiSuccess<List<FavoriteForum>>(
      List<FavoriteForum>.from(favoriteForums),
    );
  }

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> unfavoriteForum({
    required String favid,
  }) async {
    unfavoriteCalls.add(favid);
    const result = ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(message: '取消收藏成功'),
    );
    if (result.isSuccess) {
      favoriteForums = favoriteForums
          .where((item) => item.favid != favid)
          .toList();
    }
    return result;
  }
}

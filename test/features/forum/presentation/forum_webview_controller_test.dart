import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/favorites/data/providers/favorite_directory_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/tags/data/repositories/forum_tag_repository.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';

import '../../../support/favorite_command_test_support.dart';

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
    expect(state.searchScope, isNull);
    expect(state.fid, isNull);
    expect(state.tid, isNull);
    expect(state.boardName, isNull);
    expect(state.pageTitle, isNull);
    expect(state.canGoBack, isFalse);
    expect(state.favoriteForums, isEmpty);
    expect(state.currentFavoriteForum, isNull);
    expect(state.isFavoriteMutationLoading, isFalse);
    expect(state.threadDetailMenu, isNull);
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

  test(
    'onProgress updates loading progress while keeping loading state',
    () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      container.read(forumWebViewControllerProvider.notifier).onProgress(42);

      final state = await container.read(forumWebViewControllerProvider.future);
      expect(state.loadingProgress, 42);
      expect(state.isLoading, isTrue);
    },
  );

  test('onPageFinished resolves board name and canGoBack', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    await container
        .read(forumWebViewControllerProvider.notifier)
        .onPageFinished(
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

  test(
    'forum display completion refreshes favorite forums and matches current forum',
    () async {
      final favoriteRepository = _FakeForumFavoriteRepository(
        favoriteForums: <FavoriteForumEntry>[
          _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
          _favoriteForum(fid: '66', favid: 'fav-66', title: '讨论区'),
        ],
      );
      final container = _createContainer(
        favoriteRepository: favoriteRepository,
      );
      addTearDown(container.dispose);

      await container
          .read(forumWebViewControllerProvider.notifier)
          .onPageFinished(
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
    },
  );

  test(
    'curforum search keeps search scope and fid when result url drops srhfid',
    () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        forumWebViewControllerProvider.notifier,
      );
      await controller.onPageFinished(
        rawUrl:
            'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
        pageTitle: '综合区页面',
        canGoBack: true,
      );

      controller.onPageStarted(
        'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=55&mobile=2',
      );
      await controller.onPageFinished(
        rawUrl:
            'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=55&mobile=2',
        pageTitle: '帖子搜索',
        canGoBack: true,
      );

      controller.onPageStarted(
        'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
      );
      await controller.onPageFinished(
        rawUrl:
            'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
        pageTitle: '帖子搜索',
        canGoBack: true,
      );

      final state = await container.read(forumWebViewControllerProvider.future);
      expect(state.pageKind, ForumWebViewPageKind.search);
      expect(state.searchScope, ForumWebViewSearchScope.curForum);
      expect(state.fid, '55');
      expect(state.boardName, '综合区');
    },
  );

  test('forum search stays in forum scope without fid', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    controller.onPageStarted(
      'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
    );
    await controller.onPageFinished(
      rawUrl:
          'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
      pageTitle: '帖子搜索',
      canGoBack: true,
    );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.search);
    expect(state.searchScope, ForumWebViewSearchScope.forum);
    expect(state.fid, isNull);
    expect(state.boardName, isNull);
  });

  test('thread detail keeps previous fid when url does not carry it', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    controller.onPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );
    await controller.onPageFinished(
      rawUrl:
          'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      pageTitle: '综合区页面',
      canGoBack: true,
    );
    await pumpEventQueue();
    controller.onPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    await controller.onPageFinished(
      rawUrl:
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      pageTitle: '主题标题',
      canGoBack: true,
    );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.threadDetail);
    expect(state.fid, '55');
    expect(state.tid, '123');
    expect(state.boardName, '综合区');
    expect(state.threadDetailMenu?.isAuthorOnly, isFalse);
    expect(state.threadDetailMenu?.isReverseOrder, isFalse);
    expect(state.isLoading, isFalse);
    expect(state.loadingProgress, 100);
  });

  test(
    'thread detail start derives author and order flags from current url',
    () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      container
          .read(forumWebViewControllerProvider.notifier)
          .onPageStarted(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&authorid=9&ordertype=1&mobile=2',
          );

      final state = await container.read(forumWebViewControllerProvider.future);
      expect(state.pageKind, ForumWebViewPageKind.threadDetail);
      expect(state.threadDetailMenu?.isAuthorOnly, isTrue);
      expect(state.threadDetailMenu?.isReverseOrder, isTrue);
      expect(
        state.threadDetailMenu?.normalThreadUri?.toString(),
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&ordertype=1&mobile=2',
      );
      expect(
        state.threadDetailMenu?.normalOrderUri.toString(),
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
      );
    },
  );

  test('thread detail completion merges dom snapshot with fallback urls', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    const rawUrl =
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&mobile=2';
    final controller = container.read(forumWebViewControllerProvider.notifier);
    controller.onPageStarted(rawUrl);
    await controller.onPageFinished(
      rawUrl: rawUrl,
      pageTitle: '主题标题',
      canGoBack: true,
      threadMenuSnapshot: ForumThreadMenuSnapshot(
        authorOnlyUri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&authorid=9&mobile=2',
        ),
        reverseOrderUri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&ordertype=1&mobile=2',
        ),
      ),
    );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.threadDetailMenu?.isAuthorOnly, isFalse);
    expect(
      state.threadDetailMenu?.authorOnlyUri?.toString(),
      contains('authorid=9'),
    );
    expect(
      state.threadDetailMenu?.reverseOrderUri.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&ordertype=1&mobile=2',
    );
    expect(
      state.threadDetailMenu?.normalOrderUri.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&mobile=2',
    );
  });

  test(
    'thread detail can fallback normalThreadUri when current url already filters author',
    () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      const rawUrl =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&authorid=9&mobile=2';
      final controller = container.read(
        forumWebViewControllerProvider.notifier,
      );
      controller.onPageStarted(rawUrl);
      await controller.onPageFinished(
        rawUrl: rawUrl,
        pageTitle: '主题标题',
        canGoBack: true,
        threadMenuSnapshot: const ForumThreadMenuSnapshot(),
      );

      final state = await container.read(forumWebViewControllerProvider.future);
      expect(state.threadDetailMenu?.isAuthorOnly, isTrue);
      expect(
        state.threadDetailMenu?.normalThreadUri?.toString(),
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
    },
  );

  test(
    'thread detail hides author action when no dom link is available',
    () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      const rawUrl =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2';
      final controller = container.read(
        forumWebViewControllerProvider.notifier,
      );
      controller.onPageStarted(rawUrl);
      await controller.onPageFinished(
        rawUrl: rawUrl,
        pageTitle: '主题标题',
        canGoBack: true,
        threadMenuSnapshot: const ForumThreadMenuSnapshot(),
      );

      final state = await container.read(forumWebViewControllerProvider.future);
      expect(state.threadDetailMenu?.isAuthorOnly, isFalse);
      expect(state.threadDetailMenu?.authorOnlyUri, isNull);
    },
  );

  test('non thread page clears thread detail menu', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    controller.onPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
    );
    controller.onPageStarted(
      'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
    );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.search);
    expect(state.threadDetailMenu, isNull);
  });

  test(
    'board name falls back to page title when tag lookup misses fid',
    () async {
      final container = _createContainer(
        repository: _FakeForumTagRepository(const <ForumBoardTagSet>[]),
      );
      addTearDown(container.dispose);

      await container
          .read(forumWebViewControllerProvider.notifier)
          .onPageFinished(
            rawUrl:
                'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=66&mobile=2',
            pageTitle: '回退标题',
            canGoBack: false,
          );

      final state = await container.read(forumWebViewControllerProvider.future);
      expect(state.boardName, '回退标题');
      expect(state.canGoBack, isFalse);
    },
  );

  test('favoriteCurrentForum refreshes favorite state after success', () async {
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: const <FavoriteForumEntry>[],
      onFavorite: (fid) =>
          _favoriteForum(fid: fid, favid: 'fav-$fid', title: '版块$fid'),
    );
    final container = _createContainer(favoriteRepository: favoriteRepository);
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    controller.onPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );

    final result = await controller.favoriteCurrentForum();

    expect(result, isA<DataCommandApplied<ForumFavoriteReceipt>>());
    expect(favoriteRepository.favoriteCalls, <String>['55']);
    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.currentFavoriteForum?.fid, '55');
    expect(state.isFavoriteMutationLoading, isFalse);
  });

  test(
    'unfavoriteCurrentForum refreshes favorite state after success',
    () async {
      final favoriteRepository = _FakeForumFavoriteRepository(
        favoriteForums: <FavoriteForumEntry>[
          _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
        ],
      );
      final container = _createContainer(
        favoriteRepository: favoriteRepository,
      );
      addTearDown(container.dispose);

      final controller = container.read(
        forumWebViewControllerProvider.notifier,
      );
      await controller.onPageFinished(
        rawUrl:
            'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
        pageTitle: '综合区页面',
        canGoBack: true,
      );
      await pumpEventQueue();

      final result = await controller.unfavoriteCurrentForum();

      expect(result, isA<DataCommandApplied<ForumFavoriteReceipt>>());
      expect(favoriteRepository.unfavoriteCalls, <String>['fav-55']);
      final state = await container.read(forumWebViewControllerProvider.future);
      expect(state.currentFavoriteForum, isNull);
      expect(state.favoriteForums, isEmpty);
    },
  );

  test('unfavoriteForum refreshes cached favorite forums', () async {
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: <FavoriteForumEntry>[
        _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
        _favoriteForum(fid: '66', favid: 'fav-66', title: '讨论区'),
      ],
    );
    final container = _createContainer(favoriteRepository: favoriteRepository);
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    final preload = await controller.loadFavoriteForums();
    expect(preload.isSuccess, isTrue);

    final result = await controller.unfavoriteForum(
      forum: favoriteRepository.favoriteForums.first,
    );

    expect(result, isA<DataCommandApplied<ForumFavoriteReceipt>>());
    expect(favoriteRepository.unfavoriteCalls, <String>['fav-55']);
    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.favoriteForums.map((item) => item.fid), <String>['66']);
  });

  test('unfavoriteForum fails closed without identity capability', () async {
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: <FavoriteForumEntry>[
        _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
      ],
      sourceCapabilities: _unsupportedRemoteIdentityCapabilities,
    );
    final container = _createContainer(favoriteRepository: favoriteRepository);
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    final preload = await controller.loadFavoriteForums();
    expect(preload.isSuccess, isTrue);

    final result = await controller.unfavoriteForum(
      forum: favoriteRepository.favoriteForums.first,
    );

    expect(result, isA<DataCommandNotSent<ForumFavoriteReceipt>>());
    expect(favoriteRepository.unfavoriteCalls, isEmpty);
  });
}

ProviderContainer _createContainer({
  ForumTagRepository? repository,
  _FakeForumFavoriteRepository? favoriteRepository,
}) {
  final resolvedFavoriteRepository =
      favoriteRepository ?? _FakeForumFavoriteRepository();
  final container = ProviderContainer(
    overrides: [
      forumTagRepositoryProvider.overrideWithValue(
        repository ?? _FakeForumTagRepository(_defaultBoards),
      ),
      favoriteForumCommandProvider.overrideWithValue(
        resolvedFavoriteRepository,
      ),
      favoriteForumDirectoryRepositoryProvider.overrideWithValue(
        resolvedFavoriteRepository.directory,
      ),
    ],
  );
  container.listen(forumWebViewControllerProvider, (previous, next) {});
  return container;
}

const List<ForumBoardTagSet> _defaultBoards = <ForumBoardTagSet>[
  ForumBoardTagSet(fid: '55', name: '综合区', tags: <ForumTagDefinition>[]),
];

class _FakeForumTagRepository implements ForumTagRepository {
  const _FakeForumTagRepository(this.boards);

  final List<ForumBoardTagSet> boards;

  @override
  Future<ForumTagLookup> loadLookup() async {
    return ForumTagLookup(boards);
  }
}

FavoriteForumEntry _favoriteForum({
  required String fid,
  required String favid,
  required String title,
}) {
  return FavoriteForumEntry(
    fid: fid,
    title: title,
    remoteFavoriteId: favid,
    description: '',
    threadCount: 0,
    postCount: 0,
    todayPostCount: 0,
  );
}

class _FakeForumFavoriteRepository implements FavoriteForumCommand {
  _FakeForumFavoriteRepository({
    List<FavoriteForumEntry>? favoriteForums,
    this.onFavorite,
    FavoriteForumDirectorySourceCapabilities? sourceCapabilities,
  }) : directory = _FakeFavoriteForumDirectoryRepository(
         favoriteForums ?? const <FavoriteForumEntry>[],
         sourceCapabilities ?? _sourceCapabilities,
       );

  final _FakeFavoriteForumDirectoryRepository directory;
  final FavoriteForumEntry Function(String fid)? onFavorite;

  final List<String> favoriteCalls = <String>[];
  final List<String> unfavoriteCalls = <String>[];

  List<FavoriteForumEntry> get favoriteForums => directory.favoriteForums;

  int get loadCallCount => directory.loadCallCount;

  @override
  FavoriteMutationCapabilities get capabilities =>
      allFavoriteMutationCapabilities;

  @override
  Future<DataCommandResult<ForumFavoriteReceipt>> execute(
    SetForumFavoriteRequest request,
  ) async {
    if (request.targetState == FavoriteTargetState.favorited) {
      favoriteCalls.add(request.fid);
      final forum =
          onFavorite?.call(request.fid) ??
          _favoriteForum(
            fid: request.fid,
            favid: 'fav-${request.fid}',
            title: '版块${request.fid}',
          );
      directory.favoriteForums = <FavoriteForumEntry>[
        ...favoriteForums.where((item) => item.fid != forum.fid),
        forum,
      ];
      return appliedForumFavorite(
        fid: request.fid,
        targetState: request.targetState,
        remoteFavoriteId: forum.remoteFavoriteId,
      );
    }
    final favid = request.knownRemoteFavoriteId ?? '';
    unfavoriteCalls.add(favid);
    directory.favoriteForums = favoriteForums
        .where(
          (item) => item.fid != request.fid && item.remoteFavoriteId != favid,
        )
        .toList();
    return appliedForumFavorite(
      fid: request.fid,
      targetState: request.targetState,
      remoteFavoriteId: favid,
    );
  }
}

class _FakeFavoriteForumDirectoryRepository
    implements FavoriteForumDirectoryRepository {
  _FakeFavoriteForumDirectoryRepository(
    List<FavoriteForumEntry> favoriteForums,
    this._capabilities,
  ) : favoriteForums = List<FavoriteForumEntry>.from(favoriteForums);

  List<FavoriteForumEntry> favoriteForums;
  final FavoriteForumDirectorySourceCapabilities _capabilities;
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
      data: FavoriteForumDirectoryData(
        items: List<FavoriteForumEntry>.from(favoriteForums),
      ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
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

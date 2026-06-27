import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' as riverpod_misc;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/cache_load_policy.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/widgets/forum_home_widgets.dart';

void main() {
  group('ForumHomePage', () {
    testWidgets('stays buildable before data returns and then renders list', (
      tester,
    ) async {
      final completer = Completer<ApiResult<ForumHomePayload>>();
      final repository = _FakeForumHomeRepository(() => completer.future);

      await tester.pumpWidget(_buildTestApp(repository));

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byKey(const Key('forum-home-list')), findsNothing);

      completer.complete(ApiSuccess(_loggedOutPayload()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      expect(find.text('综合区'), findsOneWidget);
      expect(find.text('公告区'), findsOneWidget);
    });

    testWidgets(
      'renders carousel, grouped sections, forum rows, and today counts',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async => ApiSuccess(_loggedOutPayloadWithCarousel()),
        );

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
        expect(find.byKey(const Key('forum-home-carousel')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const Key('forum-home-carousel'))).height,
          greaterThan(0),
        );
        expect(find.text('综合区'), findsOneWidget);
        expect(find.text('公告区'), findsOneWidget);
        expect(find.text('今日 2'), findsOneWidget);
        expect(find.byKey(const Key('forum-card-2')), findsOneWidget);
        expect(find.textContaining('共1 个分组'), findsNothing);
      },
    );

    testWidgets('renders forum list when carousel is empty', (tester) async {
      final repository = _FakeForumHomeRepository(
        () async => ApiSuccess(_loggedOutPayload()),
      );

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-home-carousel')), findsNothing);
      expect(find.byKey(const Key('forum-card-2')), findsOneWidget);
    });

    testWidgets(
      'renders favorite forum section when logged in payload has favorites',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async => ApiSuccess(_loggedInPayloadWithFavorites()),
        );

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pumpAndSettle();

        expect(find.text('我收藏的版块'), findsOneWidget);
        expect(find.byKey(const Key('forum-favorite-card-2')), findsOneWidget);
        expect(find.byKey(const Key('forum-favorite-card-55')), findsOneWidget);
        expect(find.text('综合区'), findsOneWidget);
      },
    );

    testWidgets(
      'favorite forums use forum index description when favorite description is empty',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async =>
              ApiSuccess(_loggedInPayloadWithEmptyFavoriteDescription()),
        );

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-favorite-card-2')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('forum-favorite-card-2')),
            matching: find.text('站点公告与维护信息'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'favorite forums use home html descriptions before forum index fallback',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async =>
              ApiSuccess(_loggedInPayloadWithChromeFavoriteDescriptions()),
        );

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pumpAndSettle();

        expect(find.text('风声水起。'), findsOneWidget);
        expect(find.text('爱的推广会。'), findsOneWidget);
        expect(find.text('外文作品翻译的分享与赏析。'), findsOneWidget);
      },
    );

    testWidgets(
      'section header toggles forum rows with minus and plus indicators',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async => ApiSuccess(_loggedInPayloadWithFavorites()),
        );

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-favorite-card-2')), findsOneWidget);
        var indicator = tester.widget<Text>(
          find.byKey(const Key('forum-section-indicator-我收藏的版块')),
        );
        expect(indicator.data, '-');

        await tester.tap(find.byKey(const Key('forum-section-toggle-我收藏的版块')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));

        final rotatingIndicator = tester.widget<RotationTransition>(
          find
              .ancestor(
                of: find.byKey(const Key('forum-section-indicator-我收藏的版块')),
                matching: find.byType(RotationTransition),
              )
              .first,
        );
        expect(rotatingIndicator.turns.value, greaterThan(0));
        expect(rotatingIndicator.turns.value, lessThanOrEqualTo(0.25));
        expect(find.byKey(const Key('forum-favorite-card-2')), findsOneWidget);

        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-favorite-card-2')), findsNothing);
        indicator = tester.widget<Text>(
          find.byKey(const Key('forum-section-indicator-我收藏的版块')),
        );
        expect(indicator.data, '+');

        await tester.tap(find.byKey(const Key('forum-section-toggle-我收藏的版块')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-favorite-card-2')), findsOneWidget);
        indicator = tester.widget<Text>(
          find.byKey(const Key('forum-section-indicator-我收藏的版块')),
        );
        expect(indicator.data, '-');
      },
    );

    testWidgets('opens forum display page when forum row is tapped', (
      tester,
    ) async {
      final observer = _CountingNavigatorObserver();
      final repository = _FakeForumHomeRepository(
        () async => ApiSuccess(_loggedOutPayload()),
      );

      await tester.pumpWidget(
        _buildTestApp(repository, navigatorObservers: [observer]),
      );
      await tester.pumpAndSettle();

      final pushCountBeforeTap = observer.pushCount;
      await tester.tap(find.byKey(const Key('forum-card-2')));

      expect(observer.pushCount, pushCountBeforeTap + 1);
    });

    testWidgets('opens thread detail when carousel target is a thread link', (
      tester,
    ) async {
      final observer = _CountingNavigatorObserver();
      final repository = _FakeForumHomeRepository(
        () async => ApiSuccess(_loggedOutPayloadWithCarousel()),
      );

      await tester.pumpWidget(
        _buildTestApp(repository, navigatorObservers: [observer]),
      );
      await tester.pumpAndSettle();

      final pushCountBeforeTap = observer.pushCount;
      await tester.tap(find.byKey(const Key('forum-home-carousel-item-0')));

      expect(observer.pushCount, pushCountBeforeTap + 1);
    });

    testWidgets(
      'launches external URL when carousel target is not a thread link',
      (tester) async {
        final launcher = _FakeForumWebViewExternalLauncher();
        final repository = _FakeForumHomeRepository(
          () async => ApiSuccess(
            _loggedOutPayload(
              carouselItems: const [
                ForumHomeCarouselItem(
                  imageUrl: 'https://bbs.yamibo.com/banner.jpg',
                  targetUrl: 'https://www.yamibo.com/',
                ),
              ],
            ),
          ),
        );

        await tester.pumpWidget(_buildTestApp(repository, launcher: launcher));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('forum-home-carousel-item-0')));
        await tester.pump();

        expect(
          launcher.launchedUris.single,
          Uri.parse('https://www.yamibo.com/'),
        );
      },
    );

    testWidgets('dark theme native home surfaces are theme driven', (
      tester,
    ) async {
      final repository = _FakeForumHomeRepository(
        () async => ApiSuccess(_loggedInPayloadWithFavorites()),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(repository),
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const ForumHomePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final palette = ForumHomeNativePalette.resolve(AppTheme.dark());
      expect(palette.background, AppTheme.dark().scaffoldBackgroundColor);
      expect(
        palette.sectionBodyBackground,
        AppTheme.dark().colorScheme.surfaceContainer,
      );
      expect(palette.sectionBodyBackground, isNot(Colors.white));
      expect(find.byKey(const Key('forum-favorite-card-2')), findsOneWidget);
    });

    testWidgets('pull to refresh forces forum home network reload', (
      tester,
    ) async {
      final repository = _FakeForumHomeRepository(
        () async => ApiSuccess(_loggedOutPayload()),
      );

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(repository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
      ]);

      final refreshIndicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await refreshIndicator.onRefresh();
      await tester.pumpAndSettle();

      expect(repository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
        CacheLoadPolicy.networkFirst,
      ]);
    });

    testWidgets('login transition forces forum home network reload', (
      tester,
    ) async {
      final repository = _FakeForumHomeRepository(
        () async => ApiSuccess(_loggedOutPayload()),
      );
      final container = ProviderContainer(overrides: _overrides(repository));
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ForumHomePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
      ]);

      container
          .read(authSessionControllerProvider.notifier)
          .acceptSession(_loggedInSession());
      await tester.pumpAndSettle();

      expect(repository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
        CacheLoadPolicy.networkFirst,
      ]);
    });
  });
}

Widget _buildTestApp(
  ForumHomeRepository repository, {
  ForumWebViewExternalLauncher? launcher,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) {
  return ProviderScope(
    overrides: _overrides(repository, launcher: launcher),
    child: MaterialApp(
      navigatorObservers: navigatorObservers,
      home: const ForumHomePage(),
    ),
  );
}

List<riverpod_misc.Override> _overrides(
  ForumHomeRepository repository, {
  ForumWebViewExternalLauncher? launcher,
  AuthRepository? authRepository,
}) {
  return [
    forumHomeRepositoryProvider.overrideWithValue(repository),
    authRepositoryProvider.overrideWithValue(
      authRepository ?? _FakeAuthRepository(),
    ),
    imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
    imageRequestHeaderBuilderProvider.overrideWithValue(
      const _FakeImageRequestHeaderBuilder(),
    ),
    if (launcher != null)
      forumWebViewExternalLauncherProvider.overrideWithValue(launcher),
  ];
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

ForumHomePayload _loggedOutPayload({
  List<ForumHomeCarouselItem> carouselItems = const <ForumHomeCarouselItem>[],
}) {
  return ForumHomePayload(
    forumIndex: _sampleForumIndexData(),
    isLoggedIn: false,
    favoriteForums: const [],
    chromeData: ForumHomeChromeData(carouselItems: carouselItems),
  );
}

ForumHomePayload _loggedOutPayloadWithCarousel() {
  return _loggedOutPayload(
    carouselItems: const [
      ForumHomeCarouselItem(
        imageUrl: 'https://bbs.yamibo.com/banner.jpg',
        targetUrl: 'https://bbs.yamibo.com/thread-570956-1-1.html',
      ),
    ],
  );
}

ForumHomePayload _loggedInPayloadWithFavorites() {
  return ForumHomePayload(
    forumIndex: _sampleForumIndexData(),
    isLoggedIn: true,
    favoriteForums: [
      FavoriteForum(
        favid: '1',
        fid: '2',
        title: '百合会综合讨论区',
        description: '常逛版块',
        threads: 12,
        posts: 34,
        todayPosts: 1,
      ),
      FavoriteForum(
        favid: '2',
        fid: '55',
        title: '漫画交流区',
        description: '',
        threads: 56,
        posts: 78,
        todayPosts: 2,
      ),
    ],
  );
}

ForumHomePayload _loggedInPayloadWithEmptyFavoriteDescription() {
  return ForumHomePayload(
    forumIndex: _sampleForumIndexData(),
    isLoggedIn: true,
    favoriteForums: [
      FavoriteForum(
        favid: '1',
        fid: '2',
        title: '公告区',
        description: '',
        threads: 12,
        posts: 34,
        todayPosts: 0,
      ),
    ],
  );
}

ForumHomePayload _loggedInPayloadWithChromeFavoriteDescriptions() {
  return ForumHomePayload(
    forumIndex: _sampleForumIndexData(),
    isLoggedIn: true,
    favoriteForums: [
      FavoriteForum(
        favid: '1',
        fid: '33',
        title: '海域區',
        description: '',
        threads: 12,
        posts: 34,
        todayPosts: 0,
      ),
      FavoriteForum(
        favid: '2',
        fid: '30',
        title: '中文百合漫画区',
        description: '',
        threads: 56,
        posts: 78,
        todayPosts: 0,
      ),
      FavoriteForum(
        favid: '3',
        fid: '55',
        title: '轻小说/译文区',
        description: '',
        threads: 90,
        posts: 123,
        todayPosts: 0,
      ),
    ],
    chromeData: const ForumHomeChromeData(
      favoriteForums: [
        ForumHomeChromeForumItem(
          fid: '33',
          title: '海域區',
          description: '风声水起。',
          todayPosts: 122,
        ),
        ForumHomeChromeForumItem(
          fid: '30',
          title: '中文百合漫画区',
          description: '爱的推广会。',
          todayPosts: 105,
        ),
        ForumHomeChromeForumItem(
          fid: '55',
          title: '轻小说/译文区',
          description: '外文作品翻译的分享与赏析。',
          todayPosts: 69,
        ),
      ],
    ),
  );
}

class _FakeForumHomeRepository implements ForumHomeRepository {
  _FakeForumHomeRepository(this._loader);

  final Future<ApiResult<ForumHomePayload>> Function() _loader;
  final cachePolicies = <CacheLoadPolicy>[];

  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    cachePolicies.add(cachePolicy);
    return _loader();
  }
}

SessionInfo _loggedInSession() {
  return SessionInfo(
    uid: '597454',
    username: 'tester',
    formhash: '14502ecf',
    isLoggedIn: true,
  );
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

class _FakeImageRequestHeaderBuilder implements ImageRequestHeaderBuilder {
  const _FakeImageRequestHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
  }
}

class _FakeImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      fromCache: true,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    return null;
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(success: true, cacheKey: request.cacheKey);
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}

class _FakeForumWebViewExternalLauncher
    implements ForumWebViewExternalLauncher {
  final launchedUris = <Uri>[];

  @override
  Future<bool> launch(Uri uri) async {
    launchedUris.add(uri);
    return true;
  }
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

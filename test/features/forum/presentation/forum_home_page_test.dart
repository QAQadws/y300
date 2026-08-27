import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' as riverpod_misc;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import '../../../support/forum_auth_test_support.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    hide ForumHomeFavoriteForum, ForumHomeRepository;
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/domain/services/native_page_cache_invalidation_service.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/favorites/data/providers/favorite_directory_providers.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/services/forum_home_request_profile_resolver.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/widgets/forum_home_widgets.dart';
import '../../../support/favorite_command_test_support.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';

import '../../../support/forum_home_test_support.dart';

void main() {
  group('ForumHomePage', () {
    testWidgets('more menu exposes refresh and unfavorite actions', (
      tester,
    ) async {
      final repository = _FakeForumHomeRepository(
        () async => forumHomeReadSuccess(_loggedOutPayload()),
      );

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('forum-home-more-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('forum-home-refresh-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-home-unfavorite-action')),
        findsOneWidget,
      );
      expect(find.text('刷新页面'), findsOneWidget);
      expect(find.text('取消收藏'), findsOneWidget);
    });

    testWidgets('more menu refresh forces a network request', (tester) async {
      final repository = _FakeForumHomeRepository(
        () async => forumHomeReadSuccess(_loggedOutPayload()),
      );

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum-home-more-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum-home-refresh-action')));
      await tester.pumpAndSettle();

      expect(repository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
        CacheLoadPolicy.networkFirst,
      ]);
    });

    testWidgets('more menu opens the shared unfavorite picker', (tester) async {
      final homeRepository = _FakeForumHomeRepository(
        () async => forumHomeReadSuccess(_loggedOutPayload()),
      );
      final favoriteRepository = _FakeForumFavoriteRepository(
        favoriteForums: <FavoriteForumEntry>[
          _favoriteDirectoryForum(
            fid: '55',
            remoteFavoriteId: 'fav-55',
            title: '综合区',
          ),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(
          homeRepository,
          extraOverrides: [
            favoriteForumCommandProvider.overrideWithValue(favoriteRepository),
            favoriteForumDirectoryRepositoryProvider.overrideWithValue(
              favoriteRepository.directory,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum-home-more-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum-home-unfavorite-action')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('forum-favorite-forum-picker')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('forum-favorite-forum-picker')),
          matching: find.text('综合区'),
        ),
        findsOneWidget,
      );
      expect(favoriteRepository.loadCallCount, 1);

      await tester.tap(
        find.byKey(const Key('forum-favorite-forum-item-fav-55')),
      );
      await tester.pumpAndSettle();

      expect(favoriteRepository.unfavoriteFavids, <String>['fav-55']);
      expect(
        find.byKey(const Key('forum-favorite-forum-picker')),
        findsNothing,
      );
      expect(find.text('已取消收藏本版'), findsOneWidget);
      expect(homeRepository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
        CacheLoadPolicy.networkFirst,
      ]);
    });

    testWidgets('stays buildable before data returns and then renders list', (
      tester,
    ) async {
      final completer = Completer<ForumHomeReadResult>();
      final repository = _FakeForumHomeRepository(() => completer.future);

      await tester.pumpWidget(_buildTestApp(repository));

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byKey(const Key('forum-home-list')), findsNothing);
      expect(find.byKey(const Key('forum-home-blank-body')), findsOneWidget);
      expect(
        find.byKey(const Key('forum-home-refresh-progress')),
        findsNothing,
      );

      completer.complete(forumHomeReadSuccess(_loggedOutPayload()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      expect(find.text('综合区'), findsOneWidget);
      expect(find.text('公告区'), findsOneWidget);
    });

    testWidgets(
      'renders carousel, grouped sections, forum rows, and today counts',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async => forumHomeReadSuccess(_loggedOutPayloadWithCarousel()),
        );

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
        expect(find.byKey(const Key('forum-home-carousel')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const Key('forum-home-carousel'))).height,
          greaterThan(0),
        );
        final carouselClip = tester.widget<ClipRRect>(
          find.ancestor(
            of: find.byKey(const Key('forum-home-carousel')),
            matching: find.byType(ClipRRect),
          ),
        );
        expect(carouselClip.borderRadius, BorderRadius.circular(4));
        expect(find.text('综合区'), findsOneWidget);
        expect(find.text('公告区'), findsOneWidget);
        expect(find.text('今日'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.byKey(const Key('forum-card-2')), findsOneWidget);
        expect(find.textContaining('共1 个分组'), findsNothing);
      },
    );

    testWidgets('carousel uses sticky forum head image cache request', (
      tester,
    ) async {
      final cacheService = _RecordingImageCacheService();
      final repository = _FakeForumHomeRepository(
        () async => forumHomeReadSuccess(_loggedOutPayloadWithCarousel()),
      );

      await tester.pumpWidget(
        _buildTestApp(repository, imageCacheService: cacheService),
      );
      await tester.pump();
      await tester.pump();

      final carouselImage = tester.widget<CachedLibraryImage>(
        find.descendant(
          of: find.byKey(const Key('forum-home-carousel')),
          matching: find.byType(CachedLibraryImage),
        ),
      );

      expect(carouselImage.request?.role, ImageCacheRole.forumHeadImage);
      expect(carouselImage.request?.ownerType, ImageCacheOwnerType.forum);
      expect(
        carouselImage.request?.effectiveRetentionClass,
        ImageRetentionClass.sticky,
      );
      expect(
        carouselImage.request?.sourceUrl,
        'https://bbs.yamibo.com/banner.jpg',
      );
      expect(
        cacheService.requests.where(
          (request) => request.role == ImageCacheRole.forumHeadImage,
        ),
        isNotEmpty,
      );
    });

    testWidgets(
      'carousel applies a ratio update without replacing its content',
      (tester) async {
        Widget build(double? aspectRatio) {
          return ProviderScope(
            overrides: [
              imageCacheServiceProvider.overrideWithValue(
                _FakeImageCacheService(),
              ),
              forumImageRefererProvider.overrideWithValue(
                'https://bbs.yamibo.com/',
              ),
            ],
            child: LocalizedTestApp(
              home: Scaffold(
                body: ForumHomeCarousel(
                  items: [
                    ForumHomeCarouselItem(
                      imageUrl: 'https://bbs.yamibo.com/banner.jpg',
                      targetUrl:
                          'https://bbs.yamibo.com/thread-570956-1-1.html',
                      aspectRatio: aspectRatio,
                    ),
                  ],
                  imageReferer: 'https://bbs.yamibo.com/',
                  onOpen: (_) {},
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(build(null));
        await tester.pump();

        final carousel = find.byKey(const Key('forum-home-carousel'));
        final width = tester.getSize(carousel).width;
        expect(tester.getSize(carousel).height, closeTo(width / 3.45, 0.01));

        await tester.pumpWidget(build(3));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.getSize(carousel).height, closeTo(width / 3, 0.01));
      },
    );

    testWidgets('carousel adopts the first decoded image ratio', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
            forumImageRefererProvider.overrideWithValue(
              'https://bbs.yamibo.com/',
            ),
          ],
          child: LocalizedTestApp(
            home: Scaffold(
              body: ForumHomeCarousel(
                items: const [
                  ForumHomeCarouselItem(
                    imageUrl: 'https://bbs.yamibo.com/banner.jpg',
                    targetUrl: 'https://bbs.yamibo.com/thread-570956-1-1.html',
                  ),
                ],
                imageReferer: 'https://bbs.yamibo.com/',
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final carousel = find.byKey(const Key('forum-home-carousel'));
      final width = tester.getSize(carousel).width;
      final image = tester.widget<CachedLibraryImage>(
        find.descendant(
          of: carousel,
          matching: find.byType(CachedLibraryImage),
        ),
      );

      image.onImageResolved!(const Size(900, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.getSize(carousel).height, closeTo(width / 3, 0.01));
    });

    testWidgets('carousel pending item prewarm uses forum image precache', (
      tester,
    ) async {
      final precacheService = _RecordingForumImagePrecacheService();
      const oldItems = [
        ForumHomeCarouselItem(
          imageUrl: 'https://bbs.yamibo.com/old-banner.jpg',
          targetUrl: 'https://bbs.yamibo.com/thread-1-1-1.html',
        ),
      ];
      const newItems = [
        ForumHomeCarouselItem(
          imageUrl: 'https://bbs.yamibo.com/new-banner.jpg',
          targetUrl: 'https://bbs.yamibo.com/thread-2-1-1.html',
        ),
      ];

      Widget build(List<ForumHomeCarouselItem> items) {
        return ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
            forumImageRefererProvider.overrideWithValue(
              'https://bbs.yamibo.com/',
            ),
            forumImagePrecacheServiceProvider.overrideWithValue(
              precacheService,
            ),
          ],
          child: LocalizedTestApp(
            home: Scaffold(
              body: ForumHomeCarousel(
                items: items,
                imageReferer: 'https://bbs.yamibo.com/',
                onOpen: (_) {},
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(build(oldItems));
      await tester.pump();
      await tester.pumpWidget(build(newItems));
      await tester.pump();

      expect(precacheService.decodedSpecs, hasLength(1));
      expect(
        precacheService.decodedSpecs.single.kind,
        ForumImageKind.forumHeadImage,
      );
      expect(precacheService.decodedSpecs.single.ownerId, 'home');
      expect(
        precacheService.decodedSpecs.single.sourceUrl,
        'https://bbs.yamibo.com/new-banner.jpg',
      );
    });

    testWidgets('renders forum list when carousel is empty', (tester) async {
      final repository = _FakeForumHomeRepository(
        () async => forumHomeReadSuccess(_loggedOutPayload()),
      );

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-home-carousel')), findsNothing);
      expect(find.byKey(const Key('forum-card-2')), findsOneWidget);
    });

    testWidgets('today badge appears when refreshed data adds today count', (
      tester,
    ) async {
      var requestCount = 0;
      final refreshCompleter = Completer<ForumHomeReadResult>();
      final repository = _FakeForumHomeRepository(() {
        requestCount += 1;
        if (requestCount == 1) {
          return Future<ForumHomeReadResult>.value(
            forumHomeReadSuccess(_loggedOutPayloadNoToday()),
          );
        }
        return refreshCompleter.future;
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('今日'), findsNothing);

      final refreshIndicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final refreshFuture = refreshIndicator.onRefresh();
      await tester.pump();

      refreshCompleter.complete(forumHomeReadSuccess(_loggedOutPayload()));
      await refreshFuture;
      await tester.pumpAndSettle();

      expect(find.text('今日'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets(
      'hides directory fields when their capabilities are unsupported',
      (tester) async {
        final capabilities = ForumDirectoryReadCapabilities(
          values: DataCapabilitySet<ForumDirectoryCapability>.from(
            supported: const <ForumDirectoryCapability>[
              ForumDirectoryCapability.stableSectionIdentity,
              ForumDirectoryCapability.orderedSections,
              ForumDirectoryCapability.stableForumIdentity,
              ForumDirectoryCapability.orderedForums,
            ],
            unsupported: const <ForumDirectoryCapability>[
              ForumDirectoryCapability.forumDescription,
              ForumDirectoryCapability.todayPostCount,
            ],
          ),
        );
        final repository = _FakeForumHomeRepository(
          () async => forumHomeReadSuccess(
            _loggedOutPayload(todayPosts: 9, description: '不应显示'),
            capabilities: capabilities,
          ),
        );

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pumpAndSettle();

        expect(find.text('不应显示'), findsNothing);
        expect(find.text('今日'), findsNothing);
      },
    );

    testWidgets(
      'today badge disappears when refreshed data removes today count',
      (tester) async {
        var requestCount = 0;
        final refreshCompleter = Completer<ForumHomeReadResult>();
        final repository = _FakeForumHomeRepository(() {
          requestCount += 1;
          if (requestCount == 1) {
            return Future<ForumHomeReadResult>.value(
              forumHomeReadSuccess(_loggedOutPayload()),
            );
          }
          return refreshCompleter.future;
        });

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pumpAndSettle();

        expect(find.text('今日'), findsOneWidget);

        final refreshIndicator = tester.widget<RefreshIndicator>(
          find.byType(RefreshIndicator),
        );
        final refreshFuture = refreshIndicator.onRefresh();
        await tester.pump();

        refreshCompleter.complete(
          forumHomeReadSuccess(_loggedOutPayloadNoToday()),
        );
        await refreshFuture;
        await tester.pumpAndSettle();

        expect(find.text('今日'), findsNothing);
      },
    );

    testWidgets('today badge keeps stable subtree when count changes', (
      tester,
    ) async {
      var requestCount = 0;
      final refreshCompleter = Completer<ForumHomeReadResult>();
      final repository = _FakeForumHomeRepository(() {
        requestCount += 1;
        if (requestCount == 1) {
          return Future<ForumHomeReadResult>.value(
            forumHomeReadSuccess(_loggedOutPayload()),
          );
        }
        return refreshCompleter.future;
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      final beforeElement = tester.element(
        find.byKey(const ValueKey('forum-home-today-badge-filled')),
      );
      expect(find.text('今日'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      final refreshIndicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final refreshFuture = refreshIndicator.onRefresh();
      await tester.pump();

      refreshCompleter.complete(
        forumHomeReadSuccess(_loggedOutPayloadWithTodayCount(8)),
      );
      await refreshFuture;
      await tester.pump();

      final afterElement = tester.element(
        find.byKey(const ValueKey('forum-home-today-badge-filled')),
      );
      expect(identical(beforeElement, afterElement), isTrue);
      expect(find.text('今日'), findsOneWidget);
    });

    testWidgets(
      'manual content mode projects server text without reloading home',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async => forumHomeReadSuccess(_loggedOutPayload()),
        );

        await tester.pumpWidget(
          _buildTestApp(
            repository,
            extraOverrides: <riverpod_misc.Override>[
              appServerContentConversionModeProvider.overrideWithValue(
                TextConversionMode.toTraditional,
              ),
              textConverterProvider.overrideWith(
                (ref, mode) => _ProjectionTestConverter(mode),
              ),
              plainTextBatchConversionServiceProvider.overrideWithValue(
                _ProjectionPrefixBatchConversionService(),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('T:综合区'), findsOneWidget);
        expect(find.text('T:公告区'), findsOneWidget);
        expect(find.text('T:站点公告与维护信息'), findsOneWidget);
        expect(
          find.byKey(const Key('forum-section-toggle-regular:1')),
          findsOneWidget,
        );
        expect(repository.cachePolicies, <CacheLoadPolicy>[
          CacheLoadPolicy.cacheFirst,
        ]);
      },
    );

    testWidgets(
      'silent refresh triggers when page becomes active after threshold',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async => forumHomeReadSuccess(_loggedOutPayload()),
        );
        final fakeNow = _MutableNow(DateTime(2026, 6, 29, 12, 0, 0));

        await tester.pumpWidget(
          _buildTestApp(repository, isActive: false, nowProvider: fakeNow.call),
        );
        await tester.pumpAndSettle();

        fakeNow.value = fakeNow.value.add(const Duration(seconds: 61));

        await tester.pumpWidget(
          _buildTestApp(repository, isActive: true, nowProvider: fakeNow.call),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(repository.cachePolicies, <CacheLoadPolicy>[
          CacheLoadPolicy.cacheFirst,
          CacheLoadPolicy.networkFirst,
        ]);
        expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      },
    );

    testWidgets(
      'renders favorite forum section when logged in payload has favorites',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async => forumHomeReadSuccess(_loggedInPayloadWithFavorites()),
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
          () async => forumHomeReadSuccess(
            _loggedInPayloadWithEmptyFavoriteDescription(),
          ),
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
        expect(
          find.descendant(
            of: find.byKey(const Key('forum-favorite-card-2')),
            matching: find.text('0'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'favorite forums use home html descriptions before forum index fallback',
      (tester) async {
        final repository = _FakeForumHomeRepository(
          () async => forumHomeReadSuccess(
            _loggedInPayloadWithChromeFavoriteDescriptions(),
          ),
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
          () async => forumHomeReadSuccess(_loggedInPayloadWithFavorites()),
        );

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-favorite-card-2')), findsOneWidget);
        var indicator = tester.widget<Text>(
          find.byKey(const Key('forum-section-indicator-favorite:2,55')),
        );
        expect(indicator.data, '-');

        await tester.tap(
          find.byKey(const Key('forum-section-toggle-favorite:2,55')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));

        final rotatingIndicator = tester.widget<RotationTransition>(
          find
              .ancestor(
                of: find.byKey(
                  const Key('forum-section-indicator-favorite:2,55'),
                ),
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
          find.byKey(const Key('forum-section-indicator-favorite:2,55')),
        );
        expect(indicator.data, '+');

        await tester.tap(
          find.byKey(const Key('forum-section-toggle-favorite:2,55')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-favorite-card-2')), findsOneWidget);
        indicator = tester.widget<Text>(
          find.byKey(const Key('forum-section-indicator-favorite:2,55')),
        );
        expect(indicator.data, '-');
      },
    );

    testWidgets('opens forum display page when forum row is tapped', (
      tester,
    ) async {
      final observer = _CountingNavigatorObserver();
      final repository = _FakeForumHomeRepository(
        () async => forumHomeReadSuccess(_loggedOutPayload()),
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
        () async => forumHomeReadSuccess(_loggedOutPayloadWithCarousel()),
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
          () async => forumHomeReadSuccess(
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
        () async => forumHomeReadSuccess(_loggedInPayloadWithFavorites()),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(repository),
          child: LocalizedTestApp(
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
      var requestCount = 0;
      final refreshCompleter = Completer<ForumHomeReadResult>();
      final repository = _FakeForumHomeRepository(() {
        requestCount += 1;
        if (requestCount == 1) {
          return Future<ForumHomeReadResult>.value(
            forumHomeReadSuccess(_loggedOutPayload()),
          );
        }
        return refreshCompleter.future;
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(repository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
      ]);
      expect(find.byKey(const Key('forum-home-list')), findsOneWidget);

      final refreshIndicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final refreshFuture = refreshIndicator.onRefresh();
      await tester.pump();

      expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      expect(
        find.byKey(const Key('forum-home-refresh-progress')),
        findsNothing,
      );

      refreshCompleter.complete(forumHomeReadSuccess(_loggedOutPayload()));
      await refreshFuture;
      await tester.pumpAndSettle();

      expect(repository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
        CacheLoadPolicy.networkFirst,
      ]);
      expect(repository.requestProfiles, <DocumentRequestProfile?>[
        DocumentRequestProfile.anonymous,
        DocumentRequestProfile.anonymous,
      ]);
    });

    testWidgets(
      'auth and network pending still render cached home immediately',
      (tester) async {
        final authRepository = _PendingAuthRepository(
          session: SessionInfo(
            uid: '0',
            username: '',
            formhash: '',
            isLoggedIn: false,
          ),
        );
        final refreshCompleter = Completer<ForumHomeReadResult>();
        final repository = _FakeForumHomeRepository(
          () => refreshCompleter.future,
          cachedEntry: ForumHomeCacheEntry(
            payload: _loggedOutPayloadNoToday(),
            capabilities: forumHomeTestCapabilities,
            metadata: const DataReadMetadata(
              origin: DataReadOrigin.freshSnapshot,
              freshness: DataReadFreshness.freshCache,
            ),
            updatedAt: DateTime(2026, 6, 29, 11),
          ),
        );
        final container = ProviderContainer(
          overrides: _overrides(
            repository,
            authRepository: authRepository,
            requestProfileResolver: const _FakeForumHomeRequestProfileResolver(
              DocumentRequestProfile.anonymous,
            ),
          ),
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const LocalizedTestApp(home: ForumHomePage()),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(Duration.zero);

        expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
        expect(find.byKey(const Key('forum-card-2')), findsOneWidget);
        expect(find.byKey(const Key('forum-home-blank-body')), findsNothing);
        expect(repository.cachedRequestProfiles, <DocumentRequestProfile>[
          DocumentRequestProfile.anonymous,
        ]);
        expect(repository.cachePolicies, <CacheLoadPolicy>[
          CacheLoadPolicy.networkFirst,
        ]);
        expect(
          find.byKey(const Key('forum-home-refresh-progress')),
          findsNothing,
        );

        authRepository.complete();
        refreshCompleter.complete(forumHomeReadSuccess(_loggedOutPayload()));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'background cache refresh keeps today subtree and applies updated value',
      (tester) async {
        final refreshCompleter = Completer<ForumHomeReadResult>();
        final repository = _FakeForumHomeRepository(
          () => refreshCompleter.future,
          cachedEntry: ForumHomeCacheEntry(
            payload: _loggedOutPayload(),
            capabilities: forumHomeTestCapabilities,
            metadata: const DataReadMetadata(
              origin: DataReadOrigin.freshSnapshot,
              freshness: DataReadFreshness.freshCache,
            ),
            updatedAt: DateTime(2026, 6, 29, 11),
          ),
        );

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pump();
        await tester.pump(Duration.zero);
        await tester.pump();

        final beforeElement = tester.element(
          find.byKey(const ValueKey('forum-home-today-badge-filled')),
        );
        expect(find.text('2'), findsOneWidget);

        refreshCompleter.complete(
          forumHomeReadSuccess(_loggedOutPayloadWithTodayCount(8)),
        );
        await tester.pump();

        final afterElement = tester.element(
          find.byKey(const ValueKey('forum-home-today-badge-filled')),
        );
        expect(identical(beforeElement, afterElement), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('8'), findsOneWidget);
      },
    );

    testWidgets('background refresh failure keeps cached content visible', (
      tester,
    ) async {
      final repository = _FakeForumHomeRepository(
        () async => const DataReadFailure(
          kind: DataReadFailureKind.network,
          diagnosticMessage: 'offline',
        ),
        cachedEntry: ForumHomeCacheEntry(
          payload: _loggedOutPayload(),
          capabilities: forumHomeTestCapabilities,
          metadata: const DataReadMetadata(
            origin: DataReadOrigin.freshSnapshot,
            freshness: DataReadFreshness.freshCache,
          ),
          updatedAt: DateTime(2026, 6, 29, 11),
        ),
      );

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      expect(find.byKey(const Key('forum-home-blank-body')), findsNothing);
      expect(find.byKey(const Key('forum-home-retry-button')), findsNothing);
    });

    testWidgets(
      'login transition invalidates cached home and shows a blank body',
      (tester) async {
        final authRepository = _FakeAuthRepository();
        var requestCount = 0;
        final reloadCompleter = Completer<ForumHomeReadResult>();
        final repository = _FakeForumHomeRepository(() {
          requestCount += 1;
          if (requestCount == 1) {
            return Future<ForumHomeReadResult>.value(
              forumHomeReadSuccess(_loggedOutPayload()),
            );
          }
          return reloadCompleter.future;
        });
        final invalidationService =
            _RecordingNativePageCacheInvalidationService();
        final container = ProviderContainer(
          overrides: [
            ..._overrides(repository, authRepository: authRepository),
            nativePageCacheInvalidationServiceProvider.overrideWithValue(
              invalidationService,
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const LocalizedTestApp(home: ForumHomePage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-home-list')), findsOneWidget);

        authRepository.setSession(_loggedInSession());
        await container.read(authSessionControllerProvider.notifier).refresh();
        await tester.pump();

        expect(find.byKey(const Key('forum-home-blank-body')), findsOneWidget);
        expect(find.byKey(const Key('forum-home-list')), findsNothing);

        reloadCompleter.complete(
          forumHomeReadSuccess(_loggedInPayloadWithFavorites()),
        );
        await tester.pumpAndSettle();

        expect(repository.cachePolicies, <CacheLoadPolicy>[
          CacheLoadPolicy.cacheFirst,
          CacheLoadPolicy.cacheFirst,
        ]);
        expect(repository.requestProfiles, <DocumentRequestProfile?>[
          DocumentRequestProfile.anonymous,
          DocumentRequestProfile.loggedIn,
        ]);
        expect(invalidationService.invalidateForumHomeCalls, 1);
        expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      },
    );

    testWidgets(
      'account switch invalidates cached home and shows a blank body',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          session: _loggedInSession(uid: '10001', username: 'alice'),
        );
        var requestCount = 0;
        final reloadCompleter = Completer<ForumHomeReadResult>();
        final repository = _FakeForumHomeRepository(() {
          requestCount += 1;
          if (requestCount == 1) {
            return Future<ForumHomeReadResult>.value(
              forumHomeReadSuccess(_loggedInPayloadWithFavorites()),
            );
          }
          return reloadCompleter.future;
        });
        final invalidationService =
            _RecordingNativePageCacheInvalidationService();
        final container = ProviderContainer(
          overrides: [
            ..._overrides(repository, authRepository: authRepository),
            nativePageCacheInvalidationServiceProvider.overrideWithValue(
              invalidationService,
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const LocalizedTestApp(home: ForumHomePage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forum-home-list')), findsOneWidget);

        authRepository.setSession(
          _loggedInSession(uid: '20002', username: 'bob'),
        );
        await container.read(authSessionControllerProvider.notifier).refresh();
        await tester.pump();

        expect(find.byKey(const Key('forum-home-blank-body')), findsOneWidget);
        expect(find.byKey(const Key('forum-home-list')), findsNothing);

        reloadCompleter.complete(
          forumHomeReadSuccess(_loggedInPayloadWithFavorites()),
        );
        await tester.pumpAndSettle();

        expect(repository.cachePolicies, <CacheLoadPolicy>[
          CacheLoadPolicy.cacheFirst,
          CacheLoadPolicy.cacheFirst,
        ]);
        expect(repository.requestProfiles, <DocumentRequestProfile?>[
          DocumentRequestProfile.loggedIn,
          DocumentRequestProfile.loggedIn,
        ]);
        expect(invalidationService.invalidateForumHomeCalls, 1);
        expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      },
    );
  });
}

Widget _buildTestApp(
  ForumHomeRepository repository, {
  ForumWebViewExternalLauncher? launcher,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
  bool isActive = true,
  DateTime Function()? nowProvider,
  ImageCacheService? imageCacheService,
  ForumImagePrecacheService? forumImagePrecacheService,
  List<riverpod_misc.Override> extraOverrides =
      const <riverpod_misc.Override>[],
}) {
  return ProviderScope(
    overrides: _overrides(
      repository,
      launcher: launcher,
      nowProvider: nowProvider,
      imageCacheService: imageCacheService,
      forumImagePrecacheService: forumImagePrecacheService,
    )..addAll(extraOverrides),
    child: LocalizedTestApp(
      navigatorObservers: navigatorObservers,
      home: ForumHomePage(isActive: isActive),
    ),
  );
}

List<riverpod_misc.Override> _overrides(
  ForumHomeRepository repository, {
  ForumWebViewExternalLauncher? launcher,
  AuthRepository? authRepository,
  DateTime Function()? nowProvider,
  ImageCacheService? imageCacheService,
  ForumImagePrecacheService? forumImagePrecacheService,
  ForumHomeRequestProfileResolver? requestProfileResolver,
}) {
  return [
    forumHomeRepositoryProvider.overrideWithValue(repository),
    ...forumAuthOverrides(authRepository ?? _FakeAuthRepository()),
    imageCacheServiceProvider.overrideWithValue(
      imageCacheService ?? _FakeImageCacheService(),
    ),
    forumImagePrecacheServiceProvider.overrideWithValue(
      forumImagePrecacheService ?? _FakeForumImagePrecacheService(),
    ),
    forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    forumHomeRequestProfileResolverProvider.overrideWithValue(
      requestProfileResolver ??
          const _FakeForumHomeRequestProfileResolver(
            DocumentRequestProfile.anonymous,
          ),
    ),
    if (nowProvider != null)
      forumHomeNowProvider.overrideWithValue(nowProvider),
    if (launcher != null)
      forumWebViewExternalLauncherProvider.overrideWithValue(launcher),
  ];
}

ForumDirectoryData _sampleDirectory({
  int? todayPosts = 2,
  String description = '站点公告与维护信息',
}) {
  return ForumDirectoryData(
    sections: [
      ForumDirectorySection(
        identity: '1',
        title: '综合区',
        forums: [
          ForumDirectoryForum(
            fid: '2',
            title: '公告区',
            description: description,
            todayPosts: todayPosts,
          ),
        ],
      ),
    ],
  );
}

ForumHomePayload _loggedOutPayload({
  List<ForumHomeCarouselItem> carouselItems = const <ForumHomeCarouselItem>[],
  int? todayPosts = 2,
  String description = '站点公告与维护信息',
}) {
  return ForumHomePayload(
    directory: _sampleDirectory(
      todayPosts: todayPosts,
      description: description,
    ),
    isLoggedIn: false,
    favoriteForums: const [],
    chromeData: ForumHomeChromeData(carouselItems: carouselItems),
  );
}

ForumHomePayload _loggedOutPayloadNoToday() {
  return ForumHomePayload(
    directory: _sampleDirectory(todayPosts: null),
    isLoggedIn: false,
    favoriteForums: const [],
  );
}

ForumHomePayload _loggedOutPayloadWithTodayCount(int todayPosts) {
  return ForumHomePayload(
    directory: _sampleDirectory(todayPosts: todayPosts, description: '站务公告'),
    isLoggedIn: false,
    favoriteForums: [
      ForumHomeFavoriteForum(
        fid: '2',
        title: '公告区',
        description: '站务公告',
        todayPosts: todayPosts,
      ),
    ],
    chromeData: ForumHomeChromeData(
      favoriteForums: [
        ForumHomeChromeForumItem(
          fid: '2',
          title: '公告区',
          description: '站务公告',
          todayPosts: todayPosts,
        ),
      ],
    ),
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
    directory: _sampleDirectory(),
    isLoggedIn: true,
    favoriteForums: [
      ForumHomeFavoriteForum(
        fid: '2',
        title: '百合会综合讨论区',
        description: '常逛版块',
        todayPosts: 1,
      ),
      ForumHomeFavoriteForum(
        fid: '55',
        title: '漫画交流区',
        description: '',
        todayPosts: 2,
      ),
    ],
  );
}

ForumHomePayload _loggedInPayloadWithEmptyFavoriteDescription() {
  return ForumHomePayload(
    directory: _sampleDirectory(),
    isLoggedIn: true,
    favoriteForums: [
      ForumHomeFavoriteForum(
        fid: '2',
        title: '公告区',
        description: '',
        todayPosts: 0,
      ),
    ],
  );
}

ForumHomePayload _loggedInPayloadWithChromeFavoriteDescriptions() {
  return ForumHomePayload(
    directory: _sampleDirectory(),
    isLoggedIn: true,
    favoriteForums: [
      ForumHomeFavoriteForum(
        fid: '33',
        title: '海域區',
        description: '',
        todayPosts: 0,
      ),
      ForumHomeFavoriteForum(
        fid: '30',
        title: '中文百合漫画区',
        description: '',
        todayPosts: 0,
      ),
      ForumHomeFavoriteForum(
        fid: '55',
        title: '轻小说/译文区',
        description: '',
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
  _FakeForumHomeRepository(this._loader, {this.cachedEntry});

  final Future<ForumHomeReadResult> Function() _loader;
  final ForumHomeCacheEntry? cachedEntry;
  final cachePolicies = <CacheLoadPolicy>[];
  final requestProfiles = <DocumentRequestProfile?>[];
  final cachedRequestProfiles = <DocumentRequestProfile>[];

  @override
  Future<ForumHomeCacheEntry?> readCachedPayload({
    required DocumentRequestProfile requestProfile,
  }) async {
    cachedRequestProfiles.add(requestProfile);
    return cachedEntry;
  }

  @override
  Future<ForumHomeReadResult> getForumHomePayload({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  }) {
    cachePolicies.add(cachePolicy);
    requestProfiles.add(requestProfileOverride);
    return _loader();
  }
}

FavoriteForumEntry _favoriteDirectoryForum({
  required String fid,
  required String remoteFavoriteId,
  required String title,
}) {
  return FavoriteForumEntry(
    fid: fid,
    title: title,
    remoteFavoriteId: remoteFavoriteId,
    description: '',
    threadCount: 0,
    postCount: 0,
    todayPostCount: 0,
  );
}

class _FakeForumFavoriteRepository implements FavoriteForumCommand {
  _FakeForumFavoriteRepository({
    required List<FavoriteForumEntry> favoriteForums,
  }) : directory = _FakeFavoriteForumDirectoryRepository(favoriteForums);

  final _FakeFavoriteForumDirectoryRepository directory;
  final favoriteFids = <String>[];
  final unfavoriteFavids = <String>[];

  int get loadCallCount => directory.loadCallCount;

  @override
  FavoriteMutationCapabilities get capabilities =>
      allFavoriteMutationCapabilities;

  @override
  Future<DataCommandResult<ForumFavoriteReceipt>> execute(
    SetForumFavoriteRequest request,
  ) async {
    if (request.targetState == FavoriteTargetState.favorited) {
      favoriteFids.add(request.fid);
    } else {
      final favid = request.knownRemoteFavoriteId;
      if (favid != null) {
        unfavoriteFavids.add(favid);
      }
    }
    return appliedForumFavorite(
      fid: request.fid,
      targetState: request.targetState,
      remoteFavoriteId: request.knownRemoteFavoriteId,
    );
  }
}

class _FakeFavoriteForumDirectoryRepository
    implements FavoriteForumDirectoryRepository {
  _FakeFavoriteForumDirectoryRepository(this.favoriteForums);

  final List<FavoriteForumEntry> favoriteForums;
  int loadCallCount = 0;

  @override
  FavoriteForumDirectorySourceCapabilities get capabilities =>
      _favoriteForumSourceCapabilities;

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
}

final _favoriteForumSourceCapabilities =
    FavoriteForumDirectorySourceCapabilities(
      values: DataCapabilitySet<FavoriteForumDirectoryCapability>.supported(
        FavoriteForumDirectoryCapability.values,
      ),
    );

class _MutableNow {
  _MutableNow(this.value);

  DateTime value;

  DateTime call() => value;
}

SessionInfo _loggedInSession({
  String uid = '597454',
  String username = 'tester',
}) {
  return SessionInfo(
    uid: uid,
    username: username,
    formhash: '14502ecf',
    isLoggedIn: true,
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({SessionInfo? session}) : _session = session;

  SessionInfo? _session;

  void setSession(SessionInfo session) {
    _session = session;
  }

  void setSignedOut() {
    _session = null;
  }

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    final session = _session;
    if (session != null) {
      return ApiSuccess(session);
    }
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

class _PendingAuthRepository extends _FakeAuthRepository {
  _PendingAuthRepository({required super.session});

  final Completer<ApiResult<SessionInfo>> _completer =
      Completer<ApiResult<SessionInfo>>();

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete(super.refreshSession());
    }
  }

  @override
  Future<ApiResult<SessionInfo>> refreshSession() {
    return _completer.future;
  }
}

class _FakeForumHomeRequestProfileResolver
    implements ForumHomeRequestProfileResolver {
  const _FakeForumHomeRequestProfileResolver(this.profile);

  final DocumentRequestProfile profile;

  @override
  Future<DocumentRequestProfile> resolve() async => profile;
}

class _RecordingNativePageCacheInvalidationService
    implements NativePageCacheInvalidationService {
  int invalidateForumHomeCalls = 0;

  @override
  Future<void> invalidateForumDisplay(String fid) async {}

  @override
  Future<void> invalidateForumHome() async {
    invalidateForumHomeCalls += 1;
  }

  @override
  Future<void> invalidateThread(String tid) async {}
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
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
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

class _RecordingImageCacheService extends _FakeImageCacheService {
  final requests = <ImageCacheRequest>[];

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    requests.add(request);
    return super.ensureCached(request);
  }
}

class _FakeForumImagePrecacheService implements ForumImagePrecacheService {
  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async {
    return const ForumImagePrecacheResult(success: true);
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    return const ForumImagePrecacheResult(success: true, decoded: true);
  }
}

class _RecordingForumImagePrecacheService
    extends _FakeForumImagePrecacheService {
  final decodedSpecs = <ForumImageLoadSpec>[];

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    decodedSpecs.add(spec);
    return super.precacheDecoded(
      context: context,
      spec: spec,
      expectedDisplaySize: expectedDisplaySize,
    );
  }
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

class _ProjectionPrefixBatchConversionService
    implements PlainTextBatchConversionService {
  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    return <String>[for (final source in sources) 'T:$source'];
  }
}

class _ProjectionTestConverter implements TextConverter {
  const _ProjectionTestConverter(this.mode);

  @override
  String get id => 'projection-test:${mode.name}';

  @override
  final TextConversionMode mode;

  @override
  Future<String> convertHtml(String html) async => html;
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

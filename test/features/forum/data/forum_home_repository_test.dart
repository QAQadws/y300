import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_resource_client.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/data/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/data/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ForumHomeHtmlRepository', () {
    test(
      'loads forum home from mobile HTML and probes first carousel image',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter();
        final repository = _buildHtmlRepository(adapter);

        final result = await repository.getForumHomePayload();

        expect(result.isSuccess, isTrue);
        final payload = result.dataOrNull!;
        expect(payload.isLoggedIn, isTrue);
        expect(payload.favoriteForums.map((forum) => forum.fid), ['33']);
        expect(payload.forumIndex.categories.map((category) => category.name), [
          '庙堂',
        ]);
        expect(payload.forumIndex.forums.map((forum) => forum.fid), [
          '16',
          '370',
        ]);
        expect(payload.chromeData.carouselItems, hasLength(1));
        expect(
          payload.chromeData.carouselItems.single.targetUrl,
          'https://bbs.yamibo.com/thread-570956-1-1.html',
        );
        expect(
          payload.chromeData.carouselItems.single.aspectRatio,
          closeTo(3.0, 0.01),
        );
        expect(adapter.htmlRequestedUris, <String>[
          'https://bbs.yamibo.com/index.php?mobile=2',
        ]);
        expect(adapter.userAgents.single, contains('Mobile'));
        expect(adapter.imageRequestedUris, <String>[
          'https://bbs.yamibo.com/data/attachment/block/95/banner.jpg',
        ]);
      },
    );

    test(
      'returns failure when mobile HTML request fails without API fallback',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
        final repository = _buildHtmlRepository(adapter);

        final result = await repository.getForumHomePayload();

        expect(result.isFailure, isTrue);
        expect(result.errorOrNull?.statusCode, 503);
        expect(adapter.htmlRequestedUris, <String>[
          'https://bbs.yamibo.com/index.php?mobile=2',
        ]);
        expect(adapter.imageRequestedUris, isEmpty);
      },
    );

    test(
      'default provider does not read forumindex profile or myfavforum',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter();
        final gateway = _buildGateway(adapter);
        final forumRepository = _CountingForumRepository();
        final authRepository = _CountingAuthRepository();
        final favoriteRepository = _CountingFavoriteRepository();
        final container = ProviderContainer(
          overrides: [
            forumRepositoryProvider.overrideWithValue(forumRepository),
            authRepositoryProvider.overrideWithValue(authRepository),
            favoriteRepositoryProvider.overrideWithValue(favoriteRepository),
            yamiboHtmlClientProvider.overrideWithValue(
              YamiboHtmlClient(gateway: gateway),
            ),
            yamiboResourceClientProvider.overrideWithValue(
              YamiboResourceClient(gateway: gateway),
            ),
            imageRequestHeaderBuilderProvider.overrideWithValue(
              const _StaticImageRequestHeaderBuilder(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final result = await container
            .read(forumHomeRepositoryProvider)
            .getForumHomePayload();

        expect(result.isSuccess, isTrue);
        expect(forumRepository.getForumIndexCalls, 0);
        expect(authRepository.refreshSessionCalls, 0);
        expect(favoriteRepository.getFavoriteForumsCalls, 0);
        expect(adapter.htmlRequestedUris, <String>[
          'https://bbs.yamibo.com/index.php?mobile=2',
        ]);
      },
    );
  });

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

    test('includes home chrome payload when chrome loader succeeds', () async {
      final repository = DiscuzForumHomeRepository(
        loadForumIndex: () async => ApiSuccess(_sampleForumIndexData()),
        refreshSession: () async => ApiSuccess(_loggedOutSession()),
        loadChrome: () async => const ApiSuccess(
          ForumHomeChromeData(
            carouselItems: [
              ForumHomeCarouselItem(
                imageUrl: 'https://bbs.yamibo.com/banner.jpg',
                targetUrl: 'https://bbs.yamibo.com/thread-1-1-1.html',
              ),
            ],
          ),
        ),
      );

      final result = await repository.getForumHomePayload();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.chromeData.carouselItems, hasLength(1));
      expect(
        result.dataOrNull!.chromeData.carouselItems.single.targetUrl,
        'https://bbs.yamibo.com/thread-1-1-1.html',
      );
    });

    test('degrades to empty chrome when chrome loader fails', () async {
      final repository = DiscuzForumHomeRepository(
        loadForumIndex: () async => ApiSuccess(_sampleForumIndexData()),
        refreshSession: () async => ApiSuccess(_loggedOutSession()),
        loadChrome: () async => const ApiFailure(
          ApiError(type: ApiErrorType.network, message: 'offline'),
        ),
      );

      final result = await repository.getForumHomePayload();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.chromeData.carouselItems, isEmpty);
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

ForumHomeHtmlRepository _buildHtmlRepository(
  _ForumHomeHtmlTestAdapter adapter,
) {
  final gateway = _buildGateway(adapter);
  return ForumHomeHtmlRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
    imageProbe: ForumHomeCarouselImageProbe(
      resourceClient: YamiboResourceClient(gateway: gateway),
      headerBuilder: const _StaticImageRequestHeaderBuilder(),
    ),
  );
}

YamiboHttpGateway _buildGateway(_ForumHomeHtmlTestAdapter adapter) {
  return YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: Dio(
      BaseOptions(
        baseUrl: 'https://bbs.yamibo.com',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    )..httpClientAdapter = adapter,
    enableLog: false,
  );
}

class _ForumHomeHtmlTestAdapter implements HttpClientAdapter {
  _ForumHomeHtmlTestAdapter({this.failMobileIndex = false});

  final bool failMobileIndex;
  final htmlRequestedUris = <String>[];
  final imageRequestedUris = <String>[];
  final userAgents = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isImageRequest = options.uri.path.endsWith('/banner.jpg');
    if (isImageRequest) {
      imageRequestedUris.add(options.uri.toString());
      return ResponseBody.fromBytes(_pngBytes(width: 300, height: 100), 200);
    }

    htmlRequestedUris.add(options.uri.toString());
    userAgents.add(options.headers['User-Agent']?.toString() ?? '');
    if (failMobileIndex) {
      return ResponseBody.fromString('unavailable', 503);
    }
    if (options.uri.path.endsWith('/index.php')) {
      return ResponseBody.fromString(_mobileHomeHtml, 200);
    }

    return ResponseBody.fromString(
      jsonEncode(<String, String>{'unexpected': options.uri.toString()}),
      404,
    );
  }

  Uint8List _pngBytes({required int width, required int height}) {
    final bytes = Uint8List(24);
    bytes.setAll(0, const <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
    final data = ByteData.sublistView(bytes);
    data.setUint32(16, width, Endian.big);
    data.setUint32(20, height, Endian.big);
    return bytes;
  }
}

class _StaticImageRequestHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageRequestHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{
      'User-Agent': DiscuzImageRequestHeaderBuilder.browserUserAgent,
      'Accept': DiscuzImageRequestHeaderBuilder.imageAcceptHeader,
      'Referer': 'https://bbs.yamibo.com/',
    };
  }
}

class _CountingForumRepository implements ForumRepository {
  int getForumIndexCalls = 0;

  @override
  Future<ApiResult<ForumIndexData>> getForumIndex() async {
    getForumIndexCalls++;
    throw StateError('forumindex must not be called by HTML-first home');
  }
}

class _CountingAuthRepository implements AuthRepository {
  int refreshSessionCalls = 0;

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    refreshSessionCalls++;
    throw StateError('profile must not be called by HTML-first home');
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

class _CountingFavoriteRepository implements FavoriteRepository {
  int getFavoriteForumsCalls = 0;

  @override
  Future<ApiResult<List<FavoriteForum>>> getFavoriteForums() async {
    getFavoriteForumsCalls++;
    throw StateError('myfavforum must not be called by HTML-first home');
  }

  @override
  Future<ApiResult<FavoriteThreadsPage>> getFavoriteThreads({
    required int page,
  }) async {
    throw StateError('favorite threads are not part of this test');
  }
}

const _mobileHomeHtml = '''
<body id="forum">
  <div class="index-top-wrapper">
    <div class="yami-swiper">
      <div class="swiper-slide">
        <a href="thread-570956-1-1.html">
          <img src="data/attachment/block/95/banner.jpg">
        </a>
      </div>
    </div>
  </div>
  <div class="forumlist cl">
    <div class="subforumshow cl" href="#sub-forum-myfav">
      <h2><a href="javascript:;">我收藏的版块</a></h2>
    </div>
    <div id="sub-forum-myfav" class="sub-forum mlist1 cl">
      <ul>
        <li>
          <a href="forum.php?mod=forumdisplay&amp;fid=33&amp;mobile=2"
             class="murl">
            <p class="mtit">海域區<span class="mnum">今日 88</span></p>
            <p class="mtxt">风声水起。</p>
          </a>
        </li>
      </ul>
    </div>
    <div class="subforumshow cl" href="#sub-forum_14">
      <h2><a href="javascript:;">庙堂</a></h2>
    </div>
    <div id="sub-forum_14" class="sub-forum mlist1 cl">
      <ul>
        <li>
          <a href="forum.php?mod=forumdisplay&amp;fid=16&amp;mobile=2"
             class="murl">
            <p class="mtit">管理版<span class="mnum">今日 5</span></p>
            <p class="mtxt">既无论先民后主，何必辩你们我们。</p>
          </a>
        </li>
        <li>
          <a href="forum.php?mod=forumdisplay&amp;fid=370&amp;mobile=2"
             class="murl">
            <p class="mtit">使用指南</p>
            <p class="mtxt">使用问题看本版</p>
          </a>
        </li>
      </ul>
    </div>
  </div>
</body>
''';

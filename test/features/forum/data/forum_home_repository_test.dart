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
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/favorites/data/repositories/favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/services/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/data/repositories/forum_repository.dart';

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

    test('writes successful HTML and parsed payload to page caches', () async {
      final adapter = _ForumHomeHtmlTestAdapter();
      final documentCache = _FakeDocumentCacheService();
      final snapshotCache = _FakeParsedSnapshotCacheService<ForumHomePayload>();
      final now = DateTime(2026, 1, 1, 10);
      final repository = _buildHtmlRepository(
        adapter,
        documentCacheService: documentCache,
        snapshotCacheService: snapshotCache,
        now: () => now,
      );

      final result = await repository.getForumHomePayload();

      expect(result.isSuccess, isTrue);
      expect(documentCache.putDocuments, hasLength(1));
      final document = documentCache.putDocuments.single;
      expect(document.ownerType, CacheOwnerType.forum);
      expect(document.ownerId, 'home');
      expect(document.requestProfile, DocumentRequestProfile.anonymous);
      expect(document.body, _mobileHomeHtml);
      expect(document.contentType, 'text/html');
      expect(document.statusCode, 200);
      expect(document.fetchedAt, now);
      expect(snapshotCache.putValues, hasLength(1));
      expect(
        snapshotCache.putValues.single.forumIndex.forums.map(
          (forum) => forum.fid,
        ),
        <String>['16', '370'],
      );
      expect(snapshotCache.putDescriptors.single.snapshotType, 'forum.home');
      expect(
        snapshotCache.putDescriptors.single.cacheKey,
        contains(DocumentRequestProfile.anonymous.id),
      );
    });

    test('returns fresh home snapshot before network request', () async {
      final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
      final snapshotCache = _FakeParsedSnapshotCacheService<ForumHomePayload>();
      final descriptor = const CacheKeyCanonicalizer().forumHomeSnapshot(
        requestProfile: DocumentRequestProfile.anonymous,
      );
      snapshotCache.seed(
        descriptor,
        ForumHomePayload(
          forumIndex: ForumIndexData(
            categories: <ForumCategory>[
              ForumCategory(fid: 'cached-1', name: '缓存分类', forums: ['88']),
            ],
            forums: <ForumItem>[
              ForumItem(
                fid: '88',
                name: '缓存版块',
                threads: 0,
                posts: 0,
                todayPosts: 0,
                description: '',
                icon: '',
                subForums: <ForumItem>[],
              ),
            ],
          ),
          isLoggedIn: false,
          favoriteForums: const <FavoriteForum>[],
        ),
      );
      final repository = _buildHtmlRepository(
        adapter,
        snapshotCacheService: snapshotCache,
      );

      final result = await repository.getForumHomePayload();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.forumIndex.forums.single.name, '缓存版块');
      expect(adapter.htmlRequestedUris, isEmpty);
      expect(adapter.imageRequestedUris, isEmpty);
    });

    test(
      'writes logged in home cache under logged in request profile',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter();
        final documentCache = _FakeDocumentCacheService();
        final snapshotCache =
            _FakeParsedSnapshotCacheService<ForumHomePayload>();
        final sessionStore = YamiboSessionStore()
          ..saveExtracted(
            YamiboSessionSnapshot(
              isLoggedIn: true,
              uid: '597454',
              username: 'tester',
              formhash: '14502ecf',
              updatedAt: DateTime(2026, 1, 1),
              source: 'test',
            ),
          );
        final repository = _buildHtmlRepository(
          adapter,
          sessionStore: sessionStore,
          documentCacheService: documentCache,
          snapshotCacheService: snapshotCache,
        );

        final result = await repository.getForumHomePayload();

        expect(result.isSuccess, isTrue);
        expect(
          documentCache.putDocuments.single.requestProfile,
          DocumentRequestProfile.loggedIn,
        );
        expect(
          snapshotCache.putDescriptors.single.cacheKey,
          contains(DocumentRequestProfile.loggedIn.id),
        );
      },
    );

    test(
      'request profile override takes precedence over session store when writing caches',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter();
        final documentCache = _FakeDocumentCacheService();
        final snapshotCache =
            _FakeParsedSnapshotCacheService<ForumHomePayload>();
        final sessionStore = YamiboSessionStore()
          ..saveExtracted(
            YamiboSessionSnapshot(
              isLoggedIn: true,
              uid: '597454',
              username: 'tester',
              formhash: '14502ecf',
              updatedAt: DateTime(2026, 1, 1),
              source: 'test',
            ),
          );
        final repository = _buildHtmlRepository(
          adapter,
          sessionStore: sessionStore,
          documentCacheService: documentCache,
          snapshotCacheService: snapshotCache,
        );

        final result = await repository.getForumHomePayload(
          requestProfileOverride: DocumentRequestProfile.anonymous,
        );

        expect(result.isSuccess, isTrue);
        expect(
          documentCache.putDocuments.single.requestProfile,
          DocumentRequestProfile.anonymous,
        );
        expect(
          snapshotCache.putDescriptors.single.cacheKey,
          contains(DocumentRequestProfile.anonymous.id),
        );
      },
    );

    test(
      'network first skips fresh home snapshot and refreshes network',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter();
        final snapshotCache =
            _FakeParsedSnapshotCacheService<ForumHomePayload>();
        final descriptor = const CacheKeyCanonicalizer().forumHomeSnapshot(
          requestProfile: DocumentRequestProfile.anonymous,
        );
        snapshotCache.seed(
          descriptor,
          ForumHomePayload(
            forumIndex: ForumIndexData(
              categories: <ForumCategory>[
                ForumCategory(fid: 'cached-1', name: '缓存分类', forums: ['88']),
              ],
              forums: <ForumItem>[
                ForumItem(
                  fid: '88',
                  name: '缓存版块',
                  threads: 0,
                  posts: 0,
                  todayPosts: 0,
                  description: '',
                  icon: '',
                  subForums: <ForumItem>[],
                ),
              ],
            ),
            isLoggedIn: false,
            favoriteForums: const <FavoriteForum>[],
          ),
        );
        final repository = _buildHtmlRepository(
          adapter,
          snapshotCacheService: snapshotCache,
        );

        final result = await repository.getForumHomePayload(
          cachePolicy: CacheLoadPolicy.networkFirst,
        );

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull!.forumIndex.forums.map((forum) => forum.fid), [
          '16',
          '370',
        ]);
        expect(adapter.htmlRequestedUris, <String>[
          'https://bbs.yamibo.com/index.php?mobile=2',
        ]);
      },
    );

    test('parses cached home HTML when network fails', () async {
      final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
      final documentCache = _FakeDocumentCacheService();
      final now = DateTime(2026, 1, 1, 11);
      final descriptor = const CacheKeyCanonicalizer().forumHome(
        requestProfile: DocumentRequestProfile.anonymous,
      );
      documentCache.seed(
        CachedDocument(
          cacheKey: descriptor.cacheKey,
          ownerType: descriptor.ownerType,
          ownerId: descriptor.ownerId,
          sourceUrl: descriptor.sourceUrl,
          body: _mobileHomeHtml,
          fetchedAt: DateTime(2026, 1, 1, 10),
          updatedAt: DateTime(2026, 1, 1, 10),
        ),
      );
      final repository = _buildHtmlRepository(
        adapter,
        documentCacheService: documentCache,
        now: () => now,
      );

      final result = await repository.getForumHomePayload();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.forumIndex.forums.map((forum) => forum.fid), [
        '16',
        '370',
      ]);
      expect(documentCache.touchedKeys, <String>[descriptor.cacheKey]);
      expect(documentCache.touchedAt[descriptor.cacheKey], now);
    });

    test(
      'request profile override uses explicit cache bucket for document fallback',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
        final documentCache = _FakeDocumentCacheService();
        final sessionStore = YamiboSessionStore()
          ..saveExtracted(
            YamiboSessionSnapshot(
              isLoggedIn: true,
              uid: '597454',
              username: 'tester',
              formhash: '14502ecf',
              updatedAt: DateTime(2026, 1, 1),
              source: 'test',
            ),
          );
        final descriptor = const CacheKeyCanonicalizer().forumHome(
          requestProfile: DocumentRequestProfile.anonymous,
        );
        documentCache.seed(
          CachedDocument(
            cacheKey: descriptor.cacheKey,
            ownerType: descriptor.ownerType,
            ownerId: descriptor.ownerId,
            sourceUrl: descriptor.sourceUrl,
            requestProfile: descriptor.requestProfile,
            body: _mobileHomeHtml,
            fetchedAt: DateTime(2026, 1, 1, 10),
            updatedAt: DateTime(2026, 1, 1, 10),
          ),
        );
        final repository = _buildHtmlRepository(
          adapter,
          sessionStore: sessionStore,
          documentCacheService: documentCache,
        );

        final result = await repository.getForumHomePayload(
          cachePolicy: CacheLoadPolicy.networkFirst,
          requestProfileOverride: DocumentRequestProfile.anonymous,
        );

        expect(result.isSuccess, isTrue);
        expect(documentCache.touchedKeys, <String>[descriptor.cacheKey]);
      },
    );

    test(
      'network failure does not fall back to other request profile cache',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
        final documentCache = _FakeDocumentCacheService();
        final loggedInDescriptor = const CacheKeyCanonicalizer().forumHome(
          requestProfile: DocumentRequestProfile.loggedIn,
        );
        documentCache.seed(
          CachedDocument(
            cacheKey: loggedInDescriptor.cacheKey,
            ownerType: loggedInDescriptor.ownerType,
            ownerId: loggedInDescriptor.ownerId,
            sourceUrl: loggedInDescriptor.sourceUrl,
            requestProfile: loggedInDescriptor.requestProfile,
            body: _mobileHomeHtml,
            fetchedAt: DateTime(2026, 1, 1, 10),
            updatedAt: DateTime(2026, 1, 1, 10),
          ),
        );
        final repository = _buildHtmlRepository(
          adapter,
          documentCacheService: documentCache,
        );

        final result = await repository.getForumHomePayload(
          cachePolicy: CacheLoadPolicy.networkFirst,
        );

        expect(result.isFailure, isTrue);
        expect(documentCache.touchedKeys, isEmpty);
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
            documentCacheServiceProvider.overrideWithValue(
              _FakeDocumentCacheService(),
            ),
            parsedSnapshotCacheServiceProvider.overrideWithValue(
              _FakeParsedSnapshotCacheService<ForumHomePayload>(),
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
  _ForumHomeHtmlTestAdapter adapter, {
  DocumentCacheService? documentCacheService,
  ParsedSnapshotCacheService? snapshotCacheService,
  YamiboSessionStore? sessionStore,
  DateTime Function()? now,
}) {
  final gateway = _buildGateway(adapter);
  return ForumHomeHtmlRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
    imageProbe: ForumHomeCarouselImageProbe(
      resourceClient: YamiboResourceClient(gateway: gateway),
      headerBuilder: const _StaticImageRequestHeaderBuilder(),
    ),
    sessionStore: sessionStore,
    documentCacheService: documentCacheService,
    snapshotCacheService: snapshotCacheService,
    now: now,
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

class _FakeParsedSnapshotCacheService<T> implements ParsedSnapshotCacheService {
  final _snapshots = <String, T>{};
  final putDescriptors = <SnapshotCacheDescriptor>[];
  final putValues = <T>[];

  void seed(SnapshotCacheDescriptor descriptor, T value) {
    _snapshots[descriptor.cacheKey] = value;
  }

  @override
  Future<CachedSnapshot<R>?> get<R>(
    SnapshotCacheDescriptor descriptor,
    SnapshotCodec<R> codec,
  ) async {
    final value = _snapshots[descriptor.cacheKey];
    if (value is! R) {
      return null;
    }
    return CachedSnapshot<R>(
      cacheKey: descriptor.cacheKey,
      ownerType: descriptor.ownerType,
      ownerId: descriptor.ownerId,
      snapshotType: codec.snapshotType,
      codecVersion: codec.codecVersion,
      parserVersion: codec.parserVersion,
      value: value,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      staleAt: DateTime(2099, 1, 1),
      expiresAt: DateTime(2099, 1, 2),
    );
  }

  @override
  Future<void> put<R>(
    SnapshotCacheDescriptor descriptor,
    R value,
    SnapshotCodec<R> codec, {
    required SnapshotCachePolicy policy,
  }) async {
    putDescriptors.add(descriptor);
    if (value is T) {
      putValues.add(value);
      _snapshots[descriptor.cacheKey] = value;
    }
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {}

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async {
    return 0;
  }

  @override
  Future<int> deleteExpired(DateTime now) async => 0;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    return const StorageUsageSection(
      bucket: StorageBucket.pageCache,
      label: '页面缓存',
      bytes: 0,
      clearable: false,
    );
  }
}

class _FakeDocumentCacheService implements DocumentCacheService {
  final _documents = <String, CachedDocument>{};
  final putDocuments = <CachedDocument>[];
  final touchedKeys = <String>[];
  final touchedAt = <String, DateTime>{};

  void seed(CachedDocument document) {
    _documents[document.cacheKey] = document;
  }

  @override
  Future<CachedDocument?> getByKey(String cacheKey) async {
    return _documents[cacheKey];
  }

  @override
  Future<void> put(CachedDocument document) async {
    putDocuments.add(document);
    _documents[document.cacheKey] = document;
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {
    touchedKeys.add(cacheKey);
    touchedAt[cacheKey] = accessedAt;
  }

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async {
    final before = _documents.length;
    _documents.removeWhere(
      (_, document) =>
          document.ownerType == ownerType && document.ownerId == ownerId,
    );
    return before - _documents.length;
  }

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async {
    final before = _documents.length;
    _documents.removeWhere(
      (_, document) =>
          document.ownerType == ownerType &&
          document.ownerId.startsWith(ownerIdPrefix),
    );
    return before - _documents.length;
  }

  @override
  Future<int> deleteOlderThan(DateTime cutoff) async => 0;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    return const StorageUsageSection(
      bucket: StorageBucket.pageCache,
      label: '页面缓存',
      bytes: 0,
      clearable: false,
    );
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

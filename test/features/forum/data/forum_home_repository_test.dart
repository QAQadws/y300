import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
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
import 'package:y300/features/forum/data/services/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/domain/models/forum_directory_models.dart';

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
        expect(payload.isLoggedIn, isFalse);
        expect(payload.favoriteForums.map((forum) => forum.fid), ['33']);
        expect(payload.directory.sections, hasLength(1));
        expect(payload.directory.sections.map((section) => section.title), [
          '庙堂',
        ]);
        expect(
          payload.directory.sections.single.forums.map((forum) => forum.fid),
          ['16', '370'],
        );
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
        snapshotCache.putValues.single.directory.sections.single.forums.map(
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
          directory: const ForumDirectoryData(
            sections: [
              ForumDirectorySection(
                identity: 'cached-1',
                title: '缓存分类',
                forums: [
                  ForumDirectoryForum(
                    fid: '88',
                    title: '缓存版块',
                    description: '',
                    todayPosts: null,
                  ),
                ],
              ),
            ],
          ),
          isLoggedIn: false,
          favoriteForums: const <ForumHomeFavoriteForum>[],
        ),
      );
      final repository = _buildHtmlRepository(
        adapter,
        snapshotCacheService: snapshotCache,
      );

      final result = await repository.getForumHomePayload();

      expect(result.isSuccess, isTrue);
      expect(
        result.dataOrNull!.directory.sections.single.forums.single.title,
        '缓存版块',
      );
      expect(adapter.htmlRequestedUris, isEmpty);
      expect(adapter.imageRequestedUris, isEmpty);
    });

    test(
      'directory load reuses fresh snapshot and preserves read metadata',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
        final snapshotCache =
            _FakeParsedSnapshotCacheService<ForumHomePayload>();
        final descriptor = const CacheKeyCanonicalizer().forumHomeSnapshot(
          requestProfile: DocumentRequestProfile.anonymous,
        );
        snapshotCache.seed(descriptor, _cachedHomePayload());
        final repository = _buildHtmlRepository(
          adapter,
          snapshotCacheService: snapshotCache,
        );

        final result = await repository.load(const ForumDirectoryQuery());

        expect(result.isSuccess, isTrue);
        final metadata = result.when(
          success: (_, _, value) => value,
          failure: (_) => throw StateError('expected success'),
        );
        expect(metadata.origin, DataReadOrigin.freshSnapshot);
        expect(metadata.freshness, DataReadFreshness.freshCache);
        expect(result.dataOrNull!.sections.single.forums.single.fid, '88');
        expect(adapter.htmlRequestedUris, isEmpty);
        expect(adapter.imageRequestedUris, isEmpty);
      },
    );

    test('fresh snapshot login state follows the request profile', () async {
      final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
      final snapshotCache = _FakeParsedSnapshotCacheService<ForumHomePayload>();
      final descriptor = const CacheKeyCanonicalizer().forumHomeSnapshot(
        requestProfile: DocumentRequestProfile.loggedIn,
      );
      snapshotCache.seed(descriptor, _cachedHomePayload());
      final repository = _buildHtmlRepository(
        adapter,
        snapshotCacheService: snapshotCache,
      );

      final result = await repository.getForumHomePayload(
        requestProfileOverride: DocumentRequestProfile.loggedIn,
      );

      expect(result.dataOrNull?.isLoggedIn, isTrue);
      expect(adapter.htmlRequestedUris, isEmpty);
    });

    test(
      'directory load uses stale document fallback with stale provenance',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
        final documentCache = _FakeDocumentCacheService();
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
            fetchedAt: DateTime(2026, 1, 1, 9),
            updatedAt: DateTime(2026, 1, 1, 9),
          ),
        );
        final repository = _buildHtmlRepository(
          adapter,
          documentCacheService: documentCache,
        );

        final result = await repository.load(const ForumDirectoryQuery());

        expect(result.isSuccess, isTrue);
        final metadata = result.when(
          success: (_, _, value) => value,
          failure: (_) => throw StateError('expected success'),
        );
        expect(metadata.origin, DataReadOrigin.cachedDocumentFallback);
        expect(metadata.freshness, DataReadFreshness.staleOrUnknown);
        expect(result.dataOrNull!.sections.single.forums, hasLength(2));
        expect(adapter.imageRequestedUris, isEmpty);
      },
    );

    test(
      'readCachedPayload returns a stale snapshot without any network work',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
        final snapshotCache =
            _FakeParsedSnapshotCacheService<ForumHomePayload>()
              ..updatedAt = DateTime(2026, 1, 1, 9)
              ..staleAt = DateTime(2026, 1, 1, 9, 5)
              ..expiresAt = DateTime(2026, 1, 2, 9);
        final descriptor = const CacheKeyCanonicalizer().forumHomeSnapshot(
          requestProfile: DocumentRequestProfile.anonymous,
        );
        snapshotCache.seed(descriptor, _cachedHomePayload());
        final repository = _buildHtmlRepository(
          adapter,
          snapshotCacheService: snapshotCache,
          now: () => DateTime(2026, 1, 1, 10),
        );

        final cached = await repository.readCachedPayload(
          requestProfile: DocumentRequestProfile.anonymous,
        );

        expect(
          cached?.payload.directory.sections.single.forums.single.title,
          '缓存版块',
        );
        expect(cached?.updatedAt, DateTime(2026, 1, 1, 9));
        expect(adapter.htmlRequestedUris, isEmpty);
        expect(adapter.imageRequestedUris, isEmpty);
      },
    );

    test(
      'readCachedPayload parses cached HTML without probing carousel image',
      () async {
        final adapter = _ForumHomeHtmlTestAdapter(failMobileIndex: true);
        final documentCache = _FakeDocumentCacheService();
        final descriptor = const CacheKeyCanonicalizer().forumHome(
          requestProfile: DocumentRequestProfile.anonymous,
        );
        final updatedAt = DateTime(2026, 1, 1, 9);
        documentCache.seed(
          CachedDocument(
            cacheKey: descriptor.cacheKey,
            ownerType: descriptor.ownerType,
            ownerId: descriptor.ownerId,
            sourceUrl: descriptor.sourceUrl,
            requestProfile: descriptor.requestProfile,
            body: _mobileHomeHtml,
            fetchedAt: updatedAt,
            updatedAt: updatedAt,
          ),
        );
        final repository = _buildHtmlRepository(
          adapter,
          documentCacheService: documentCache,
          now: () => DateTime(2026, 1, 1, 10),
        );

        final cached = await repository.readCachedPayload(
          requestProfile: DocumentRequestProfile.anonymous,
        );

        expect(cached?.payload.directory.sections, hasLength(1));
        expect(cached?.updatedAt, updatedAt);
        expect(
          cached?.payload.chromeData.carouselItems.single.aspectRatio,
          isNull,
        );
        expect(documentCache.touchedKeys, isEmpty);
        expect(adapter.htmlRequestedUris, isEmpty);
        expect(adapter.imageRequestedUris, isEmpty);
      },
    );

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
            directory: _cachedHomePayload().directory,
            isLoggedIn: false,
            favoriteForums: const <ForumHomeFavoriteForum>[],
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
        expect(
          result.dataOrNull!.directory.sections.single.forums.map(
            (forum) => forum.fid,
          ),
          ['16', '370'],
        );
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
      expect(
        result.dataOrNull!.directory.sections.single.forums.map(
          (forum) => forum.fid,
        ),
        ['16', '370'],
      );
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
        expect(result.failureOrNull?.statusCode, 503);
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
        final container = ProviderContainer(
          overrides: [
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
        final homeRepository = container.read(forumHomeRepositoryProvider);
        final directoryRepository = container.read(
          forumDirectoryRepositoryProvider,
        );
        expect(homeRepository, isA<ForumHomeHtmlRepository>());
        expect(directoryRepository, same(homeRepository));
        expect(adapter.htmlRequestedUris, <String>[
          'https://bbs.yamibo.com/index.php?mobile=2',
        ]);
      },
    );
  });
}

ForumHomePayload _cachedHomePayload() {
  return ForumHomePayload(
    directory: const ForumDirectoryData(
      sections: [
        ForumDirectorySection(
          identity: 'cached-1',
          title: '缓存分类',
          forums: [
            ForumDirectoryForum(
              fid: '88',
              title: '缓存版块',
              description: '',
              todayPosts: null,
            ),
          ],
        ),
      ],
    ),
    isLoggedIn: false,
    favoriteForums: const <ForumHomeFavoriteForum>[],
  );
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

class _FakeParsedSnapshotCacheService<T> implements ParsedSnapshotCacheService {
  final _snapshots = <String, T>{};
  final putDescriptors = <SnapshotCacheDescriptor>[];
  final putValues = <T>[];
  DateTime updatedAt = DateTime(2026, 1, 1);
  DateTime staleAt = DateTime(2099, 1, 1);
  DateTime expiresAt = DateTime(2099, 1, 2);

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
      updatedAt: updatedAt,
      staleAt: staleAt,
      expiresAt: expiresAt,
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

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/forum/data/repositories/forum_display_repository.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'ForumDisplayHtmlRepository requests mobile forumdisplay HTML',
    () async {
      final adapter = _ForumDisplayHtmlTestAdapter();
      final repository = _buildRepository(adapter);

      final result = await repository.getForumDisplay(fid: '30', page: 2);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.forumName, '中文百合漫画区');
      expect(result.dataOrNull!.threads.single.tid, '572604');
      final requested = Uri.parse(adapter.requestedUris.single);
      expect(requested.origin, 'https://bbs.yamibo.com');
      expect(requested.path, '/forum.php');
      expect(requested.queryParameters['mod'], 'forumdisplay');
      expect(requested.queryParameters['fid'], '30');
      expect(requested.queryParameters['page'], '2');
      expect(requested.queryParameters['mobile'], '2');
      expect(adapter.userAgents.single, contains('Mobile'));
    },
  );

  test(
    'ForumDisplayHtmlRepository keeps forumdisplay query parameters',
    () async {
      final adapter = _ForumDisplayHtmlTestAdapter();
      final repository = _buildRepository(adapter);

      final result = await repository.getForumDisplayByQuery(
        const ForumDisplayQuery(
          fid: '30',
          page: 3,
          parameters: <String, String>{
            'filter': 'typeid',
            'typeid': '69',
            'orderby': 'lastpost',
          },
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.requestedUris.single, contains('mod=forumdisplay'));
      expect(adapter.requestedUris.single, contains('fid=30'));
      expect(adapter.requestedUris.single, contains('page=3'));
      expect(adapter.requestedUris.single, contains('filter=typeid'));
      expect(adapter.requestedUris.single, contains('typeid=69'));
      expect(adapter.requestedUris.single, contains('orderby=lastpost'));
      expect(adapter.requestedUris.single, contains('mobile=2'));
    },
  );

  test('ForumDisplayHtmlRepository wraps HTML request failure', () async {
    final adapter = _ForumDisplayHtmlTestAdapter(statusCode: 503);
    final repository = _buildRepository(adapter);

    final result = await repository.getForumDisplay(fid: '30');

    expect(result.isFailure, isTrue);
    expect(result.errorOrNull?.statusCode, 503);
    expect(result.errorOrNull?.message, contains('帖子列表 HTML 加载失败'));
  });

  test(
    'ForumDisplayHtmlRepository writes successful parse to snapshot cache',
    () async {
      final adapter = _ForumDisplayHtmlTestAdapter();
      final snapshotCache = _FakeParsedSnapshotCacheService<ForumDisplayData>();
      final repository = _buildRepository(
        adapter,
        snapshotCacheService: snapshotCache,
      );

      final result = await repository.getForumDisplay(fid: '30', page: 2);

      expect(result.isSuccess, isTrue);
      expect(snapshotCache.putValues, hasLength(1));
      expect(snapshotCache.putValues.single.forumName, '中文百合漫画区');
      expect(snapshotCache.putDescriptors.single.snapshotType, 'forum.display');
    },
  );

  test(
    'ForumDisplayHtmlRepository writes successful HTML to document cache',
    () async {
      final adapter = _ForumDisplayHtmlTestAdapter();
      final documentCache = _FakeDocumentCacheService();
      final now = DateTime(2026, 1, 1, 10);
      final repository = _buildRepository(
        adapter,
        documentCacheService: documentCache,
        now: () => now,
      );

      final result = await repository.getForumDisplay(fid: '30', page: 2);

      expect(result.isSuccess, isTrue);
      expect(documentCache.putDocuments, hasLength(1));
      final document = documentCache.putDocuments.single;
      expect(document.body, _html);
      expect(document.ownerType, CacheOwnerType.forumDisplay);
      expect(document.requestProfile, DocumentRequestProfile.anonymous);
      expect(document.ownerId, contains('fid=30'));
      expect(document.ownerId, contains('page=2'));
      expect(document.contentType, 'text/html');
      expect(document.statusCode, 200);
      expect(document.fetchedAt, now);
    },
  );

  test(
    'ForumDisplayHtmlRepository parses cached document when network fails',
    () async {
      final adapter = _ForumDisplayHtmlTestAdapter(statusCode: 503);
      final documentCache = _FakeDocumentCacheService();
      final now = DateTime(2026, 1, 1, 11);
      final repository = _buildRepository(
        adapter,
        documentCacheService: documentCache,
        now: () => now,
      );
      final descriptor = const CacheKeyCanonicalizer().forumDisplay(
        fid: '30',
        page: 2,
        queryParameters: const <String, String>{
          'mod': 'forumdisplay',
          'fid': '30',
          'mobile': '2',
          'page': '2',
        },
        requestProfile: DocumentRequestProfile.anonymous,
      );
      documentCache.seed(
        CachedDocument(
          cacheKey: descriptor.cacheKey,
          ownerType: descriptor.ownerType,
          ownerId: descriptor.ownerId,
          sourceUrl: descriptor.sourceUrl,
          body: _html,
          fetchedAt: DateTime(2026, 1, 1, 10),
          updatedAt: DateTime(2026, 1, 1, 10),
        ),
      );

      final result = await repository.getForumDisplay(fid: '30', page: 2);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.forumName, '中文百合漫画区');
      expect(result.dataOrNull!.threads.single.tid, '572604');
      expect(documentCache.touchedKeys, <String>[descriptor.cacheKey]);
      expect(documentCache.touchedAt[descriptor.cacheKey], now);
    },
  );

  test(
    'ForumDisplayHtmlRepository returns fresh snapshot before network',
    () async {
      final adapter = _ForumDisplayHtmlTestAdapter(statusCode: 503);
      final snapshotCache = _FakeParsedSnapshotCacheService<ForumDisplayData>();
      final descriptor = const CacheKeyCanonicalizer().forumDisplaySnapshot(
        fid: '30',
        page: 2,
        queryParameters: const <String, String>{
          'mod': 'forumdisplay',
          'fid': '30',
          'mobile': '2',
          'page': '2',
        },
        requestProfile: DocumentRequestProfile.anonymous,
      );
      snapshotCache.seed(
        descriptor,
        ForumDisplayData(
          fid: '30',
          forumName: '缓存版块',
          currentPage: 2,
          perPage: 20,
          totalThreads: 0,
          threads: const <ForumThreadSummary>[],
        ),
      );
      final repository = _buildRepository(
        adapter,
        snapshotCacheService: snapshotCache,
      );

      final result = await repository.getForumDisplay(fid: '30', page: 2);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.forumName, '缓存版块');
      expect(adapter.requestedUris, isEmpty);
    },
  );

  test(
    'ForumDisplayHtmlRepository networkFirst skips fresh snapshot and refreshes',
    () async {
      final adapter = _ForumDisplayHtmlTestAdapter();
      final snapshotCache = _FakeParsedSnapshotCacheService<ForumDisplayData>();
      final documentCache = _FakeDocumentCacheService();
      final descriptor = const CacheKeyCanonicalizer().forumDisplaySnapshot(
        fid: '30',
        page: 2,
        queryParameters: const <String, String>{
          'mod': 'forumdisplay',
          'fid': '30',
          'mobile': '2',
          'page': '2',
        },
        requestProfile: DocumentRequestProfile.anonymous,
      );
      snapshotCache.seed(
        descriptor,
        ForumDisplayData(
          fid: '30',
          forumName: '缓存版块',
          currentPage: 2,
          perPage: 20,
          totalThreads: 0,
          threads: const <ForumThreadSummary>[],
        ),
      );
      final repository = _buildRepository(
        adapter,
        documentCacheService: documentCache,
        snapshotCacheService: snapshotCache,
      );

      final result = await repository.getForumDisplay(
        fid: '30',
        page: 2,
        cachePolicy: CacheLoadPolicy.networkFirst,
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.forumName, '中文百合漫画区');
      expect(adapter.requestedUris, hasLength(1));
      expect(documentCache.putDocuments, hasLength(1));
      expect(snapshotCache.putValues, hasLength(1));
    },
  );

  test(
    'ForumDisplayHtmlRepository separates logged in forumdisplay cache',
    () async {
      final adapter = _ForumDisplayHtmlTestAdapter();
      final documentCache = _FakeDocumentCacheService();
      final snapshotCache = _FakeParsedSnapshotCacheService<ForumDisplayData>();
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
      final repository = _buildRepository(
        adapter,
        sessionStore: sessionStore,
        documentCacheService: documentCache,
        snapshotCacheService: snapshotCache,
      );

      final result = await repository.getForumDisplay(fid: '30', page: 2);

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
    'ForumDisplayHtmlRepository failure does not use other profile cache',
    () async {
      final adapter = _ForumDisplayHtmlTestAdapter(statusCode: 503);
      final documentCache = _FakeDocumentCacheService();
      final loggedInDescriptor = const CacheKeyCanonicalizer().forumDisplay(
        fid: '30',
        page: 2,
        queryParameters: const <String, String>{
          'mod': 'forumdisplay',
          'fid': '30',
          'mobile': '2',
          'page': '2',
        },
        requestProfile: DocumentRequestProfile.loggedIn,
      );
      documentCache.seed(
        CachedDocument(
          cacheKey: loggedInDescriptor.cacheKey,
          ownerType: loggedInDescriptor.ownerType,
          ownerId: loggedInDescriptor.ownerId,
          sourceUrl: loggedInDescriptor.sourceUrl,
          requestProfile: loggedInDescriptor.requestProfile,
          body: _html,
          fetchedAt: DateTime(2026, 1, 1, 10),
          updatedAt: DateTime(2026, 1, 1, 10),
        ),
      );
      final repository = _buildRepository(
        adapter,
        documentCacheService: documentCache,
      );

      final result = await repository.getForumDisplay(
        fid: '30',
        page: 2,
        cachePolicy: CacheLoadPolicy.networkFirst,
      );

      expect(result.isFailure, isTrue);
      expect(documentCache.touchedKeys, isEmpty);
    },
  );
}

ForumDisplayHtmlRepository _buildRepository(
  _ForumDisplayHtmlTestAdapter adapter, {
  DocumentCacheService? documentCacheService,
  ParsedSnapshotCacheService? snapshotCacheService,
  YamiboSessionStore? sessionStore,
  DateTime Function()? now,
}) {
  final gateway = YamiboHttpGateway(
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
  return ForumDisplayHtmlRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
    sessionStore: sessionStore,
    documentCacheService: documentCacheService,
    snapshotCacheService: snapshotCacheService,
    now: now,
  );
}

class _ForumDisplayHtmlTestAdapter implements HttpClientAdapter {
  _ForumDisplayHtmlTestAdapter({this.statusCode = 200});

  final int statusCode;
  final requestedUris = <String>[];
  final userAgents = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri.toString());
    userAgents.add(options.headers['User-Agent']?.toString() ?? '');
    return ResponseBody.fromString(
      statusCode == 200 ? _html : 'unavailable',
      statusCode,
    );
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

const _html = '''
<html>
<head><title>中文百合漫画区 - 百合会</title></head>
<body id="forum">
  <div class="forumdisplay-top cl">
    <h2><img src="data/attachment/common/34/common_30_icon.gif" alt="中文百合漫画区" />中文百合漫画区</h2>
    <p>今日: <span>105</span>主题: <span>52718</span>排名: <span>1</span></p>
  </div>
  <div class="threadlist_box mt10 cl">
    <div class="threadlist cl">
      <ul>
        <li class="list">
          <div class="threadlist_top cl">
            <a href="home.php?mod=space&amp;uid=732009&amp;mobile=2" class="mimg">
              <img src="https://bbs.yamibo.com/avatar.jpg">
            </a>
            <div class="muser">
              <h3><a href="home.php?mod=space&amp;uid=732009&amp;mobile=2" class="mmc">nkdndixnx</a></h3>
              <span class="mtime">2026-6-18 14:42</span>
            </div>
          </div>
          <a href="forum.php?mod=viewthread&amp;tid=572604&amp;mobile=2">
            <div class="threadlist_tit cl"><em>测试帖子</em></div>
          </a>
          <a href="forum.php?mod=viewthread&amp;tid=572604&amp;mobile=2">
            <div class="threadlist_mes cl">测试摘要</div>
          </a>
          <div class="threadlist_foot cl">
            <ul>
              <li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=typeid&amp;typeid=69&amp;mobile=2">#長篇連載</a></li>
              <li><i class="dm-eye-fill"></i>119</li>
              <li><i class="dm-chat-s-fill"></i>0</li>
            </ul>
          </div>
        </li>
      </ul>
    </div>
    <div class="pg"><strong>2</strong></div>
  </div>
</body>
</html>
''';

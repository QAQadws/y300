import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/cache/domain/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/cache/domain/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ThreadDetailHtmlRepository requests desktop viewthread HTML', () async {
    final adapter = _ThreadDetailHtmlTestAdapter();
    final repository = _buildRepository(adapter);

    final result = await repository.getThreadDetail(tid: '572529', page: 3);

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.subject, '测试帖子');
    expect(result.dataOrNull!.posts.single.author, 'alice');
    final requested = Uri.parse(adapter.requestedUris.single);
    expect(requested.origin, 'https://bbs.yamibo.com');
    expect(requested.path, '/forum.php');
    expect(requested.queryParameters['mod'], 'viewthread');
    expect(requested.queryParameters['tid'], '572529');
    expect(requested.queryParameters['page'], '3');
    expect(requested.queryParameters.containsKey('mobile'), isFalse);
    expect(adapter.userAgents.single, isNot(contains('Mobile')));
  });

  test(
    'ThreadDetailHtmlRepository wraps desktop HTML request failure',
    () async {
      final adapter = _ThreadDetailHtmlTestAdapter(statusCode: 503);
      final repository = _buildRepository(adapter);

      final result = await repository.getThreadDetail(tid: '572529');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.statusCode, 503);
      expect(result.errorOrNull?.message, contains('帖子详情 HTML 加载失败'));
    },
  );

  test(
    'ThreadDetailHtmlRepository writes successful HTML to document cache',
    () async {
      final adapter = _ThreadDetailHtmlTestAdapter();
      final documentCache = _FakeDocumentCacheService();
      final now = DateTime(2026, 1, 1);
      final repository = _buildRepository(
        adapter,
        documentCacheService: documentCache,
        now: () => now,
      );

      final result = await repository.getThreadDetail(
        tid: '572529',
        page: 3,
        queryParameters: const <String, String>{'ordertype': '1'},
      );

      expect(result.isSuccess, isTrue);
      expect(documentCache.putDocuments, hasLength(1));
      final cached = documentCache.putDocuments.single;
      expect(cached.body, _html);
      expect(cached.ownerType, CacheOwnerType.thread);
      expect(cached.ownerId, contains('tid=572529'));
      expect(cached.ownerId, contains('page=3'));
      expect(cached.ownerId, contains('ordertype=1'));
      expect(cached.contentType, 'text/html');
      expect(cached.statusCode, 200);
      expect(cached.fetchedAt, now);
    },
  );

  test(
    'ThreadDetailHtmlRepository writes successful parse to snapshot cache',
    () async {
      final adapter = _ThreadDetailHtmlTestAdapter();
      final snapshotCache = _FakeParsedSnapshotCacheService<ThreadDetailData>();
      final repository = _buildRepository(
        adapter,
        snapshotCacheService: snapshotCache,
      );

      final result = await repository.getThreadDetail(tid: '572529', page: 3);

      expect(result.isSuccess, isTrue);
      expect(snapshotCache.putValues, hasLength(1));
      expect(snapshotCache.putValues.single.subject, '测试帖子');
      expect(snapshotCache.putDescriptors.single.snapshotType, 'thread.detail');
    },
  );

  test(
    'ThreadDetailHtmlRepository returns fresh snapshot before network request',
    () async {
      final adapter = _ThreadDetailHtmlTestAdapter(statusCode: 503);
      final snapshotCache = _FakeParsedSnapshotCacheService<ThreadDetailData>();
      final descriptor = const CacheKeyCanonicalizer().threadDetailSnapshot(
        tid: '572529',
        page: 1,
      );
      snapshotCache.seed(
        descriptor,
        ThreadDetailData(
          tid: '572529',
          fid: '33',
          subject: '缓存帖子',
          author: 'cached',
          replies: 0,
          views: 0,
          currentPage: 1,
          perPage: 20,
          posts: const <ThreadPost>[],
        ),
      );
      final repository = _buildRepository(
        adapter,
        snapshotCacheService: snapshotCache,
      );

      final result = await repository.getThreadDetail(tid: '572529');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.subject, '缓存帖子');
      expect(adapter.requestedUris, isEmpty);
    },
  );

  test(
    'ThreadDetailHtmlRepository parses cached HTML when network fails',
    () async {
      final adapter = _ThreadDetailHtmlTestAdapter(statusCode: 503);
      final documentCache = _FakeDocumentCacheService();
      final now = DateTime(2026, 1, 1, 10);
      final repository = _buildRepository(
        adapter,
        documentCacheService: documentCache,
        now: () => now,
      );
      final descriptor = documentCache.descriptorForThread(
        tid: '572529',
        page: 1,
      );
      documentCache.seed(
        CachedDocument(
          cacheKey: descriptor.cacheKey,
          ownerType: descriptor.ownerType,
          ownerId: descriptor.ownerId,
          sourceUrl: descriptor.sourceUrl,
          body: _html,
          fetchedAt: DateTime(2026, 1, 1, 9),
          updatedAt: DateTime(2026, 1, 1, 9),
        ),
      );

      final result = await repository.getThreadDetail(tid: '572529');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.subject, '测试帖子');
      expect(documentCache.touchedKeys, <String>[descriptor.cacheKey]);
      expect(documentCache.touchedAt[descriptor.cacheKey], now);
    },
  );
}

ThreadDetailHtmlRepository _buildRepository(
  _ThreadDetailHtmlTestAdapter adapter, {
  DocumentCacheService? documentCacheService,
  ParsedSnapshotCacheService? snapshotCacheService,
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
  return ThreadDetailHtmlRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
    documentCacheService: documentCacheService,
    snapshotCacheService: snapshotCacheService,
    now: now,
  );
}

class _ThreadDetailHtmlTestAdapter implements HttpClientAdapter {
  _ThreadDetailHtmlTestAdapter({this.statusCode = 200});

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

  DocumentCacheDescriptor descriptorForThread({
    required String tid,
    required int page,
  }) {
    return const CacheKeyCanonicalizer().threadDetail(tid: tid, page: page);
  }

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
<body id="nv_forum" class="pg_viewthread">
  <a href="javascript:;" rel="curforum" fid="33" class="curtype">本版</a>
  <div id="postlist" class="pl bm">
    <table>
      <tr>
        <td class="pls"><div class="hm ptn"><span>查看:</span> <span>12</span><span>回复:</span> <span>1</span></div></td>
        <td class="plc ptm pbn vwthd">
          <h1 class="ts">
            <a href="forum.php?mod=forumdisplay&amp;fid=33&amp;filter=typeid&amp;typeid=410">[理性探讨]</a>
            <span id="thread_subject">测试帖子</span>
          </h1>
        </td>
      </tr>
    </table>
    <div id="post_1">
      <table id="pid1" class="plhin">
        <tr>
          <td class="pls">
            <div class="pi"><div class="authi"><a href="space-uid-10.html" class="xw1">alice</a></div></div>
            <div class="avatar"><a><img src="https://bbs.yamibo.com/avatar.jpg" class="user_avatar"></a></div>
          </td>
          <td class="plc">
            <div class="pi">
              <strong><a id="postnum1"><em>1</em><sup>#</sup></a></strong>
              <div class="pti"><div class="authi"><em id="authorposton1">发表于 2026-6-20 10:00</em></div></div>
            </div>
            <div class="pcb"><table><tr><td class="t_f" id="postmessage_1">正文</td></tr></table></div>
          </td>
        </tr>
      </table>
    </div>
  </div>
</body>
</html>
''';

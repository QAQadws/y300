import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart' as forum;
import 'package:y300/core/network/yamibo_forum_client_host_adapters.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/services/forum_home_carousel_dimension_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ForumHomeHtmlRepository', () {
    test(
      'projects one mobile HTML read and restores local dimensions',
      () async {
        final fixture = _buildFixture();

        final result = await fixture.repository.getForumHomePayload();

        expect(result.isSuccess, isTrue);
        final payload = result.dataOrNull!;
        expect(payload.isLoggedIn, isFalse);
        expect(payload.favoriteForums.map((item) => item.fid), ['33']);
        expect(payload.directory.sections.single.title, '庙堂');
        expect(
          payload.directory.sections.single.forums.map((item) => item.fid),
          ['16', '370'],
        );
        expect(payload.chromeData.carouselItems.single.aspectRatio, 3);
        expect(fixture.network.documentRequests, 1);
        expect(fixture.dimensions.lastKnownRequests, 1);
        expect(fixture.dimensions.lastSpec?.ownerId, 'home');
        expect(
          fixture.network.lastRequest?.uri.toString(),
          'https://bbs.yamibo.com/index.php?mobile=2',
        );
      },
    );

    test(
      'writes and reuses the package snapshot without another request',
      () async {
        final fixture = _buildFixture();

        final first = await fixture.repository.getForumHomePayload();
        fixture.network.failDocuments = true;
        final second = await fixture.repository.getForumHomePayload();

        expect(first.isSuccess, isTrue);
        expect(second.isSuccess, isTrue);
        expect(second.dataOrNull!.directory.sections.single.title, '庙堂');
        expect(
          second.dataOrNull!.chromeData.carouselItems.single.aspectRatio,
          3,
        );
        expect(fixture.network.documentRequests, 1);
        expect(fixture.dimensions.lastKnownRequests, 2);
        expect(fixture.documents.values, hasLength(1));
        expect(fixture.snapshots.values, hasLength(1));
        expect(
          second.when(
            success: (_, _, metadata) => metadata.origin,
            failure: (_) => forum.DataReadOrigin.unknown,
          ),
          forum.DataReadOrigin.freshSnapshot,
        );
      },
    );

    test(
      'network-first failure falls back to the existing cached document',
      () async {
        final fixture = _buildFixture();
        expect(
          (await fixture.repository.getForumHomePayload()).isSuccess,
          isTrue,
        );
        fixture.snapshots.values.clear();
        fixture.network.failDocuments = true;

        final result = await fixture.repository.getForumHomePayload(
          cachePolicy: forum.CacheLoadPolicy.networkFirst,
        );

        expect(result.isSuccess, isTrue);
        expect(
          result.when(
            success: (_, _, metadata) => metadata.origin,
            failure: (_) => forum.DataReadOrigin.unknown,
          ),
          forum.DataReadOrigin.cachedDocumentFallback,
        );
        expect(fixture.network.documentRequests, 2);
        expect(fixture.dimensions.lastKnownRequests, 2);
      },
    );

    test(
      'keeps an unresolved carousel ratio null without network probing',
      () async {
        final fixture = _buildFixture(dimensions: null);

        final result = await fixture.repository.getForumHomePayload();

        expect(result.isSuccess, isTrue);
        expect(
          result.dataOrNull!.chromeData.carouselItems.single.aspectRatio,
          isNull,
        );
        expect(fixture.network.documentRequests, 1);
        expect(fixture.dimensions.lastKnownRequests, 1);
      },
    );

    test('authenticated reads keep their own cache partition', () async {
      final session = YamiboSessionStore()
        ..saveExtracted(
          YamiboSessionSnapshot(
            isLoggedIn: true,
            uid: '10',
            username: 'fixture',
            formhash: 'fixture-formhash',
            updatedAt: DateTime(2026, 1, 1),
            source: 'test',
          ),
        );
      final fixture = _buildFixture(sessionStore: session);

      final result = await fixture.repository.getForumHomePayload();

      expect(result.dataOrNull?.isLoggedIn, isTrue);
      expect(
        fixture.documents.values.values.single.requestProfile,
        DocumentRequestProfile.loggedIn,
      );
      expect(
        fixture.documents.values.values.single.cacheKey,
        contains(DocumentRequestProfile.loggedIn.id),
      );
    });
  });
}

_HomeFixture _buildFixture({
  YamiboSessionStore? sessionStore,
  ForumImageDimensions? dimensions = const ForumImageDimensions(
    width: 300,
    height: 100,
    source: ForumImageDimensionSource.cacheMetadata,
  ),
}) {
  final network = _HomeNetwork();
  final dimensionIndex = _RecordingForumImageDimensionIndex(dimensions);
  final documents = _MemoryDocumentCacheService();
  final snapshots = _MemorySnapshotCacheService();
  final config = forum.ForumClientConfig(
    siteOrigin: Uri.parse('https://bbs.yamibo.com'),
    apiOrigin: Uri.parse('https://api.yamibo.com/mobile/index.php'),
  );
  final client = forum.YamiboForumClientBuilder(
    config: config,
    network: network,
    sessionStore: sessionStore == null
        ? null
        : Y300ForumSessionAdapter(sessionStore),
    documentStore: Y300ForumDocumentStoreAdapter(documents),
    snapshotStore: Y300ForumSnapshotStoreAdapter(snapshots),
  ).buildStandardClient();
  return _HomeFixture(
    repository: ForumHomeHtmlRepository(
      repository: client.forumHome!,
      directoryRepository: client.forumDirectory!,
      sessionStore: sessionStore,
      dimensionResolver: ForumHomeCarouselDimensionResolver(
        dimensionIndex: dimensionIndex,
      ),
    ),
    network: network,
    documents: documents,
    snapshots: snapshots,
    dimensions: dimensionIndex,
  );
}

final class _HomeFixture {
  const _HomeFixture({
    required this.repository,
    required this.network,
    required this.documents,
    required this.snapshots,
    required this.dimensions,
  });

  final ForumHomeHtmlRepository repository;
  final _HomeNetwork network;
  final _MemoryDocumentCacheService documents;
  final _MemorySnapshotCacheService snapshots;
  final _RecordingForumImageDimensionIndex dimensions;
}

final class _HomeNetwork implements forum.ForumClientNetwork {
  int documentRequests = 0;
  bool failDocuments = false;
  forum.ForumRequest? lastRequest;

  @override
  Future<forum.ForumTransportResult<forum.ForumResponse<Object?>>> send(
    forum.ForumRequest request,
  ) async {
    documentRequests += 1;
    lastRequest = request;
    if (failDocuments) {
      return const forum.ForumTransportError(
        forum.ForumTransportFailure(
          kind: forum.ForumTransportFailureKind.network,
          code: 'offline',
        ),
      );
    }
    return forum.ForumTransportSuccess(
      forum.ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const {
          'content-type': ['text/html'],
        },
        body: _mobileHomeHtml,
      ),
    );
  }
}

final class _RecordingForumImageDimensionIndex
    implements ForumImageDimensionIndex {
  _RecordingForumImageDimensionIndex(this.dimensions);

  final ForumImageDimensions? dimensions;
  int lastKnownRequests = 0;
  ForumImageLoadSpec? lastSpec;

  @override
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec) async {
    lastSpec = spec;
    return dimensions;
  }

  @override
  Future<ForumImageDimensions?> getLastKnownBySpec(
    ForumImageLoadSpec spec,
  ) async {
    lastKnownRequests += 1;
    lastSpec = spec;
    return dimensions;
  }

  @override
  Future<void> recordDecodedDimensions({
    required ForumImageLoadSpec spec,
    required Size size,
  }) async {}
}

final class _MemoryDocumentCacheService implements DocumentCacheService {
  final values = <String, CachedDocument>{};

  @override
  Future<CachedDocument?> getByKey(String cacheKey) async => values[cacheKey];

  @override
  Future<void> put(CachedDocument document) async {
    values[document.cacheKey] = document;
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {}

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async => 0;

  @override
  Future<int> deleteOlderThan(DateTime cutoff) async => 0;

  @override
  Future<StorageUsageSection> calculateUsage() async =>
      const StorageUsageSection(
        bucket: StorageBucket.pageCache,
        label: 'page cache',
        bytes: 0,
        clearable: false,
      );
}

final class _MemorySnapshotCacheService implements ParsedSnapshotCacheService {
  final values = <String, Object?>{};

  @override
  Future<CachedSnapshot<T>?> get<T>(
    SnapshotCacheDescriptor descriptor,
    SnapshotCodec<T> codec,
  ) async {
    final value = values[descriptor.cacheKey];
    if (value is! T) return null;
    final now = DateTime(2026, 1, 1);
    return CachedSnapshot<T>(
      cacheKey: descriptor.cacheKey,
      ownerType: descriptor.ownerType,
      ownerId: descriptor.ownerId,
      snapshotType: codec.snapshotType,
      codecVersion: codec.codecVersion,
      parserVersion: codec.parserVersion,
      value: value,
      createdAt: now,
      updatedAt: now,
      staleAt: DateTime(2099, 1, 1),
      expiresAt: DateTime(2099, 1, 2),
    );
  }

  @override
  Future<void> put<T>(
    SnapshotCacheDescriptor descriptor,
    T value,
    SnapshotCodec<T> codec, {
    required SnapshotCachePolicy policy,
  }) async {
    values[descriptor.cacheKey] = value;
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {}

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async => 0;

  @override
  Future<int> deleteExpired(DateTime now) async => 0;

  @override
  Future<StorageUsageSection> calculateUsage() async =>
      const StorageUsageSection(
        bucket: StorageBucket.pageCache,
        label: 'page cache',
        bytes: 0,
        clearable: false,
      );
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
      <a href="forum.php?mod=forumdisplay&amp;fid=33&amp;mobile=2" class="murl">
        <p class="mtit">海域區<span class="mnum">今日 88</span></p>
        <p class="mtxt">风声水起。</p>
      </a>
    </div>
    <div class="subforumshow cl" href="#sub-forum_14">
      <h2><a href="javascript:;">庙堂</a></h2>
    </div>
    <div id="sub-forum_14" class="sub-forum mlist1 cl">
      <a href="forum.php?mod=forumdisplay&amp;fid=16&amp;mobile=2" class="murl">
        <p class="mtit">管理版<span class="mnum">今日 5</span></p>
        <p class="mtxt">既无论先民后主，何必辩你们我们。</p>
      </a>
      <a href="forum.php?mod=forumdisplay&amp;fid=370&amp;mobile=2" class="murl">
        <p class="mtit">使用指南</p><p class="mtxt">使用问题看本版</p>
      </a>
    </div>
  </div>
</body>
''';

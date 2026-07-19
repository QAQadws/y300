import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart';
import 'package:y300/features/reader_shared/domain/metrics/reader_performance_metrics.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_capability.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_preload_coordinator.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_store.dart';

void main() {
  group('ReaderImageSessionPreloadCoordinator', () {
    test('builds decoded and disk windows around the current index', () {
      final coordinator = ReaderImageSessionPreloadCoordinator();
      final requests = coordinator.buildRequests(
        content: _content(count: 7),
        focusIndex: 3,
        scrollDirection: ContinuousImageScrollDirection.forward,
        capability: _TestCapability(),
      );

      expect(requests.map((request) => request.index), <int>[
        3,
        4,
        5,
        6,
        2,
        1,
        0,
      ]);
      expect(
        requests
            .where(
              (request) =>
                  request.kind == ReaderImageSessionPreloadKind.decoded,
            )
            .map((request) => request.index),
        <int>[3, 4, 2],
      );
      expect(
        requests
            .where(
              (request) => request.kind == ReaderImageSessionPreloadKind.disk,
            )
            .map((request) => request.index),
        <int>[5, 6, 1, 0],
      );
    });

    test('orders nearby images by reverse scroll direction', () {
      final coordinator = ReaderImageSessionPreloadCoordinator();
      final requests = coordinator.buildRequests(
        content: _content(count: 7),
        focusIndex: 3,
        scrollDirection: ContinuousImageScrollDirection.reverse,
        capability: _TestCapability(),
      );

      expect(requests.map((request) => request.index), <int>[
        3,
        2,
        1,
        0,
        4,
        5,
        6,
      ]);
    });

    testWidgets('submits decoded and disk preload tasks with dedupe', (
      tester,
    ) async {
      final service = _RecordingPrecacheService();
      final scheduled = <ReaderImageSessionPreloadScheduled>[];
      final metrics = ReaderPerformanceMetricsCollector();
      final coordinator = ReaderImageSessionPreloadCoordinator(
        onScheduled: scheduled.add,
        performanceMetrics: metrics,
      );
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            coordinator.submitWindow(
              context: context,
              content: _content(count: 5),
              focusIndex: 2,
              scrollDirection: ContinuousImageScrollDirection.forward,
              capability: _TestCapability(),
              precacheService: service,
              expectedDisplaySize: const Size(300, 500),
            );
            coordinator.submitWindow(
              context: context,
              content: _content(count: 5),
              focusIndex: 2,
              scrollDirection: ContinuousImageScrollDirection.forward,
              capability: _TestCapability(),
              precacheService: service,
              expectedDisplaySize: const Size(300, 500),
            );
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();

      expect(service.decodedSpecs.map((spec) => spec.imageIndex), <int>[
        2,
        3,
        1,
      ]);
      expect(service.diskSpecs.map((spec) => spec.imageIndex), <int>[4, 0]);
      expect(service.displaySizes.toSet(), <Size>{const Size(300, 500)});
      expect(scheduled, hasLength(5));
      expect(scheduled.map((event) => event.readerOwnerId).toSet(), <String>{
        'reader-owner',
      });
      expect(scheduled.map((event) => event.generation).toSet(), <int>{0});
      final taskIdentities = scheduled
          .map((event) => '${event.spec.cacheKey}:${event.kind.name}')
          .toSet();
      expect(taskIdentities, hasLength(scheduled.length));
      expect(metrics.snapshot.preloadRequestCount, 10);
      expect(metrics.snapshot.preloadHitCount, 3);
      expect(metrics.snapshot.providerMismatchCount, 0);
    });

    testWidgets('submits the shared lookahead window for an adjacent owner', (
      tester,
    ) async {
      final service = _RecordingPrecacheService();
      final scheduled = <ReaderImageSessionPreloadScheduled>[];
      final coordinator = ReaderImageSessionPreloadCoordinator(
        onScheduled: scheduled.add,
      );
      final plan = ReaderAdjacentPreloadPlan(
        ownerId: 'next-episode',
        images: List<ReaderAdjacentPreloadImage>.generate(6, (index) {
          return ReaderAdjacentPreloadImage(
            itemId: 'next-episode:$index',
            imageIndex: index,
            spec: ForumImageLoadSpec(
              kind: ForumImageKind.comicReaderPage,
              url: Uri.parse('https://img.test/next-$index.jpg'),
              ownerId: 'comic-1',
              ownerType: ImageCacheOwnerType.comic,
              episodeId: 'next-episode',
              imageIndex: index,
              cacheKey: 'next-cache-$index',
              retentionClass: ImageRetentionClass.recentReader,
            ),
          );
        }),
      );

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            coordinator.submitAdjacentWindow(
              context: context,
              plan: plan,
              precacheService: service,
              expectedDisplaySize: const Size(300, 500),
            );
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();

      expect(service.decodedSpecs.map((spec) => spec.imageIndex), <int>[0, 1]);
      expect(service.diskSpecs.map((spec) => spec.imageIndex), <int>[2, 3]);
      expect(scheduled, hasLength(4));
      expect(scheduled.map((event) => event.readerOwnerId).toSet(), <String>{
        'next-episode',
      });
      expect(scheduled.map((event) => event.kind).toSet(), {
        ReaderImageSessionPreloadKind.decoded,
        ReaderImageSessionPreloadKind.disk,
      });
    });

    testWidgets('submits the shared lookahead window for an adjacent owner', (
      tester,
    ) async {
      final service = _RecordingPrecacheService();
      final scheduled = <ReaderImageSessionPreloadScheduled>[];
      final coordinator = ReaderImageSessionPreloadCoordinator(
        onScheduled: scheduled.add,
      );
      final plan = ReaderAdjacentPreloadPlan(
        ownerId: 'next-episode',
        images: List<ReaderAdjacentPreloadImage>.generate(6, (index) {
          return ReaderAdjacentPreloadImage(
            itemId: 'next-episode:$index',
            imageIndex: index,
            spec: ForumImageLoadSpec(
              kind: ForumImageKind.comicReaderPage,
              url: Uri.parse('https://img.test/next-$index.jpg'),
              ownerId: 'comic-1',
              ownerType: ImageCacheOwnerType.comic,
              episodeId: 'next-episode',
              imageIndex: index,
              cacheKey: 'next-cache-$index',
              retentionClass: ImageRetentionClass.recentReader,
            ),
          );
        }),
      );

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            coordinator.submitAdjacentWindow(
              context: context,
              plan: plan,
              precacheService: service,
              expectedDisplaySize: const Size(300, 500),
            );
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();

      expect(service.decodedSpecs.map((spec) => spec.imageIndex), <int>[0, 1]);
      expect(service.diskSpecs.map((spec) => spec.imageIndex), <int>[2, 3]);
      expect(scheduled, hasLength(4));
      expect(scheduled.map((event) => event.readerOwnerId).toSet(), <String>{
        'next-episode',
      });
      expect(scheduled.map((event) => event.kind).toSet(), {
        ReaderImageSessionPreloadKind.decoded,
        ReaderImageSessionPreloadKind.disk,
      });
    });

    testWidgets('upgrades pending disk work to decoded without stale work', (
      tester,
    ) async {
      final service = _RecordingPrecacheService();
      final coordinator = ReaderImageSessionPreloadCoordinator();
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            final content = _content(count: 5);
            coordinator.submitWindow(
              context: context,
              content: content,
              focusIndex: 0,
              scrollDirection: ContinuousImageScrollDirection.forward,
              capability: _TestCapability(),
              precacheService: service,
            );
            coordinator.submitWindow(
              context: context,
              content: content,
              focusIndex: 3,
              scrollDirection: ContinuousImageScrollDirection.forward,
              capability: _TestCapability(),
              precacheService: service,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();

      expect(
        service.diskSpecs.map((spec) => spec.imageIndex),
        isNot(contains(3)),
      );
      expect(service.decodedSpecs.map((spec) => spec.imageIndex), contains(3));
      expect(service.diskSpecs.where((spec) => spec.imageIndex == 3), isEmpty);
      expect(
        service.decodedSpecs.where((spec) => spec.imageIndex == 3),
        hasLength(1),
      );
    });

    testWidgets('marks stale results ignored after session reset', (
      tester,
    ) async {
      final decodedCompleter = Completer<ForumImagePrecacheResult>();
      final service = _RecordingPrecacheService(decodedCompleter);
      final results = <ReaderImageSessionPreloadResult>[];
      final metrics = ReaderPerformanceMetricsCollector();
      final coordinator = ReaderImageSessionPreloadCoordinator(
        onResult: results.add,
        performanceMetrics: metrics,
      );
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            coordinator.submitWindow(
              context: context,
              content: _content(count: 1),
              focusIndex: 0,
              scrollDirection: ContinuousImageScrollDirection.idle,
              capability: _TestCapability(),
              precacheService: service,
            );
            return const SizedBox.shrink();
          },
        ),
      );

      coordinator.resetSession();
      decodedCompleter.complete(const ForumImagePrecacheResult(success: true));
      await tester.pump();

      expect(results, hasLength(1));
      expect(results.single.applied, isFalse);
      expect(results.single.stale, isTrue);
      expect(metrics.snapshot.staleTaskCount, 1);
      expect(metrics.snapshot.providerMismatchCount, 0);
    });

    testWidgets('applies results to session store and writes to sink', (
      tester,
    ) async {
      final store = ReaderImageSessionStore();
      addTearDown(store.dispose);
      final sink = _RecordingPreparationSink();
      final coordinator = ReaderImageSessionPreloadCoordinator(
        sessionStore: store,
      );
      final content = _content(count: 1);
      coordinator.resetSession(
        readerOwnerId: content.ownerId,
        items: content.items,
      );
      final binding = store.bindingFor(content.items.single);
      final service = _RecordingPrecacheService();
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            coordinator.submitWindow(
              context: context,
              content: content,
              focusIndex: 0,
              scrollDirection: ContinuousImageScrollDirection.idle,
              capability: _SinkCapability(sink),
              precacheService: service,
            );
            return const SizedBox();
          },
        ),
      );
      await tester.pump();

      expect(binding.value.status, ReaderImageSessionStatus.decoded);
      expect(binding.value.localPath, '/cache/0.jpg');
      expect(sink.records, hasLength(1));
      expect(sink.records.single.itemId, content.items.single.id);
    });

    testWidgets('rapid windows stay bounded and latest seek is promoted', (
      tester,
    ) async {
      final service = _BlockingPrecacheService();
      final coordinator = ReaderImageSessionPreloadCoordinator(
        policy: const ReaderImageSessionPreloadPolicy(
          decodedRadius: 1,
          diskRadius: 3,
          maxConcurrentTasks: 2,
        ),
      );
      addTearDown(coordinator.dispose);
      final content = _content(count: 20);
      late BuildContext readerContext;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            readerContext = context;
            return const SizedBox.shrink();
          },
        ),
      );

      for (var index = 0; index < 10; index++) {
        coordinator.submitWindow(
          context: readerContext,
          content: content,
          focusIndex: index,
          scrollDirection: ContinuousImageScrollDirection.forward,
          capability: _TestCapability(),
          precacheService: service,
        );
      }
      coordinator.promoteSeekTarget(
        context: readerContext,
        content: content,
        index: 15,
        capability: _TestCapability(),
        precacheService: service,
      );
      coordinator.promoteSeekTarget(
        context: readerContext,
        content: content,
        index: 16,
        capability: _TestCapability(),
        precacheService: service,
      );

      expect(coordinator.runningTaskCount, 2);
      expect(coordinator.pendingTaskCount, lessThanOrEqualTo(8));
      expect(service.startedSpecs, hasLength(2));

      service.completeNext();
      await tester.pump();

      expect(service.startedSpecs.map((spec) => spec.imageIndex), contains(16));
      expect(
        service.startedSpecs.map((spec) => spec.imageIndex),
        isNot(contains(15)),
      );
      expect(coordinator.runningTaskCount, lessThanOrEqualTo(2));
      expect(coordinator.pendingTaskCount, lessThanOrEqualTo(7));
    });

    testWidgets('forced prepareOne retries through store and metadata sink', (
      tester,
    ) async {
      final store = ReaderImageSessionStore();
      addTearDown(store.dispose);
      final sink = _RecordingPreparationSink();
      final coordinator = ReaderImageSessionPreloadCoordinator(
        sessionStore: store,
      );
      addTearDown(coordinator.dispose);
      final content = _content(count: 1);
      coordinator.resetSession(
        readerOwnerId: content.ownerId,
        items: content.items,
      );
      final binding = store.bindingFor(content.items.single);
      final service = _SequentialPrecacheService(<ForumImagePrecacheResult>[
        const ForumImagePrecacheResult(
          success: false,
          failureReason: 'decode_failed',
        ),
        const ForumImagePrecacheResult(
          success: true,
          decoded: true,
          cacheKey: 'cache-0',
          localPath: '/cache/retried.jpg',
        ),
      ]);
      late BuildContext readerContext;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            readerContext = context;
            return const SizedBox.shrink();
          },
        ),
      );

      final first = await coordinator.prepareOne(
        context: readerContext,
        content: content,
        index: 0,
        capability: _SinkCapability(sink),
        precacheService: service,
      );
      expect(first?.result.success, isFalse);
      expect(binding.value.status, ReaderImageSessionStatus.failed);

      final retried = await coordinator.prepareOne(
        context: readerContext,
        content: content,
        index: 0,
        capability: _SinkCapability(sink),
        precacheService: service,
        force: true,
      );

      expect(retried?.result.success, isTrue);
      expect(binding.value.status, ReaderImageSessionStatus.decoded);
      expect(binding.value.localPath, '/cache/retried.jpg');
      expect(service.decodedSpecs, hasLength(2));
      expect(sink.records, hasLength(1));
      expect(sink.records.single.localPath, '/cache/retried.jpg');
    });

    testWidgets('dispose suppresses future submissions', (tester) async {
      final service = _RecordingPrecacheService();
      final coordinator = ReaderImageSessionPreloadCoordinator()..dispose();
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            coordinator.submitWindow(
              context: context,
              content: _content(count: 3),
              focusIndex: 1,
              scrollDirection: ContinuousImageScrollDirection.idle,
              capability: _TestCapability(),
              precacheService: service,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();

      expect(service.decodedSpecs, isEmpty);
      expect(service.diskSpecs, isEmpty);
    });
  });
}

ReaderContent _content({required int count}) {
  return ReaderContent(
    ownerId: 'reader-owner',
    items: List<ContinuousImageItem>.generate(count, (index) {
      return ContinuousImageItem(
        ownerId: 'reader-owner',
        id: 'reader-owner:$index',
        url: 'https://img.test/$index.jpg',
        cacheKey: 'cache-$index',
        index: index,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
      );
    }),
  );
}

class _TestCapability extends ReaderCapability {
  @override
  ReaderContent get content => _content(count: 1);

  @override
  ImageRequestHeaderBuilder? get imageHeaderBuilder => null;

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    return const ReaderTitleSpec(title: 'reader');
  }

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) {
    return const SizedBox.shrink();
  }

  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) {
    return ImageCacheRequest(
      cacheKey: item.cacheKey,
      sourceUrl: item.url,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: item.ownerId,
      role: ImageCacheRole.threadInline,
      imageIndex: item.index,
      retentionClass: ImageRetentionClass.recentReader,
    );
  }

  @override
  ForumImageLoadSpec? imageLoadSpecFor(ContinuousImageItem item) {
    return ForumImageLoadSpec(
      kind: ForumImageKind.threadInline,
      url: Uri.parse(item.url),
      ownerId: item.ownerId,
      ownerType: ImageCacheOwnerType.thread,
      imageIndex: item.index,
      cacheKey: item.cacheKey,
      retentionClass: ImageRetentionClass.recentReader,
    );
  }
}

class _SinkCapability extends _TestCapability {
  _SinkCapability(this.sink);

  final ReaderImagePreparationSink sink;

  @override
  ReaderImagePreparationSink get imagePreparationSink => sink;
}

class _RecordingPreparationSink implements ReaderImagePreparationSink {
  final records = <ReaderImagePreparationRecord>[];

  @override
  Future<void> record(ReaderImagePreparationRecord record) async {
    records.add(record);
  }
}

class _RecordingPrecacheService implements ForumImagePrecacheService {
  _RecordingPrecacheService([this.decodedCompleter]);

  final Completer<ForumImagePrecacheResult>? decodedCompleter;
  final decodedSpecs = <ForumImageLoadSpec>[];
  final diskSpecs = <ForumImageLoadSpec>[];
  final displaySizes = <Size?>[];

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async {
    diskSpecs.add(spec);
    return ForumImagePrecacheResult(
      success: true,
      cacheKey: spec.cacheKey,
      localPath: '/cache/${spec.imageIndex}.jpg',
    );
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) {
    decodedSpecs.add(spec);
    displaySizes.add(expectedDisplaySize);
    final completer = decodedCompleter;
    if (completer != null) {
      return completer.future;
    }
    return Future<ForumImagePrecacheResult>.value(
      ForumImagePrecacheResult(
        success: true,
        decoded: true,
        cacheKey: spec.cacheKey,
        localPath: '/cache/${spec.imageIndex}.jpg',
      ),
    );
  }
}

class _BlockingPrecacheService implements ForumImagePrecacheService {
  final startedSpecs = <ForumImageLoadSpec>[];
  final _completers = <Completer<ForumImagePrecacheResult>>[];

  void completeNext() {
    final completer = _completers.firstWhere((item) => !item.isCompleted);
    completer.complete(const ForumImagePrecacheResult(success: true));
  }

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(ForumImageLoadSpec spec) {
    return _start(spec);
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) {
    return _start(spec);
  }

  Future<ForumImagePrecacheResult> _start(ForumImageLoadSpec spec) {
    startedSpecs.add(spec);
    final completer = Completer<ForumImagePrecacheResult>();
    _completers.add(completer);
    return completer.future;
  }
}

class _SequentialPrecacheService implements ForumImagePrecacheService {
  _SequentialPrecacheService(this.results);

  final List<ForumImagePrecacheResult> results;
  final decodedSpecs = <ForumImageLoadSpec>[];

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async {
    throw StateError('Unexpected disk-only request');
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    decodedSpecs.add(spec);
    return results.removeAt(0);
  }
}

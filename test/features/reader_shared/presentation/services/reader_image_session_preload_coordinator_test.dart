import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_capability.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_preload_coordinator.dart';

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
      final coordinator = ReaderImageSessionPreloadCoordinator();
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
    });

    testWidgets('upgrades disk-only scheduled image to decoded when focused', (
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

      expect(service.diskSpecs.map((spec) => spec.imageIndex), contains(3));
      expect(service.decodedSpecs.map((spec) => spec.imageIndex), contains(3));
      expect(
        service.diskSpecs.where((spec) => spec.imageIndex == 3),
        hasLength(1),
      );
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
      final coordinator = ReaderImageSessionPreloadCoordinator(
        onResult: results.add,
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

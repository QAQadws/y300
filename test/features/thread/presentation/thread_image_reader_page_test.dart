import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/thread_image_reader_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('ThreadImageReaderPage renders continuous image list', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: MaterialApp(home: ThreadImageReaderPage(request: _request())),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ThreadImageReaderPage), findsOneWidget);
    expect(find.byType(ContinuousImageReaderView), findsOneWidget);
    expect(find.byKey(const Key('thread-image-reader-list')), findsOneWidget);
    expect(find.byType(CachedLibraryImage), findsWidgets);
  });

  testWidgets('ThreadImageReaderPage exposes general reading chrome only', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: MaterialApp(home: ThreadImageReaderPage(request: _request())),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 打开 overlay 菜单（点击中央 tap 区）。
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('shared-reader-center-tap-zone'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump(const Duration(milliseconds: 300));

    // 通用阅读能力：滑块 / 页码标签 / 显示设置入口。
    expect(
      find.byKey(const Key('shared-reader-progress-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-current-label')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-display')),
      findsOneWidget,
    );

    // detail 强相关项不应出现：书签 / 原帖 / 章节 / 缓存 / 翻章。
    expect(
      find.byKey(const Key('shared-reader-top-action-bookmark')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shared-reader-top-action-open-thread')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-cache')),
      findsNothing,
    );
    // 翻章按钮属于共享进度条 chrome，帖子图片阅读器没有"上一话/下一话"语义，
    // 因此它们存在但被禁用（onPressed == null）。
    final prevButton = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-prev-button')),
    );
    final nextButton = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-next-button')),
    );
    expect(prevButton.onPressed, isNull);
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('ThreadImageReaderPage preloads reader session images', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    final precacheService = _RecordingForumImagePrecacheService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(cacheService),
          forumImagePrecacheServiceProvider.overrideWithValue(precacheService),
        ],
        child: MaterialApp(home: ThreadImageReaderPage(request: _request())),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(precacheService.decodedSpecs, isNotEmpty);
    expect(
      precacheService.decodedSpecs.map((spec) => spec.kind).toSet(),
      <ForumImageKind>{ForumImageKind.threadInline},
    );
    expect(
      precacheService.decodedSpecs.map((spec) => spec.retentionClass).toSet(),
      <ImageRetentionClass>{ImageRetentionClass.recentReader},
    );
    expect(precacheService.decodedSpecs.first.ownerId, 'thread:100:post:p1');
    expect(precacheService.decodedSpecs.first.cacheKey, 'thread/inline/page-1');
  });
}

ThreadImageOpenRequest _request() {
  final items = <ContinuousImageItem>[
    const ContinuousImageItem(
      ownerId: 'thread:100:post:p1',
      id: 'thread:100:post:p1:0:thread/inline/page-1',
      url: 'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
      cacheKey: 'thread/inline/page-1',
      index: 0,
      sourceKind: ContinuousImageSourceKind.threadImageReader,
      knownWidth: 200,
      knownHeight: 120,
      knownDimensionSource: ContinuousImageDimensionSource.html,
      fallbackAspectRatio: 0.7,
      spacingAfter: 10,
    ),
    const ContinuousImageItem(
      ownerId: 'thread:100:post:p1',
      id: 'thread:100:post:p1:1:thread/inline/page-2',
      url: 'https://bbs.yamibo.com/data/attachment/forum/page-2.jpg',
      cacheKey: 'thread/inline/page-2',
      index: 1,
      sourceKind: ContinuousImageSourceKind.threadImageReader,
      knownWidth: 200,
      knownHeight: 120,
      knownDimensionSource: ContinuousImageDimensionSource.html,
      fallbackAspectRatio: 0.7,
      spacingAfter: 10,
    ),
  ];
  return ThreadImageOpenRequest(
    tid: '100',
    pid: 'p1',
    postNumber: 1,
    referer: 'https://bbs.yamibo.com/thread-100-1-1.html',
    group: const ThreadPostImageGroup(
      tid: '100',
      pid: 'p1',
      postNumber: 1,
      entries: <ThreadPostImageEntry>[],
    ),
    initialIndex: 0,
    continuousImages: items,
  );
}

class _RecordingImageCacheService implements ImageCacheService {
  final requests = <ImageCacheRequest>[];
  final getCachedKeys = <String>[];

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    requests.add(request);
    return CachedImageResult(success: true, cacheKey: request.cacheKey);
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    getCachedKeys.add(cacheKey);
    return null;
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
    );
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

class _RecordingForumImagePrecacheService implements ForumImagePrecacheService {
  final decodedSpecs = <ForumImageLoadSpec>[];
  final diskSpecs = <ForumImageLoadSpec>[];

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
  }) async {
    decodedSpecs.add(spec);
    return ForumImagePrecacheResult(
      success: true,
      decoded: true,
      cacheKey: spec.cacheKey,
      localPath: '/cache/${spec.imageIndex}.jpg',
    );
  }
}

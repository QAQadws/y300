import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_reader_view.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_capability.dart';

void main() {
  group('ReaderCapability defaults', () {
    final context = ReaderEngineContext(
      currentIndex: 0,
      totalCount: 1,
      mode: ContinuousImageReaderMode.vertical,
      actions: _NoopEngineActions(),
    );

    test('minimal capability exposes no extra chrome', () {
      final capability = _MinimalCapability();
      expect(capability.topActions(context), isEmpty);
      expect(capability.bottomActions(context), isEmpty);
      expect(capability.chapterNav(context), isNull);
      expect(capability.verticalTrailingBuilder(context), isNull);
    });

    test('lifecycle hooks are no-ops by default', () async {
      final capability = _MinimalCapability();
      capability.onImageVisible(3);
      capability.onScrollProgress(index: 3, offset: 120);
      await capability.onExit();
      // 无异常即通过：默认实现允许帖子图片阅读器只关心内容与缓存请求。
      expect(capability.content.length, 1);
    });

    test('default imageLoadSpecFor maps cache request into load spec', () {
      final capability = _MinimalCapability();
      final item = capability.content.items.single;
      final spec = capability.imageLoadSpecFor(item);

      expect(spec, isNotNull);
      expect(spec!.kind, ForumImageKind.threadInline);
      expect(spec.url.toString(), item.url);
      expect(spec.ownerId, item.ownerId);
      expect(spec.ownerType, ImageCacheOwnerType.thread);
      expect(spec.imageIndex, item.index);
      expect(spec.cacheKey, item.cacheKey);
    });
  });
}

class _MinimalCapability extends ReaderCapability {
  @override
  ReaderContent get content => ReaderContent(
    ownerId: 'owner',
    items: const <ContinuousImageItem>[
      ContinuousImageItem(
        ownerId: 'owner',
        id: 'owner:0:key',
        url: 'https://example.com/0.jpg',
        cacheKey: 'key',
        index: 0,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
      ),
    ],
  );

  @override
  String? get imageReferer => null;

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    return const ReaderTitleSpec(title: '图片阅读');
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
    );
  }
}

class _NoopEngineActions implements ReaderEngineActions {
  @override
  void openDisplaySettings() {}

  @override
  void cycleReaderMode() {}

  @override
  void openModeSheet() {}

  @override
  void exportCurrentImage() {}
}

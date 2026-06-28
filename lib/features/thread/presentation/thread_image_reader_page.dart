import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';

class ThreadImageReaderPage extends StatelessWidget {
  const ThreadImageReaderPage({
    super.key,
    required this.request,
    this.imageHeaderBuilder,
    this.mode = ContinuousImageReaderMode.vertical,
  });

  final ThreadImageOpenRequest request;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ContinuousImageReaderMode mode;

  @override
  Widget build(BuildContext context) {
    return ContinuousImageReaderRoute(
      title: '图片阅读',
      items: request.continuousImages,
      initialIndex: request.initialIndex,
      imageHeaderBuilder: imageHeaderBuilder,
      mode: mode,
      listKey: const Key('thread-image-reader-list'),
      pageKey: const Key('thread-image-reader-page-view'),
      requestBuilder: (item) => ImageCacheRequest(
        cacheKey: item.cacheKey,
        sourceUrl: item.url,
        ownerType: ImageCacheOwnerType.thread,
        ownerId: item.ownerId,
        role: ImageCacheRole.threadInline,
        imageIndex: item.index,
        retentionClass: ImageRetentionClass.recentReader,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_capability.dart';

/// 帖子图片阅读器页面。
///
/// 基于共享 [ImageReaderEngine]，通过 [ThreadImageReaderCapability] 注入帖子图片
/// 专属能力（内容来源、缓存请求、图片渲染），获得与漫画同源的阅读体验（模式切换 /
/// 缩放 / 滑块 / 页码 / 显示设置），但不含书签 / 下载 / 章节 / 上一话下一话等 detail
/// 强相关项。
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
    return ImageReaderEngine(
      key: const Key('thread-image-reader-engine'),
      listKey: const Key('thread-image-reader-list'),
      pageKey: const Key('thread-image-reader-page-view'),
      slotKeyPrefix: 'thread-image-reader-image-slot',
      capability: ThreadImageReaderCapability(
        request: request,
        imageHeaderBuilder: imageHeaderBuilder,
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

/// 阶段 0 基线：复现"视口上方图片缓存比例异步回填导致高度突变"。
///
/// 该测试刻意构造一张"矮图"位于视口上方、其余为占位高图的场景。当
/// [ThreadPostResourceLayoutPolicy.adaptiveBlockImagesForReading] 下
/// `_loadCachedAspectRatio` 绕过 above-viewport 保护时，上方图片高度会从
/// fallback(0.7) 突然收缩到缓存真实比例(2.0)，使其下方内容整体上移——也就是
/// 用户感知到的"上滑回溯"。
///
/// 阶段 1 修复后，应保证：视口上方图片在异步缓存比例到达时不改变已布局高度。
void main() {
  testWidgets(
    'baseline: above-viewport block image keeps stable height when cached '
    'ratio arrives (adaptive policy)',
    (tester) async {
      // 缓存里存了真实比例 2.0（很矮），与 fallback 0.7（很高）差异巨大。
      final cacheService = _SizedImageCacheService(<String, CachedImageResult>{
        'thread-inline-top': const CachedImageResult(
          success: true,
          cacheKey: 'thread-inline-top',
          width: 1000,
          height: 500,
        ),
      });

      const topImage = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/top.jpg',
        rawUrl: 'data/attachment/forum/top.jpg',
        index: 0,
      );

      final probeKey = GlobalKey();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(cacheService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 350,
                  height: 400,
                  child: SingleChildScrollView(
                    // 初始 offset 让顶部图片完全滚出视口（在视口上方）。
                    controller: ScrollController(initialScrollOffset: 700),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(
                          width: 350,
                          child: ThreadPostImageBlockView(
                            document: ThreadPostBodyDocument(
                              blocks: <ThreadPostBodyBlock>[topImage],
                            ),
                            image: topImage,
                            images: <ThreadPostImageBlock>[topImage],
                            resourceLayoutPolicy: ThreadPostResourceLayoutPolicy
                                .adaptiveBlockImagesForReading,
                            blockImageCacheRequestBuilder: _topImageRequest,
                          ),
                        ),
                        // 视口内的探针，用于测量"上方高度变化导致的位移"。
                        SizedBox(key: probeKey, height: 900),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // 首帧（pumpWidget 已完成一帧）：异步缓存尚未返回（被 gate 阻塞），上方
      // 图片用 fallback 0.7，高度 = 350/0.7 ≈ 500。此刻测量探针位置作为基准。
      final probeTopBefore = tester.getTopLeft(find.byKey(probeKey)).dy;

      // 放行 gate：缓存比例(2.0)到达并 setState，上方图片高度收缩到 350/2.0=175。
      cacheService.release();
      await tester.pump();
      await tester.pump();

      final probeTopAfter = tester.getTopLeft(find.byKey(probeKey)).dy;

      // 期望：视口上方图片高度不应因异步缓存比例变化而改变，探针不位移。
      // 阶段 1 修复后：_loadCachedAspectRatio 补齐了 above-viewport 保护。
      expect(
        probeTopAfter,
        closeTo(probeTopBefore, 1.0),
        reason: '视口上方图片缓存比例异步到达时不应改变已布局高度（防止上滑回溯）',
      );
    },
  );

  testWidgets(
    'within-viewport block image still applies cached ratio (no over-correction)',
    (tester) async {
      // 同样的缓存比例 2.0，但图片就在视口内：此时应当应用真实比例（稳定优先不等于
      // 永不修正），验证 above-viewport 保护没有误伤视口内图片。
      final cacheService = _SizedImageCacheService(<String, CachedImageResult>{
        'thread-inline-top': const CachedImageResult(
          success: true,
          cacheKey: 'thread-inline-top',
          width: 1000,
          height: 500,
        ),
      });
      const topImage = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/data/attachment/forum/top.jpg',
        rawUrl: 'data/attachment/forum/top.jpg',
        index: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(cacheService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 350,
                  // 视口比图片矮：图片(高度 500 @0.7)横跨视口，明确属于"视口内"。
                  height: 300,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: const [
                        ThreadPostImageBlockView(
                          document: ThreadPostBodyDocument(
                            blocks: <ThreadPostBodyBlock>[topImage],
                          ),
                          image: topImage,
                          images: <ThreadPostImageBlock>[topImage],
                          resourceLayoutPolicy: ThreadPostResourceLayoutPolicy
                              .adaptiveBlockImagesForReading,
                          blockImageCacheRequestBuilder: _topImageRequest,
                        ),
                        SizedBox(height: 1200),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      cacheService.release();
      await tester.pump();
      await tester.pump();

      final size = tester.getSize(find.byType(ThreadPostImageBlockView));
      expect(size.width, 350);
      expect(size.width / size.height, closeTo(2.0, 0.01));
    },
  );
}

ImageCacheRequest _topImageRequest(ThreadPostImageBlock image) {
  return const ImageCacheRequest(
    cacheKey: 'thread-inline-top',
    sourceUrl: 'https://bbs.yamibo.com/data/attachment/forum/top.jpg',
    ownerType: ImageCacheOwnerType.thread,
    ownerId: 'tid-1',
    role: ImageCacheRole.threadInline,
  );
}

class _SizedImageCacheService implements ImageCacheService {
  _SizedImageCacheService(this.results);

  final Map<String, CachedImageResult> results;
  final Completer<void> _gate = Completer<void>();

  /// 放行 getCached：让测试精确控制"缓存比例何时回填"，从而分离首帧基准与
  /// 异步回填后的位移测量。
  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    await _gate.future;
    return results[cacheKey];
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
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

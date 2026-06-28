import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';

/// 只读、同步的图片真实尺寸来源。
///
/// 由表现层在 plan 装配前用持久化缓存预热，使 [ThreadPostResourceLayoutHintResolver]
/// 在 HTML 未携带宽高时仍能得到可信比例，从而首帧即定高、避免滚动中异步改高。
/// 领域层只依赖这个抽象，不依赖任何缓存实现或 Flutter。
abstract interface class ThreadPostImageDimensionLookup {
  /// 同一份尺寸数据的指纹；并入 resolver 签名以驱动 render plan 缓存失效。
  String get signature;

  /// 按 [ThreadPostResourceLayoutHints.blockImageKey] 查询块级图片真实尺寸。
  ThreadPostResourceDimension? blockImageDimension(ThreadPostImageBlock image);

  /// 按 [ThreadPostResourceLayoutHints.inlineImageKey] 查询行内图片真实尺寸。
  ThreadPostResourceDimension? inlineImageDimension(
    ThreadPostInlineImage image,
  );
}

class ThreadPostResourceLayoutHintResolver {
  const ThreadPostResourceLayoutHintResolver({
    this.defaultBlockImageAspectRatio = 0.7,
    this.lockForCurrentBuild = false,
    this.lockTrustedDimensions = false,
    this.dimensionLookup,
  }) : assert(defaultBlockImageAspectRatio > 0);

  final double defaultBlockImageAspectRatio;
  final bool lockForCurrentBuild;

  /// 当 hint 来自可信尺寸（HTML 或持久化缓存）时锁定首帧高度。
  ///
  /// 与 [lockForCurrentBuild]（锁定全部，含默认占位）不同，本开关只锁可信尺寸，
  /// 让无尺寸图片仍可在受 above-viewport 保护下做一次 decode 回填。
  final bool lockTrustedDimensions;

  /// 可选的持久化尺寸来源；为空时退化为"仅用 HTML 宽高"的既有行为。
  final ThreadPostImageDimensionLookup? dimensionLookup;

  /// Legacy string fingerprint — kept for backward compatibility.
  String get signature {
    return [
      defaultBlockImageAspectRatio.toStringAsFixed(6),
      lockForCurrentBuild,
      lockTrustedDimensions,
      dimensionLookup?.signature ?? 'noLookup',
    ].join('|');
  }

  @override
  bool operator ==(Object other) {
    if (other is! ThreadPostResourceLayoutHintResolver) return false;
    return defaultBlockImageAspectRatio == other.defaultBlockImageAspectRatio &&
        lockForCurrentBuild == other.lockForCurrentBuild &&
        lockTrustedDimensions == other.lockTrustedDimensions &&
        (dimensionLookup?.signature ?? 'noLookup') ==
            (other.dimensionLookup?.signature ?? 'noLookup');
  }

  @override
  int get hashCode => Object.hash(
    defaultBlockImageAspectRatio,
    lockForCurrentBuild,
    lockTrustedDimensions,
    dimensionLookup?.signature ?? 'noLookup',
  );

  ThreadPostResourceLayoutHints resolve(ThreadPostBodyDocument document) {
    final blockImages = <String, ThreadPostBlockImageLayoutHint>{};
    final inlineImages = <String, ThreadPostInlineImageLayoutHint>{};

    void collect(List<ThreadPostBodyBlock> blocks) {
      for (final block in blocks) {
        if (block is ThreadPostImageBlock) {
          final key = ThreadPostResourceLayoutHints.blockImageKey(block);
          blockImages[key] = _blockImageHint(block);
        } else if (block is ThreadPostTextBlock) {
          for (final run in block.runs) {
            final image = run.inlineImage;
            if (image == null) {
              continue;
            }
            final hint = _inlineImageHint(image);
            if (hint == null) {
              continue;
            }
            final key = ThreadPostResourceLayoutHints.inlineImageKey(image);
            inlineImages[key] = hint;
          }
        } else if (block is ThreadPostQuoteBlock) {
          collect(block.blocks);
        }
      }
    }

    collect(document.blocks);
    return ThreadPostResourceLayoutHints(
      blockImages: Map<String, ThreadPostBlockImageLayoutHint>.unmodifiable(
        blockImages,
      ),
      inlineImages: Map<String, ThreadPostInlineImageLayoutHint>.unmodifiable(
        inlineImages,
      ),
    );
  }

  ThreadPostBlockImageLayoutHint _blockImageHint(ThreadPostImageBlock image) {
    // 优先级：HTML 宽高 → 持久化缓存尺寸 → 内容默认。前两者为"可信尺寸"，
    // 在 lockTrustedDimensions 模式下锁定首帧高度；默认值不锁，留给受 above-viewport
    // 保护的一次性 decode 回填。
    final htmlDimension = _dimension(image.originalWidth, image.originalHeight);
    if (htmlDimension != null) {
      return _trustedBlockHint(
        htmlDimension.aspectRatio,
        ThreadPostResourceLayoutHintSource.htmlAttribute,
      );
    }
    final cachedDimension = dimensionLookup?.blockImageDimension(image);
    if (cachedDimension != null && cachedDimension.isValid) {
      return _trustedBlockHint(
        cachedDimension.aspectRatio,
        ThreadPostResourceLayoutHintSource.cachedDimension,
      );
    }
    return ThreadPostBlockImageLayoutHint(
      aspectRatio: defaultBlockImageAspectRatio,
      source: ThreadPostResourceLayoutHintSource.contentDefault,
      lockForCurrentBuild: lockForCurrentBuild,
    );
  }

  ThreadPostBlockImageLayoutHint _trustedBlockHint(
    double aspectRatio,
    ThreadPostResourceLayoutHintSource source,
  ) {
    return ThreadPostBlockImageLayoutHint(
      aspectRatio: aspectRatio,
      source: source,
      lockForCurrentBuild: lockForCurrentBuild || lockTrustedDimensions,
    );
  }

  ThreadPostInlineImageLayoutHint? _inlineImageHint(
    ThreadPostInlineImage image,
  ) {
    final htmlDimension = _dimension(image.originalWidth, image.originalHeight);
    if (htmlDimension != null) {
      return _trustedInlineHint(
        htmlDimension,
        ThreadPostResourceLayoutHintSource.htmlAttribute,
      );
    }
    final cachedDimension = dimensionLookup?.inlineImageDimension(image);
    if (cachedDimension != null && cachedDimension.isValid) {
      return _trustedInlineHint(
        cachedDimension,
        ThreadPostResourceLayoutHintSource.cachedDimension,
      );
    }
    return null;
  }

  ThreadPostInlineImageLayoutHint _trustedInlineHint(
    ThreadPostResourceDimension dimension,
    ThreadPostResourceLayoutHintSource source,
  ) {
    return ThreadPostInlineImageLayoutHint(
      width: dimension.width,
      height: dimension.height,
      source: source,
      lockForCurrentBuild: lockForCurrentBuild || lockTrustedDimensions,
    );
  }

  ThreadPostResourceDimension? _dimension(double? width, double? height) {
    if (width == null || height == null) {
      return null;
    }
    final dimension = ThreadPostResourceDimension(width: width, height: height);
    return dimension.isValid ? dimension : null;
  }
}

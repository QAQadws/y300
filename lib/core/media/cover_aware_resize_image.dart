import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 缓存 key：组合内层 provider 的 key 与目标显示框尺寸。
///
/// 公开以满足 `ImageProvider<T>` 对 key 类型的可见性要求（与 SDK 的
/// `ResizeImageKey` 同理）；外部不应自行构造，仅由 [CoverAwareResizeImage] 使用。
@immutable
class CoverResizeKey {
  const CoverResizeKey(this.providerKey, this.boxWidth, this.boxHeight);

  final Object providerKey;
  final int boxWidth;
  final int boxHeight;

  @override
  bool operator ==(Object other) {
    return other is CoverResizeKey &&
        other.providerKey == providerKey &&
        other.boxWidth == boxWidth &&
        other.boxHeight == boxHeight;
  }

  @override
  int get hashCode => Object.hash(providerKey, boxWidth, boxHeight);
}

/// 面向 `BoxFit.cover` 的解码降采样 provider。
///
/// 背景：[ResizeImage] 只有 `fit`（contain）/`exact` 两种策略，都按“缩进框内”
/// 处理。但封面用的是 `cover`（填满后裁剪），其缩放约束是**两个方向取较大者**。
/// 若仍按 contain 思路只约束单边，横长竖短的图在竖瓦片里会被放大解码后再上采样，
/// 导致明显模糊（每行本数越多、瓦片越窄越明显）。
///
/// 本 provider 借助 `instantiateImageCodecWithSize` 的 `getTargetSize` 回调拿到
/// **原图真实尺寸**，按 cover 缩放因子 `max(boxW/iw, boxH/ih)` 计算解码尺寸，
/// 保证解码图在宽、高两个方向都 ≥ 显示框（再裁剪），既清晰又不浪费内存。
/// 仅对 cover 场景使用；contain/列表仍用普通的宽度降采样策略。
class CoverAwareResizeImage extends ImageProvider<CoverResizeKey> {
  CoverAwareResizeImage(
    this.imageProvider, {
    required this.boxWidth,
    required this.boxHeight,
  });

  final ImageProvider imageProvider;

  /// 显示框的物理像素尺寸（已含 devicePixelRatio）。
  final int boxWidth;
  final int boxHeight;

  /// 便捷构造：显示框为逻辑尺寸时，传入 devicePixelRatio 自动换算为物理像素。
  static ImageProvider resizeIfNeeded({
    required ImageProvider provider,
    required double? logicalWidth,
    required double? logicalHeight,
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    final w =
        (logicalWidth != null && logicalWidth.isFinite && logicalWidth > 0)
        ? (logicalWidth * dpr).round()
        : null;
    final h =
        (logicalHeight != null && logicalHeight.isFinite && logicalHeight > 0)
        ? (logicalHeight * dpr).round()
        : null;
    // 两边都未知时无法计算 cover 目标，退回原 provider（不降采样，保清晰）。
    if (w == null || h == null) {
      return provider;
    }
    return CoverAwareResizeImage(provider, boxWidth: w, boxHeight: h);
  }

  /// 给定原图真实尺寸，计算 cover 场景下的解码目标像素（不上采样）。
  ///
  /// 提取为纯函数以便单测：解码图需在宽、高两个方向都 ≥ 显示框（cover 缩放因子
  /// 取两方向较大者）；原图比所需还小时按原尺寸（`scale` 封顶 1）。
  @visibleForTesting
  ui.TargetImageSize computeTargetSize(
    int intrinsicWidth,
    int intrinsicHeight,
  ) {
    if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
      return const ui.TargetImageSize();
    }
    final coverScale = math.max(
      boxWidth / intrinsicWidth,
      boxHeight / intrinsicHeight,
    );
    final scale = math.min(coverScale, 1.0);
    final targetWidth = math.max(1, (intrinsicWidth * scale).ceil());
    final targetHeight = math.max(1, (intrinsicHeight * scale).ceil());
    return ui.TargetImageSize(width: targetWidth, height: targetHeight);
  }

  @override
  ImageStreamCompleter loadImage(
    CoverResizeKey key,
    ImageDecoderCallback decode,
  ) {
    Future<ui.Codec> decodeCover(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) {
      assert(
        getTargetSize == null,
        'CoverAwareResizeImage cannot be composed with another provider that '
        'applies getTargetSize.',
      );
      return decode(
        buffer,
        getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
          return computeTargetSize(intrinsicWidth, intrinsicHeight);
        },
      );
    }

    final completer = imageProvider.loadImage(key.providerKey, decodeCover);
    if (!kReleaseMode) {
      completer.debugLabel =
          '${completer.debugLabel} - CoverResized($boxWidth×$boxHeight)';
    }
    return completer;
  }

  @override
  Future<CoverResizeKey> obtainKey(ImageConfiguration configuration) {
    Completer<CoverResizeKey>? completer;
    SynchronousFuture<CoverResizeKey>? result;
    imageProvider.obtainKey(configuration).then((Object key) {
      if (completer == null) {
        result = SynchronousFuture<CoverResizeKey>(
          CoverResizeKey(key, boxWidth, boxHeight),
        );
      } else {
        completer.complete(CoverResizeKey(key, boxWidth, boxHeight));
      }
    });
    if (result != null) {
      return result!;
    }
    completer = Completer<CoverResizeKey>();
    return completer.future;
  }

  @override
  bool operator ==(Object other) {
    return other is CoverAwareResizeImage &&
        other.imageProvider == imageProvider &&
        other.boxWidth == boxWidth &&
        other.boxHeight == boxHeight;
  }

  @override
  int get hashCode => Object.hash(imageProvider, boxWidth, boxHeight);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'CoverAwareResizeImage')}($boxWidth×$boxHeight)';
}

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 封面焦点（归一化坐标）。
///
/// 用于自定义封面的“焦点选区”：宽幅图的中部未必是合适区域，焦点让用户在
/// **不裁剪原图**的前提下指定 `BoxFit.cover` 的对齐点。坐标系与 [Alignment]
/// 一致——`x`/`y` 取值 [-1, 1]，`(-1,-1)` 为左上、`(0,0)` 为居中、`(1,1)` 为右下。
///
/// 这是一个值对象（Value Object）：不可变、按值相等，便于在模型/控件间传递。
@immutable
class CoverFocalPoint {
  const CoverFocalPoint(this.x, this.y);

  /// 居中（等价于默认的 [Alignment.center]）。
  static const CoverFocalPoint center = CoverFocalPoint(0, 0);

  final double x;
  final double y;

  /// 从持久化的可空坐标构造；任一维度为空都视为“未设置”，返回 null。
  ///
  /// 这样调用方可用 `?? Alignment.center` 自然回退到居中，无需散落空判断。
  static CoverFocalPoint? fromNullable(double? x, double? y) {
    if (x == null || y == null) return null;
    return CoverFocalPoint(x, y).clamped();
  }

  /// 夹紧到合法范围 [-1, 1]，防御越界输入。
  CoverFocalPoint clamped() {
    return CoverFocalPoint(
      x.clamp(-1.0, 1.0).toDouble(),
      y.clamp(-1.0, 1.0).toDouble(),
    );
  }

  /// 映射为 Flutter 的 [Alignment]，直接喂给 `Image`/`DecorationImage` 的
  /// `alignment` 参数即可在 `BoxFit.cover` 下生效。
  Alignment toAlignment() => Alignment(x, y);

  @override
  bool operator ==(Object other) =>
      other is CoverFocalPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'CoverFocalPoint($x, $y)';
}

/// 将持久化的可空焦点坐标解析为可直接使用的 [Alignment]，未设置时回退居中。
Alignment coverAlignmentFromFocus(double? focusX, double? focusY) {
  return CoverFocalPoint.fromNullable(focusX, focusY)?.toAlignment() ??
      Alignment.center;
}

import 'package:flutter/material.dart';

import 'package:y300/core/media/cover_crop_geometry.dart';
import 'package:y300/core/media/cover_focal_point.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 封面焦点选区对话框结果。
typedef CoverFocalPointResult = CoverFocalPoint;

/// 默认封面宽高比（宽/高）。与书架网格瓦片一致（2:3）。
const double kCoverFocalAspectRatio = 2 / 3;

/// 封面焦点选区器：在完整原图上叠加一个**封面宽高比**的固定尺寸预选框，
/// 用户拖动选框（或图片）来指定 `BoxFit.cover` 的焦点，**不裁剪原图**。
///
/// 设计：
/// - 原图按 `contain` 完整展示，保证用户能看到全图，再决定取景区域。
/// - 选框尺寸恒定（封面比例下能放进原图的最大矩形），只能在原图内平移。
/// - 输出归一化焦点 [-1,1]，由调用方持久化并喂给展示控件的 `alignment`。
///
/// 几何换算全部委托给纯函数 [CoverCropGeometry]，本控件只负责手势与绘制。
class CoverFocalPointPicker extends StatefulWidget {
  const CoverFocalPointPicker({
    super.key,
    required this.image,
    this.initialFocus,
    this.aspectRatio = kCoverFocalAspectRatio,
    this.title,
  });

  final ImageProvider image;
  final CoverFocalPoint? initialFocus;
  final double aspectRatio;
  final String? title;

  /// 以模态对话框形式打开，返回选定焦点；取消返回 null。
  static Future<CoverFocalPoint?> show(
    BuildContext context, {
    required ImageProvider image,
    CoverFocalPoint? initialFocus,
    double aspectRatio = kCoverFocalAspectRatio,
    String? title,
  }) {
    return showDialog<CoverFocalPoint>(
      context: context,
      builder: (_) => CoverFocalPointPicker(
        image: image,
        initialFocus: initialFocus,
        aspectRatio: aspectRatio,
        title: title,
      ),
    );
  }

  @override
  State<CoverFocalPointPicker> createState() => _CoverFocalPointPickerState();
}

class _CoverFocalPointPickerState extends State<CoverFocalPointPicker> {
  Size? _imageSize;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// 当前焦点（归一化）。
  CoverFocalPoint _focus = CoverFocalPoint.center;

  /// 图片是否加载失败（损坏/缺失）。失败时不再无限转圈，给出可关闭的提示。
  bool _imageFailed = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.initialFocus?.clamped() ?? CoverFocalPoint.center;
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant CoverFocalPointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _imageSize = null;
      _resolveImage();
    }
  }

  void _resolveImage() {
    _detachStream();
    _imageFailed = false;
    final stream = widget.image.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, _) {
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        if (mounted) {
          setState(() => _imageSize = size);
        }
      },
      onError: (error, stackTrace) {
        if (mounted) {
          setState(() => _imageFailed = true);
        }
      },
    );
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  void _detachStream() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detachStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title ?? l10n.libraryCoverFocalTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.libraryCoverFocalHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Flexible(child: _buildStage()),
              const SizedBox(height: 12),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    if (_imageFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(AppLocalizations.of(context).libraryCoverImageLoadFailed),
        ),
      );
    }
    final imageSize = _imageSize;
    if (imageSize == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 原图按 contain 适配到舞台：求展示缩放与展示矩形。
        final displayScale = _containScale(imageSize, constraints.biggest);
        final displaySize = imageSize * displayScale;
        return Center(
          child: SizedBox(
            width: displaySize.width,
            height: displaySize.height,
            child: _CropOverlay(
              image: widget.image,
              imageSize: imageSize,
              displaySize: displaySize,
              aspectRatio: widget.aspectRatio,
              focus: _focus,
              onFocusChanged: (focus) => setState(() => _focus = focus),
            ),
          ),
        );
      },
    );
  }

  double _containScale(Size content, Size box) {
    if (content.width <= 0 || content.height <= 0) return 1;
    final scaleW = box.width / content.width;
    final scaleH = box.height / content.height;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    return scale.isFinite && scale > 0 ? scale : 1;
  }

  Widget _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => setState(() => _focus = CoverFocalPoint.center),
          child: Text(l10n.libraryCoverCenter),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_focus),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}

/// 叠加在展示图上的可拖动裁剪框。坐标在“展示空间”内运算，焦点用原图空间换算。
class _CropOverlay extends StatelessWidget {
  const _CropOverlay({
    required this.image,
    required this.imageSize,
    required this.displaySize,
    required this.aspectRatio,
    required this.focus,
    required this.onFocusChanged,
  });

  final ImageProvider image;
  final Size imageSize;
  final Size displaySize;
  final double aspectRatio;
  final CoverFocalPoint focus;
  final ValueChanged<CoverFocalPoint> onFocusChanged;

  @override
  Widget build(BuildContext context) {
    // 选框在原图空间的尺寸，再按展示缩放换算到展示空间。
    final cropImageSize = CoverCropGeometry.cropSizeFor(imageSize, aspectRatio);
    final scaleX = displaySize.width / imageSize.width;
    final scaleY = displaySize.height / imageSize.height;
    final cropDisplaySize = Size(
      cropImageSize.width * scaleX,
      cropImageSize.height * scaleY,
    );
    final cropImageTopLeft = CoverCropGeometry.cropTopLeftFromFocus(
      imageSize: imageSize,
      cropSize: cropImageSize,
      focus: focus,
    );
    final cropDisplayTopLeft = Offset(
      cropImageTopLeft.dx * scaleX,
      cropImageTopLeft.dy * scaleY,
    );

    void handleDelta(Offset delta) {
      final nextImageTopLeft = CoverCropGeometry.clampCropTopLeft(
        imageSize: imageSize,
        cropSize: cropImageSize,
        cropTopLeft:
            cropImageTopLeft + Offset(delta.dx / scaleX, delta.dy / scaleY),
      );
      onFocusChanged(
        CoverCropGeometry.focusFromCropTopLeft(
          imageSize: imageSize,
          cropSize: cropImageSize,
          cropTopLeft: nextImageTopLeft,
        ),
      );
    }

    return GestureDetector(
      onPanUpdate: (details) => handleDelta(details.delta),
      child: Stack(
        children: [
          // 完整原图（contain）。
          Positioned.fill(
            child: Image(image: image, fit: BoxFit.contain),
          ),
          // 选框外的遮罩 + 选框边框。
          Positioned.fill(
            child: CustomPaint(
              painter: _CropMaskPainter(
                cropRect: cropDisplayTopLeft & cropDisplaySize,
                borderColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  _CropMaskPainter({required this.cropRect, required this.borderColor});

  final Rect cropRect;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final mask = Paint()..color = Colors.black54;
    // 用奇偶填充挖出选框区域。
    final path = Path()
      ..addRect(full)
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, mask);

    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(cropRect, border);
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.borderColor != borderColor;
  }
}

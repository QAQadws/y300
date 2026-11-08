import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../models/novel_reader_paper_geometry.dart';

/// One page rail, one fold clock. Both page faces use the same geometry, even
/// when PageView paints the stationary destination after the moving sheet.
class NovelReaderPaperClock extends ChangeNotifier {
  NovelReaderPaperClock(this.controller) {
    controller.addListener(_tick);
  }
  final PageController controller;
  double _touchY = 0.5;
  NovelReaderPaperGeometry? _geometry;
  double get page =>
      controller.hasClients && controller.position.hasContentDimensions
      ? controller.page ?? controller.initialPage.toDouble()
      : controller.initialPage.toDouble();
  set touchY(double value) {
    final next = value.clamp(0.0, 1.0);
    if (next == _touchY) return;
    _touchY = next;
    _tick();
  }

  void _tick() {
    _geometry = null;
    notifyListeners();
  }

  NovelReaderPaperGeometry geometry(Size size) => _geometry?.size == size
      ? _geometry!
      : (_geometry = NovelReaderPaperGeometry(
          size: size,
          progress: page - page.floorToDouble(),
          touchY: _touchY,
        ));
  @override
  void dispose() {
    controller.removeListener(_tick);
    _geometry = null;
    super.dispose();
  }
}

/// The SDK owns a display-density texture only while a turn is in progress.
/// No async screenshot cache can outlive the page, owner, or layout generation.
class NovelReaderPaperTurn extends StatefulWidget {
  const NovelReaderPaperTurn({
    super.key,
    this.clock,
    required this.controller,
    required this.index,
    required this.reverse,
    required this.enabled,
    required this.paperColor,
    required this.child,
  });
  final NovelReaderPaperClock? clock;
  final PageController controller;
  final int index;
  final bool reverse, enabled;
  final Color paperColor;
  final Widget child;
  @override
  State<NovelReaderPaperTurn> createState() => _NovelReaderPaperTurnState();
}

class _NovelReaderPaperTurnState extends State<NovelReaderPaperTurn> {
  final _snapshot = SnapshotController();
  late NovelReaderPaperClock _clock;
  late final _PaperPainter _painter;
  @override
  void initState() {
    super.initState();
    _clock = widget.clock ?? NovelReaderPaperClock(widget.controller);
    _painter = _PaperPainter(widget, _clock, _snapshot);
  }

  @override
  void didUpdateWidget(NovelReaderPaperTurn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock ||
        oldWidget.controller != widget.controller) {
      final oldClock = _clock;
      _clock = widget.clock ?? NovelReaderPaperClock(widget.controller);
      _painter.update(widget, _clock);
      if (oldWidget.clock == null) oldClock.dispose();
    } else {
      _painter.update(widget, _clock);
    }
  }

  @override
  void dispose() {
    _painter.dispose();
    _snapshot.dispose();
    if (widget.clock == null) _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _snapshot,
    mode: SnapshotMode.permissive,
    autoresize: true,
    painter: _painter,
    child: widget.child,
  );
}

class _PaperPainter extends SnapshotPainter {
  _PaperPainter(this.config, this.clock, this.snapshot) {
    clock.addListener(_tick);
    _sync();
  }
  NovelReaderPaperTurn config;
  NovelReaderPaperClock clock;
  final SnapshotController snapshot;
  ui.Image? _image;
  ui.ImageShader? _texture;
  double get offset => config.index - clock.page;
  bool get active =>
      config.enabled && offset.abs() > 0.000001 && offset.abs() < 0.999999;
  bool get moving => offset < 0;
  @visibleForTesting
  int snapshotCount = 0;
  void _releaseTexture() {
    _texture?.dispose();
    _texture = null;
    _image = null;
  }

  void _sync() {
    snapshot.allowSnapshotting = active;
    if (!active) _releaseTexture();
  }

  void _tick() {
    _sync();
    notifyListeners();
  }

  void update(NovelReaderPaperTurn next, NovelReaderPaperClock nextClock) {
    if (nextClock != clock) {
      clock.removeListener(_tick);
      nextClock.addListener(_tick);
      snapshot.clear();
      _releaseTexture();
    }
    clock = nextClock;
    config = next;
    _tick();
  }

  Path _path(Path path, Size size) => config.reverse
      ? path.transform(
          (Matrix4.identity()
                ..translateByDouble(size.width, 0, 0, 1)
                ..scaleByDouble(-1, 1, 1, 1))
              .storage,
        )
      : path;

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) {
    if (!config.enabled || this.offset.abs() < 0.000001) {
      painter(context, offset);
      return;
    }
    if (!active) return;
    final geometry = clock.geometry(size);
    // This also covers permissive snapshot fallback (e.g. a platform view).
    final visible = moving
        ? Path.combine(
            PathOperation.difference,
            geometry.front.outline,
            geometry.back.outline,
          )
        : Path.combine(
            PathOperation.difference,
            Path()..addRect(Offset.zero & size),
            geometry.sheet,
          );
    context.pushClipPath(
      true,
      offset,
      Offset.zero & size,
      _path(visible, size),
      (context, offset) {
        painter(context, offset);
        _shadow(context.canvas, offset, size, geometry, moving: moving);
      },
    );
    if (moving) {
      // A platform view cannot supply a texture. Keep the opaque back face so
      // the complementary destination clip never leaves a hole in the sheet.
      final canvas = context.canvas;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      if (config.reverse) {
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
      }
      _face(canvas, geometry.back, null, 1, size, geometry.lift, back: true);
      canvas.restore();
    }
  }

  void _shadow(
    Canvas canvas,
    Offset offset,
    Size size,
    NovelReaderPaperGeometry geometry, {
    required bool moving,
  }) {
    if (geometry.lift < 0.0001) return;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final shadow = moving ? geometry.back.outline : geometry.sheet;
    final sign = config.reverse ? -1.0 : 1.0;
    canvas.drawPath(
      _path(shadow, size).shift(
        Offset(sign * (moving ? -4 : 5) * geometry.lift, 2 * geometry.lift),
      ),
      Paint()
        ..color = const Color(0xFF000000)
            .withValues(alpha: (moving ? 0.22 : 0.26) * geometry.lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 6 * geometry.lift),
    );
    canvas.restore();
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    if (!identical(_image, image)) {
      _releaseTexture();
      _image = image;
      snapshotCount++;
    }
    if (!active || !moving) {
      paint(context, offset, size, (context, offset) {
        context.canvas.drawImageRect(
          image,
          Offset.zero & sourceSize,
          offset & size,
          Paint(),
        );
      });
      return;
    }
    final geometry = clock.geometry(size), canvas = context.canvas;
    final visible = Path.combine(
      PathOperation.difference,
      geometry.front.outline,
      geometry.back.outline,
    );
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    if (config.reverse) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.save();
    canvas.clipPath(visible);
    _face(
      canvas,
      geometry.front,
      image,
      pixelRatio,
      size,
      geometry.lift,
      back: false,
    );
    // The cast shadow belongs to the unturned front face, below the curled back.
    final canonicalBack = geometry.back.outline;
    canvas.drawPath(
      canonicalBack.shift(Offset(-4 * geometry.lift, 2 * geometry.lift)),
      Paint()
        ..color = const Color(0xFF000000)
            .withValues(alpha: 0.22 * geometry.lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 6 * geometry.lift),
    );
    canvas.restore();
    _face(
      canvas,
      geometry.back,
      image,
      pixelRatio,
      size,
      geometry.lift,
      back: true,
    );
    canvas.restore();
  }

  void _face(
    Canvas canvas,
    NovelReaderPaperMesh mesh,
    ui.Image? image,
    double ratio,
    Size size,
    double lift, {
    required bool back,
  }) {
    if (mesh.isEmpty) return;
    final paper = back
        ? Color.lerp(config.paperColor, const Color(0xFFFFFFFF), 0.04)!
        : config.paperColor;
    final colors = Int32List.fromList([
      for (final normal in mesh.normals)
        Color.lerp(
          paper,
          const Color(0xFF000000),
          (1 - normal.abs()) * 0.20 * lift,
        )!.toARGB32(),
    ]);
    final surface = ui.Vertices.raw(
      ui.VertexMode.triangles,
      mesh.positions,
      colors: colors,
      indices: mesh.indices,
    );
    canvas.drawVertices(surface, BlendMode.srcOver, Paint());
    surface.dispose();
    if (image == null) return;
    final uv = Float32List(mesh.uv.length);
    for (var i = 0; i < uv.length; i += 2) {
      uv[i] = (config.reverse ? size.width - mesh.uv[i] : mesh.uv[i]) * ratio;
      uv[i + 1] = mesh.uv[i + 1] * ratio;
    }
    final inkColors = Int32List.fromList([
      for (final normal in mesh.normals)
        Color.lerp(
          const Color(0xFFFFFFFF),
          const Color(0xFF000000),
          (1 - normal.abs()) * 0.20 * lift,
        )!.withValues(alpha: back ? 0.10 * lift : 1).toARGB32(),
    ]);
    final ink = ui.Vertices.raw(
      ui.VertexMode.triangles,
      mesh.positions,
      textureCoordinates: uv,
      colors: inkColors,
      indices: mesh.indices,
    );
    canvas.drawVertices(
      ink,
      BlendMode.modulate,
      Paint()
        ..shader = (_texture ??= ui.ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
        ))
        ..filterQuality = FilterQuality.medium,
    );
    ink.dispose();
    if (back) {
      canvas.drawPath(
        mesh.outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color(0xFF000000).withValues(alpha: 0.12 * lift),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) => true;
  @override
  void dispose() {
    clock.removeListener(_tick);
    _releaseTexture();
    super.dispose();
  }
}

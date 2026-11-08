import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A developable cylindrical fold. UVs retain the original page coordinates;
/// the back face mirrors ink through geometry instead of reversing text nodes.
class NovelReaderPaperMesh {
  NovelReaderPaperMesh._(List<_PaperColumn> columns) {
    final points = <double>[];
    final texture = <double>[];
    final light = <double>[];
    final triangles = <int>[];
    outline = Path();
    if (columns.length < 2) {
      positions = Float32List(0);
      uv = Float32List(0);
      normals = Float32List(0);
      indices = Uint16List(0);
      return;
    }
    for (var i = 0; i < columns.length; i++) {
      final column = columns[i];
      for (final point in [column.top, column.bottom]) {
        points.addAll([point.target.dx, point.target.dy]);
        texture.addAll([point.source.dx, point.source.dy]);
        light.add(point.normal);
      }
      if (i + 1 < columns.length) {
        final a = i * 2;
        triangles.addAll([a, a + 1, a + 2, a + 1, a + 3, a + 2]);
      }
    }
    outline.moveTo(columns.first.top.target.dx, columns.first.top.target.dy);
    for (final column in columns.skip(1)) {
      outline.lineTo(column.top.target.dx, column.top.target.dy);
    }
    for (final column in columns.reversed) {
      outline.lineTo(column.bottom.target.dx, column.bottom.target.dy);
    }
    outline.close();
    positions = Float32List.fromList(points);
    uv = Float32List.fromList(texture);
    normals = Float32List.fromList(light);
    indices = Uint16List.fromList(triangles);
  }

  late final Float32List positions, uv, normals;
  late final Uint16List indices;
  late final Path outline;
  bool get isEmpty => indices.isEmpty;
}

class NovelReaderPaperGeometry {
  NovelReaderPaperGeometry({
    required this.size,
    required double progress,
    required double touchY,
  }) {
    final t = progress.clamp(0.0, 1.0);
    lift = math.sin(math.pi * t);
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      front = NovelReaderPaperMesh._([]);
      back = NovelReaderPaperMesh._([]);
      return;
    }
    // Tilt is bounded by the page aspect ratio so a low/high contact bends a
    // corner without producing an almost horizontal fold on a tall viewport.
    final angle =
        (touchY.clamp(0.0, 1.0) - 0.5) *
        0.5 *
        lift *
        math.min(1.0, size.width * 2 / size.height);
    final cos = math.cos(angle), sin = math.sin(angle);
    final originY = touchY.clamp(0.0, 1.0) * size.height;
    Offset sourceToFold(Offset p) => Offset(
      p.dx * cos + (p.dy - originY) * sin,
      -p.dx * sin + (p.dy - originY) * cos,
    );
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ].map(sourceToFold).toList();
    final minU = corners.map((p) => p.dx).reduce(math.min);
    final maxU = corners.map((p) => p.dx).reduce(math.max);
    final radius = size.width * (0.018 + 0.13 * lift);
    final tangent = maxU * (1 - t) + minU * t - radius * t;
    final crest = tangent + math.pi * radius / 2;
    final values = <double>{
      minU, maxU,
      for (final p in corners) p.dx,
      for (var i = 1; i < 64; i++) minU + (maxU - minU) * i / 64,
      // Explicit fold samples keep both faces joined even at tiny radii.
      for (var i = 0; i <= 32; i++) tangent + math.pi * radius * i / 32,
    }.where((u) => u >= minU && u <= maxU).toList()..sort();
    final columns = <_PaperColumn>[];
    for (final u in values) {
      final intersections = <double>[];
      for (var i = 0; i < 4; i++) {
        final a = corners[i], b = corners[(i + 1) % 4];
        if ((b.dx - a.dx).abs() < 0.0000001) {
          if ((u - a.dx).abs() < 0.0000001) intersections.addAll([a.dy, b.dy]);
        } else {
          final fraction = (u - a.dx) / (b.dx - a.dx);
          if (fraction >= -0.0000001 && fraction <= 1.0000001) {
            intersections.add(a.dy + (b.dy - a.dy) * fraction.clamp(0.0, 1.0));
          }
        }
      }
      if (intersections.isEmpty) continue;
      final d = u - tangent;
      final double mappedU, z, normal;
      if (d <= 0) {
        mappedU = u;
        z = 0;
        normal = 1;
      } else if (d < math.pi * radius) {
        final phi = d / radius;
        mappedU = tangent + radius * math.sin(phi);
        z = radius * (1 - math.cos(phi));
        normal = math.cos(phi);
      } else {
        mappedU = 2 * tangent + math.pi * radius - u;
        z = 2 * radius;
        normal = -1;
      }
      _PaperPoint point(double v) {
        final source = Offset(u * cos - v * sin, u * sin + v * cos + originY);
        final target = Offset(
          mappedU * cos - v * sin,
          mappedU * sin + v * cos + originY,
        );
        final center = Offset(size.width * 0.5, size.height * 0.5);
        final perspective =
            1 / (1 - z / (math.max(size.width, size.height) * 3.5));
        return _PaperPoint(
          Offset(
            source.dx.clamp(0.0, size.width),
            source.dy.clamp(0.0, size.height),
          ),
          center + (target - center) * perspective,
          normal,
        );
      }

      columns.add(
        _PaperColumn(
          u,
          point(intersections.reduce(math.min)),
          point(intersections.reduce(math.max)),
        ),
      );
    }
    // The 90-degree column belongs to both meshes. No triangle crosses the
    // front/back boundary, so complementary clips never expose doubled ink.
    front = NovelReaderPaperMesh._(
      columns.where((c) => c.u <= crest + 0.000001).toList(),
    );
    back = NovelReaderPaperMesh._(
      columns.where((c) => c.u >= crest - 0.000001).toList(),
    );
  }

  final Size size;
  late final double lift;
  late final NovelReaderPaperMesh front, back;
  Path get sheet =>
      Path.combine(PathOperation.union, front.outline, back.outline);
}

class _PaperPoint {
  const _PaperPoint(this.source, this.target, this.normal);
  final Offset source, target;
  final double normal;
}

class _PaperColumn {
  const _PaperColumn(this.u, this.top, this.bottom);
  final double u;
  final _PaperPoint top, bottom;
}

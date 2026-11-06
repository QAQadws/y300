import 'dart:math' as math;

import 'package:flutter/painting.dart';

typedef _Interval = ({double left, double right});
typedef _Edge = ({Offset from, Offset to, int direction});

/// The union of the actual background rectangles before viewport clipping.
/// Owns only the contours and the most recently requested paint path.
final class ForumBodyTextBackgroundGeometry {
  ForumBodyTextBackgroundGeometry(List<Rect> rectangles)
    : _single = rectangles.length == 1 ? rectangles.single : null,
      _contours = rectangles.length > 1 ? _unionContours(rectangles) : const [];

  final Rect? _single;
  final List<List<Offset>> _contours;
  Path? _path;
  double? _radius;

  void paint(Canvas canvas, Paint paint, double radius) {
    final single = _single;
    if (single != null) {
      if (radius == 0) {
        canvas.drawRect(single, paint);
      } else {
        final clamped = math.min(radius, single.shortestSide / 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(single, Radius.circular(clamped)),
          paint,
        );
      }
      return;
    }
    if (_radius != radius) {
      _path = Path();
      for (final contour in _contours) {
        _addContour(_path!, contour, radius);
      }
      _radius = radius;
    }
    canvas.drawPath(_path!, paint);
  }

  static void _addContour(Path path, List<Offset> corners, double radius) {
    for (var index = 0; index < corners.length; index++) {
      final corner = corners[index];
      final incoming = corner - corners[(index - 1) % corners.length];
      final outgoing = corners[(index + 1) % corners.length] - corner;
      final convex = incoming.dx * outgoing.dy > incoming.dy * outgoing.dx;
      // Each end gets at most half its straight edge. Concave corners and
      // holes keep their exact inset so rounding never paints into a gap.
      final r = convex
          ? math.min(radius, math.min(incoming.distance, outgoing.distance) / 2)
          : 0.0;
      final start = r == 0
          ? corner
          : corner - incoming * (r / incoming.distance);
      if (index == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      if (r > 0) {
        path.arcToPoint(
          corner + outgoing * (r / outgoing.distance),
          radius: Radius.circular(r),
        );
      }
    }
    path.close();
  }

  static List<List<Offset>> _unionContours(List<Rect> rectangles) {
    final events = <double, List<({Rect rect, bool start})>>{};
    for (final rect in rectangles) {
      if (rect.isEmpty) continue;
      (events[rect.top] ??= []).add((rect: rect, start: true));
      (events[rect.bottom] ??= []).add((rect: rect, start: false));
    }
    final heights = events.keys.toList()..sort();
    final active = <Rect, int>{};
    final outgoing = <Offset, List<_Edge>>{};
    void add(Offset from, Offset to, int direction) {
      (outgoing[from] ??= []).add((from: from, to: to, direction: direction));
    }

    // Bands contain disjoint, horizontally merged intervals. Vertical sides
    // come from each band; only coverage changes produce horizontal edges.
    var above = <_Interval>[];
    for (var index = 0; index < heights.length; index++) {
      final y = heights[index];
      for (final event in events[y]!) {
        final count = (active[event.rect] ?? 0) + (event.start ? 1 : -1);
        if (count == 0) {
          active.remove(event.rect);
        } else {
          active[event.rect] = count;
        }
      }
      final below = <_Interval>[];
      for (final rect
          in active.keys.toList()..sort((a, b) => a.left.compareTo(b.left))) {
        if (below.isEmpty || below.last.right < rect.left) {
          below.add((left: rect.left, right: rect.right));
        } else if (below.last.right < rect.right) {
          below.last = (left: below.last.left, right: rect.right);
        }
      }
      _difference(
        below,
        above,
        (left, right) => add(Offset(left, y), Offset(right, y), 0),
      );
      _difference(
        above,
        below,
        (left, right) => add(Offset(right, y), Offset(left, y), 2),
      );
      if (below.isNotEmpty) {
        final bottom = heights[index + 1];
        for (final interval in below) {
          add(Offset(interval.right, y), Offset(interval.right, bottom), 1);
          add(Offset(interval.left, bottom), Offset(interval.left, y), 3);
        }
      }
      above = below;
    }

    final contours = <List<Offset>>[];
    final visited = <_Edge>{};
    for (final edges in outgoing.values) {
      for (final first in edges) {
        if (visited.contains(first)) continue;
        final corners = <Offset>[];
        var edge = first;
        do {
          if (!visited.add(edge)) {
            throw StateError('Invalid background contour');
          }
          final candidates = outgoing[edge.to]!;
          var next = candidates.first;
          // At a point contact, the right turn stays on the same component.
          for (final candidate in candidates.skip(1)) {
            if ((candidate.direction - edge.direction) % 4 == 1) {
              next = candidate;
            }
          }
          if (edge.direction != next.direction) corners.add(edge.to);
          edge = next;
        } while (edge != first);
        contours.add(corners);
      }
    }
    return contours;
  }

  static void _difference(
    List<_Interval> included,
    List<_Interval> excluded,
    void Function(double left, double right) emit,
  ) {
    var index = 0;
    for (final interval in included) {
      var left = interval.left;
      while (index < excluded.length && excluded[index].right <= left) {
        index++;
      }
      while (index < excluded.length && excluded[index].left < interval.right) {
        final gap = excluded[index];
        if (left < gap.left) emit(left, gap.left);
        left = gap.right;
        if (left >= interval.right) break;
        index++;
      }
      if (left < interval.right) emit(left, interval.right);
    }
  }
}

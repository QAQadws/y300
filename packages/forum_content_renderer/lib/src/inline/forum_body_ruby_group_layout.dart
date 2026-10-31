import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';

enum ForumBodyRubyPart { base, annotation }

enum ForumBodyRubyGroupFailure { scope, content, geometry, overflow }

final class ForumBodyRubyGroupException implements Exception {
  const ForumBodyRubyGroupException(this.failure);
  final ForumBodyRubyGroupFailure failure;
  @override
  String toString() => 'ForumBodyRubyGroupException(${failure.name})';
}

final class ForumBodyRubyHit {
  const ForumBodyRubyHit({required this.part, required this.position});
  final ForumBodyRubyPart part;
  final HtmlProjectedSourcePosition position;
}

/// One indivisible horizontal ruby pair, borrowing its two native layouts from
/// the reading owner's cache. The base supplies the alphabetic baseline; the
/// annotation is centered above it. Each side keeps its own Unicode/source
/// projection, styles and actual per-font-size TextScaler input.
///
/// This port consumes already-grouped content. It neither parses a ruby element
/// nor flattens its annotation into ordinary text. The parent inline composer
/// owns group/source ordering, legal page boundaries and placeholder placement.
final class ForumBodyRubyGroupLayout {
  /// Parent inline/layout identities include this geometry contract separately
  /// from the underlying paragraph shaping backend revision.
  static const revision = 1;

  ForumBodyRubyGroupLayout._({
    required ForumBodyParagraphLease base,
    required ForumBodyParagraphLease? annotation,
    required HtmlDisplayTextProjection annotationProjection,
    required this.size,
    required this.baseline,
    required this.baseOffset,
    required this.annotationOffset,
    required double annotationHitBoundary,
  }) : _base = base,
       _annotation = annotation,
       hasAnnotation = annotation != null,
       _annotationHitBoundary = annotationHitBoundary,
       _annotationProjection = annotationProjection;

  factory ForumBodyRubyGroupLayout.create({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required ForumBodyParagraphContent annotation,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
  }) {
    if (base.identity != annotation.identity ||
        base.fontRevision != annotation.fontRevision ||
        base.styleRevision != annotation.styleRevision) {
      throw const ForumBodyRubyGroupException(ForumBodyRubyGroupFailure.scope);
    }
    if (base.layoutMode != ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
        annotation.layoutMode !=
            ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
        base.projection.text.isEmpty) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    // Geometry is already in logical layout pixels. Never rescale the group a
    // second time after its per-size child layouts have resolved TextScaler.
    if (!gap.isFinite ||
        gap < 0 ||
        gap > 16384 ||
        !maxWidth.isFinite ||
        maxWidth <= 0 ||
        maxWidth > 16384) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.geometry,
      );
    }
    ForumBodyParagraphLease? baseLease;
    ForumBodyParagraphLease? annotationLease;
    try {
      baseLease = cache.acquire(
        content: base,
        width: maxWidth,
        textScaler: textScaler,
      );
      if (annotation.projection.text.isNotEmpty) {
        annotationLease = cache.acquire(
          content: annotation,
          width: maxWidth,
          textScaler: textScaler,
        );
      }
      final baseLayout = baseLease.layout;
      final baseBounds = _textBounds(baseLease);
      final annotationBounds = annotationLease == null
          ? Rect.zero
          : _textBounds(annotationLease);
      final width = math.max(baseBounds.width, annotationBounds.width);
      final baseTop = annotationLease == null
          ? 0.0
          : annotationBounds.height + gap;
      final baseOffset = Offset(
        (width - baseBounds.width) / 2 - baseBounds.left,
        baseTop - baseBounds.top,
      );
      final height = baseTop + baseBounds.height;
      final baseline = baseOffset.dy + baseLayout.lines.single.baseline;
      if (width > maxWidth) {
        throw const ForumBodyRubyGroupException(
          ForumBodyRubyGroupFailure.overflow,
        );
      }
      if (!height.isFinite ||
          height <= 0 ||
          height > 16384 ||
          !baseline.isFinite ||
          baseline < 0 ||
          baseline > height) {
        throw const ForumBodyRubyGroupException(
          ForumBodyRubyGroupFailure.geometry,
        );
      }
      return ForumBodyRubyGroupLayout._(
        base: baseLease,
        annotation: annotationLease,
        annotationProjection: annotation.projection,
        size: Size(width, height),
        baseline: baseline,
        baseOffset: baseOffset,
        annotationOffset: Offset(
          (width - annotationBounds.width) / 2 - annotationBounds.left,
          -annotationBounds.top,
        ),
        annotationHitBoundary: annotationBounds.height + gap / 2,
      );
    } catch (_) {
      annotationLease?.release();
      baseLease?.release();
      rethrow;
    }
  }

  ForumBodyParagraphLease? _base;
  ForumBodyParagraphLease? _annotation;
  final HtmlDisplayTextProjection _annotationProjection;
  final Size size;
  final double baseline;
  final Offset baseOffset;
  final Offset annotationOffset;
  final bool hasAnnotation;
  final double _annotationHitBoundary;

  bool get isActive =>
      _base?.isActive == true && (_annotation?.isActive ?? true);

  static Rect _textBounds(ForumBodyParagraphLease lease) {
    final layout = lease.layout;
    var bounds = Rect.fromLTWH(0, 0, layout.width, layout.height);
    // Author line-height can be smaller than the actual font boxes, including
    // fallback emoji and nested larger runs. Reserve their real extent without
    // reshaping the font or changing the paragraph's source coordinates.
    for (final box in layout.selectionBoxes(
      0,
      lease.content.projection.text.length,
    )) {
      bounds = bounds.expandToInclude(box.toRect());
    }
    return bounds;
  }

  /// Already scaled geometry for a direct TextPainter placeholder. A Widget
  /// host must not apply an additional inline-widget scale to this native box.
  PlaceholderDimensions get placeholderDimensions {
    _ensureActive();
    return PlaceholderDimensions(
      size: size,
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      baselineOffset: baseline,
    );
  }

  HtmlDisplayTextProjection projectionFor(ForumBodyRubyPart part) {
    _ensureActive();
    return part == ForumBodyRubyPart.base
        ? _base!.content.projection
        : _annotationProjection;
  }

  void paint(Canvas canvas, Offset offset) {
    _ensureActive();
    _base!.layout.paint(canvas, offset + baseOffset);
    _annotation?.layout.paint(canvas, offset + annotationOffset);
  }

  ForumBodyRubyHit sourceAt(Offset offset) {
    _ensureActive();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    final annotation = _annotation;
    final useAnnotation =
        annotation != null && offset.dy < _annotationHitBoundary;
    return ForumBodyRubyHit(
      part: useAnnotation
          ? ForumBodyRubyPart.annotation
          : ForumBodyRubyPart.base,
      position: useAnnotation
          ? annotation.layout.sourceAt(offset - annotationOffset)
          : _base!.layout.sourceAt(offset - baseOffset),
    );
  }

  List<TextBox> selectionBoxes({
    required ForumBodyRubyPart part,
    required int startUtf16,
    required int endUtf16,
  }) {
    _ensureActive();
    final projection = projectionFor(part);
    RangeError.checkValidRange(startUtf16, endUtf16, projection.text.length);
    final lease = part == ForumBodyRubyPart.base ? _base : _annotation;
    if (lease == null) return const [];
    final offset = part == ForumBodyRubyPart.base
        ? baseOffset
        : annotationOffset;
    return List.unmodifiable([
      for (final box in lease.layout.selectionBoxes(startUtf16, endUtf16))
        TextBox.fromLTRBD(
          box.left + offset.dx,
          box.top + offset.dy,
          box.right + offset.dx,
          box.bottom + offset.dy,
          box.direction,
        ),
    ]);
  }

  void _ensureActive() {
    if (!isActive) throw StateError('Ruby group layout is retired');
  }

  /// Releases only this group's borrowed leases, never its reading owner.
  void close() {
    final base = _base;
    final annotation = _annotation;
    _base = null;
    _annotation = null;
    annotation?.release();
    base?.release();
  }
}

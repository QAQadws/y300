import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_ruby_group_contract.dart';
import 'forum_body_ruby_group_metrics.dart';

export 'forum_body_ruby_group_contract.dart'
    show ForumBodyRubyGroupFailure, ForumBodyRubyGroupException;

enum ForumBodyRubyPart { base, annotation }

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
  static const revision = ForumBodyRubyGroupMetrics.revision;

  ForumBodyRubyGroupLayout._({
    required ForumBodyTextLease base,
    required ForumBodyTextLease? annotation,
    required ForumBodyParagraphContent annotationContent,
    required this.metrics,
  }) : _base = base,
       _annotation = annotation,
       _annotationContent = annotationContent;

  factory ForumBodyRubyGroupLayout.create({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required ForumBodyParagraphContent annotation,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
  }) => _acquire(
    cache: cache,
    base: base,
    annotation: annotation,
    textScaler: textScaler,
    gap: gap,
    maxWidth: maxWidth,
    cachedOnly: false,
  )!;

  /// No native construction on a miss. A partial hit is released immediately;
  /// the caller prepares missing child inputs outside the visible paint path.
  static ForumBodyRubyGroupLayout? tryCreateCached({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required ForumBodyParagraphContent annotation,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
  }) => _acquire(
    cache: cache,
    base: base,
    annotation: annotation,
    textScaler: textScaler,
    gap: gap,
    maxWidth: maxWidth,
    cachedOnly: true,
  );

  static void validateInputs({
    required ForumBodyParagraphContent base,
    required ForumBodyParagraphContent annotation,
    double gap = 0,
    double maxWidth = 16384,
  }) => validateForumBodyRubyGroupInputs(
    base: base,
    annotation: annotation,
    gap: gap,
    maxWidth: maxWidth,
  );

  static ForumBodyRubyGroupLayout? _acquire({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required ForumBodyParagraphContent annotation,
    required TextScaler textScaler,
    required double gap,
    required double maxWidth,
    required bool cachedOnly,
  }) {
    validateInputs(
      base: base,
      annotation: annotation,
      gap: gap,
      maxWidth: maxWidth,
    );
    ForumBodyParagraphLease? baseLease;
    ForumBodyParagraphLease? annotationLease;
    try {
      baseLease = cachedOnly
          ? cache.tryAcquireCached(
              content: base,
              width: maxWidth,
              textScaler: textScaler,
            )
          : cache.acquire(
              content: base,
              width: maxWidth,
              textScaler: textScaler,
            );
      if (baseLease == null) return null;
      if (annotation.projection.text.isNotEmpty) {
        annotationLease = cachedOnly
            ? cache.tryAcquireCached(
                content: annotation,
                width: maxWidth,
                textScaler: textScaler,
              )
            : cache.acquire(
                content: annotation,
                width: maxWidth,
                textScaler: textScaler,
              );
        if (annotationLease == null) {
          baseLease.release();
          return null;
        }
      }
      return ForumBodyRubyGroupLayout.adopt(
        cache: cache,
        baseLease: baseLease,
        annotation: annotation,
        annotationLease: annotationLease,
        gap: gap,
        maxWidth: maxWidth,
      );
    } catch (_) {
      annotationLease?.release();
      baseLease?.release();
      rethrow;
    }
  }

  /// Takes ownership of exactly these handles on success AND failure, never
  /// their owner or another alias. Preparation can transfer already pinned
  /// children without lookup, scaling callbacks or another native build.
  factory ForumBodyRubyGroupLayout.adopt({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextLease baseLease,
    required ForumBodyParagraphContent annotation,
    ForumBodyTextLease? annotationLease,
    double gap = 0,
    double maxWidth = 16384,
  }) {
    try {
      final metrics = ForumBodyRubyGroupMetrics.measure(
        cache: cache,
        baseLease: baseLease,
        annotation: annotation,
        annotationLease: annotationLease,
        gap: gap,
        maxWidth: maxWidth,
      );
      final baseLayout = baseLease.layout;
      if (!baseLayout.isPaintPrepared ||
          (annotationLease != null &&
              !annotationLease.layout.isPaintPrepared)) {
        throw StateError('Ruby child paint is not prepared');
      }
      return ForumBodyRubyGroupLayout._(
        base: baseLease,
        annotation: annotationLease,
        annotationContent: annotation,
        metrics: metrics,
      );
    } catch (_) {
      annotationLease?.release();
      baseLease.release();
      rethrow;
    }
  }

  ForumBodyTextLease? _base;
  ForumBodyTextLease? _annotation;
  ForumBodyParagraphContent? _annotationContent;
  final ForumBodyRubyGroupMetrics metrics;
  Size get size => metrics.size;
  double get baseline => metrics.baseline;
  Offset get baseOffset => metrics.baseOffset;
  Offset get annotationOffset => metrics.annotationOffset;
  bool get hasAnnotation => metrics.hasAnnotation;

  bool get isActive =>
      _base?.isActive == true &&
      _base!.layout.isPaintPrepared &&
      (_annotation == null ||
          (_annotation!.isActive && _annotation!.layout.isPaintPrepared));

  /// Proves a prepared group's child handles use the same reading budget as
  /// its parent, without acquiring aliases or retaining another cache owner.
  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      isActive &&
      cache.ownsLease(_base!) &&
      (_annotation == null || cache.ownsLease(_annotation!));

  /// Borrowed handles for aggregate page admission. Does not acquire aliases;
  /// only close/adoption transfers their lifetime, including retired owners.
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_base,
    ?_annotation,
  ];

  ForumBodyParagraphContent contentFor(ForumBodyRubyPart part) {
    _ensureActive();
    return part == ForumBodyRubyPart.base
        ? _base!.content
        : _annotationContent!;
  }

  /// Already scaled geometry for a direct TextPainter placeholder. A Widget
  /// host must not apply an additional inline-widget scale to this native box.
  PlaceholderDimensions get placeholderDimensions {
    _ensureActive();
    return metrics.placeholderDimensions;
  }

  HtmlDisplayTextProjection projectionFor(ForumBodyRubyPart part) {
    _ensureActive();
    return part == ForumBodyRubyPart.base
        ? _base!.content.projection
        : _annotationContent!.projection;
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
    final emptyBase = _base!.content.projection.text.isEmpty;
    final useAnnotation =
        annotation != null &&
        (emptyBase || offset.dy < metrics.annotationHitBoundary);
    final position = useAnnotation
        ? annotation.layout.sourceAt(offset - annotationOffset)
        : _base!.layout.sourceAt(offset - baseOffset);
    return ForumBodyRubyHit(
      part: useAnnotation
          ? ForumBodyRubyPart.annotation
          : ForumBodyRubyPart.base,
      position: emptyBase && offset.dy >= metrics.annotationHitBoundary
          ? HtmlProjectedSourcePosition(
              sourceRune: position.sourceRune,
              displayUtf16: position.displayUtf16,
              isExact: false,
            )
          : position,
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
    _annotationContent = null;
    annotation?.release();
    base?.release();
  }
}

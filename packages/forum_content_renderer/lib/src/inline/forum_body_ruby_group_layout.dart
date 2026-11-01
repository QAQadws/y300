import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
import 'forum_body_ruby_group_contract.dart';
import 'forum_body_ruby_group_metrics.dart';

export 'forum_body_ruby_group_contract.dart'
    show ForumBodyRubyGroupFailure, ForumBodyRubyGroupException;

enum ForumBodyRubyPart { base, annotation }

typedef ForumBodyRubyGroupMemberSnapshot = ({
  ForumBodyTextLease base,
  List<({ForumBodyParagraphContent content, ForumBodyTextLease? lease})>
  annotations,
});

final class ForumBodyRubyHit {
  const ForumBodyRubyHit({
    required this.part,
    required this.position,
    required this.annotationIndex,
  }) : assert(
         (part == ForumBodyRubyPart.annotation) == (annotationIndex != null),
       ),
       assert(annotationIndex == null || annotationIndex >= 0);
  final ForumBodyRubyPart part;
  final HtmlProjectedSourcePosition position;

  /// Original annotation rank, including missing inner positions. Null for base.
  final int? annotationIndex;
}

/// One indivisible horizontal column, borrowing one base and each nonempty
/// annotation's native layout from the reading owner's existing cache. Each
/// rank keeps its own source projection, styles and per-size TextScaler input.
///
/// This port consumes already-grouped content. It neither parses ruby nor
/// flattens its annotations into ordinary text. The parent composer owns source
/// ordering, legal page boundaries and placeholder placement.
final class ForumBodyRubyGroupLayout {
  static const revision = ForumBodyRubyGroupMetrics.revision;

  ForumBodyRubyGroupLayout._({
    required ForumBodyTextLease base,
    required List<
      ({ForumBodyParagraphContent content, ForumBodyTextLease? lease})
    >
    annotations,
    required this.metrics,
  }) : _base = base,
       _annotations = List.unmodifiable(annotations);

  factory ForumBodyRubyGroupLayout.create({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required ForumBodyParagraphContent annotation,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
    ForumBodyRubySide side = ForumBodyRubySide.over,
  }) => ForumBodyRubyGroupLayout.createLayers(
    cache: cache,
    base: base,
    annotations: [(content: annotation, gap: gap, side: side)],
    textScaler: textScaler,
    maxWidth: maxWidth,
  );

  factory ForumBodyRubyGroupLayout.createLayers({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required List<
      ({ForumBodyParagraphContent content, double gap, ForumBodyRubySide side})
    >
    annotations,
    TextScaler textScaler = TextScaler.noScaling,
    double maxWidth = 16384,
  }) => _acquireLayers(
    cache: cache,
    base: base,
    annotations: annotations,
    textScaler: textScaler,
    maxWidth: maxWidth,
    cachedOnly: false,
  )!;

  /// No native construction on a miss. Partial hits are released immediately;
  /// the caller prepares missing inputs outside the visible paint path.
  static ForumBodyRubyGroupLayout? tryCreateCached({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required ForumBodyParagraphContent annotation,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
    ForumBodyRubySide side = ForumBodyRubySide.over,
  }) => tryCreateCachedLayers(
    cache: cache,
    base: base,
    annotations: [(content: annotation, gap: gap, side: side)],
    textScaler: textScaler,
    maxWidth: maxWidth,
  );

  static ForumBodyRubyGroupLayout? tryCreateCachedLayers({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required List<
      ({ForumBodyParagraphContent content, double gap, ForumBodyRubySide side})
    >
    annotations,
    TextScaler textScaler = TextScaler.noScaling,
    double maxWidth = 16384,
  }) => _acquireLayers(
    cache: cache,
    base: base,
    annotations: annotations,
    textScaler: textScaler,
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

  static ForumBodyRubyGroupLayout? _acquireLayers({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required List<
      ({ForumBodyParagraphContent content, double gap, ForumBodyRubySide side})
    >
    annotations,
    required TextScaler textScaler,
    required double maxWidth,
    required bool cachedOnly,
  }) {
    // TextScaler may call user code while acquiring. Snapshot rank identity
    // before the first callback, so mutation cannot change adopted ownership.
    final inputs = List.of(annotations);
    validateForumBodyRubyColumnInputs(
      base: base,
      annotations: [
        for (final item in inputs) (content: item.content, gap: item.gap),
      ],
      maxWidth: maxWidth,
    );
    ForumBodyParagraphLease? acquire(ForumBodyParagraphContent content) =>
        cachedOnly
        ? cache.tryAcquireCached(
            content: content,
            width: maxWidth,
            textScaler: textScaler,
          )
        : cache.acquire(
            content: content,
            width: maxWidth,
            textScaler: textScaler,
          );
    ForumBodyParagraphLease? baseLease;
    final leases = <ForumBodyParagraphLease?>[];
    var transferred = false;
    try {
      baseLease = acquire(base);
      if (baseLease == null) return null;
      for (final item in inputs) {
        final lease = item.content.projection.text.isEmpty
            ? null
            : acquire(item.content);
        leases.add(lease);
        if (lease == null && item.content.projection.text.isNotEmpty) {
          return null;
        }
      }
      final group = ForumBodyRubyGroupLayout.adoptLayers(
        cache: cache,
        baseLease: baseLease,
        annotations: [
          for (final (index, item) in inputs.indexed)
            (
              content: item.content,
              lease: leases[index],
              gap: item.gap,
              side: item.side,
            ),
        ],
        maxWidth: maxWidth,
      );
      transferred = true;
      return group;
    } finally {
      if (!transferred) {
        for (final lease in leases) {
          lease?.release();
        }
        baseLease?.release();
      }
    }
  }

  /// Consumes exactly these handles on success AND failure, never their owner
  /// or another alias. No lookup, scaling callback or native build is needed.
  factory ForumBodyRubyGroupLayout.adopt({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextLease baseLease,
    required ForumBodyParagraphContent annotation,
    ForumBodyTextLease? annotationLease,
    double gap = 0,
    double maxWidth = 16384,
    ForumBodyRubyLevelMetrics? level,
    ForumBodyRubySide side = ForumBodyRubySide.over,
  }) => ForumBodyRubyGroupLayout.adoptLayers(
    cache: cache,
    baseLease: baseLease,
    annotations: [
      (content: annotation, lease: annotationLease, gap: gap, side: side),
    ],
    maxWidth: maxWidth,
    level: level,
  );

  factory ForumBodyRubyGroupLayout.adoptLayers({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextLease baseLease,
    required List<
      ({
        ForumBodyParagraphContent content,
        ForumBodyTextLease? lease,
        double gap,
        ForumBodyRubySide side,
      })
    >
    annotations,
    double maxWidth = 16384,
    ForumBodyRubyLevelMetrics? level,
  }) {
    final inputs = List.of(annotations);
    ForumBodyRubyGroupAssembly? assembly;
    var transferred = false;
    try {
      if (!cache.ownsLease(baseLease) ||
          inputs.any(
            (item) => item.lease != null && !cache.ownsLease(item.lease!),
          )) {
        throw StateError(
          'Ruby child lease is not active in this reading owner',
        );
      }
      assembly = ForumBodyRubyGroupAssembly(
        cache: cache,
        base: baseLease.content,
        annotations: [
          for (final item in inputs)
            (content: item.content, gap: item.gap, side: item.side),
        ],
        maxWidth: maxWidth,
        level: level,
      );
      assembly.addBase(baseLease);
      for (final item in inputs) {
        assembly.addAnnotation(item.lease);
      }
      while (!assembly.isReady) {
        assembly.advance(maxParts: 32);
      }
      final result = assembly.takeLayout();
      transferred = true;
      return result;
    } finally {
      assembly?.close();
      if (!transferred) {
        for (final item in inputs) {
          item.lease?.release();
        }
        baseLease.release();
      }
    }
  }
  ForumBodyTextLease? _base;
  List<({ForumBodyParagraphContent content, ForumBodyTextLease? lease})>
  _annotations;
  final ForumBodyRubyGroupMetrics metrics;

  /// Borrow immutable member identities without traversing every rank. This is
  /// not an active-owner or paint proof: an assembling consumer checks each
  /// member before adoption. Holding the snapshot does not extend ownership.
  ForumBodyRubyGroupMemberSnapshot inspectMembers() {
    final base = _base;
    if (base == null) throw StateError('Ruby group layout is retired');
    return (base: base, annotations: _annotations);
  }

  Size get size => metrics.size;
  double get baseline => metrics.baseline;
  Offset get baseOffset => metrics.baseOffset;
  Offset get annotationOffset => metrics.annotationOffset;
  bool get hasAnnotation => metrics.hasAnnotation;
  int get annotationCount => metrics.annotations.length;

  bool get isActive =>
      _base?.isActive == true &&
      _base!.layout.isPaintPrepared &&
      _annotations.every(
        (item) =>
            item.lease == null ||
            (item.lease!.isActive && item.lease!.layout.isPaintPrepared),
      );

  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      isActive &&
      cache.ownsLease(_base!) &&
      _annotations.every(
        (item) => item.lease == null || cache.ownsLease(item.lease!),
      );

  /// Borrowed handles in base/rank order, omitting empty ranks. Only close or
  /// adoption transfers lifetime, including when the reading owner retires.
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_base,
    for (final item in _annotations) ?item.lease,
  ];

  /// Omit annotationIndex only for a single-level group. Base has no rank.
  ForumBodyParagraphContent contentFor(
    ForumBodyRubyPart part, {
    int? annotationIndex,
  }) {
    _ensureActive();
    if (part == ForumBodyRubyPart.base) {
      if (annotationIndex != null) throw ArgumentError.value(annotationIndex);
      return _base!.content;
    }
    return _annotations[_rank(annotationIndex)].content;
  }

  int _rank(int? index) {
    if (index == null) {
      if (_annotations.length != 1) {
        throw StateError('Multi-level ruby requires an annotation index');
      }
      return 0;
    }
    RangeError.checkValidIndex(index, _annotations, 'annotationIndex');
    return index;
  }

  PlaceholderDimensions get placeholderDimensions {
    _ensureActive();
    return metrics.placeholderDimensions;
  }

  HtmlDisplayTextProjection projectionFor(
    ForumBodyRubyPart part, {
    int? annotationIndex,
  }) => contentFor(part, annotationIndex: annotationIndex).projection;

  void paint(Canvas canvas, Offset offset) {
    _ensureActive();
    _base!.layout.paint(canvas, offset + baseOffset);
    for (final (index, item) in _annotations.indexed) {
      item.lease?.layout.paint(
        canvas,
        offset + metrics.annotations[index].offset,
      );
    }
  }

  ForumBodyRubyHit sourceAt(Offset offset) {
    _ensureActive();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    double distance(double top, double bottom) => offset.dy < top
        ? top - offset.dy
        : offset.dy > bottom
        ? offset.dy - bottom
        : 0;
    var selected = -1;
    var bestTop = metrics.baseBandTop;
    var bestDistance = distance(metrics.baseBandTop, metrics.baseBandBottom);
    var nearest = -1;
    var nearestDistance = double.infinity;
    var nearestTop = double.negativeInfinity;
    for (final (index, item) in _annotations.indexed) {
      if (item.lease == null) continue;
      final band = metrics.annotations[index];
      final delta = distance(band.bandTop, band.bandBottom);
      // At an exact midpoint choose the physically lower band, matching the
      // original over/under boundary convention without sorting source ranks.
      if (delta < nearestDistance ||
          (delta == nearestDistance && band.bandTop > nearestTop)) {
        nearestDistance = delta;
        nearestTop = band.bandTop;
        nearest = index;
      }
      if (delta < bestDistance ||
          (delta == bestDistance && band.bandTop > bestTop)) {
        bestDistance = delta;
        bestTop = band.bandTop;
        selected = index;
      }
    }
    final forcedAnnotation =
        selected < 0 && _base!.content.projection.text.isEmpty;
    if (forcedAnnotation) selected = nearest;
    final useAnnotation = selected >= 0;
    final lease = useAnnotation ? _annotations[selected].lease! : _base!;
    final origin = useAnnotation
        ? metrics.annotations[selected].offset
        : baseOffset;
    final position = lease.layout.sourceAt(offset - origin);
    return ForumBodyRubyHit(
      part: useAnnotation
          ? ForumBodyRubyPart.annotation
          : ForumBodyRubyPart.base,
      annotationIndex: useAnnotation ? selected : null,
      position: forcedAnnotation
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
    int? annotationIndex,
  }) {
    _ensureActive();
    final projection = projectionFor(part, annotationIndex: annotationIndex);
    RangeError.checkValidRange(startUtf16, endUtf16, projection.text.length);
    final rank = part == ForumBodyRubyPart.base ? null : _rank(annotationIndex);
    final lease = rank == null ? _base : _annotations[rank].lease;
    if (lease == null) return const [];
    final offset = rank == null ? baseOffset : metrics.annotations[rank].offset;
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

  void close() {
    final base = _base;
    final annotations = _annotations;
    _base = null;
    _annotations = const [];
    for (final item in annotations) {
      item.lease?.release();
    }
    base?.release();
  }
}

/// Internal ownership transaction shared by synchronous adoption and bounded
/// preparation. Each append measures exactly its transferred child; numeric
/// finalization never revisits native glyphs or remeasures an entire column.
final class ForumBodyRubyGroupAssembly {
  ForumBodyRubyGroupAssembly({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required List<
      ({ForumBodyParagraphContent content, double gap, ForumBodyRubySide side})
    >
    annotations,
    double maxWidth = 16384,
    ForumBodyRubyLevelMetrics? level,
    this.preparePaint = true,
  }) : _cache = cache,
       _contents = [for (final item in annotations) item.content],
       _measurement = ForumBodyRubyGroupMeasurement(
         base: base,
         annotations: annotations,
         maxWidth: maxWidth,
         level: level,
       );
  ForumBodyParagraphCache? _cache;
  List<ForumBodyParagraphContent> _contents;
  ForumBodyRubyGroupMeasurement? _measurement;
  final bool preparePaint;
  ForumBodyTextLease? _base;
  final _handles = Set<ForumBodyTextLease>.identity();
  final _annotations =
      <({ForumBodyParagraphContent content, ForumBodyTextLease? lease})>[];
  bool get isReady => _measurement?.isReady == true;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => _handles;

  void addBase(ForumBodyTextLease lease) {
    if (_base != null || _cache == null) {
      lease.release();
      throw StateError('Ruby assembly cannot accept a base');
    }
    _base = lease;
    _handles.add(lease);
    try {
      _guard();
      _measurement!.addBase(_cache!, lease);
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }

  void addAnnotation(ForumBodyTextLease? lease) {
    try {
      _guard();
      if (_base == null || _annotations.length >= _contents.length) {
        throw StateError('Ruby assembly rank is out of order');
      }
      if (lease != null && !_handles.add(lease)) {
        throw StateError('Each ruby position must transfer a distinct handle');
      }
      _annotations.add((content: _contents[_annotations.length], lease: lease));
      _measurement!.addAnnotation(_cache!, lease);
      _guard();
    } catch (_) {
      lease?.release();
      close();
      rethrow;
    }
  }

  int advance({required int maxParts}) {
    try {
      _guard();
      final first = _measurement!.positionedAnnotations;
      final parts = _measurement!.advance(maxParts: maxParts);
      if (!preparePaint) {
        for (var rank = first; rank < first + parts; rank++) {
          final item = _annotations[rank];
          _annotations[rank] = (content: item.content, lease: null);
          _handles.remove(item.lease);
          item.lease?.release();
          _guard();
        }
        if (isReady) {
          final base = _base;
          _base = null;
          _handles.remove(base);
          base?.release();
        }
      }
      _guard();
      return parts;
    } catch (_) {
      close();
      rethrow;
    }
  }

  ForumBodyRubyGroupLayout takeLayout() {
    _guard();
    if (!isReady || !preparePaint) {
      throw StateError('Ruby readable assembly is not ready');
    }
    final result = ForumBodyRubyGroupLayout._(
      base: _base!,
      annotations: _annotations,
      metrics: _measurement!.takeMetrics(),
    );
    _handles.clear();
    _base = null;
    close();
    return result;
  }

  ForumBodyRubyGroupMetrics takeMetrics() {
    _guard();
    if (!isReady || preparePaint) {
      throw StateError('Ruby metric assembly is not ready');
    }
    final result = _measurement!.takeMetrics();
    close();
    return result;
  }

  void _guard() {
    final cache = _cache;
    if (cache == null || cache.isClosed) {
      throw StateError('Ruby assembly owner is retired');
    }
    for (final handle in _handles) {
      if (!cache.ownsLease(handle) ||
          (preparePaint && !handle.layout.isPaintPrepared)) {
        throw StateError('Ruby child is retired or unprepared');
      }
    }
  }

  void close() {
    final handles = _handles.toList();
    _handles.clear();
    _base = null;
    _annotations.clear();
    _contents = const [];
    _measurement?.close();
    _measurement = null;
    _cache = null;
    for (final handle in handles) {
      handle.release();
    }
  }
}

part of 'forum_body_ruby_group_metrics.dart';

/// Native text adapter for the shared numeric stack. Scope and live owner
/// validation stay here; the geometry worker never accepts a lease or content.
final class ForumBodyRubyGroupMeasurement {
  ForumBodyRubyGroupMeasurement({
    required ForumBodyParagraphContent base,
    required List<
      ({ForumBodyParagraphContent content, double gap, ForumBodyRubySide side})
    >
    annotations,
    this.maxWidth = 16384,
    this.level,
    bool allowEmptyBase = false,
  }) : _baseContent = base,
       _inputs = List.of(annotations) {
    validateForumBodyRubyColumnInputs(
      base: base,
      annotations: [
        for (final item in _inputs) (content: item.content, gap: item.gap),
      ],
      maxWidth: maxWidth,
      allowEmptyBase: allowEmptyBase,
    );
    _geometry = ForumBodyRubyGroupGeometry(
      annotations: [
        for (final item in _inputs)
          (
            hasAnnotation: item.content.projection.text.isNotEmpty,
            gap: item.gap,
            side: item.side,
          ),
      ],
      maxWidth: maxWidth,
      level: level,
    );
  }
  ForumBodyParagraphContent? _baseContent;
  List<
    ({ForumBodyParagraphContent content, double gap, ForumBodyRubySide side})
  >
  _inputs;
  late final ForumBodyRubyGroupGeometry _geometry;
  final double maxWidth;
  final ForumBodyRubyLevelMetrics? level;
  int get measuredAnnotations => _geometry.measuredAnnotations;
  int get positionedAnnotations => _geometry.positionedAnnotations;
  bool get isMeasured => _geometry.isMeasured;
  bool get isReady => _geometry.isReady;

  void addBase(ForumBodyParagraphCache cache, ForumBodyTextLease lease) {
    _geometry._ensureActive();
    if (_geometry._baseBounds != null) {
      throw StateError('Ruby base was already measured');
    }
    if (!cache.ownsLease(lease)) throw StateError('Ruby base owner is retired');
    if (!identical(lease.content, _baseContent)) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    _geometry.addBase(
      ForumBodyRubyChildMetrics.measure(
        cache: cache,
        lease: lease,
        content: _baseContent!,
      ),
    );
  }

  void addAnnotation(ForumBodyParagraphCache cache, ForumBodyTextLease? lease) {
    _geometry._ensureActive();
    if (_geometry._baseBounds == null ||
        measuredAnnotations >= _inputs.length) {
      throw StateError('Ruby annotation is out of order');
    }
    final item = _inputs[measuredAnnotations];
    if (lease != null && !cache.ownsLease(lease)) {
      throw StateError('Ruby annotation owner is retired');
    }
    if (item.content.projection.text.isNotEmpty != (lease != null) ||
        (lease != null && !identical(lease.content, item.content))) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    _geometry.addAnnotation(
      lease == null
          ? null
          : ForumBodyRubyChildMetrics.measure(
              cache: cache,
              lease: lease,
              content: item.content,
            ),
    );
  }

  int advance({required int maxParts}) => _geometry.advance(maxParts: maxParts);
  ForumBodyRubyGroupMetrics takeMetrics() {
    final result = _geometry.takeMetrics();
    _baseContent = null;
    _inputs = const [];
    return result;
  }

  void close() {
    _baseContent = null;
    _inputs = const [];
    _geometry.close();
  }
}

part of 'forum_body_text_page_session.dart';

bool _isHeadingOpening(ForumBodyBlockFlowBoundary unit) =>
    unit.boundary.kind == ForumBodyTextFlowBoundaryKind.openBlock &&
    (unit.boundary.event!.node as ForumBodyElement).kind ==
        ForumBodyElementKind.heading &&
    !unit.boundary.event!.style.visibilityHidden &&
    unit.collapseTitle == null;

/// Reads one title and the immediately following block from the actual flow.
/// Everything is replayed through normal admission, including the first
/// barrier. A speculative plan owns at most one paragraph's native work.
final class _HeadingKeepProbe {
  _HeadingKeepProbe(this.opening, double pendingMargin)
    : _units = [opening],
      _gap = pendingMargin,
      _pageStartTrim = pendingMargin;

  final ForumBodyBlockFlowBoundary opening;
  final List<ForumBodyBlockFlowUnit> _units;
  int _replayIndex = 0;
  int sourceWorkLeft = 96;
  int _formatWorkLeft = 160;
  double _gap, _pageStartTrim;
  bool _beforeFirstPadding = true;
  bool _headingClosed = false;
  String? _followingPath;
  ForumBodyBlockFlowUnit? _heading, _following;
  double? _headingExtent;
  ForumBodyEmphasisPageAdmission? _plain;
  ForumBodyInlinePageAdmission? _inline;
  bool isReplaying = false;

  bool get isMeasuring => _following != null && !isReplaying;
  bool get isDrained => _replayIndex == _units.length;
  ForumBodyBlockFlowUnit take() => _units[_replayIndex++];

  String get _headingPath => opening.boundary.event!.node.path;

  static String? _parentPath(String path) {
    final separator = path.lastIndexOf('/');
    return separator < 0 ? null : path.substring(0, separator);
  }

  void observe(ForumBodyBlockFlowUnit? unit, int work) {
    sourceWorkLeft -= work;
    if (unit != null) _units.add(unit);
    if (_units.length >= 24 || sourceWorkLeft <= 0) {
      close();
      return;
    }
    switch (unit) {
      case null:
        return;
      case ForumBodyBlockFlowSpace():
        if (unit.extent < 0) {
          close();
          return;
        }
        _gap += unit.extent;
        if (unit.kind != ForumBodyBlockSpaceKind.collapsedMargin) {
          _beforeFirstPadding = false;
        }
        if (_heading == null && _beforeFirstPadding) {
          _pageStartTrim += unit.extent;
        }
      case ForumBodyBlockFlowBoundary():
        final boundary = unit.boundary;
        final event = boundary.event;
        final node = event?.node as ForumBodyElement?;
        if (boundary.kind == ForumBodyTextFlowBoundaryKind.closeBlock &&
            node?.path == _headingPath &&
            _heading != null &&
            !_headingClosed) {
          _headingClosed = true;
        } else if (boundary.kind == ForumBodyTextFlowBoundaryKind.openBlock &&
            _headingClosed &&
            unit.collapseTitle == null &&
            node != null &&
            (node.kind == ForumBodyElementKind.paragraph ||
                node.kind == ForumBodyElementKind.container) &&
            event!.style.role == ForumBodyTextRole.body &&
            !event.style.visibilityHidden &&
            _parentPath(node.path) ==
                (_followingPath ?? _parentPath(_headingPath))) {
          _followingPath = node.path;
        } else {
          close();
        }
      case ForumBodyBlockFlowParagraph(:final paragraph, :final listMarkers):
        _observeText(
          unit,
          paragraph.content.path,
          paragraph.content.style,
          paragraph.window,
          listMarkers.isNotEmpty ||
              paragraph.content.projection.text.trim().isEmpty,
        );
      case ForumBodyBlockFlowInline(:final paragraph, :final listMarkers):
        _observeText(
          unit,
          paragraph.content.path,
          paragraph.content.style,
          paragraph.window,
          listMarkers.isNotEmpty ||
              paragraph.content.parts.any(
                (part) => part is ForumBodyInlineFlowExclusion,
              ),
        );
      case ForumBodyBlockFlowImage() ||
          ForumBodyBlockFlowTable() ||
          ForumBodyBlockFlowRule() ||
          ForumBodyBlockFlowListItemStart():
        close();
    }
  }

  void _observeText(
    ForumBodyBlockFlowUnit unit,
    String? path,
    ForumBodyResolvedStyle style,
    ForumBodyParagraphWindow window,
    bool unsupported,
  ) {
    if (!unsupported && !style.visibilityHidden) {
      if (!_headingClosed &&
          _heading == null &&
          path == _headingPath &&
          window == ForumBodyParagraphWindow.full &&
          style.role == ForumBodyTextRole.heading) {
        _heading = unit;
        return;
      }
      if (_headingClosed &&
          style.role == ForumBodyTextRole.body &&
          path == (_followingPath ?? _parentPath(_headingPath))) {
        _following = unit;
        return;
      }
    }
    close();
  }

  int measure(ForumBodyTextPageSession session, {required int maxParts}) {
    final whole = _headingExtent == null;
    final unit = whole ? _heading! : _following!;
    final budget = math.min(maxParts, _formatWorkLeft);
    if (budget == 0) {
      close();
      return 1;
    }
    final double? extent;
    try {
      switch (unit) {
        case ForumBodyBlockFlowParagraph():
          final admission = _plain ??= session._openParagraphPlan(
            unit.paragraph.content,
            unit.contentWidth,
          );
          if (!admission.isReady) {
            final step = admission.advance(maxParts: budget);
            return _charge(step.partsPrepared, step.waitingForLayoutBudget);
          }
          extent = _plainExtent(admission, unit.paragraph.window, whole);
          _plain = null;
        case ForumBodyBlockFlowInline():
          final admission = _inline ??= session._openInlinePlan(unit);
          if (!admission.isReady) {
            final step = admission.advance(maxParts: budget);
            return _charge(step.partsPrepared, step.waitingForLayoutBudget);
          }
          final ready = admission.take();
          _inline = null;
          try {
            final layout = ready.lease.layout;
            final frames = ready.content.fontFrames;
            extent = _extent(
              layout.lineWindow(unit.paragraph.window),
              frames?.lines ?? layout.lines,
              whole,
              (start, end) =>
                  frames?.fragment(start, end).height ??
                  layout.fragment(start, end).height,
            );
          } finally {
            ready.lease.release();
          }
        default:
          throw StateError('Unsupported heading measurement unit');
      }
    } catch (_) {
      // A speculative failure is retried only by normal admission in source
      // order. An optional lookahead must never wait for its own pinned cache.
      close();
      session._ensureActivePlan();
      return 1;
    }
    if (extent == null || !extent.isFinite || extent <= 0) {
      close();
    } else if (whole) {
      _headingExtent = extent;
    } else {
      final occupied = _gap + _headingExtent! + extent;
      session._composer.keepHeadingWithFollower(
        occupiedExtent: occupied,
        freshExtent: occupied - _pageStartTrim,
      );
      close();
    }
    return _charge(1, false);
  }

  int _charge(int parts, bool waiting) {
    final used = math.max(1, parts);
    _formatWorkLeft -= used;
    if (waiting) close();
    return used;
  }

  static double? _plainExtent(
    ForumBodyEmphasisPageAdmission admission,
    ForumBodyParagraphWindow window,
    bool whole,
  ) {
    if (admission.isPlain) {
      final lease = admission.takePlainLease();
      try {
        final layout = lease.layout;
        return _extent(
          layout.lineWindow(window),
          layout.lines,
          whole,
          (start, end) => layout.fragment(start, end).height,
        );
      } finally {
        lease.release();
      }
    }
    if (admission.isFitted) return admission.takeFitted().plan.metrics.height;
    final layout = admission.take().entries.paragraph;
    return _extent(
      layout.lineWindow(window),
      layout.lines,
      whole,
      (start, end) => layout.fragment(start, end).height,
    );
  }

  static double? _extent(
    ({int startLine, int endLine}) range,
    List<ForumBodyParagraphLine> lines,
    bool whole,
    double Function(int, int) height,
  ) {
    final start = range.startLine;
    if (start == range.endLine) return null;
    if (whole) return height(start, range.endLine);
    // Probe a fixed prefix of physical rows, never split a protected group.
    final limit = math.min(range.endLine, start + 4);
    for (var end = start + 1; end <= limit; end++) {
      if (lines[end - 1].canBreakAfter &&
          lines[end - 1].coverageEndUtf16 > lines[start].coverageStartUtf16) {
        return height(start, end);
      }
    }
    return null;
  }

  void close() {
    _plain?.close();
    _plain = null;
    _inline?.close();
    _inline = null;
    isReplaying = true;
  }
}

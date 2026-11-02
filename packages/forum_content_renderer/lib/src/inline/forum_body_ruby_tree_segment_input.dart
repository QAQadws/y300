part of 'forum_body_ruby_tree_input.dart';

/// Original base/gap/annotation order is also the later source-binding order.
/// Physical placement is resolved separately by the shared numeric segment.
final class _SegmentGroupWork extends _TreeWork {
  _SegmentGroupWork(this.group, this.units, this.pairing)
    : columnInputs = [
        for (final unit in units)
          if (unit.kind != ForumBodyRubyBaseInputKind.gap) unit.child,
      ];
  final ForumBodyRubyGroupContent group;
  final List<ForumBodyRubyBaseChildInput> units;
  final List<ForumBodyRubyChildInput> columnInputs;
  final ForumBodyRubyAnnotationPairing pairing;
  final bases = <int>[];
  final spans = <ForumBodyRubyTreeSegmentSpan>[];
  final gaps = <ForumBodyRubyTreeSegmentGap>[];
  final annotationGaps = <ForumBodyRubyTreeSegmentAnnotationGap>[];
  final fences = <ForumBodyRubyTreeSegmentFence>[];
  final children = <ForumBodyRubyTreeSegmentChild>[];
  final spanRanks = <int, List<int>>{};
  final annotationGapRanks = <int, List<int>>{};
  _PendingSegmentChild? pending;
  _GapEdgeWork? gapWork;
  int unit = 0;
  int rank = 0;
  int span = 0;
  int annotationGap = 0;

  @override
  void advance(ForumBodyRubyTreeInputPreparation owner) {
    if (pairing.columnCount == 0) _unsupported(group.rootPath);
    final waiting = pending;
    if (waiting != null) {
      final node = owner._takeChild();
      final index = switch (waiting.kind) {
        ForumBodyRubyTreeSegmentChildKind.base => bases.length,
        ForumBodyRubyTreeSegmentChildKind.span => spans.length,
        ForumBodyRubyTreeSegmentChildKind.gap => gaps.length,
        ForumBodyRubyTreeSegmentChildKind.annotationGap =>
          annotationGaps.length,
        ForumBodyRubyTreeSegmentChildKind.fence => fences.length,
      };
      switch (waiting.kind) {
        case ForumBodyRubyTreeSegmentChildKind.base:
          bases.add(node);
        case ForumBodyRubyTreeSegmentChildKind.span:
          (spanRanks[waiting.rank!] ??= []).add(index);
          spans.add((
            child: node,
            startColumn: waiting.start,
            endColumn: waiting.end,
            rank: waiting.rank!,
          ));
        case ForumBodyRubyTreeSegmentChildKind.gap:
          gaps.add((child: node, beforeColumn: waiting.start));
        case ForumBodyRubyTreeSegmentChildKind.annotationGap:
          (annotationGapRanks[waiting.rank!] ??= []).add(index);
          annotationGaps.add((child: node, beforeSpan: waiting.end));
        case ForumBodyRubyTreeSegmentChildKind.fence:
          fences.add((
            child: node,
            beforeColumn: waiting.start,
            rank: waiting.rank,
          ));
      }
      children.add((node: node, kind: waiting.kind, index: index));
      pending = null;
      return;
    }
    if (unit < units.length) {
      final current = units[unit];
      if (current.kind == ForumBodyRubyBaseInputKind.gap) {
        final content = (current.child as ForumBodyRubyTextChildInput).content;
        final edge = bases.isEmpty || bases.length == columnInputs.length;
        if (!_openGap(
          owner,
          content,
          beforeColumn: bases.length,
          trim: edge,
          previous: edge ? null : columnInputs[bases.length - 1],
          next: edge ? null : columnInputs[bases.length],
        )) {
          return;
        }
      } else {
        final child = current.child;
        if (current.kind == ForumBodyRubyBaseInputKind.implicit &&
            child is ForumBodyRubyTextChildInput &&
            (forumBodyInlineHasCollapsibleEdge(child.content, leading: true) ||
                forumBodyInlineHasCollapsibleEdge(
                  child.content,
                  leading: false,
                ))) {
          _unsupported(child.path);
        }
        pending = const _PendingSegmentChild(
          ForumBodyRubyTreeSegmentChildKind.base,
        );
        owner._stack.add(_ChildWork(child, annotation: false));
      }
      unit++;
      return;
    }
    if (bases.length < pairing.columnCount) {
      pending = const _PendingSegmentChild(
        ForumBodyRubyTreeSegmentChildKind.base,
      );
      owner._stack.add(
        _ChildWork(
          ForumBodyRubyChildInput.implicit(group, const []),
          annotation: false,
        ),
      );
      return;
    }
    if (rank < pairing.levels.length) {
      final level = pairing.levels[rank];
      if (span == level.spans.length) {
        if (annotationGap != level.gaps.length) _unsupported(group.rootPath);
        if (spanRanks.containsKey(rank)) {
          spanRanks[rank] = List.unmodifiable(spanRanks[rank]!);
        }
        if (annotationGapRanks.containsKey(rank)) {
          annotationGapRanks[rank] = List.unmodifiable(
            annotationGapRanks[rank]!,
          );
        }
        rank++;
        span = 0;
        annotationGap = 0;
        return;
      }
      final target = level.spans[span];
      if (annotationGap < level.gaps.length &&
          identical(level.gaps[annotationGap].next, target)) {
        final gap = level.gaps[annotationGap];
        if (!_openGap(
          owner,
          gap.content,
          beforeColumn: gap.beforeColumn,
          rank: rank,
          beforeSpan: spans.length,
          previous: _annotationChild(group, gap.previous.box),
          next: _annotationChild(group, gap.next.box),
        )) {
          return;
        }
        annotationGap++;
        return;
      }
      pending = _PendingSegmentChild(
        ForumBodyRubyTreeSegmentChildKind.span,
        start: target.startColumn,
        end: target.endColumn,
        rank: rank,
      );
      owner._stack.add(
        _ChildWork(_annotationChild(group, target.box), annotation: true),
      );
      span++;
      return;
    }
    owner._finish(
      ForumBodyRubyTreeSegment._(
        ForumBodyRubyRootBoxInput.fromGroup(group),
        ForumBodyRubyContainerBackground.fromGroup(group),
        group,
        bases: bases,
        spans: spans,
        gaps: gaps,
        annotationGaps: annotationGaps,
        fences: fences,
        children: children,
        sides: [for (final level in pairing.levels) level.side],
        spanRanks: spanRanks,
        annotationGapRanks: annotationGapRanks,
      ),
    );
  }

  bool _openGap(
    ForumBodyRubyTreeInputPreparation owner,
    ForumBodyParagraphContent content, {
    required int beforeColumn,
    bool trim = false,
    int? rank,
    int? beforeSpan,
    ForumBodyRubyChildInput? previous,
    ForumBodyRubyChildInput? next,
  }) {
    var actual = content;
    if (trim) {
      final end = content.projection.text.length;
      actual = windowForumBodyInlineText(content, end, end);
    } else if (content.projection.hasCollapsibleSegmentBreaks) {
      final work = gapWork ??= _GapEdgeWork(content, previous!, next!);
      work.advance();
      if (!work.isReady) return false;
      actual = work.result!;
      gapWork = null;
    }
    final kind = actual.projection.text.isEmpty
        ? ForumBodyRubyTreeSegmentChildKind.fence
        : rank == null
        ? ForumBodyRubyTreeSegmentChildKind.gap
        : ForumBodyRubyTreeSegmentChildKind.annotationGap;
    pending = _PendingSegmentChild(
      kind,
      start: beforeColumn,
      end: beforeSpan ?? 0,
      rank: rank,
    );
    owner._stack.add(
      _ChildWork(
        ForumBodyRubyChildInput.implicit(group, [
          ForumBodyRubyTextContent(actual),
        ]),
        annotation: false,
        emptyNeedsNative: false,
      ),
    );
    return true;
  }

  @override
  void close() {
    gapWork = null;
    pending = null;
  }
}

final class _PendingSegmentChild {
  const _PendingSegmentChild(
    this.kind, {
    this.start = 0,
    this.end = 0,
    this.rank,
  });
  final ForumBodyRubyTreeSegmentChildKind kind;
  final int start;
  final int end;
  final int? rank;
}

/// Probe only the child's actual base-facing text edge. Nested annotation text
/// cannot decide whether a base-level CJK segment break should disappear.
final class _ChildTextEdge {
  _ChildTextEdge(ForumBodyRubyChildInput input, this.leading)
    : frames = [_parts(input, leading)];
  final bool leading;
  final List<Iterator<ForumBodyRubyInlineContent>> frames;
  bool isReady = false;
  String? result;
  static Iterator<ForumBodyRubyInlineContent> _parts(
    ForumBodyRubyChildInput input,
    bool leading,
  ) {
    final parts = switch (input) {
      ForumBodyRubyTextChildInput(:final content) => [
        ForumBodyRubyTextContent(content),
      ],
      ForumBodyRubySequenceChildInput(:final parts) => parts,
    };
    return (leading ? parts : parts.reversed).iterator;
  }

  void advance() {
    if (isReady) throw StateError('Ruby text edge is complete');
    if (frames.isEmpty) {
      isReady = true;
      return;
    }
    final cursor = frames.last;
    if (!cursor.moveNext()) {
      frames.removeLast();
      return;
    }
    final part = cursor.current;
    switch (part) {
      case ForumBodyRubyTextContent(:final content):
        final value = leading
            ? content.projection.firstGrapheme
            : content.projection.lastGrapheme;
        if (value != null) {
          result = value;
          isReady = true;
          frames.clear();
        }
      case ForumBodyRubyBaseContent(:final parts):
        frames.add((leading ? parts : parts.reversed).iterator);
      case ForumBodyRubyNestedContent(:final groups):
        final values = (leading ? groups : groups.reversed).expand(
          (group) => leading ? group.base : group.base.reversed,
        );
        frames.add(values.iterator);
      case ForumBodyRubyAnnotationContent():
        _unsupported(part.path);
    }
  }
}

final class _GapEdgeWork {
  _GapEdgeWork(
    this.gap,
    ForumBodyRubyChildInput previous,
    ForumBodyRubyChildInput next,
  ) : before = _ChildTextEdge(previous, false),
      after = _ChildTextEdge(next, true);
  final ForumBodyParagraphContent gap;
  final _ChildTextEdge before;
  final _ChildTextEdge after;
  ForumBodyParagraphContent? result;
  bool get isReady => result != null;
  void advance() {
    if (!before.isReady) {
      before.advance();
      return;
    }
    if (!after.isReady) {
      after.advance();
      return;
    }
    result = resolveForumBodyRubyGapWhitespaceAtEdges(
      gap: gap,
      precedingGrapheme: before.result,
      followingGrapheme: after.result,
    );
  }
}

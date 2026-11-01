part of 'forum_body_ruby_segment_layout.dart';

typedef ForumBodyRubySegmentColumnInput = ({
  ForumBodyParagraphContent base,
  List<ForumBodyParagraphContent> annotations,
});

enum _SegmentAssemblyState { active, ready, transferred, failed, closed }

/// Shared ownership transaction for synchronous adoption and cooperative
/// preparation. A column header and EACH actual rank are separate units; one
/// spanning glyph is measured only when that member is consumed, never again
/// at publication. Native acquisition/picture preparation stays with the host.
final class ForumBodyRubySegmentAssembly {
  ForumBodyRubySegmentAssembly({
    required ForumBodyParagraphCache cache,
    required ForumBodyRubySegmentMetrics metrics,
    required List<ForumBodyRubySegmentColumnInput> columns,
    required List<ForumBodyParagraphContent> spans,
    List<ForumBodyRubySegmentColumnInput> gaps = const [],
    List<ForumBodyParagraphContent> annotationGaps = const [],
    void Function()? ensureOwner,
  }) : _cache = cache,
       _metrics = metrics,
       _ensureOwner = ensureOwner,
       _columnInputs = [
         for (final column in columns)
           (
             base: column.base,
             annotations: List.unmodifiable(column.annotations),
           ),
       ],
       _spanInputs = List.of(spans) {
    _annotationGapInputs = List.of(annotationGaps);
    _gapInputs = [
      for (final gap in gaps)
        (base: gap.base, annotations: List.unmodifiable(gap.annotations)),
    ];
    if (columns.isEmpty ||
        columns.length != metrics.columns.length ||
        spans.length != metrics.spans.length ||
        gaps.length != metrics.gaps.length) {
      ForumBodyRubySegmentLayout._invalid();
    }
    if (annotationGaps.length != metrics.annotationGaps.length) {
      ForumBodyRubySegmentLayout._invalid();
    }
  }
  ForumBodyParagraphCache? _cache;
  ForumBodyRubySegmentMetrics? _metrics;
  void Function()? _ensureOwner;
  List<ForumBodyRubySegmentColumnInput> _columnInputs;
  List<ForumBodyParagraphContent> _spanInputs;
  List<ForumBodyParagraphContent> _annotationGapInputs = [];
  List<ForumBodyRubySegmentColumnInput> _gapInputs = [];
  List<ForumBodyRubyGroupLayout> _columns = [];
  List<ForumBodyRubySegmentAnnotation> _spans = [];
  List<ForumBodyRubySegmentAnnotation> _annotationGaps = [];
  List<ForumBodyRubyGroupLayout> _gaps = [];
  Map<int, List<int>> _spanRanks = {};
  Map<int, List<int>> _annotationGapRanks = {};
  final _handles = Set<ForumBodyTextLease>.identity();
  ForumBodyRubyGroupLayout? _pendingColumn;
  ForumBodyRubyGroupMemberSnapshot? _members;
  ForumBodyRubySegmentAnnotation? _pendingSpan;
  var _rank = 0;
  var _headerChecked = false;
  var _pendingGap = false;
  var _pendingAnnotationGap = false;
  var _state = _SegmentAssemblyState.active;
  var _operating = false;
  bool get isReady => _state == _SegmentAssemblyState.ready;
  bool get hasPendingMember => _pendingColumn != null || _pendingSpan != null;
  int get preparedColumnCount => _columns.length;
  int get preparedSpanCount => _spans.length;
  int get preparedGapCount => _gaps.length;
  int get preparedAnnotationGapCount => _annotationGaps.length;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    for (final column in _columns) ...column.nativeLeases,
    for (final gap in _gaps) ...gap.nativeLeases,
    if (_pendingColumn != null) ..._pendingColumn!.nativeLeases,
    for (final span in _spans) ?span.lease,
    for (final gap in _annotationGaps) ?gap.lease,
    ?_pendingSpan?.lease,
  ];

  void addColumn(ForumBodyRubyGroupLayout column) {
    try {
      _operate(() {
        _guard();
        if (_state != _SegmentAssemblyState.active ||
            hasPendingMember ||
            _columns.length >= _columnInputs.length ||
            _spans.isNotEmpty) {
          throw StateError('Ruby segment cannot accept a column');
        }
        _pendingColumn = column;
        _pendingGap = false;
        _members = column.inspectMembers();
        _headerChecked = false;
        _rank = 0;
      });
    } catch (_) {
      column.close();
      rethrow;
    }
  }

  void addGap(ForumBodyRubyGroupLayout gap) {
    try {
      _operate(() {
        _guard();
        if (_state != _SegmentAssemblyState.active ||
            hasPendingMember ||
            _columns.length != _columnInputs.length ||
            _gaps.length >= _gapInputs.length ||
            _spans.isNotEmpty) {
          throw StateError('Ruby segment cannot accept a gap');
        }
        _pendingColumn = gap;
        _pendingGap = true;
        _members = gap.inspectMembers();
        _headerChecked = false;
        _rank = 0;
      });
    } catch (_) {
      gap.close();
      rethrow;
    }
  }

  void addSpan(ForumBodyRubySegmentAnnotation span) {
    try {
      _operate(() {
        _guard();
        if (_state != _SegmentAssemblyState.active ||
            hasPendingMember ||
            _columns.length != _columnInputs.length ||
            _gaps.length != _gapInputs.length ||
            _spans.length >= _spanInputs.length) {
          throw StateError('Ruby segment cannot accept an annotation');
        }
        _pendingSpan = span;
        _pendingAnnotationGap = false;
      });
    } catch (_) {
      span.lease?.release();
      rethrow;
    }
  }

  void addAnnotationGap(ForumBodyRubySegmentAnnotation gap) {
    try {
      _operate(() {
        _guard();
        if (_state != _SegmentAssemblyState.active ||
            hasPendingMember ||
            _columns.length != _columnInputs.length ||
            _gaps.length != _gapInputs.length ||
            _spans.length != _spanInputs.length ||
            _annotationGaps.length >= _annotationGapInputs.length) {
          throw StateError('Ruby segment cannot accept an annotation gap');
        }
        _pendingSpan = gap;
        _pendingAnnotationGap = true;
      });
    } catch (_) {
      gap.lease?.release();
      rethrow;
    }
  }

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      if (_state != _SegmentAssemblyState.active) {
        throw StateError('Ruby segment assembly is not active');
      }
      var work = 0;
      while (work < maxParts && hasPendingMember) {
        if (_pendingColumn != null) {
          _advanceColumn();
        } else {
          _advanceSpan();
        }
        work++;
        _guard();
      }
      if (!hasPendingMember &&
          _columns.length == _columnInputs.length &&
          _gaps.length == _gapInputs.length &&
          _spans.length == _spanInputs.length &&
          _annotationGaps.length == _annotationGapInputs.length &&
          work < maxParts) {
        // Publication is a real unit even when the previous quantum ended
        // exactly on its final member. No member/glyph is measured here.
        _guard();
        _state = _SegmentAssemblyState.ready;
        work++;
      }
      return work;
    });
  }

  void _advanceColumn() {
    final column = _pendingColumn!;
    final members = _members!;
    final index = _pendingGap ? _gaps.length : _columns.length;
    final expected = _pendingGap ? _gapInputs[index] : _columnInputs[index];
    final target = _pendingGap
        ? _metrics!.gaps[index].font
        : _metrics!.columns[index];
    if (!_headerChecked) {
      _own(members.base);
      if (!identical(members.base.content, expected.base)) {
        ForumBodyRubySegmentLayout._invalid(ForumBodyRubyGroupFailure.content);
      }
      if (members.annotations.length != expected.annotations.length ||
          members.annotations.length != target.annotations.length ||
          !ForumBodyRubySegmentLayout._sameColumnHeader(
            column.metrics,
            target,
          )) {
        ForumBodyRubySegmentLayout._invalid();
      }
      _headerChecked = true;
    } else {
      final item = members.annotations[_rank];
      if (_pendingGap &&
          (item.lease != null || item.content.projection.text.isNotEmpty)) {
        ForumBodyRubySegmentLayout._invalid(ForumBodyRubyGroupFailure.content);
      }
      if (!identical(item.content, expected.annotations[_rank]) ||
          item.content.projection.text.isNotEmpty != (item.lease != null) ||
          (item.lease != null &&
              !identical(item.lease!.content, item.content))) {
        ForumBodyRubySegmentLayout._invalid(ForumBodyRubyGroupFailure.content);
      }
      if (!ForumBodyRubySegmentLayout._sameScope(expected.base, item.content)) {
        ForumBodyRubySegmentLayout._invalid(ForumBodyRubyGroupFailure.scope);
      }
      if (item.lease != null) _own(item.lease!);
      if (!ForumBodyRubySegmentLayout._sameAnnotation(
        column.metrics.annotations[_rank],
        target.annotations[_rank],
      )) {
        ForumBodyRubySegmentLayout._invalid();
      }
      _rank++;
    }
    if (_headerChecked && _rank == members.annotations.length) {
      (_pendingGap ? _gaps : _columns).add(column);
      _pendingColumn = null;
      _members = null;
    }
  }

  void _advanceSpan() {
    final item = _pendingSpan!;
    final index = _pendingAnnotationGap
        ? _annotationGaps.length
        : _spans.length;
    final expected = _pendingAnnotationGap
        ? _metrics!.annotationGaps[index].input.annotation
        : _metrics!.spans[index].input.annotation;
    final scope = _columnInputs.first.base;
    if (!identical(
          item.content,
          _pendingAnnotationGap
              ? _annotationGapInputs[index]
              : _spanInputs[index],
        ) ||
        item.content.projection.text.isNotEmpty != (item.lease != null) ||
        (item.lease != null && !identical(item.lease!.content, item.content))) {
      ForumBodyRubySegmentLayout._invalid(ForumBodyRubyGroupFailure.content);
    }
    if (!ForumBodyRubySegmentLayout._sameScope(scope, item.content) ||
        item.content.layoutMode !=
            ForumBodyParagraphLayoutMode.intrinsicSingleLine) {
      ForumBodyRubySegmentLayout._invalid(ForumBodyRubyGroupFailure.scope);
    }
    if (item.lease != null) _own(item.lease!);
    final actual = ForumBodyRubyAnnotationMetrics.measure(
      cache: _cache!,
      lease: item.lease,
      side: expected.side,
      gap: expected.gap,
    );
    if (!ForumBodyRubySegmentLayout._sameAnnotation(
      actual,
      expected,
      positions: false,
    )) {
      ForumBodyRubySegmentLayout._invalid();
    }
    if (_pendingAnnotationGap) {
      (_annotationGapRanks[_metrics!
                  .annotationGaps[index]
                  .input
                  .annotationIndex] ??=
              [])
          .add(index);
      _annotationGaps.add(item);
    } else {
      (_spanRanks[_metrics!.spans[index].input.annotationIndex] ??= []).add(
        index,
      );
      _spans.add(item);
    }
    _pendingSpan = null;
  }

  void _own(ForumBodyTextLease lease) {
    if (!_cache!.ownsLease(lease) || !lease.layout.isPaintPrepared) {
      throw StateError('Ruby segment member is not readable in this owner');
    }
    final content = lease.content;
    if (!ForumBodyRubySegmentLayout._sameScope(
      _columnInputs.first.base,
      content,
    )) {
      ForumBodyRubySegmentLayout._invalid(ForumBodyRubyGroupFailure.scope);
    }
    if (!_handles.add(lease)) {
      ForumBodyRubySegmentLayout._invalid(ForumBodyRubyGroupFailure.content);
    }
  }

  ForumBodyRubySegmentLayout takeLayout() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby segment assembly is incomplete');
    final result = ForumBodyRubySegmentLayout._(
      _columns,
      _spans,
      _metrics!,
      _spanRanks,
      _gaps,
      _annotationGaps,
      _annotationGapRanks,
    );
    _columns = [];
    _gaps = [];
    _annotationGaps = [];
    _spans = [];
    _spanRanks = {};
    _annotationGapRanks = {};
    _state = _SegmentAssemblyState.transferred;
    _dropOwner();
    return result;
  });

  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Ruby segment assembly operation is reentrant');
    }
    _operating = true;
    try {
      return action();
    } catch (_) {
      _retire(_SegmentAssemblyState.failed);
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != _SegmentAssemblyState.active && !isReady) {
      throw StateError('Ruby segment assembly is retired');
    }
    _ensureOwner?.call();
    if ((_state != _SegmentAssemblyState.active && !isReady) ||
        _cache!.isClosed) {
      throw StateError('Ruby segment assembly owner is retired');
    }
    for (final handle in _handles) {
      if (!_cache!.ownsLease(handle) || !handle.layout.isPaintPrepared) {
        throw StateError('Ruby segment assembly member is retired');
      }
    }
  }

  void _retire(_SegmentAssemblyState state) {
    if (_state != _SegmentAssemblyState.active && !isReady) return;
    _state = state;
    _pendingColumn?.close();
    _pendingColumn = null;
    _pendingSpan?.lease?.release();
    _pendingSpan = null;
    for (final column in _columns) {
      column.close();
    }
    for (final gap in _gaps) {
      gap.close();
    }
    for (final span in _spans) {
      span.lease?.release();
    }
    for (final gap in _annotationGaps) {
      gap.lease?.release();
    }
    _columns = [];
    _gaps = [];
    _annotationGaps = [];
    _spans = [];
    _spanRanks.clear();
    _annotationGapRanks.clear();
    _dropOwner();
  }

  void _dropOwner() {
    _cache = null;
    _metrics = null;
    _ensureOwner = null;
    _members = null;
    _columnInputs = const [];
    _gapInputs = const [];
    _spanInputs = const [];
    _annotationGapInputs = const [];
    _handles.clear();
  }

  void close() => _retire(_SegmentAssemblyState.closed);
}

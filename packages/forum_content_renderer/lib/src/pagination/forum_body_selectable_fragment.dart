import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../services/forum_http_text_link_detector.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_selectable_text.dart';
import 'forum_body_text_glyph_hit.dart';
import 'forum_body_text_highlight.dart';
import 'forum_body_text_page_composer.dart';

/// Collects selection across the mounted slices of one native flow. Flutter
/// still dispatches gestures through each scrollable and page container.
final class ForumBodyFlowSelectionScope extends StatefulWidget {
  const ForumBodyFlowSelectionScope({required this.child, super.key});

  final Widget child;

  @override
  ForumBodyFlowSelectionScopeState createState() =>
      ForumBodyFlowSelectionScopeState();
}

final class ForumBodyFlowSelectionScopeState
    extends State<ForumBodyFlowSelectionScope> {
  final _delegate = _FlowSelectionDelegate();

  /// True after an explicit Select All, even if the view only mounts a slice.
  bool get isWholeBodySelected => _delegate.selectedAll;

  /// Live copy payload. Retired or unmounted deliveries contribute nothing.
  String? get selectedText => _delegate.getSelectedContent()?.plainText;

  /// Source endpoints of the live selection. The value retains no layout or
  /// view; a host must qualify it against its own current document and layout.
  ForumBodySourceRange? get selectedSourceRange =>
      _delegate.selectedSourceRange;

  /// Verifies a detected occurrence using the live selected display ranges.
  /// The detector's offsets address [selectedText], including paragraph breaks.
  bool confirmsSelectedLink(ForumHttpTextLink link) =>
      _delegate.confirmsSelectedLink(link);

  static _FlowSelectionDelegate? _of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_FlowSelectionRegistry>()
      ?.delegate;

  @override
  Widget build(BuildContext context) => SelectionContainer(
    delegate: _delegate,
    child: _FlowSelectionRegistry(delegate: _delegate, child: widget.child),
  );

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }
}

final class _FlowSelectionRegistry extends InheritedWidget {
  const _FlowSelectionRegistry({required this.delegate, required super.child});

  final _FlowSelectionDelegate delegate;

  @override
  bool updateShouldNotify(_FlowSelectionRegistry oldWidget) =>
      delegate != oldWidget.delegate;
}

final class _FlowSelectionDelegate extends StaticSelectionContainerDelegate {
  final fragments = <_RenderSelectableFragment>{};
  bool selectedAll = false;

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    selectedAll = event is SelectAllSelectionEvent;
    return super.dispatchSelectionEvent(event);
  }

  List<_RenderSelectableFragment> get _selected =>
      fragments
          .where(
            (fragment) => fragment.value.status == SelectionStatus.uncollapsed,
          )
          .toList()
        ..sort((a, b) {
          final first = a._input.fragment;
          final second = b._input.fragment;
          final order = (first.sourceHint?.runeStart ?? -1).compareTo(
            second.sourceHint?.runeStart ?? -1,
          );
          return order != 0 ? order : compareOrder(a, b);
        });

  @override
  SelectedContent? getSelectedContent() => _joinSelected(_selected);

  @override
  void add(Selectable selectable) {
    super.add(selectable);
    final binding = SchedulerBinding.instance;
    // A nested scroll container can register after a frame's microtasks.
    // The delegate queues the update but an idle viewport may need a frame.
    if (binding.schedulerPhase == SchedulerPhase.idle) {
      binding.ensureVisualUpdate();
    }
  }

  @override
  void didChangeSelectables() {
    final hadContent = value.hasContent;
    super.didChangeSelectables();
    if (!hadContent && value.hasContent) {
      // The enclosing selection listener and region can still need to
      // register after this callback makes the first slice selectable.
      SchedulerBinding.instance.ensureVisualUpdate();
    }
  }

  ForumBodySourceRange? get selectedSourceRange {
    final selected = _selected;
    final identity = selected.firstOrNull?._input.sourceIdentity;
    if (identity == null ||
        selected.any((item) => item._input.sourceIdentity != identity)) {
      return null;
    }
    int? start, end;
    for (final (binding, range) in _selectionPieces(selected)) {
      if (binding == null) continue;
      final source = binding.projection.sourceEnvelope(
        startUtf16: range.start,
        endUtf16: range.end,
      )!;
      start = math.min(start ?? source.runeStart, source.runeStart);
      end = math.max(end ?? source.runeEnd, source.runeEnd);
    }
    if (start == null || end == null || end <= start) return null;
    return ForumBodySourceRange(identity, start, end);
  }

  bool confirmsSelectedLink(ForumHttpTextLink link) {
    if (link.start < 0 || link.start >= link.end) return false;
    HtmlDisplayTextProjection? projection;
    var selectedOffset = 0;
    var displayStart = 0, displayEnd = 0;
    for (final (binding, range) in _selectionPieces(_selected)) {
      final next = selectedOffset + (range.end - range.start);
      if (next > link.start && selectedOffset < link.end) {
        if (binding == null) return false;
        final start =
            range.start + math.max<int>(0, link.start - selectedOffset);
        final end =
            range.start + math.min<int>(next, link.end) - selectedOffset;
        if (projection == null) {
          projection = binding.projection;
          displayStart = start;
        } else if (!identical(binding.projection, projection) ||
            start != displayEnd) {
          return false;
        }
        displayEnd = end;
        // Inline resources occupy an engine slot but no display text units.
        if (binding is ForumBodyPreparedInlineFragment &&
            binding.view.content.images.keys.any((index) {
              final offset = binding
                  .view
                  .content
                  .projection
                  .atoms[index]
                  .displayStartUtf16;
              return displayStart < offset && offset < end;
            })) {
          return false;
        }
      }
      selectedOffset = next;
      if (next >= link.end) break;
    }
    if (projection == null || selectedOffset < link.end) return false;
    final text = projection.text;
    final breaks = projection.collapsibleSegmentBreakOffsets;
    var evidence = text;
    if (breaks.isNotEmpty) {
      final units = text.codeUnits.toList();
      for (final offset in breaks) {
        units[offset] = 0x0A;
      }
      evidence = String.fromCharCodes(units);
    }
    final scan = const ForumHttpTextLinkDetector().detect(
      evidence,
      maxCandidates: evidence.length,
    );
    return !scan.isLimited &&
        scan.links.any(
          (candidate) =>
              candidate.start == displayStart &&
              candidate.end == displayEnd &&
              candidate.text == link.text,
        );
  }
}

/// Keeps paragraph separators local to the active page's selected fragments.
final class ForumBodyPageSelectionScope extends StatefulWidget {
  const ForumBodyPageSelectionScope({required this.child, super.key});

  final Widget child;

  @override
  State<ForumBodyPageSelectionScope> createState() =>
      _PageSelectionScopeState();
}

final class _PageSelectionScopeState
    extends State<ForumBodyPageSelectionScope> {
  final _delegate = _PageSelectionDelegate();

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }
}

final class _PageSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  Comparator<Selectable> get compareOrder => (a, b) {
    if (a is _RenderSelectableFragment && b is _RenderSelectableFragment) {
      final first = a._input.columnOrder;
      final second = b._input.columnOrder;
      if (first != null && second != null) {
        return first.fragmentIndex.compareTo(second.fragmentIndex);
      }
    }
    return super.compareOrder(a, b);
  };

  @override
  SelectedContent? getSelectedContent() =>
      _joinSelected(selectables.whereType<_RenderSelectableFragment>());
}

SelectedContent? _joinSelected(Iterable<_RenderSelectableFragment> selected) {
  final output = StringBuffer();
  for (final (binding, range) in _selectionPieces(selected)) {
    output.write(
      binding == null ? '\n' : range.textInside(binding.projection.text),
    );
  }
  return output.isEmpty ? null : SelectedContent(plainText: output.toString());
}

Iterable<(ForumBodyPreparedTextFragment?, TextRange)> _selectionPieces(
  Iterable<_RenderSelectableFragment> selected,
) sync* {
  ForumBodyTextPageFragment? previous;
  var endsWithBreak = false;
  for (final selectable in selected) {
    if (selectable.value.status != SelectionStatus.uncollapsed) continue;
    final binding = selectable._input.binding;
    final text = binding.projection.text;
    final current = selectable._input.fragment;
    final base = selectable._base!, extent = selectable._extent!;
    final ranges = selectable._text!.intersection(
      math.min(base, extent),
      math.max(base, extent),
    );
    for (final range in ranges) {
      if (previous != null &&
          previous.path != current.path &&
          !endsWithBreak &&
          text.codeUnitAt(range.start) != 0x0A) {
        yield (null, const TextRange(start: 0, end: 1));
      }
      yield (binding, range);
      previous = current;
      endsWithBreak = text.codeUnitAt(range.end - 1) == 0x0A;
    }
  }
}

/// Registers the exact mounted native fragment with Flutter's selection area.
/// This render object borrows the painted delivery and never owns its leases.
final class ForumBodySelectableFragment extends SingleChildRenderObjectWidget {
  const ForumBodySelectableFragment({
    required this.binding,
    required this.fragment,
    required this.pageSize,
    required this.sourceIdentity,
    required this.identity,
    required this.registrar,
    required super.child,
    this.columnOrder,
    super.key,
  });

  final ForumBodyPreparedTextFragment binding;
  final ForumBodyTextPageFragment fragment;
  final Size pageSize;
  final ForumBodyIdentity sourceIdentity;
  final Object identity;
  final SelectionRegistrar? registrar;
  final ({ForumBodyPageColumns geometry, int fragmentIndex})? columnOrder;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSelectableFragment(this, _color(context), _flowSelection(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSelectableFragment).update(
      this,
      _color(context),
      _flowSelection(context),
    );
  }

  _FlowSelectionDelegate? _flowSelection(BuildContext context) =>
      registrar == null ? null : ForumBodyFlowSelectionScopeState._of(context);

  Color _color(BuildContext context) => registrar == null
      ? const Color(0x00000000)
      : DefaultSelectionStyle.of(context).selectionColor ??
            const Color(0x663F51B5);
}

final class _RenderSelectableFragment extends RenderProxyBox
    with Selectable, SelectionRegistrant {
  _RenderSelectableFragment(this._input, this._color, this._flow);

  ForumBodySelectableFragment _input;
  Color _color;
  _FlowSelectionDelegate? _flow;
  ForumBodySelectableText? _text;
  List<Rect> _bounds = const [];
  Rect _hitBounds = Rect.zero;
  Rect _clip = Rect.zero;
  final _geometry = ValueNotifier<SelectionGeometry>(_empty);
  int? _base, _extent;
  LayerLink? _startHandle, _endHandle;
  static const _empty = SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: false,
  );

  void update(
    ForumBodySelectableFragment input,
    Color color,
    _FlowSelectionDelegate? flow,
  ) {
    final changed =
        input.identity != _input.identity ||
        input.sourceIdentity != _input.sourceIdentity ||
        !identical(input.binding, _input.binding) ||
        input.pageSize != _input.pageSize ||
        input.registrar != _input.registrar ||
        flow != _flow;
    if (changed) _retire();
    _input = input;
    _flow = flow;
    if (_color != color) {
      _color = color;
      markNeedsPaint();
    }
    if (changed) markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_text != null || _input.registrar == null || !_input.binding.isActive) {
      return;
    }
    final fragment = _input.fragment;
    final binding = _input.binding;
    _clip = (Offset.zero & size).intersect(
      Rect.fromLTWH(
        -fragment.left,
        -fragment.top,
        _input.pageSize.width,
        _input.pageSize.height,
      ),
    );
    final ranges = forumBodyVisibleTextRanges(
      binding.projection,
      binding.runs,
      fragment.coverageStartUtf16,
      fragment.coverageEndUtf16,
      includeAnnotations: false,
    )!;
    if (ranges.isEmpty) return;
    _text = ForumBodySelectableText(binding.projection, ranges);
    _bounds = [
      for (final box in _boxes(_text!.start, _text!.end)) box.toRect(),
    ];
    if (_bounds.isEmpty) return;
    _hitBounds = _bounds.reduce((a, b) => a.expandToInclude(b));
    _updateGeometry();
    _flow?.fragments.add(this);
    registrar = _input.registrar;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_input.registrar != null) markNeedsLayout();
  }

  void _retire() {
    _flow?.fragments.remove(this);
    registrar = null;
    _text = null;
    _bounds = const [];
    _base = _extent = null;
    pushHandleLayers(null, null);
    _updateGeometry();
  }

  @override
  void detach() {
    _retire();
    super.detach();
  }

  @override
  void dispose() {
    _retire();
    _geometry.dispose();
    super.dispose();
  }

  @override
  void addListener(VoidCallback listener) => _geometry.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _geometry.removeListener(listener);

  @override
  SelectionGeometry get value =>
      _input.binding.isActive ? _geometry.value : _empty;

  @override
  List<Rect> get boundingBoxes => value.hasContent ? _bounds : const [];

  @override
  int get contentLength => value.hasContent ? _text!.length : 0;

  Iterable<TextBox> _boxes(int start, int end) sync* {
    for (final range in _text!.intersection(start, end)) {
      for (final box in _input.binding.glyphBoxes(range.start, range.end)) {
        final rect = box.toRect().intersect(_clip);
        if (!rect.isEmpty) {
          yield TextBox.fromLTRBD(
            rect.left,
            rect.top,
            rect.right,
            rect.bottom,
            box.direction,
          );
        }
      }
    }
  }

  @override
  SelectedContentRange? getSelection() {
    if (!value.hasSelection) return null;
    return SelectedContentRange(
      startOffset: _text!.offsetAt(_base!),
      endOffset: _text!.offsetAt(_extent!),
    );
  }

  @override
  SelectedContent? getSelectedContent() {
    if (value.status != SelectionStatus.uncollapsed) return null;
    final text = _text!.copy(
      math.min(_base!, _extent!),
      math.max(_base!, _extent!),
    );
    return text.isEmpty ? null : SelectedContent(plainText: text);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (!value.hasContent || !attached) return SelectionResult.none;
    final result = switch (event) {
      ClearSelectionEvent() => _select(null, null),
      SelectAllSelectionEvent() => _select(_text!.start, _text!.end),
      SelectWordSelectionEvent(:final globalPosition) => _selectAt(
        globalPosition,
      ),
      SelectParagraphSelectionEvent(:final globalPosition, :final absorb) =>
        absorb
            ? _select(_text!.start, _text!.end, SelectionResult.next)
            : _selectAt(globalPosition, paragraph: true),
      SelectionEdgeUpdateEvent() => _moveEdge(event),
      GranularlyExtendSelectionEvent() => _extend(event),
      DirectionallyExtendSelectionEvent() => _extendLine(event),
      _ => SelectionResult.none,
    };
    _updateGeometry();
    return result;
  }

  SelectionResult _select(
    int? base,
    int? extent, [
    SelectionResult result = SelectionResult.end,
  ]) {
    _base = base;
    _extent = extent;
    return result;
  }

  SelectionResult _selectAt(Offset global, {bool paragraph = false}) {
    final hit = ForumBodyTextGlyphHit.at(
      binding: _input.binding,
      fragment: _input.fragment,
      pageSize: _input.pageSize,
      point: globalToLocal(global),
      requireExactSource: false,
    );
    if (hit == null) return SelectionResult.none;
    for (final range in hit.paintedRanges) {
      if (_text!.offsetAt(range.start) == _text!.offsetAt(range.end)) continue;
      final word = paragraph
          ? TextRange(start: _text!.start, end: _text!.end)
          : _text!.wordAt(range.start);
      return _select(word.start, word.end);
    }
    return SelectionResult.none;
  }

  ForumBodyPreparedTextFragment get _body {
    final body = _input.binding;
    return body is ForumBodyPreparedListItemFragment ? body.body : body;
  }

  int _caret(Offset local, {required bool forward}) {
    final text = _text!;
    if (local.dy < _hitBounds.top) return text.start;
    if (local.dy >= _hitBounds.bottom) return text.end;
    final display = ForumBodySelectableText.caretAt(_body, local) ?? text.start;
    return text.snap(display, forward: forward);
  }

  SelectionResult _setEdge(int position, {required bool isEnd}) {
    if (isEnd) {
      _base ??= position;
      _extent = position;
    } else {
      _extent ??= position;
      _base = position;
    }
    if (position <= _text!.start) return SelectionResult.previous;
    if (position >= _text!.end) return SelectionResult.next;
    return SelectionResult.end;
  }

  SelectionResult _moveEdge(SelectionEdgeUpdateEvent event) {
    final isEnd = event.type == SelectionEventType.endEdgeUpdate;
    final local = globalToLocal(event.globalPosition);
    if (!local.isFinite) return SelectionResult.none;
    final text = _text!;
    if (_input.columnOrder case final order?) {
      final fragment = _input.fragment;
      final width = _input.pageSize.width;
      final column = order.geometry.indexAt(
        width,
        fragment.left + fragment.width / 2,
      );
      final target = order.geometry.indexAt(width, fragment.left + local.dx);
      // The target's column takes precedence over its vertical position.
      // A drag from the bottom of a column can continue at the next one's top.
      if (target != column) {
        return _setEdge(target < column ? text.start : text.end, isEnd: isEnd);
      }
    }
    final other = isEnd ? _base : _extent;
    var position = _caret(local, forward: isEnd);
    if (event.granularity == TextGranularity.word &&
        position > text.start &&
        position < text.end) {
      final forward = other == null ? isEnd : position >= other;
      final glyph = text.adjacentGlyph(position, forward: !forward);
      if (glyph != null) {
        final word = text.wordAt(glyph);
        position = forward ? word.end : word.start;
      }
    }
    return _setEdge(position, isEnd: isEnd);
  }

  SelectionResult _extend(GranularlyExtendSelectionEvent event) {
    final text = _text!;
    final current =
        (event.isEnd ? _extent : _base) ??
        (event.forward ? text.start : text.end);
    final limit = event.forward ? text.end : text.start;
    if (current == limit) return _setEdge(limit, isEnd: event.isEnd);
    final position = switch (event.granularity) {
      TextGranularity.character => text.step(current, forward: event.forward),
      TextGranularity.word => text.step(
        current,
        forward: event.forward,
        word: true,
      ),
      TextGranularity.line => _lineBoundary(current, forward: event.forward),
      TextGranularity.paragraph || TextGranularity.document => limit,
    };
    return _setEdge(position, isEnd: event.isEnd);
  }

  int _lineBoundary(int current, {required bool forward}) {
    for (final line in _body.lines) {
      if (current < line.coverageStartUtf16 ||
          current > line.coverageEndUtf16) {
        continue;
      }
      final edge = forward ? line.coverageEndUtf16 : line.coverageStartUtf16;
      if (edge != current) return _text!.snap(edge, forward: forward);
    }
    return forward ? _text!.end : _text!.start;
  }

  SelectionResult _extendLine(DirectionallyExtendSelectionEvent event) {
    final rows = _body.lines.toList();
    if (rows.isEmpty || !event.dx.isFinite) return SelectionResult.none;
    final forward = switch (event.direction) {
      SelectionExtendDirection.nextLine ||
      SelectionExtendDirection.forward => true,
      _ => false,
    };
    final point = event.isEnd
        ? value.endSelectionPoint
        : value.startSelectionPoint;
    final y = point?.localPosition.dy;
    var index = y == null
        ? (forward ? 0 : rows.length - 1)
        : rows.indexWhere((row) => y <= row.bottom).clamp(0, rows.length - 1);
    switch (event.direction) {
      case SelectionExtendDirection.nextLine:
        if (y != null) index++;
      case SelectionExtendDirection.previousLine:
        if (y != null) index--;
      case SelectionExtendDirection.forward:
      case SelectionExtendDirection.backward:
        break;
    }
    if (index < 0 || index >= rows.length) {
      return _setEdge(forward ? _text!.end : _text!.start, isEnd: event.isEnd);
    }
    final row = rows[index];
    final rowY = (row.top + row.bottom) / 2;
    final globalY = localToGlobal(Offset(0, rowY)).dy;
    final pointOnRow = globalToLocal(Offset(event.dx, globalY));
    _setEdge(_caret(pointOnRow, forward: forward), isEnd: event.isEnd);
    return SelectionResult.end;
  }

  SelectionPoint? _handle(
    int position, {
    required bool leading,
    required bool collapsed,
  }) {
    final text = _text!;
    var forward = (leading && position < text.end) || position <= text.start;
    final step = text.step(position, forward: forward);
    var box = _boxes(
      math.min(position, step),
      math.max(position, step),
    ).firstOrNull;
    if (box == null) {
      // Line breaks and trimmed wrap spaces still count in the copy range,
      // but a Flutter selection edge needs the nearest painted box.
      TextBox? nearest(bool after) => after
          ? _boxes(position, text.end).firstOrNull
          : _boxes(text.start, position).lastOrNull;
      box = nearest(forward);
      if (box == null) {
        forward = !forward;
        box = nearest(forward);
      }
      if (box == null) return null;
    }
    final left = forward == (box.direction == TextDirection.ltr);
    return SelectionPoint(
      localPosition: Offset(left ? box.left : box.right, box.bottom),
      lineHeight: box.bottom - box.top,
      handleType: collapsed
          ? TextSelectionHandleType.collapsed
          : left
          ? TextSelectionHandleType.left
          : TextSelectionHandleType.right,
    );
  }

  void _updateGeometry() {
    final SelectionGeometry next;
    if (_text == null || _bounds.isEmpty) {
      next = _empty;
    } else if (_base == null || _extent == null) {
      next = const SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: true,
      );
    } else {
      final collapsed = _text!.offsetAt(_base!) == _text!.offsetAt(_extent!);
      final forward = _base! <= _extent!;
      next = SelectionGeometry(
        startSelectionPoint: _handle(
          _base!,
          leading: forward,
          collapsed: collapsed,
        ),
        endSelectionPoint: _handle(
          _extent!,
          leading: !forward,
          collapsed: collapsed,
        ),
        selectionRects: collapsed
            ? const []
            : [
                for (final box in _boxes(
                  math.min(_base!, _extent!),
                  math.max(_base!, _extent!),
                ))
                  box.toRect(),
              ],
        status: collapsed
            ? SelectionStatus.collapsed
            : SelectionStatus.uncollapsed,
        hasContent: true,
      );
    }
    if (next == _geometry.value) return;
    markNeedsPaint();
    _geometry.value = next;
  }

  @override
  bool get alwaysNeedsCompositing => _startHandle != null || _endHandle != null;

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (_startHandle == startHandle && _endHandle == endHandle) return;
    _startHandle = startHandle;
    _endHandle = endHandle;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final geometry = value;
    if (!geometry.hasSelection) return;
    final highlight = Paint()
      ..color = _color.withValues(alpha: math.min(.45, _color.a));
    for (final rect in geometry.selectionRects) {
      context.canvas.drawRect(rect.shift(offset), highlight);
    }
    void leader(LayerLink? link, SelectionPoint? point) {
      if (link == null || point == null) return;
      context.pushLayer(
        LeaderLayer(link: link, offset: offset + point.localPosition),
        (_, _) {},
        Offset.zero,
      );
    }

    leader(_startHandle, geometry.startSelectionPoint);
    leader(_endHandle, geometry.endSelectionPoint);
  }
}

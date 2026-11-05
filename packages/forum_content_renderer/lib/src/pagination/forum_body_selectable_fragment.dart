import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_selectable_text.dart';
import 'forum_body_text_glyph_hit.dart';
import 'forum_body_text_page_composer.dart';

/// Registers the exact mounted native fragment with Flutter's selection area.
/// This render object borrows the painted delivery and never owns its leases.
final class ForumBodySelectableFragment extends SingleChildRenderObjectWidget {
  const ForumBodySelectableFragment({
    required this.binding,
    required this.fragment,
    required this.pageSize,
    required this.identity,
    required this.registrar,
    required super.child,
    super.key,
  });

  final ForumBodyPreparedTextFragment binding;
  final ForumBodyTextPageFragment fragment;
  final Size pageSize;
  final Object identity;
  final SelectionRegistrar? registrar;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSelectableFragment(this, _color(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSelectableFragment).update(this, _color(context));
  }

  Color _color(BuildContext context) => registrar == null
      ? const Color(0x00000000)
      : DefaultSelectionStyle.of(context).selectionColor ??
            const Color(0x663F51B5);
}

final class _RenderSelectableFragment extends RenderProxyBox
    with Selectable, SelectionRegistrant {
  _RenderSelectableFragment(this._input, this._color);

  ForumBodySelectableFragment _input;
  Color _color;
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

  void update(ForumBodySelectableFragment input, Color color) {
    final changed =
        input.identity != _input.identity ||
        input.pageSize != _input.pageSize ||
        input.registrar != _input.registrar;
    _input = input;
    if (_color != color) {
      _color = color;
      markNeedsPaint();
    }
    if (changed) {
      _retire();
      markNeedsLayout();
    }
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
    registrar = _input.registrar;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_input.registrar != null) markNeedsLayout();
  }

  void _retire() {
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
    final forward = (leading && position < text.end) || position <= text.start;
    final step = text.step(position, forward: forward);
    final box = _boxes(
      math.min(position, step),
      math.max(position, step),
    ).firstOrNull;
    if (box == null) return null;
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

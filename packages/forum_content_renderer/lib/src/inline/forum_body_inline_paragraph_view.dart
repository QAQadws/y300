import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_inline_paragraph_layout.dart';
import 'forum_body_inline_span_content.dart';
import 'forum_body_inline_image_input.dart';
import '../paragraph/forum_body_paragraph_layout.dart'
    show ForumBodyParagraphLine;
import 'forum_body_ruby_group_layout.dart';
import 'forum_body_ruby_segment_layout.dart';
import 'forum_body_ruby_soft_space_layout.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_root_box.dart';
import 'forum_body_ruby_tree_layout.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_inline_paint_command.dart';
import 'forum_body_inline_paint_row.dart';
import 'forum_body_text_baseline_layout.dart';
import 'forum_body_inline_font_frame_plan.dart';
import '../pagination/forum_body_inline_page_preparation.dart';

part 'forum_body_inline_ruby_binding.dart';
part 'forum_body_inline_image_binding.dart';
part 'forum_body_inline_view_assembly.dart';
part 'forum_body_inline_ruby_binding_work.dart';
part 'forum_body_inline_background_regions.dart';
part 'forum_body_inline_paint_commands.dart';
part 'forum_body_inline_font_frame_view.dart';
part 'forum_body_inline_font_frame_view_preparation.dart';

enum ForumBodyInlineViewFailure { leases, coverage, identity, geometry }

final class ForumBodyInlineViewException implements Exception {
  const ForumBodyInlineViewException(this.failure);
  final ForumBodyInlineViewFailure failure;
  @override
  String toString() => 'ForumBodyInlineViewException(${failure.name})';
}

/// Complete readable line window: one parent and exactly its visible children.
/// No shape, recording, lookup or settings resolution happens in paint/hit.
/// The caller prepares this transaction using the reading owner's shared cache.
final class ForumBodyInlineParagraphView {
  ForumBodyInlineParagraphView._(
    this._parent,
    ForumBodyInlineParagraphFragment fragment,
    this._children,
    this._backgrounds,
    this._backgroundRows,
    this._images,
  ) : _fragment = fragment,
      width = fragment.layout.width,
      height = fragment.height,
      startLine = fragment.startLine,
      endLine = fragment.endLine,
      coverageStartUtf16 = fragment.coverageStartUtf16,
      coverageEndUtf16 = fragment.coverageEndUtf16;

  ForumBodyInlineParagraphView._empty(ForumBodyInlineParagraphLease parent)
    : _parent = parent,
      _fragment = null,
      _children = const {},
      _backgrounds = const [],
      _backgroundRows = const [],
      _images = const {},
      width = parent.layout.width,
      height = parent.layout.height,
      startLine = 0,
      endLine = 0,
      coverageStartUtf16 = 0,
      coverageEndUtf16 = 0;

  ForumBodyInlineParagraphView._allocated(
    ForumBodyInlineParagraphView source,
    _InlineFontFrameBinding frames,
    List<({Rect rect, ForumBodyRubyContainerFontBox font})> backgrounds,
  ) : _parent = source._parent,
      _fragment = source._fragment,
      _children = source._children,
      _backgrounds = backgrounds,
      _backgroundRows = source._backgroundRows,
      _images = const {},
      _fontFrames = frames,
      width = source.width,
      height = frames.window.height,
      startLine = source.startLine,
      endLine = source.endLine,
      coverageStartUtf16 = source.coverageStartUtf16,
      coverageEndUtf16 = source.coverageEndUtf16;

  /// Consumes these handles on success AND failure. Column and segment indices
  /// must be disjoint and cover exactly the visible atoms; hidden children
  /// cannot silently pin an entire long paragraph.
  factory ForumBodyInlineParagraphView.adopt({
    required ForumBodyParagraphCache cache,
    required ForumBodyInlineParagraphLease parent,
    required int startLine,
    required int endLine,
    Map<int, ForumBodyRubyGroupLayout> rubyGroups = const {},
    Map<int, ForumBodyRubySegmentLayout> rubySegments = const {},
    Map<int, ForumBodyRubySoftSpaceLayout> rubySpaces = const {},
    Map<int, ForumBodyRubyContainerFontBox> containerBackgrounds = const {},
    Map<int, ForumBodyRubyRootFontBox> rootFonts = const {},
  }) {
    final assembly = ForumBodyInlineViewAssembly(
      cache: cache,
      parent: parent,
      startLine: startLine,
      endLine: endLine,
      rubyGroups: rubyGroups,
      rubySegments: rubySegments,
      rubySpaces: rubySpaces,
      containerBackgrounds: containerBackgrounds,
      rootFonts: rootFonts,
    );
    try {
      while (!assembly.isReady) {
        assembly.advance(maxParts: 32);
      }
      return assembly.takeView();
    } finally {
      assembly.close();
    }
  }

  ForumBodyInlineParagraphLease? _parent;
  ForumBodyInlineParagraphFragment? _fragment;
  Map<int, _RubyBinding> _children;
  Map<int, ForumBodyInlineImageBinding> _images;
  List<({Rect rect, ForumBodyRubyContainerFontBox font})> _backgrounds;
  List<int> _backgroundRows;
  _InlineFontFrameBinding? _fontFrames;

  /// Actual parent row ownership of each already-bound container surface.
  /// Coordinates remain local to this natural source window; allocation is
  /// supplied by the containing format, never inferred from these rectangles.
  List<({int lineIndex, Rect rect, ForumBodyRubyContainerFontBox font})>
  get backgroundRows {
    _ensureActive();
    return _InlineBackgroundRowView(_backgrounds, _backgroundRows);
  }

  bool matchesCurrentParent(ForumBodyInlineParagraphLease parent) {
    _ensureActive();
    return parent.isActive &&
        _parent!.hasSameActiveOwner(parent) &&
        identical(_parent!.content, parent.content) &&
        _parent!.nativeInputIdentity == parent.nativeInputIdentity &&
        identical(_parent!.layout.lines, parent.layout.lines);
  }

  /// Replays one ACTUALLY bound complete child at its parent-slot origin.
  /// Hidden/off-window or trimmed atoms cannot acquire visible authority here.
  /// No parent glyph/background, viewport clip, shaping or recording is added.
  void paintBoundAtomAt(Canvas canvas, Offset origin, int atomIndex) {
    _ensureActive();
    if (!origin.dx.isFinite || !origin.dy.isFinite) {
      throw ArgumentError.value(origin);
    }
    final binding = _children[atomIndex];
    if (binding == null) _fail(ForumBodyInlineViewFailure.coverage);
    binding.paint(canvas, origin);
    _ensureActive();
  }

  /// Bounded paint-only traversal of the ACTUAL bound child at this slot.
  /// Keep this view alive until scene.dependenciesReady. Null steps are work,
  /// not permission to skip arbitrary empty subtrees in a single moveNext.
  Iterable<ForumBodyInlinePaintCommand?> boundAtomPaintCommandsAt(
    Offset origin,
    int atomIndex,
  ) sync* {
    _ensureCommandOwner(origin);
    final binding = _children[atomIndex];
    if (binding == null) _fail(ForumBodyInlineViewFailure.coverage);
    for (final step in _rubyPaintCommands(binding, origin)) {
      _ensureCommandOwner(origin);
      yield step;
    }
    _ensureCommandOwner(origin);
  }

  /// Includes the original hard viewport scope and natural parent window.
  /// Container surfaces remain one separate plane before any native glyph.
  Iterable<ForumBodyInlinePaintCommand?> paintCommands(
    Offset offset, {
    bool paintBackgrounds = true,
  }) sync* {
    _ensureCommandOwner(offset);
    if (_images.isNotEmpty) _fail(ForumBodyInlineViewFailure.coverage);
    if (_fragment == null) return;
    if (paintBackgrounds) {
      for (final surface in _backgrounds) {
        _ensureCommandOwner(offset);
        yield ForumBodyInlinePaintCommand.fill(
          surface.rect,
          surface.font.background.color,
          offset,
        );
      }
    }
    final clip = offset & Size(width, height);
    if (_fontFrames case final frames?) {
      if (frames.picture case final picture?) {
        yield ForumBodyInlinePaintCommand.picture(
          picture,
          offset,
        ).clipped(clip);
      }
    } else {
      final row = ForumBodyInlinePaintRowView.naturalWindow(
        parent: _parent!,
        startLine: startLine,
        endLine: endLine,
        ensureOwner: () => _ensureCommandOwner(offset),
      );
      yield ForumBodyInlinePaintCommand.parent(row, offset).clipped(clip);
    }
    for (final entry in _children.entries) {
      yield null;
      _ensureCommandOwner(offset);
      for (final step in boundAtomPaintCommandsAt(
        offset + _origin(entry.key),
        entry.key,
      )) {
        _ensureCommandOwner(offset);
        yield step?.clipped(clip);
      }
    }
    _ensureCommandOwner(offset);
  }

  // Check ownership in O(1); each actual leaf is checked as it is emitted and
  // again during private scene adoption. isActive would rescan the entire tree
  // for every step, defeating bounded traversal of a long nested format.
  void _ensureCommandOwner(Offset offset) {
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    final parent = _parent;
    if (parent == null || !parent.isActive || parent.layout.isDisposed) {
      throw StateError('Inline command source is retired');
    }
    _fontFrames?.guard();
  }

  List<({Rect rect, ForumBodyRubyContainerFontBox font})>
  get backgroundSurfaces {
    _ensureActive();
    return _backgrounds;
  }

  List<({Rect rect, Color color})> get containerBackgrounds {
    _ensureActive();
    return _InlineBackgroundColorView(_backgrounds);
  }

  late final Rect paintBounds = _backgrounds.fold(
    Offset.zero & Size(width, height),
    (bounds, region) => bounds.expandToInclude(region.rect),
  );
  bool get isActive =>
      _parent?.isActive == true &&
      !_parent!.layout.isDisposed &&
      _children.values.every((binding) => binding.isActive) &&
      (_fontFrames?.isActive ?? true);
  final double width;
  final double height;
  final int startLine;
  final int endLine;
  final int coverageStartUtf16;
  final int coverageEndUtf16;
  ({int startUtf16, int endUtf16})? get engineRange {
    _ensureActive();
    final fragment = _fragment;
    return fragment == null
        ? null
        : (
            startUtf16: fragment.engineCoverageStartUtf16,
            endUtf16: fragment.engineCoverageEndUtf16,
          );
  }

  ForumBodyInlineSpanContent get content {
    _ensureActive();
    return _parent!.content;
  }

  /// Text-bearing atoms only. Image bindings have independent source and
  /// pixel readiness, and must not enter a native glyph/source traversal.
  Iterable<int> get atomIndices => _children.keys;
  Map<int, ForumBodyInlineImageBinding> get images {
    _ensureActive();
    return _images;
  }

  bool get hasRenderedImages =>
      isActive && _images.values.every((image) => image.hasRenderedFrame);
  ForumBodyInlineImageBinding? imageAt(Offset point) {
    _ensureActive();
    if (!point.dx.isFinite || !point.dy.isFinite) {
      throw ArgumentError.value(point);
    }
    if (!(Offset.zero & Size(width, height)).contains(point)) return null;
    for (final image in _images.values) {
      if (image.rect.contains(point)) return image;
    }
    return null;
  }

  /// Actual visible native rows in this view's physical coordinates. Returning
  /// immutable row values neither borrows paint ownership nor proves coverage.
  Iterable<ForumBodyParagraphLine> get lines {
    _ensureActive();
    final fragment = _fragment;
    if (fragment == null) return const [];
    final top = _fontFrames?.window.top ?? fragment.top;
    return (_fontFrames?.plan.lines ?? fragment.layout.lines)
        .getRange(startLine, endLine)
        .map((line) => line.shift(Offset(0, -top)));
  }

  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_parent,
    if (_fontFrames case final frames?) ...[frames.isolated, ?frames.picture],
    for (final binding in _children.values) ...binding.nativeLeases,
  ];

  void paintContainerBackgrounds(Canvas canvas, Offset offset) {
    _ensureActive();
    for (final region in _backgrounds) {
      canvas.drawRect(
        region.rect.shift(offset),
        Paint()..color = region.font.background.color,
      );
    }
  }

  void paint(Canvas canvas, Offset offset, {bool paintBackgrounds = true}) {
    if (_images.isNotEmpty) _fail(ForumBodyInlineViewFailure.coverage);
    paintTextLayer(canvas, offset, paintBackgrounds: paintBackgrounds);
  }

  /// The native plane only. A resource-aware Surface must separately mount
  /// every bound image at its fixed rect using the current image Host.
  void paintTextLayer(
    Canvas canvas,
    Offset offset, {
    bool paintBackgrounds = true,
  }) {
    _ensureActive();
    if (_fragment == null) return;
    if (paintBackgrounds) paintContainerBackgrounds(canvas, offset);
    canvas.save();
    try {
      // Child pictures already contain their native edge coverage. A second
      // antialiased rectangular viewport compounds alpha at fractional edges.
      canvas.clipRect(offset & Size(width, height), doAntiAlias: false);
      if (_fontFrames case final frames?) {
        frames.picture?.paint(canvas, offset);
      } else {
        _fragment!.paintParent(canvas, offset);
      }
      for (final entry in _children.entries) {
        entry.value.paint(canvas, offset + _origin(entry.key));
      }
    } finally {
      canvas.restore();
    }
  }

  Offset _origin(int index) => _fontFrames == null
      ? _fragment!.layout.atomBoxes[index].toRect().topLeft -
            Offset(0, _fragment!.top)
      : _fontFrames!.plan.allocation.children[index]!.offset -
            Offset(0, _fontFrames!.window.top);

  /// Returns parent display coordinates and the ACTUAL child's source point.
  /// Off-window points clamp to this view and remain approximate, never borrow
  /// a hidden sibling's native hit or fabricate an inner placeholder offset.
  HtmlProjectedSourcePosition sourceAt(Offset offset) =>
      sourceHitAt(offset).position;

  /// Retains the actual bound child window across recursive parent views.
  /// Adjacent source endpoints alone cannot identify which child was hit.
  ({ForumBodyInlineContext? window, HtmlProjectedSourcePosition position})
  sourceHitAt(Offset offset) {
    _ensureActive();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    if (_fragment == null || coverageStartUtf16 == coverageEndUtf16) {
      final empty = content.projection.display.sourceAtUtf16(
        coverageStartUtf16,
      );
      return (
        window: null,
        position: HtmlProjectedSourcePosition(
          sourceRune: empty.sourceRune,
          displayUtf16: empty.displayUtf16,
          isExact: false,
        ),
      );
    }
    final point = Offset(
      offset.dx.clamp(0, width),
      offset.dy.clamp(0, height > 1e-7 ? height - 1e-7 : 0),
    );
    final allocatedHit = _fontFrames?.hitAt(point, _children, _origin);
    final hit = allocatedHit?.hit ?? _fragment!.hitAt(point);
    final display = content.projection.display;
    HtmlProjectedSourcePosition position;
    ForumBodyInlineContext? window;
    if (hit is ForumBodyInlineAtomHit) {
      if (_images.containsKey(hit.index)) {
        final fence = content.projection.atoms[hit.index].displayStartUtf16;
        final source = display.sourceAtUtf16(fence);
        return (
          window: null,
          position: HtmlProjectedSourcePosition(
            sourceRune: source.sourceRune,
            displayUtf16: fence,
            isExact: false,
          ),
        );
      }
      final binding = _children[hit.index];
      if (binding == null) _fail(ForumBodyInlineViewFailure.coverage);
      final child = binding.sourceAt(hit.offset);
      window = child.window;
      position = _projectChildHit(child);
    } else {
      final textHit = hit as ForumBodyInlineTextHit;
      position = textHit.position;
      // Native row rounding can leave a fractional strip outside an atom's
      // frame. Root leading in that strip still belongs to the actual row,
      // not an exact parent caret at a placeholder boundary.
      for (final entry in _children.entries) {
        if (entry.value case final _RubyRootFrameBinding binding) {
          final atom = content.projection.atoms[entry.key];
          if (position.displayUtf16 < atom.displayStartUtf16 ||
              position.displayUtf16 > atom.displayEndUtf16) {
            continue;
          }
          final local = point - _origin(entry.key);
          if (binding.hitsOuterLeading(local)) {
            final child = binding.sourceAt(local);
            window = child.window;
            position = _projectChildHit(child);
            break;
          }
        }
      }
      window ??= _plainWindowAt(position.displayUtf16, textHit.affinity);
    }
    final within = position.displayUtf16.clamp(
      coverageStartUtf16,
      coverageEndUtf16,
    );
    if (within != position.displayUtf16) {
      final projected = display.sourceAtUtf16(within);
      return (
        window: null,
        position: HtmlProjectedSourcePosition(
          sourceRune: projected.sourceRune,
          displayUtf16: projected.displayUtf16,
          isExact: false,
        ),
      );
    }
    return (
      window: window,
      position: HtmlProjectedSourcePosition(
        sourceRune: position.sourceRune,
        displayUtf16: position.displayUtf16,
        isExact:
            position.isExact &&
            point == offset &&
            height > 0 &&
            (allocatedHit?.isExact ?? true),
      ),
    );
  }

  ForumBodyInlineContext? _plainWindowAt(int position, TextAffinity affinity) {
    final windows = content.contexts;
    final atoms = content.projection.atoms;
    var low = 0, high = windows.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (windows[mid].endUtf16 < position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    ForumBodyInlineContext? edge;
    for (
      var i = low;
      i < windows.length && windows[i].startUtf16 <= position;
      i++
    ) {
      final window = windows[i];
      if (window.startUtf16 == window.endUtf16) continue;
      // A native ordinary-text hit cannot belong to a child's source window,
      // even when their caret endpoints share the same raw source coordinate.
      var first = 0, after = atoms.length;
      while (first < after) {
        final mid = (first + after) ~/ 2;
        if (atoms[mid].displayEndUtf16 <= window.startUtf16) {
          first = mid + 1;
        } else {
          after = mid;
        }
      }
      if (first < atoms.length &&
          atoms[first].displayStartUtf16 <= window.startUtf16 &&
          window.endUtf16 <= atoms[first].displayEndUtf16) {
        continue;
      }
      edge ??= window;
      if (affinity == TextAffinity.upstream
          ? window.startUtf16 < position
          : position < window.endUtf16) {
        return window;
      }
    }
    return edge;
  }

  HtmlProjectedSourcePosition _projectChildHit(_RubySourceHit child) {
    final parentDisplay = child.window.startUtf16 + child.position.displayUtf16;
    final parent = content.projection.display.sourceAtUtf16(parentDisplay);
    return HtmlProjectedSourcePosition(
      sourceRune: child.position.sourceRune,
      displayUtf16: parentDisplay,
      isExact:
          child.position.isExact &&
          parent.isExact &&
          child.position.sourceRune == parent.sourceRune,
    );
  }

  /// Resolves partial base/RT selections through the child's actual text
  /// geometry. A placeholder rectangle is never substituted for glyph boxes.
  List<TextBox> selectionBoxes(
    int startUtf16,
    int endUtf16, {
    bool clipToView = true,
  }) {
    return _selectionBoxes(
      startUtf16,
      endUtf16,
      clipToView: clipToView,
      paintedOnly: false,
    );
  }

  /// Unclipped proof boxes. Atomic geometry still comes from its own prepared
  /// child; only confirmed parent-row SPACE suffixes are excluded here.
  List<TextBox> glyphBoxes(int startUtf16, int endUtf16) => _selectionBoxes(
    startUtf16,
    endUtf16,
    clipToView: false,
    paintedOnly: true,
  );

  List<TextBox> _selectionBoxes(
    int startUtf16,
    int endUtf16, {
    required bool clipToView,
    required bool paintedOnly,
  }) {
    _ensureActive();
    RangeError.checkValidRange(
      startUtf16,
      endUtf16,
      _parent!.content.projection.display.text.length,
    );
    final start = startUtf16.clamp(coverageStartUtf16, coverageEndUtf16);
    final end = endUtf16.clamp(coverageStartUtf16, coverageEndUtf16);
    if (start >= end) return const [];
    final query = _fontFrames?.isolated.layout ?? _fragment!.layout;
    final selected = paintedOnly
        ? query.glyphSelection(start, end)
        : query.selection(start, end);
    final result = <TextBox>[];
    void add(TextBox box, Offset translation) {
      final raw = box.toRect().shift(translation);
      final rect = clipToView
          ? raw.intersect(Offset.zero & Size(width, height))
          : raw;
      if (!rect.isEmpty) {
        result.add(
          TextBox.fromLTRBD(
            rect.left,
            rect.top,
            rect.right,
            rect.bottom,
            box.direction,
          ),
        );
      }
    }

    for (final box in selected.textBoxes) {
      if (_fontFrames case final frames?) {
        final placed = frames.selectionBox(box);
        if (placed != null) add(placed, Offset.zero);
      } else {
        add(box, Offset(0, -_fragment!.top));
      }
    }
    for (final atom in selected.atoms) {
      final binding = _children[atom.index];
      if (binding == null) _fail(ForumBodyInlineViewFailure.coverage);
      final boxes = paintedOnly
          ? binding.glyphBoxes(atom.startUtf16, atom.endUtf16)
          : binding.selectionBoxes(atom.startUtf16, atom.endUtf16);
      for (final box in boxes) {
        add(box, _origin(atom.index));
      }
    }
    return List.unmodifiable(result);
  }

  void _ensureActive() {
    _fontFrames?.guard();
    if (!isActive) throw StateError('Inline paragraph view is retired');
    for (final binding in _children.values) {
      binding.ensureActive();
    }
    if (!isActive) throw StateError('Inline paragraph owner is retired');
  }

  static Never _fail(ForumBodyInlineViewFailure failure) =>
      throw ForumBodyInlineViewException(failure);
  void close() {
    final parent = _parent;
    if (parent == null) return;
    _parent = null;
    for (final image in _images.values) {
      image._retire();
    }
    _images = const {};
    for (final binding in _children.values) {
      binding.close();
    }
    _children = const {};
    _backgrounds = const [];
    _backgroundRows = const [];
    _fragment = null;
    _fontFrames?.close();
    _fontFrames = null;
    parent.release();
  }
}

final class _InlineBackgroundRowView
    extends
        ListBase<
          ({int lineIndex, Rect rect, ForumBodyRubyContainerFontBox font})
        > {
  _InlineBackgroundRowView(this.surfaces, this.rows);
  final List<({Rect rect, ForumBodyRubyContainerFontBox font})> surfaces;
  final List<int> rows;
  @override
  int get length => surfaces.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only backgrounds');
  @override
  ({int lineIndex, Rect rect, ForumBodyRubyContainerFontBox font}) operator [](
    int index,
  ) => (
    lineIndex: rows[index],
    rect: surfaces[index].rect,
    font: surfaces[index].font,
  );
  @override
  void operator []=(
    int index,
    ({int lineIndex, Rect rect, ForumBodyRubyContainerFontBox font}) value,
  ) => throw UnsupportedError('Read-only backgrounds');
}

final class _InlineBackgroundColorView
    extends ListBase<({Rect rect, Color color})> {
  _InlineBackgroundColorView(this.surfaces);
  final List<({Rect rect, ForumBodyRubyContainerFontBox font})> surfaces;
  @override
  int get length => surfaces.length;
  @override
  set length(int value) =>
      throw UnsupportedError('Read-only background surfaces');
  @override
  ({Rect rect, Color color}) operator [](int index) => (
    rect: surfaces[index].rect,
    color: surfaces[index].font.background.color,
  );
  @override
  void operator []=(int index, ({Rect rect, Color color}) value) =>
      throw UnsupportedError('Read-only background surfaces');
}

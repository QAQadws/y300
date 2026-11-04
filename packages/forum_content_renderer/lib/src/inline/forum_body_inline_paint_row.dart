import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import 'forum_body_inline_emphasis_paint_reference.dart';
import 'forum_body_inline_emphasis_row_allocation.dart';
import 'forum_body_inline_paragraph_layout.dart';

/// Pure physical paint identity; no source group, native resource
/// or callback can be recovered from it. A picture must bind the actual row.
final class ForumBodyInlinePaintRowSelector {
  const ForumBodyInlinePaintRowSelector._(
    this.nativeInputIdentity,
    this.lineIndex,
    this.clipTop,
    this.clipBottom,
    this.isEmpty,
    this.nativeOffset, {
    this.windowEndLine,
  });
  final Object nativeInputIdentity;
  final int lineIndex;
  final double clipTop, clipBottom;
  final bool isEmpty;
  final Offset nativeOffset;

  /// Non-null only for an actual natural parent fragment. The fragment itself
  /// remains in the borrowed view; its source capability never enters this key.
  final int? windowEndLine;
  bool get isNaturalWindow => windowEndLine != null;
  bool matchesInput(Object identity) => nativeInputIdentity == identity;

  /// Pure physical rebasing only. A scene still requires a current qualified
  /// row view with this same selector; translation grants no source authority.
  ForumBodyInlinePaintRowSelector shifted(Offset by) =>
      ForumBodyInlinePaintRowSelector._(
        nativeInputIdentity,
        lineIndex,
        clipTop,
        clipBottom,
        isEmpty,
        ForumBodyInlinePaintRowView._offset(by, nativeOffset),
        windowEndLine: windowEndLine,
      );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumBodyInlinePaintRowSelector &&
          nativeInputIdentity == other.nativeInputIdentity &&
          lineIndex == other.lineIndex &&
          windowEndLine == other.windowEndLine &&
          clipTop == other.clipTop &&
          clipBottom == other.clipBottom &&
          isEmpty == other.isEmpty &&
          nativeOffset == other.nativeOffset;
  @override
  int get hashCode => Object.hash(
    nativeInputIdentity,
    lineIndex,
    windowEndLine,
    clipTop,
    clipBottom,
    isEmpty,
    nativeOffset,
  );
}

/// Borrowed actual parent strip or natural row window for the common scene worker.
/// Its pure selector retains the qualified allocation-to-native translation.
/// Command offsets are scene-local; a long isolated parent's virtual coordinate
/// is not mistaken for a huge visible scene origin or an independent text row.
final class ForumBodyInlinePaintRowView {
  ForumBodyInlinePaintRowView._(
    this.parent,
    this.selector,
    this._ensureOwner, {
    ForumBodyInlineParagraphFragment? naturalWindow,
  }) : _naturalWindow = naturalWindow {
    _guard();
  }

  /// Paints ONLY this actual natural parent's legal row window. Atomic children,
  /// their outer viewport clip and current source bindings belong to the caller.
  /// Keep Fragment.paintParent as the unique authority for fractional clipping
  /// and offset arithmetic; isolated phase strips cannot stand in for it.
  factory ForumBodyInlinePaintRowView.naturalWindow({
    required ForumBodyInlineParagraphLease parent,
    required int startLine,
    required int endLine,
    required void Function() ensureOwner,
  }) {
    ensureOwner();
    if (!parent.isActive) {
      throw StateError('Natural inline paint parent is retired');
    }
    // This also rejects isolated/paint-layer parents and illegal row boundaries.
    final window = parent.layout.fragment(startLine, endLine);
    return ForumBodyInlinePaintRowView._(
      parent,
      ForumBodyInlinePaintRowSelector._(
        parent.nativeInputIdentity,
        startLine,
        window.top,
        window.bottom,
        window.coverageStartUtf16 == window.coverageEndUtf16 &&
            window.engineCoverageStartUtf16 == window.engineCoverageEndUtf16,
        Offset(0, -window.top),
        windowEndLine: endLine,
      ),
      ensureOwner,
      naturalWindow: window,
    );
  }
  factory ForumBodyInlinePaintRowView.glyphs({
    required ForumBodyInlineParagraphLease parent,
    required ForumBodyInlineEmphasisRowAllocation allocation,
    required int lineIndex,
    required void Function() ensureOwner,
    Offset allocationOrigin = Offset.zero,
  }) {
    ensureOwner();
    final rows = allocation.input.rows, geometry = rows.geometry;
    if (!parent.isActive ||
        !identical(parent.content, geometry.input.glyphInput.glyphs) ||
        parent.nativeInputIdentity != geometry.nativeInputIdentity ||
        !identical(parent.layout.lines, geometry.lines) ||
        parent.layout.rowIsolationPitch == null ||
        allocation.requiresParentPaintPhases) {
      _source();
    }
    RangeError.checkValidIndex(lineIndex, rows.rows, 'lineIndex');
    final row = rows.rows[lineIndex];
    return ForumBodyInlinePaintRowView._(
      parent,
      ForumBodyInlinePaintRowSelector._(
        parent.nativeInputIdentity,
        lineIndex,
        row.selector.clipTop,
        row.selector.clipBottom,
        row.isEmpty,
        _offset(allocationOrigin, allocation.rows[lineIndex].glyphOffset),
      ),
      ensureOwner,
    );
  }
  factory ForumBodyInlinePaintRowView.phase({
    required ForumBodyInlineParagraphLease parent,
    required ForumBodyInlineEmphasisPaintReference reference,
    required int lineIndex,
    required ForumBodyParagraphPaintLayer layer,
    required void Function() ensureOwner,
    Offset allocationOrigin = Offset.zero,
  }) {
    ensureOwner();
    final index = switch (layer) {
          ForumBodyParagraphPaintLayer.background => 0,
          ForumBodyParagraphPaintLayer.foreground => 1,
          ForumBodyParagraphPaintLayer.decoration => 2,
          ForumBodyParagraphPaintLayer.all => throw ArgumentError.value(layer),
        },
        input = switch (layer) {
          ForumBodyParagraphPaintLayer.background =>
            reference.paintInput.background,
          ForumBodyParagraphPaintLayer.foreground =>
            reference.paintInput.foreground,
          ForumBodyParagraphPaintLayer.decoration =>
            reference.paintInput.decoration,
          ForumBodyParagraphPaintLayer.all => throw ArgumentError.value(layer),
        };
    if (!parent.isActive ||
        !identical(parent.content, input) ||
        parent.nativeInputIdentity != reference.phaseInputIdentities[index] ||
        !identical(parent.layout.lines, reference.phaseLines[index]) ||
        parent.layout.rowIsolationPitch == null) {
      _source();
    }
    RangeError.checkValidIndex(
      lineIndex,
      reference.allocation.rows,
      'lineIndex',
    );
    final a = reference.allocation,
        foreground = index == 1,
        glyph = a.input.rows.rows[lineIndex],
        logical = a.input.logicalRows.rows[lineIndex],
        selected = foreground ? glyph.selector : logical.selector;
    return ForumBodyInlinePaintRowView._(
      parent,
      ForumBodyInlinePaintRowSelector._(
        parent.nativeInputIdentity,
        lineIndex,
        selected.clipTop,
        selected.clipBottom,
        foreground ? glyph.isEmpty : logical.bounds == null,
        _offset(
          allocationOrigin,
          foreground
              ? a.rows[lineIndex].glyphOffset
              : a.rows[lineIndex].logicalOffset,
        ),
      ),
      ensureOwner,
    );
  }

  final ForumBodyInlineParagraphLease parent;
  final ForumBodyInlinePaintRowSelector selector;
  final void Function() _ensureOwner;
  final ForumBodyInlineParagraphFragment? _naturalWindow;
  bool _painting = false;
  bool get isPaintPrepared => parent.isActive && parent.layout.isPaintPrepared;
  Object get nativeInputIdentity {
    _guard();
    return selector.nativeInputIdentity;
  }

  /// Rebind only to an independently owned alias of this SAME current input,
  /// content object and native line table. The scene owns/retires that alias.
  ForumBodyInlinePaintRowView bindAlias({
    required ForumBodyInlineParagraphLease parent,
    required void Function() ensureOwner,
  }) {
    _guard();
    // The borrowed row can remain active while its owner callback retires the
    // scene (and the scene's new alias). Recheck before source qualification.
    ensureOwner();
    if (!parent.isActive) throw StateError('Inline paint alias is retired');
    if (!this.parent.hasSameActiveOwner(parent) ||
        !identical(this.parent.content, parent.content) ||
        !identical(this.parent.layout.lines, parent.layout.lines) ||
        !selector.matchesInput(parent.nativeInputIdentity)) {
      _source();
    }
    return ForumBodyInlinePaintRowView._(
      parent,
      selector,
      ensureOwner,
      naturalWindow: selector.windowEndLine == null
          ? null
          : parent.layout.fragment(selector.lineIndex, selector.windowEndLine!),
    );
  }

  void paint(Canvas canvas, Offset offset) {
    if (_painting) throw StateError('Inline paint row is reentrant');
    _painting = true;
    try {
      _guard();
      if (!offset.dx.isFinite || !offset.dy.isFinite) {
        throw ArgumentError.value(offset);
      }
      if (!isPaintPrepared) {
        throw StateError('Inline row paint is not prepared');
      }
      if (_naturalWindow case final window?) {
        window.paintParent(canvas, offset);
        _guard();
        return;
      }
      if (selector.isEmpty) return;
      canvas.save();
      try {
        canvas.translate(
          offset.dx + selector.nativeOffset.dx,
          offset.dy + selector.nativeOffset.dy,
        );
        canvas.clipRect(
          Rect.fromLTRB(
            -16384,
            selector.clipTop,
            parent.layout.width + 16384,
            selector.clipBottom,
          ),
          doAntiAlias: false,
        );
        parent.layout.paintParent(canvas, Offset.zero);
      } finally {
        canvas.restore();
      }
      _guard();
    } finally {
      _painting = false;
    }
  }

  void _guard() {
    _ensureOwner();
    if (!parent.isActive || parent.layout.isDisposed) {
      throw StateError('Inline paint row owner is retired');
    }
  }

  static Never _source() => throw const ForumBodyParagraphRowException(
    ForumBodyParagraphRowFailure.source,
  );
  static Offset _offset(Offset origin, Offset native) {
    final value = origin + native;
    if (!origin.dx.isFinite ||
        !origin.dy.isFinite ||
        !value.dx.isFinite ||
        !value.dy.isFinite ||
        origin.dx.abs() > 1114112 ||
        origin.dy.abs() > 1114112 ||
        value.dx.abs() > 1114112 ||
        value.dy.abs() > 1114112) {
      throw ArgumentError('Invalid inline paint origin');
    }
    return value;
  }
}

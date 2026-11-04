import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_emphasis_allocation_geometry.dart';
import 'forum_body_inline_emphasis_paint_reference.dart';

/// Borrows four qualified current resources. Paints a single parent phase in
/// allocated coordinates without shaping, querying sources, recording a row
/// picture or drawing child/marker content. The containing scene orders them.
final class ForumBodyInlineEmphasisPaintView {
  ForumBodyInlineEmphasisPaintView.bind({
    required this.reference,
    required ForumBodyInlineParagraphLease source,
    required List<ForumBodyInlineParagraphLease> phases,
    required void Function() ensureOwner,
  }) : _source = source,
       _ensureOwner = ensureOwner {
    if (phases.length != 3) _fail();
    _phases = List.unmodifiable(phases);
    _guard();
    if (!identical(source.content, reference.paintInput.original) ||
        source.nativeInputIdentity != reference.sourceInputIdentity ||
        !identical(source.layout.lines, reference.sourceLines)) {
      _fail();
    }
    final expected = [
      reference.paintInput.background,
      reference.paintInput.foreground,
      reference.paintInput.decoration,
    ];
    for (var i = 0; i < 3; i++) {
      final p = _phases[i];
      if (!identical(p.content, expected[i]) ||
          p.nativeInputIdentity != reference.phaseInputIdentities[i] ||
          !identical(p.layout.lines, reference.phaseLines[i])) {
        _fail();
      }
    }
    _guard();
  }
  final ForumBodyInlineEmphasisPaintReference reference;
  final ForumBodyInlineParagraphLease _source;
  late final List<ForumBodyInlineParagraphLease> _phases;
  final void Function() _ensureOwner;
  bool _painting = false;
  bool get isPaintPrepared =>
      _source.isActive &&
      _phases.every(
        (p) => p.hasSameActiveOwner(_source) && p.layout.isPaintPrepared,
      );
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    _source,
    ..._phases,
  ];

  void paintPhaseRow(
    Canvas canvas,
    Offset offset,
    int lineIndex,
    ForumBodyParagraphPaintLayer layer,
  ) {
    if (_painting) throw StateError('Mixed phase paint is reentrant');
    _painting = true;
    try {
      _guard();
      final allocation = reference.allocation;
      RangeError.checkValidIndex(lineIndex, allocation.rows, 'lineIndex');
      if (!offset.dx.isFinite || !offset.dy.isFinite) {
        throw ArgumentError.value(offset);
      }
      final index = switch (layer) {
        ForumBodyParagraphPaintLayer.background => 0,
        ForumBodyParagraphPaintLayer.foreground => 1,
        ForumBodyParagraphPaintLayer.decoration => 2,
        ForumBodyParagraphPaintLayer.all => throw ArgumentError.value(layer),
      };
      if (!isPaintPrepared) {
        throw StateError('Mixed phase paint is not prepared');
      }
      final logical = allocation.input.logicalRows.rows[lineIndex],
          glyph = allocation.input.rows.rows[lineIndex],
          foreground = index == 1;
      if (foreground ? glyph.isEmpty : logical.bounds == null) return;
      final selector = foreground ? glyph.selector : logical.selector,
          row = allocation.rows[lineIndex],
          shift = foreground ? row.glyphOffset : row.logicalOffset,
          parent = _phases[index];
      canvas.save();
      try {
        canvas.translate(offset.dx + shift.dx, offset.dy + shift.dy);
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
    if (!_source.isActive ||
        _phases.any((p) => !p.hasSameActiveOwner(_source))) {
      throw StateError('Mixed phase paint owner is retired');
    }
  }
}

Never _fail() => throw const ForumBodyEmphasisAllocationException(
  ForumBodyEmphasisAllocationFailure.source,
);

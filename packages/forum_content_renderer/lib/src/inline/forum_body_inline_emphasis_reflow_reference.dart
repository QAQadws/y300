import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../paragraph/forum_body_paragraph_row_reference.dart';
import 'forum_body_inline_emphasis_children_plan.dart';

/// Verified current old/final natural parents after actual child replanning.
/// Only numeric geometry and exact immutable inputs survive. These deltas are
/// physical coordinates, never new source offsets or painted coverage.
final class ForumBodyInlineEmphasisReflowReference {
  ForumBodyInlineEmphasisReflowReference._(
    this.children,
    ForumBodyInlineParagraphLease original,
    ForumBodyInlineParagraphLease finalParent,
    List<double> deltas,
  ) : originalInputIdentity = original.nativeInputIdentity,
      finalInputIdentity = finalParent.nativeInputIdentity,
      originalLines = original.layout.lines,
      finalLines = finalParent.layout.lines,
      originalAtomBoxes = original.layout.atomBoxes,
      finalAtomBoxes = finalParent.layout.atomBoxes,
      baselineDeltas = UnmodifiableListView(deltas),
      width = finalParent.layout.width,
      originalHeight = original.layout.height,
      finalHeight = finalParent.layout.height;
  static const revision = 1;
  final ForumBodyInlineEmphasisChildrenPlan children;
  final Object originalInputIdentity, finalInputIdentity;
  final List<ForumBodyParagraphLine> originalLines, finalLines;
  final List<TextBox> originalAtomBoxes, finalAtomBoxes;
  final List<double> baselineDeltas;
  final double width, originalHeight, finalHeight;
}

/// Borrows two actual natural parents belonging to the same cache/source.
/// Native font/paint/scaler inputs and slot widths must be identical, then
/// every source/horizontal row, real target dimension and atom row/trim/x is
/// verified. Each part visits one physical row/slot or advances its row cursor.
/// No acquire, shaping, native query, paint or caller handle release occurs.
final class ForumBodyInlineEmphasisReflowReferencePreparation {
  ForumBodyInlineEmphasisReflowReferencePreparation({
    required ForumBodyInlineEmphasisChildrenPlan children,
    required ForumBodyInlineParagraphLease original,
    required ForumBodyInlineParagraphLease finalParent,
    required void Function() ensureOwner,
    this.maxLines = 4096,
    this.maxAtoms = 512,
    this.maxHeight = 1048576,
  }) : _children = children,
       _original = original,
       _finalParent = finalParent,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0 ||
        maxAtoms < 0 ||
        !maxHeight.isFinite ||
        maxHeight <= 0) {
      throw ArgumentError('Invalid mixed reflow reference budget');
    }
    try {
      _guard();
      final geometry = children.placement.input.fonts.geometry;
      if (!identical(original.content, geometry.input.glyphInput.glyphs) ||
          !identical(children.page.content, geometry.input.content) ||
          !identical(original.layout.lines, geometry.lines) ||
          original.nativeInputIdentity != geometry.nativeInputIdentity ||
          original.layout.rowIsolationPitch != null ||
          finalParent.layout.rowIsolationPitch != null ||
          !original.hasSameSourceAndInputsExceptSlotVerticalGeometry(
            finalParent,
          )) {
        _fail(ForumBodyParagraphRowReferenceFailure.source);
      }
      final a = original.layout, b = finalParent.layout;
      if (a.lineCount > maxLines ||
          b.lineCount > maxLines ||
          a.atomBoxes.length > maxAtoms) {
        _fail(ForumBodyParagraphRowReferenceFailure.limit);
      }
      if (a.lineCount != b.lineCount ||
          a.width != b.width ||
          a.atomBoxes.length != b.atomBoxes.length ||
          a.atomBoxes.length != children.page.dimensions.length ||
          a.firstLineIndent.requestedAdvance !=
              b.firstLineIndent.requestedAdvance ||
          a.firstLineIndent.appliedAdvance !=
              b.firstLineIndent.appliedAdvance) {
        _fail(ForumBodyParagraphRowReferenceFailure.geometry);
      }
      for (final height in [a.height, b.height]) {
        if (!height.isFinite || height < 0) {
          _fail(ForumBodyParagraphRowReferenceFailure.geometry);
        }
        if (height > maxHeight) {
          _fail(ForumBodyParagraphRowReferenceFailure.limit);
        }
      }
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxLines, maxAtoms;
  final double maxHeight;
  ForumBodyInlineEmphasisChildrenPlan? _children;
  ForumBodyInlineParagraphLease? _original, _finalParent;
  void Function()? _ensureOwner;
  List<double>? _deltas = [];
  ForumBodyInlineEmphasisReflowReference? _result;
  int _row = 0, _atom = 0, _atomRow = 0;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed reflow reference is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final a = _original!.layout, b = _finalParent!.layout;
        if (_row < a.lineCount) {
          final first = a.lines[_row], last = b.lines[_row];
          if (!forumBodyHaveSameParagraphLineInputs(first, last)) {
            _fail(ForumBodyParagraphRowReferenceFailure.geometry);
          }
          for (final row in [first, last]) {
            if (!row.top.isFinite ||
                !row.bottom.isFinite ||
                row.bottom < row.top ||
                !row.baseline.isFinite) {
              _fail(ForumBodyParagraphRowReferenceFailure.geometry);
            }
          }
          final delta = last.baseline - first.baseline;
          if (!delta.isFinite) {
            _fail(ForumBodyParagraphRowReferenceFailure.geometry);
          }
          _deltas!.add(delta);
          _row++;
        } else if (_atom < b.atomBoxes.length) {
          final point = b.projection.atoms[_atom].engineUtf16;
          if (_atomRow >= b.lineCount) {
            _fail(ForumBodyParagraphRowReferenceFailure.geometry);
          }
          if (point >= b.lines[_atomRow].engineCoverageEndUtf16) {
            _atomRow++;
          } else {
            final children = _children!,
                page = children.page,
                oldPage = children.placement.input.page;
            final target = page.dimensions[_atom],
                actual = b.dimensions[_atom],
                oldTarget = oldPage.dimensions[_atom],
                oldActual = a.dimensions[_atom];
            if (!_sameDimension(target, actual) ||
                !_sameDimension(oldTarget, oldActual)) {
              _fail(ForumBodyParagraphRowReferenceFailure.source);
            }
            final first = a.atomBoxes[_atom], last = b.atomBoxes[_atom];
            if (point < b.lines[_atomRow].engineCoverageStartUtf16 ||
                _atomRow !=
                    children
                        .placement
                        .input
                        .fonts
                        .geometry
                        .atomLineIndices[_atom] ||
                a.isAtomTrimmed(_atom) !=
                    oldPage.trimmedAtomIndices.contains(_atom) ||
                b.isAtomTrimmed(_atom) !=
                    page.trimmedAtomIndices.contains(_atom) ||
                first.left != last.left ||
                first.right != last.right ||
                first.direction != last.direction) {
              _fail(ForumBodyParagraphRowReferenceFailure.geometry);
            }
            _atom++;
          }
        } else {
          _result = ForumBodyInlineEmphasisReflowReference._(
            _children!,
            _original!,
            _finalParent!,
            _deltas!,
          );
          _deltas = null;
        }
        used++;
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyInlineEmphasisReflowReference takeReference() {
    if (_operating) throw StateError('Mixed reflow reference is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Mixed reflow reference is incomplete');
      final result = _result!;
      close();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_closed) throw StateError('Mixed reflow reference is retired');
    _ensureOwner!();
    if (_closed ||
        _original?.isActive != true ||
        _finalParent?.isActive != true) {
      throw StateError('Mixed reflow reference owner is retired');
    }
  }

  void close() {
    _closed = true;
    _children = null;
    _original = null;
    _finalParent = null;
    _ensureOwner = null;
    _deltas = null;
    _result = null;
  }
}

bool _sameDimension(PlaceholderDimensions a, PlaceholderDimensions b) =>
    a.size == b.size &&
    a.alignment == b.alignment &&
    a.baseline == b.baseline &&
    a.baselineOffset == b.baselineOffset;
Never _fail(ForumBodyParagraphRowReferenceFailure failure) =>
    throw ForumBodyParagraphRowReferenceException(failure);

import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../paragraph/forum_body_paragraph_row_reference.dart';
import 'forum_body_inline_span_content.dart';

/// Current full-source natural/isolated pair, retaining only actual numeric
/// rows/slots and opaque input identities. It proves no clipping gap, visible
/// child binding, allocation or canonical source coverage after capture.
final class ForumBodyInlineRowReference {
  ForumBodyInlineRowReference._(
    ForumBodyInlineParagraphLease natural,
    ForumBodyInlineParagraphLease isolated,
    List<int> atomLines,
  ) : content = natural.content,
      naturalInputIdentity = natural.nativeInputIdentity,
      isolatedInputIdentity = isolated.nativeInputIdentity,
      naturalLines = natural.layout.lines,
      isolatedLines = isolated.layout.lines,
      naturalAtomBoxes = natural.layout.atomBoxes,
      isolatedAtomBoxes = isolated.layout.atomBoxes,
      dimensions = natural.layout.dimensions,
      atomLineIndices = UnmodifiableListView(atomLines),
      width = natural.layout.width,
      naturalHeight = natural.layout.height,
      isolatedHeight = isolated.layout.height,
      rowIsolationPitch = isolated.layout.rowIsolationPitch!,
      nativeFontClearance = isolated.layout.nativeFontClearance;
  static const revision = 1;
  final ForumBodyInlineSpanContent content;
  final Object naturalInputIdentity, isolatedInputIdentity;
  final List<ForumBodyParagraphLine> naturalLines, isolatedLines;
  final List<TextBox> naturalAtomBoxes, isolatedAtomBoxes;
  final List<PlaceholderDimensions> dimensions;
  final List<int> atomLineIndices;
  final double width,
      naturalHeight,
      isolatedHeight,
      rowIsolationPitch,
      nativeFontClearance;
  int get lineCount => naturalLines.length;
}

/// Borrows the same owner's actual parents. One part validates one physical
/// row/slot or advances its engine row; publication transfers readonly storage.
final class ForumBodyInlineRowReferencePreparation {
  ForumBodyInlineRowReferencePreparation({
    required ForumBodyInlineParagraphLease natural,
    required ForumBodyInlineParagraphLease isolated,
    required void Function() ensureOwner,
    this.maxLines = 4096,
    this.maxAtoms = 512,
  }) : _natural = natural,
       _isolated = isolated,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0 || maxAtoms < 0) {
      throw ArgumentError('Invalid inline row reference budget');
    }
    try {
      _guard();
      if (!natural.hasSameSourceAndInputsExceptRowIsolation(isolated) ||
          natural.layout.rowIsolationPitch != null ||
          isolated.layout.rowIsolationPitch == null) {
        _fail(ForumBodyParagraphRowReferenceFailure.source);
      }
      final a = natural.layout, b = isolated.layout;
      if (a.lineCount > maxLines ||
          b.lineCount > maxLines ||
          a.atomBoxes.length > maxAtoms) {
        _fail(ForumBodyParagraphRowReferenceFailure.limit);
      }
      if (a.lineCount != b.lineCount ||
          a.width != b.width ||
          a.atomBoxes.length != b.atomBoxes.length ||
          a.firstLineIndent.requestedAdvance !=
              b.firstLineIndent.requestedAdvance ||
          a.firstLineIndent.appliedAdvance !=
              b.firstLineIndent.appliedAdvance) {
        _fail(ForumBodyParagraphRowReferenceFailure.geometry);
      }
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxLines, maxAtoms;
  ForumBodyInlineParagraphLease? _natural, _isolated;
  void Function()? _ensureOwner;
  List<int>? _atoms = [];
  ForumBodyInlineRowReference? _result;
  int _row = 0, _atom = 0, _atomRow = 0;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;
  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline row reference is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final a = _natural!.layout, b = _isolated!.layout;
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
          _row++;
        } else if (_atom < a.atomBoxes.length) {
          final atom = a.projection.atoms[_atom];
          if (_atomRow >= a.lineCount) {
            _fail(ForumBodyParagraphRowReferenceFailure.geometry);
          }
          final row = a.lines[_atomRow];
          if (atom.engineUtf16 >= row.engineCoverageEndUtf16) {
            _atomRow++;
          } else {
            final first = a.atomBoxes[_atom], last = b.atomBoxes[_atom];
            if (atom.engineUtf16 < row.engineCoverageStartUtf16 ||
                first.left != last.left ||
                first.right != last.right ||
                first.direction != last.direction ||
                a.isAtomTrimmed(_atom) != b.isAtomTrimmed(_atom)) {
              _fail(ForumBodyParagraphRowReferenceFailure.geometry);
            }
            // Native vertical boxes and declared physical dimensions remain
            // distinct; Float32 endpoint rounding is not a source projection.
            _atoms!.add(_atomRow);
            _atom++;
          }
        } else {
          _result = ForumBodyInlineRowReference._(
            _natural!,
            _isolated!,
            _atoms!,
          );
          _atoms = null;
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

  ForumBodyInlineRowReference takeReference() {
    if (_operating) throw StateError('Inline row reference is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Inline row reference is incomplete');
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

  static Never _fail(ForumBodyParagraphRowReferenceFailure failure) =>
      throw ForumBodyParagraphRowReferenceException(failure);
  void _guard() {
    if (_closed) throw StateError('Inline row reference is retired');
    _ensureOwner!();
    if (_closed || _natural?.isActive != true || _isolated?.isActive != true) {
      throw StateError('Inline row reference owner is retired');
    }
  }

  void close() {
    _closed = true;
    _natural = null;
    _isolated = null;
    _ensureOwner = null;
    _atoms = null;
    _result = null;
  }
}

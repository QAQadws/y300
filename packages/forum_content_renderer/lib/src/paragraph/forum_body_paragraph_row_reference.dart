import 'forum_body_paragraph_cache.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_layout.dart';
import 'forum_body_paragraph_geometry.dart'
    show forumBodyHaveSameParagraphLineInputs;

enum ForumBodyParagraphRowReferenceFailure { source, geometry, limit }

final class ForumBodyParagraphRowReferenceException implements Exception {
  const ForumBodyParagraphRowReferenceException(this.failure);
  final ForumBodyParagraphRowReferenceFailure failure;
  @override
  String toString() =>
      'ForumBodyParagraphRowReferenceException(${failure.name})';
}

/// Actual native natural and isolated row coordinates for the same full source.
/// These immutable numeric rows retain no layout, lease, owner or native object.
/// Neither the snapshot nor its keys authorize painting or source coverage.
final class ForumBodyParagraphRowReference {
  ForumBodyParagraphRowReference._(
    this.content,
    ForumBodyParagraphLease natural,
    ForumBodyParagraphLease isolated,
  ) : naturalInputIdentity = natural.nativeInputIdentity,
      isolatedInputIdentity = isolated.nativeInputIdentity,
      naturalLines = natural.layout.lines,
      isolatedLines = isolated.layout.lines,
      width = natural.layout.width,
      naturalHeight = natural.layout.height,
      isolatedHeight = isolated.layout.height,
      naturalBaseline = natural.layout.alphabeticBaseline,
      isolatedBaseline = isolated.layout.alphabeticBaseline,
      firstLineIndent = natural.layout.firstLineIndent,
      rowIsolationPitch = isolated.layout.rowIsolationPitch!;

  static const revision = 1;
  final ForumBodyParagraphContent content;
  final Object naturalInputIdentity, isolatedInputIdentity;
  final List<ForumBodyParagraphLine> naturalLines, isolatedLines;
  final double width, naturalHeight, isolatedHeight;
  final double naturalBaseline, isolatedBaseline, rowIsolationPitch;
  final ForumBodyFirstLineIndentGeometry firstLineIndent;
  int get lineCount => naturalLines.length;
}

/// Borrows two already acquired full-source paragraphs from the same cache.
/// One part verifies one actual row; final publication is a separate part.
/// It performs no native work, acquires no aliases and releases no caller lease.
final class ForumBodyParagraphRowReferencePreparation {
  ForumBodyParagraphRowReferencePreparation({
    required ForumBodyParagraphLease natural,
    required ForumBodyParagraphLease isolated,
    required void Function() ensureOwner,
    this.maxLines = 4096,
  }) : _natural = natural,
       _isolated = isolated,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0) throw ArgumentError.value(maxLines, 'maxLines');
    try {
      _guard();
      if (!natural.hasSameSourceAndInputsExceptRowIsolation(isolated) ||
          natural.content.isSourceFree ||
          natural.content.layoutMode != ForumBodyParagraphLayoutMode.wrap ||
          natural.layout.rowIsolationPitch != null ||
          isolated.layout.rowIsolationPitch == null) {
        _fail(ForumBodyParagraphRowReferenceFailure.source);
      }
      final a = natural.layout, b = isolated.layout;
      if (a.lineCount > maxLines || b.lineCount > maxLines) {
        _fail(ForumBodyParagraphRowReferenceFailure.limit);
      }
      if (a.lineCount != b.lineCount ||
          a.width != b.width ||
          a.paintScale != b.paintScale ||
          a.horizontalInset != b.horizontalInset ||
          a.firstLineIndent.requestedAdvance !=
              b.firstLineIndent.requestedAdvance ||
          a.firstLineIndent.appliedAdvance !=
              b.firstLineIndent.appliedAdvance) {
        _fail(ForumBodyParagraphRowReferenceFailure.geometry);
      }
      for (final layout in [a, b]) {
        if (!layout.width.isFinite ||
            !layout.height.isFinite ||
            layout.height < 0 ||
            !layout.alphabeticBaseline.isFinite) {
          _fail(ForumBodyParagraphRowReferenceFailure.geometry);
        }
      }
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }

  final int maxLines;
  ForumBodyParagraphLease? _natural, _isolated;
  void Function()? _ensureOwner;
  ForumBodyParagraphRowReference? _result;
  int _row = 0;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts, 'maxParts');
    if (_operating) throw StateError('Row reference preparation is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (used < maxParts && !isReady) {
        final a = _natural!.layout, b = _isolated!.layout;
        if (_row < a.lineCount) {
          _verifyRow(a.lines[_row], b.lines[_row]);
          _row++;
        } else {
          _result = ForumBodyParagraphRowReference._(
            _natural!.content,
            _natural!,
            _isolated!,
          );
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

  void _verifyRow(ForumBodyParagraphLine a, ForumBodyParagraphLine b) {
    // Struts may move vertical geometry only. Keep engine paint/coverage and
    // legal source boundaries distinct, including hard breaks/trailing spaces.
    if (!forumBodyHaveSameParagraphLineInputs(a, b)) {
      _fail(ForumBodyParagraphRowReferenceFailure.geometry);
    }
    for (final line in [a, b]) {
      if (!line.top.isFinite ||
          !line.bottom.isFinite ||
          line.bottom < line.top ||
          !line.baseline.isFinite ||
          !line.left.isFinite ||
          !line.width.isFinite ||
          line.width < 0) {
        _fail(ForumBodyParagraphRowReferenceFailure.geometry);
      }
    }
  }

  ForumBodyParagraphRowReference takeReference() {
    if (_operating) throw StateError('Row reference preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Row reference preparation is incomplete');
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
    if (_closed) throw StateError('Row reference preparation is retired');
    _ensureOwner!();
    if (_closed || _natural?.isActive != true || _isolated?.isActive != true) {
      throw StateError('Row reference owner is retired');
    }
  }

  void close() {
    _closed = true;
    _natural = null;
    _isolated = null;
    _ensureOwner = null;
    _result = null;
  }
}

Never _fail(ForumBodyParagraphRowReferenceFailure failure) =>
    throw ForumBodyParagraphRowReferenceException(failure);

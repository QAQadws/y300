import 'dart:collection';

import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import 'forum_body_emphasis_allocation_geometry.dart';
import 'forum_body_inline_emphasis_row_allocation.dart';
import 'forum_body_inline_paragraph_request.dart';
import 'forum_body_inline_span_content.dart';

/// Numeric qualification of the actual current source and three whole native
/// paint layers. No lease/cache/owner is retained and no source is authorized
/// by a paint-only input. A later binding must match these exact line tables.
final class ForumBodyInlineEmphasisPaintReference {
  ForumBodyInlineEmphasisPaintReference._(
    this.allocation,
    this.paintInput,
    ForumBodyInlineParagraphLease source,
    List<ForumBodyInlineParagraphLease> phases,
    this.requests,
    this.glyphQueries,
  ) : sourceInputIdentity = source.nativeInputIdentity,
      sourceLines = source.layout.lines,
      phaseInputIdentities = UnmodifiableListView([
        for (final p in phases) p.nativeInputIdentity,
      ]),
      phaseLines = UnmodifiableListView([
        for (final p in phases) p.layout.lines,
      ]);
  static const revision = 1;
  final ForumBodyInlineEmphasisRowAllocation allocation;
  final ForumBodyInlinePaintInput paintInput;
  final Object sourceInputIdentity;
  final List<ForumBodyParagraphLine> sourceLines;
  final List<Object> phaseInputIdentities;
  final List<List<ForumBodyParagraphLine>> phaseLines;
  final List<ForumBodyInlineParagraphRequest> requests;
  final int glyphQueries;
  Iterable<ForumBodyNativeRequestSlot> get nativeFootprint sync* {
    final input = allocation.input;
    for (final request in [input.request, ...requests]) {
      yield (
        request: request,
        width: input.natural.requestWidth,
        minimumLineCount: sourceLines.length,
      );
    }
  }
}

enum _Phase {
  inputs,
  rows,
  atoms,
  sourceFrames,
  phaseFrames,
  frames,
  sourceGlyph,
  phaseGlyph,
  publish,
  ready,
  closed,
}

/// Borrows the caller's four current resources. Each part checks one request,
/// actual row/slot/frame or native scalar glyph. No acquire, shape, recording
/// or handle release occurs, including cancellation and failed qualification.
final class ForumBodyInlineEmphasisPaintReferencePreparation {
  ForumBodyInlineEmphasisPaintReferencePreparation({
    required ForumBodyInlineEmphasisRowAllocation allocation,
    required ForumBodyInlinePaintInput paintInput,
    required ForumBodyInlineParagraphLease source,
    required List<ForumBodyInlineParagraphLease> phases,
    required void Function() ensureOwner,
    this.maxLines = 4096,
    this.maxAtoms = 512,
    this.maxBoxes = 32768,
    this.maxGlyphQueries = 65536,
  }) : _allocation = allocation,
       _paint = paintInput,
       _source = source,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0 || maxAtoms < 0 || maxBoxes < 0 || maxGlyphQueries < 0) {
      throw ArgumentError('Invalid mixed paint reference budget');
    }
    try {
      _guard();
      final input = allocation.input;
      if (phases.length != 3 ||
          !identical(source.content, paintInput.original) ||
          !identical(source.content, input.request.content) ||
          source.nativeInputIdentity != input.reference.isolatedInputIdentity ||
          !identical(source.layout.lines, input.reference.isolatedLines) ||
          allocation.rows.length != source.layout.lineCount) {
        _fail();
      }
      if (source.layout.lineCount > maxLines ||
          source.layout.atomBoxes.length > maxAtoms) {
        _limit();
      }
      _phases = List.unmodifiable(phases);
      _requests = List.unmodifiable([
        for (final content in [
          paintInput.background,
          paintInput.foreground,
          paintInput.decoration,
        ])
          ForumBodyInlineParagraphRequest(
            content: content,
            dimensions: input.request.dimensions,
            layoutMode: input.request.layoutMode,
            rowIsolationPitch: input.request.rowIsolationPitch,
          ),
      ]);
      _offset = source.layout.projection.enginePrefix.length;
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }

  final int maxLines, maxAtoms, maxBoxes, maxGlyphQueries;
  ForumBodyInlineEmphasisRowAllocation? _allocation;
  ForumBodyInlinePaintInput? _paint;
  ForumBodyInlineParagraphLease? _source;
  List<ForumBodyInlineParagraphLease> _phases = const [];
  List<ForumBodyInlineParagraphRequest> _requests = const [];
  void Function()? _ensureOwner;
  List<ForumBodyParagraphMaximumLineFrame>? _sourceFrames, _phaseFrames;
  ForumBodyParagraphGlyphGeometry? _glyph;
  ForumBodyInlineEmphasisPaintReference? _result;
  var _phase = _Phase.inputs;
  int _layer = -1, _row = 0, _atom = 0, _box = 0, _offset = 0, _queries = 0;
  bool _operating = false;
  bool get isReady => _phase == _Phase.ready;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed paint reference is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final source = _source!, a = source.layout, input = _allocation!.input;
        switch (_phase) {
          case _Phase.inputs:
            final parent = _layer < 0 ? source : _phases[_layer],
                request = _layer < 0 ? input.request : _requests[_layer],
                b = parent.layout;
            if (!parent.matchesNativeInputs(
              content: request.content,
              width: input.natural.requestWidth,
              dimensions: request.dimensions,
              textScaler: input.natural.textScaler,
              layoutMode: request.layoutMode,
              rowIsolationPitch: request.rowIsolationPitch,
            )) {
              _fail();
            }
            _guard();
            if (b.lineCount != a.lineCount ||
                b.atomBoxes.length != a.atomBoxes.length ||
                b.width != a.width ||
                b.height != a.height ||
                b.nativeFontClearance != a.nativeFontClearance ||
                b.nativeFlowTop != a.nativeFlowTop ||
                b.nativeFlowBottom != a.nativeFlowBottom ||
                b.nativeAlphabeticBaseline != a.nativeAlphabeticBaseline ||
                !identical(b.projection, a.projection) ||
                b.firstLineIndent.requestedAdvance !=
                    a.firstLineIndent.requestedAdvance ||
                b.firstLineIndent.appliedAdvance !=
                    a.firstLineIndent.appliedAdvance) {
              _geometry();
            }
            if (++_layer == 3) {
              _layer = 0;
              _phase = _Phase.rows;
            }
          case _Phase.rows:
            if (_row < a.lineCount) {
              final x = a.lines[_row], y = _phases[_layer].layout.lines[_row];
              if (!forumBodyHaveSameParagraphLineInputs(x, y) ||
                  (x.top, x.bottom, x.baseline) !=
                      (y.top, y.bottom, y.baseline)) {
                _geometry();
              }
              _row++;
            } else if (++_layer < 3) {
              _row = 0;
            } else {
              _layer = 0;
              _phase = _Phase.atoms;
            }
          case _Phase.atoms:
            if (_atom < a.atomBoxes.length) {
              final b = _phases[_layer].layout,
                  x = a.atomBoxes[_atom],
                  y = b.atomBoxes[_atom];
              if ((x.left, x.top, x.right, x.bottom, x.direction) !=
                      (y.left, y.top, y.right, y.bottom, y.direction) ||
                  a.isAtomTrimmed(_atom) != b.isAtomTrimmed(_atom)) {
                _geometry();
              }
              _atom++;
            } else if (++_layer < 3) {
              _atom = 0;
            } else {
              _layer = 0;
              _phase = _Phase.sourceFrames;
            }
          case _Phase.sourceFrames:
            _sourceFrames = a.queryMaximumLineFrames();
            if (_sourceFrames!.length > maxBoxes) _limit();
            _phase = _Phase.phaseFrames;
          case _Phase.phaseFrames:
            _phaseFrames = _phases[_layer].layout.queryMaximumLineFrames();
            if (_phaseFrames!.length > maxBoxes) _limit();
            if (_phaseFrames!.length != _sourceFrames!.length) _geometry();
            _box = 0;
            _phase = _Phase.frames;
          case _Phase.frames:
            if (_box < _sourceFrames!.length) {
              if (_sourceFrames![_box] != _phaseFrames![_box]) _geometry();
              _box++;
            } else {
              _phaseFrames = null;
              if (++_layer < 3) {
                _phase = _Phase.phaseFrames;
              } else {
                _sourceFrames = null;
                _phase = _Phase.sourceGlyph;
              }
            }
          case _Phase.sourceGlyph:
            if (_offset < a.projection.engineText.length) {
              _query();
              _glyph = a.glyphAtEngineUtf16(_offset);
              _layer = 0;
              _phase = _Phase.phaseGlyph;
            } else {
              _phase = _Phase.publish;
            }
          case _Phase.phaseGlyph:
            _query();
            final glyph = _phases[_layer].layout.glyphAtEngineUtf16(_offset),
                expected = _glyph;
            if (glyph == null || expected == null) {
              if (glyph != expected) _geometry();
            } else if (glyph.lineIndex != expected.lineIndex ||
                glyph.fontBounds != expected.fontBounds ||
                glyph.engineClusterRange != expected.engineClusterRange ||
                glyph.direction != expected.direction) {
              _geometry();
            }
            if (++_layer == 3) {
              // Visit each native scalar, including controls/style seams. This
              // cursor is never a source/grapheme boundary or slicing offset.
              final text = a.projection.engineText,
                  unit = text.codeUnitAt(_offset++);
              if (unit >= 0xd800 &&
                  unit <= 0xdbff &&
                  _offset < text.length &&
                  text.codeUnitAt(_offset) >= 0xdc00 &&
                  text.codeUnitAt(_offset) <= 0xdfff) {
                _offset++;
              }
              _glyph = null;
              _phase = _Phase.sourceGlyph;
            }
          case _Phase.publish:
            _result = ForumBodyInlineEmphasisPaintReference._(
              _allocation!,
              _paint!,
              source,
              _phases,
              _requests,
              _queries,
            );
            _phase = _Phase.ready;
          case _Phase.ready:
          case _Phase.closed:
            throw StateError('Mixed paint reference is retired');
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

  void _query() {
    if (_queries >= maxGlyphQueries) _limit();
    _queries++;
  }

  ForumBodyInlineEmphasisPaintReference takeReference() {
    if (_operating) throw StateError('Mixed paint reference is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Mixed paint reference is incomplete');
      final value = _result!;
      close();
      return value;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _Phase.closed) {
      throw StateError('Mixed paint reference is retired');
    }
    _ensureOwner!();
    if (_phase == _Phase.closed ||
        _source?.isActive != true ||
        _phases.any((p) => !p.hasSameActiveOwner(_source!))) {
      throw StateError('Mixed paint reference owner is retired');
    }
  }

  void close() {
    _phase = _Phase.closed;
    _allocation = null;
    _paint = null;
    _source = null;
    _phases = const [];
    _requests = const [];
    _ensureOwner = null;
    _sourceFrames = _phaseFrames = null;
    _glyph = null;
    _result = null;
  }
}

Never _fail() => throw const ForumBodyEmphasisAllocationException(
  ForumBodyEmphasisAllocationFailure.source,
);
Never _geometry() => throw const ForumBodyEmphasisAllocationException(
  ForumBodyEmphasisAllocationFailure.geometry,
);
Never _limit() => throw const ForumBodyEmphasisAllocationException(
  ForumBodyEmphasisAllocationFailure.limit,
);

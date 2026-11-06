import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import 'forum_body_emphasis_allocation_geometry.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_inline_emphasis_row_allocation.dart';

/// Actual prepared marker fonts plus commands for the containing ONE scene.
/// Commands carry no source authority. Closing this binding releases only its
/// font aliases; a scene already prepared from them remains independently owned.
final class ForumBodyInlineEmphasisMarkerBinding {
  ForumBodyInlineEmphasisMarkerBinding._(
    this.allocation,
    this.startLine,
    this.endLine,
    this.top,
    this.height,
    this.pictureInput,
    List<ForumBodyEmphasisMarkLease> fonts,
    ForumBodyParagraphCache cache,
    void Function() ensureOwner,
  ) : _fonts = UnmodifiableListView(fonts),
      _cache = cache,
      _ensureOwner = ensureOwner;

  final ForumBodyInlineEmphasisRowAllocation allocation;
  final int startLine, endLine;
  final double top, height;

  /// A genuinely target-free window has no scene input or marker dependencies.
  final ForumBodyTextPictureInput? pictureInput;
  List<ForumBodyEmphasisMarkLease> _fonts;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  bool get isActive =>
      _cache != null && !_cache!.isClosed && _fonts.every(_cache!.ownsLease);
  List<ForumBodyEmphasisMarkLease> get fonts {
    if (!isActive) throw StateError('Mixed markers are retired');
    _ensureOwner!();
    if (!isActive) throw StateError('Mixed marker owner is retired');
    return _fonts;
  }

  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => _fonts;
  void close() {
    final fonts = _fonts;
    _fonts = const [];
    _cache = null;
    _ensureOwner = null;
    for (final font in fonts) {
      font.release();
    }
  }
}

enum _MarkerPhase {
  scales,
  marks,
  compose,
  beginPrefix,
  prefix,
  probe,
  classify,
  acquire,
  qualify,
  publish,
  ready,
  transferred,
  closed,
}

/// Qualifies outside-parent markers against the actual final natural source,
/// reacquires their measured fonts and feeds the existing picture transaction.
/// It neither records a second marker scene nor prepares a readable page.
final class ForumBodyInlineEmphasisMarkerPreparation {
  ForumBodyInlineEmphasisMarkerPreparation({
    required ForumBodyInlineEmphasisRowAllocation allocation,
    required ForumBodyInlineParagraphLease natural,
    required ForumBodyParagraphCache cache,
    required TextScaler expectedTextScaler,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    this.startLine = 0,
    int? endLine,
    this.maxMarks = 32768,
    this.maxFonts = 2048,
    this.maxOwnedLeases = 32768,
  }) : _allocation = allocation,
       _natural = natural,
       _cache = cache,
       _callerScaler = expectedTextScaler,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner ?? ensureOwner,
       _additionalOwned = additionalOwnedLeases,
       endLine = endLine ?? allocation.rows.length {
    if (maxMarks < 0 ||
        maxMarks > ForumBodyTextPictureInput.maximumCommands ||
        maxFonts < 0 ||
        maxOwnedLeases <= 0) {
      throw ArgumentError('Invalid mixed marker budget');
    }
    try {
      _guard();
      final m = allocation.input.natural, ref = allocation.input.reference;
      if (!identical(natural.content, m.text.glyphInput.glyphs) ||
          !identical(m.page.content, m.text.glyphInput.original) ||
          natural.nativeInputIdentity != ref.naturalInputIdentity ||
          !identical(natural.layout.lines, ref.naturalLines) ||
          natural.layout.rowIsolationPitch != null) {
        _source();
      }
      // Only actual legal source groups may bound a future fragment's marks.
      natural.layout.fragment(startLine, this.endLine);
      if (allocation.marks.length > maxMarks) _limit();
      _top = allocation.rows[startLine].line.top;
      _height = allocation.rows[this.endLine - 1].line.bottom - _top;
      _samples = m.effectiveScales.entries.iterator;
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }

  final int startLine, endLine, maxMarks, maxFonts, maxOwnedLeases;
  ForumBodyInlineEmphasisRowAllocation? _allocation;
  ForumBodyInlineParagraphLease? _natural;
  ForumBodyParagraphCache? _cache;
  TextScaler? _callerScaler;
  Iterator<MapEntry<double, double>>? _samples;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  List<int> _selected = [], _fontIndices = [];
  Set<int> _seenFonts = {};
  List<ForumBodyEmphasisMarkLease> _fonts = [];
  ForumBodyTextPictureInputComposition? _composition;
  ForumBodyTextPictureInput? _input;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  List<ForumBodyNativeParagraphLease> _owned = [];
  ForumBodyParagraphBudgetException? _rejection;
  ForumBodyInlineEmphasisMarkerBinding? _result;
  var _phase = _MarkerPhase.scales, _resume = _MarkerPhase.acquire;
  int _mark = 0, _font = 0, _slot = 0, _blockedAt = -1, _rejectedAt = -1;
  double _top = 0, _height = 0;
  bool _operating = false, _miss = false;
  bool get isReady => _phase == _MarkerPhase.ready;
  bool get cacheMiss => _miss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _result?.nativeLeases ?? _fonts;

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed marker preparation is reentrant');
    _operating = true;
    final cache = _cache,
        shapes = cache?.layoutBuildCount ?? 0,
        pictures = cache?.pictureBuildCount ?? 0;
    var used = 0;
    ForumBodyEmphasisLineStep step([bool wait = false]) => (
      partsPrepared: used,
      nativeLayoutsBuilt: cache!.layoutBuildCount - shapes,
      picturesRecorded: cache.pictureBuildCount - pictures,
      waitingForLayoutBudget: wait,
    );
    try {
      _guard();
      _miss = false;
      if (_blockedAt == cache!.budgetRevision) return step(true);
      while (!isReady &&
          used < maxParts &&
          cache.layoutBuildCount == shapes &&
          cache.pictureBuildCount == pictures) {
        final a = _allocation!,
            m = a.input.natural,
            placement = m.reflow.placement,
            fm = placement.input.fonts;
        final rejectedAt = cache.budgetRevision;
        try {
          switch (_phase) {
            case _MarkerPhase.scales:
              if (_samples!.moveNext()) {
                final sample = _samples!.current,
                    actual = _callerScaler!.scale(sample.key);
                _guard();
                if (actual != sample.value) _source();
              } else {
                _samples = null;
                _callerScaler = null;
                _phase = _MarkerPhase.marks;
              }
            case _MarkerPhase.marks:
              if (_mark < a.marks.length) {
                final index = _mark++, mark = a.marks[index];
                if (mark.lineIndex >= startLine && mark.lineIndex < endLine) {
                  _selected.add(index);
                  if (_seenFonts.add(mark.fontIndex)) {
                    if (_fontIndices.length >= maxFonts) _limit();
                    _fontIndices.add(mark.fontIndex);
                  }
                }
              } else if (_selected.isEmpty) {
                _phase = _MarkerPhase.publish;
              } else {
                if (1 + _fontIndices.length > maxOwnedLeases) _limit();
                _composition = ForumBodyTextPictureInputComposition(
                  inputs: _commands(),
                  ensureOwner: _guard,
                  maxInputs: maxMarks,
                  maxCommands: maxMarks,
                );
                _phase = _MarkerPhase.compose;
              }
            case _MarkerPhase.compose:
              used += _composition!.advance(maxParts: maxParts - used);
              _guard();
              if (_composition!.isReady) {
                _input = _composition!.takeInput();
                _composition!.close();
                _composition = null;
                _phase = _MarkerPhase.beginPrefix;
              }
              continue;
            case _MarkerPhase.beginPrefix:
              _probe?.close();
              _probe = cache.createBudgetProbe();
              _owned = [];
              final extra =
                  _additionalOwned?.call() ??
                  const <ForumBodyNativeParagraphLease>[];
              _guard();
              _prefix = <ForumBodyNativeParagraphLease>[
                _natural!,
              ].followedBy(_fonts).followedBy(extra).iterator;
              _guard();
              _slot = 0;
              _phase = _MarkerPhase.prefix;
            case _MarkerPhase.prefix:
              final more = _prefix!.moveNext();
              _guard();
              if (more) {
                // Include current aliases AND reserve the remaining font slots.
                if (_owned.length + (_fontIndices.length - _fonts.length) >=
                    maxOwnedLeases) {
                  _limit();
                }
                final lease = _prefix!.current;
                _guard();
                _probe!.includeLease(lease);
                _owned.add(lease);
              } else {
                _prefix = null;
                _phase = _MarkerPhase.probe;
              }
            case _MarkerPhase.probe:
              if (_slot < _fontIndices.length) {
                fm.fonts[_fontIndices[_slot++]].request.includeBudget(
                  _probe!,
                  width: m.requestWidth,
                  textScaler: m.textScaler,
                );
              } else {
                _probe!.close();
                _probe = null;
                _phase = _rejection == null ? _resume : _MarkerPhase.classify;
              }
            case _MarkerPhase.classify:
              final external = cache.isBlockedByExternalPins(
                _rejection!,
                _owned,
              );
              _guard();
              if (cache.budgetRevision != _rejectedAt) {
                _rejection = null;
                _phase = _MarkerPhase.beginPrefix;
              } else if (!external) {
                throw ForumBodyParagraphBudgetException(
                  ForumBodyParagraphBudgetFailure.content,
                  requiredEstimatedBytes: _rejection!.requiredEstimatedBytes,
                  requiredAdditionalEntries:
                      _rejection!.requiredAdditionalEntries,
                );
              } else {
                _blockedAt = _rejectedAt;
                _rejection = null;
                _phase = _MarkerPhase.beginPrefix;
                used++;
                return step(true);
              }
            case _MarkerPhase.acquire:
              final lease = fm.fonts[_fontIndices[_font]].request.acquire(
                cache,
                width: m.requestWidth,
                textScaler: m.textScaler,
                cachedOnly: cachedOnly,
              );
              if (lease == null) {
                _guard();
                _miss = true;
                _phase = _MarkerPhase.beginPrefix;
                used++;
                return step();
              }
              _fonts.add(lease);
              _guard();
              _phase = _MarkerPhase.qualify;
            case _MarkerPhase.qualify:
              final expected = fm.fonts[_fontIndices[_font]],
                  actual = _fonts.last,
                  layout = actual.layout;
              if (actual.nativeInputIdentity != expected.nativeInputIdentity ||
                  !identical(actual.input, expected.input) ||
                  layout.width != expected.width ||
                  layout.height != expected.height ||
                  layout.alphabeticBaseline != expected.alphabeticBaseline ||
                  layout.fontBounds != expected.fontBounds ||
                  m.textScaler.scale(expected.input.textStyle.fontSize!) !=
                      expected.scaledFontSize) {
                _source();
              }
              _guard();
              _font++;
              _resume = _MarkerPhase.acquire;
              _phase = _font == _fontIndices.length
                  ? _MarkerPhase.publish
                  : _MarkerPhase.beginPrefix;
            case _MarkerPhase.publish:
              _ensureVisibleOwner!();
              _guard();
              _result = ForumBodyInlineEmphasisMarkerBinding._(
                a,
                startLine,
                endLine,
                _top,
                _height,
                _input,
                _fonts,
                cache,
                _ensureVisibleOwner!,
              );
              _fonts = [];
              if (!_result!.isActive) {
                throw StateError('Mixed marker binding is retired');
              }
              _phase = _MarkerPhase.ready;
            case _MarkerPhase.ready:
            case _MarkerPhase.transferred:
            case _MarkerPhase.closed:
              throw StateError('Mixed marker preparation is retired');
          }
        } on ForumBodyParagraphBudgetException catch (error) {
          _guard();
          if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
          _resume = _phase;
          _rejection = error;
          _rejectedAt = rejectedAt;
          _phase = _MarkerPhase.beginPrefix;
        }
        used++;
        _guard();
      }
      return step();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  Iterable<ForumBodyPositionedTextPictureInput> _commands() sync* {
    final a = _allocation!, m = a.input.natural, p = m.reflow.placement;
    for (final index in _selected) {
      final mark = p.marks[index],
          row = a.rows[mark.lineIndex],
          font = p.input.fonts.fonts[mark.fontIndex];
      yield (
        input: ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
                  nativeInputIdentity: font.nativeInputIdentity,
                  offset: mark.fontOffset,
                )
                .translated(mark.baselineOrigin)
                .translated(Offset(0, m.reflow.baselineDeltas[mark.lineIndex]))
                .translated(row.naturalOffset),
          ],
        ),
        offset: Offset(0, -_top),
      );
    }
  }

  ForumBodyInlineEmphasisMarkerBinding takeBinding() {
    if (_operating) throw StateError('Mixed marker preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Mixed markers are incomplete');
      _ensureVisibleOwner!();
      _guard();
      final result = _result!;
      _result = null;
      _phase = _MarkerPhase.transferred;
      _drop();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _MarkerPhase.closed || _phase == _MarkerPhase.transferred) {
      throw StateError('Mixed marker preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _MarkerPhase.closed ||
        _cache!.isClosed ||
        !_cache!.ownsLease(_natural!)) {
      throw StateError('Mixed marker owner is retired');
    }
  }

  void close() {
    if (_phase == _MarkerPhase.closed || _phase == _MarkerPhase.transferred) {
      return;
    }
    _phase = _MarkerPhase.closed;
    for (final font in _fonts) {
      font.release();
    }
    _fonts = [];
    _result?.close();
    _result = null;
    _drop();
  }

  void _drop() {
    _composition?.close();
    _composition = null;
    _probe?.close();
    _probe = null;
    _allocation = null;
    _natural = null;
    _cache = null;
    _callerScaler = null;
    _samples = null;
    _ensureOwner = _ensureVisibleOwner = null;
    _additionalOwned = null;
    _prefix = null;
    _owned = [];
    _selected = [];
    _fontIndices = [];
    _seenFonts = {};
    _input = null;
    _rejection = null;
  }

  static Never _source() => throw const ForumBodyEmphasisAllocationException(
    ForumBodyEmphasisAllocationFailure.source,
  );
  static Never _limit() => throw const ForumBodyEmphasisAllocationException(
    ForumBodyEmphasisAllocationFailure.limit,
  );
}

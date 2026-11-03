import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../inline/forum_body_inline_paragraph_layout.dart';
import '../inline/forum_body_emphasis_paragraph_metrics.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import 'forum_body_source_hint.dart';

part 'forum_body_emphasis_scene_reservation.dart';

enum ForumBodyTextPageFailure {
  oversizedGroup,
  invalidGeometry,
  pageLimit,
  fragmentLimit,
  nativeHandleLimit,
  nativeEntryLimit,
  nativeByteLimit,
  sceneLimit,
}

enum ForumBodyTextPageFragmentKind { paragraph, inline, emphasis }

final class ForumBodyTextPageException implements Exception {
  const ForumBodyTextPageException(this.failure);
  final ForumBodyTextPageFailure failure;
  @override
  String toString() => 'ForumBodyTextPageException(${failure.name})';
}

/// Numeric placement only: no paragraph, lease, text span, Context or callback
/// is retained by a published page. The session owns content materialization.
final class ForumBodyTextPageFragment {
  const ForumBodyTextPageFragment._({
    required this.paragraphIndex,
    required this.path,
    required this.fontRevision,
    required this.styleRevision,
    required this.startLine,
    required this.endLine,
    required this.coverageStartUtf16,
    required this.coverageEndUtf16,
    required this.sourceHint,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.kind,
  });
  final int paragraphIndex;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final int startLine;
  final int endLine;
  final int coverageStartUtf16;
  final int coverageEndUtf16;

  /// Inclusive raw source envelope, only a candidate hint. It can contain
  /// hidden/unmapped gaps. Zero-text rows and padding have no source hint.
  final ({int runeStart, int runeEnd})? sourceHint;
  final double left;
  final double top;
  final double width;
  final double height;
  final ForumBodyTextPageFragmentKind kind;
}

final class ForumBodyTextPage {
  ForumBodyTextPage._(
    this.index,
    List<ForumBodyTextPageFragment> fragments,
    this.usedHeight,
  ) : fragments = List.unmodifiable(fragments);
  final int index;
  final List<ForumBodyTextPageFragment> fragments;
  final double usedHeight;
}

/// Fixed read-only prefix over append-only storage. Completion and length are
/// captured at creation, so later publication never changes an earlier view.
/// Coverage offsets are paragraph-local display UTF-16, not semantic anchors.
final class ForumBodyTextPageSnapshot
    extends UnmodifiableListView<ForumBodyTextPage> {
  ForumBodyTextPageSnapshot._(
    List<ForumBodyTextPage> pages,
    this.identity,
    this.layoutId,
    this.width,
    this.height,
    this.isComplete,
  ) : backendRevision = ForumBodyParagraphLayout.backendRevision,
      composerRevision = ForumBodyTextPageComposer.revision,
      super(_PagePrefix(pages, pages.length));
  final ForumBodyIdentity identity;

  /// Caller-owned layout generation tag, never persisted as a reading anchor.
  final String layoutId;
  final double width;
  final double height;
  final int backendRevision;
  final int composerRevision;
  final bool isComplete;
}

final class _PagePrefix extends ListBase<ForumBodyTextPage> {
  _PagePrefix(this._pages, this._length);
  final List<ForumBodyTextPage> _pages;
  final int _length;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('Fixed page prefix');
  @override
  ForumBodyTextPage operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _pages[index];
  }

  @override
  void operator []=(int index, ForumBodyTextPage value) =>
      throw UnsupportedError('Read-only page prefix');
}

/// Text and mixed-inline composition over actual native line geometry.
/// The block layer resolves CSS/reader spacing and horizontal placement first;
/// this class does not collapse margins or infer settings. It consumes at most
/// one paragraph lease, releases it on completion/close/failure, and stops each
/// advance at the next stable page. Demand, idle waits and retry generations
/// belong to the Host. It never shapes or slices HTML.
/// Signed inter-paragraph spacing can overlap earlier content on the current
/// page. The flow cursor and occupied height are separate: overlap never erases
/// earlier fragment extents. Placement is clamped at the current page's top; sealed
/// pages cannot be pulled back into. Page-start spacing is explicit/nonnegative.
final class ForumBodyTextPageComposer {
  ForumBodyTextPageComposer({
    required this.identity,
    required this.layoutId,
    required this.width,
    required this.height,
    required this.maxPages,
    required this.maxFragments,
    this.maxNativeHandlesPerPage,
    this.maxNativeEntriesPerPage,
    this.maxNativeEstimatedBytesPerPage,
  }) {
    if (layoutId.isEmpty ||
        !width.isFinite ||
        width <= 0 ||
        !height.isFinite ||
        height <= 0 ||
        maxPages <= 0 ||
        maxFragments <= 0 ||
        (maxNativeHandlesPerPage != null && maxNativeHandlesPerPage! <= 0) ||
        (maxNativeEntriesPerPage != null && maxNativeEntriesPerPage! <= 0) ||
        (maxNativeEstimatedBytesPerPage != null &&
            maxNativeEstimatedBytesPerPage! <= 0)) {
      throw ArgumentError('Invalid page composition inputs');
    }
  }
  static const revision = 12;
  final ForumBodyIdentity identity;
  final String layoutId;
  final double width;
  final double height;

  /// Explicit metadata budgets, not measured native/GPU memory.
  final int maxPages;
  final int maxFragments;
  final int? maxNativeHandlesPerPage;
  final int? maxNativeEntriesPerPage;
  final int? maxNativeEstimatedBytesPerPage;
  final _nativeEntries = <Object, int>{};
  int _nativeBytes = 0;
  int _usedNativeHandles = 0;
  int _lastFragmentNativeHandles = 0;
  int _sceneEntries = 0, _sceneBytes = 0;
  _EmphasisSceneReservation? _lastSceneReservation;
  final _pages = <ForumBodyTextPage>[];
  final _draft = <ForumBodyTextPageFragment>[];
  ForumBodyTextPageSnapshot? _snapshot;
  _ActiveParagraph? _active;
  _ActivePadding? _padding;
  int _nextParagraphIndex = 0;
  int _fragmentCount = 0;
  double _usedHeight = 0;
  double _flowHeight = 0;
  bool _complete = false;
  bool _closed = false;

  bool get isComplete => _complete;
  bool get isClosed => _closed;
  bool get needsInput =>
      !_closed && !_complete && _active == null && _padding == null;
  bool get hasPendingPadding => _padding != null;

  /// Admission order only; consumed input can extend beyond the stable pages.
  /// This ordinal must not be persisted as a confirmed reading position.
  int get nextParagraphIndex => _nextParagraphIndex;
  int get retainedFragmentCount => _fragmentCount;
  ForumBodyTextPageSnapshot get snapshot =>
      _snapshot ??= ForumBodyTextPageSnapshot._(
        _pages,
        identity,
        layoutId,
        width,
        height,
        _complete,
      );

  /// Ownership transfers only on success; rejected leases remain the caller's.
  /// Spacing is applied once before the paragraph, never on a continuation page.
  /// The block layer explicitly chooses its spacing when starting a new page.
  void append({
    required ForumBodyParagraphLease lease,
    required int paragraphIndex,
    required double left,
    required double spaceBefore,
    required double spaceAtPageStart,
    ForumBodyParagraphWindow window = ForumBodyParagraphWindow.full,
  }) => _append(
    input: _CompositionParagraph.paragraph(lease),
    paragraphIndex: paragraphIndex,
    left: left,
    spaceBefore: spaceBefore,
    spaceAtPageStart: spaceAtPageStart,
    window: window,
  );

  /// Owns only the already measured parent. Child dimensions are part of its
  /// native input; readable page delivery separately requires source-bound
  /// visible child views, never parent paint or placeholder coverage alone.
  void appendInline({
    required ForumBodyInlineParagraphLease lease,
    required int paragraphIndex,
    required double left,
    required double spaceBefore,
    required double spaceAtPageStart,
    ForumBodyParagraphWindow window = ForumBodyParagraphWindow.full,
    int Function(int startUtf16, int endUtf16)? nativeHandleCountInRange,
    Iterable<Object> Function(int startUtf16, int endUtf16)?
    nativeEntriesInRange,
    Iterable<ForumBodyNativeInputCost> Function(int startUtf16, int endUtf16)?
    nativeCostsInRange,
  }) => _append(
    input: _CompositionParagraph.inline(
      lease,
      nativeHandleCountInRange,
      nativeEntriesInRange,
      nativeCostsInRange,
    ),
    paragraphIndex: paragraphIndex,
    left: left,
    spaceBefore: spaceBefore,
    spaceAtPageStart: spaceAtPageStart,
    window: window,
  );

  /// Numeric complete-group input only. This transfers no native resource;
  /// actual readable delivery must rebind the finalized fragment's source and
  /// single scene. The Host's generation guard remains live until consumption.
  void appendEmphasis({
    required ForumBodyEmphasisParagraphNativeEntries entries,
    required void Function() ensureOwner,
    required int paragraphIndex,
    required double left,
    required double spaceBefore,
    required double spaceAtPageStart,
    ForumBodyParagraphWindow window = ForumBodyParagraphWindow.full,
  }) => _append(
    input: _CompositionParagraph.emphasis(entries, ensureOwner),
    paragraphIndex: paragraphIndex,
    left: left,
    spaceBefore: spaceBefore,
    spaceAtPageStart: spaceAtPageStart,
    window: window,
  );

  void _append({
    required _CompositionParagraph input,
    required int paragraphIndex,
    required double left,
    required double spaceBefore,
    required double spaceAtPageStart,
    required ForumBodyParagraphWindow window,
  }) {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    input.ensureActive();
    _ensureOpen();
    if (paragraphIndex != _nextParagraphIndex ||
        input.identity != identity ||
        !left.isFinite ||
        left < 0 ||
        left + input.width > width ||
        !spaceBefore.isFinite ||
        !spaceAtPageStart.isFinite ||
        spaceAtPageStart < 0) {
      throw ArgumentError('Invalid paragraph composition inputs');
    }
    final range = input.lineWindow(window);
    if (maxNativeHandlesPerPage != null &&
        input.kind == ForumBodyTextPageFragmentKind.inline &&
        input.nativeHandleCountInRange == null) {
      throw ArgumentError(
        'Bounded inline composition requires actual request costs',
      );
    }
    if (maxNativeEntriesPerPage != null &&
        input.kind == ForumBodyTextPageFragmentKind.inline &&
        input.nativeEntriesInRange == null &&
        input.nativeCostsInRange == null) {
      throw ArgumentError(
        'Bounded inline composition requires native entry identities',
      );
    }
    if (maxNativeEstimatedBytesPerPage != null &&
        input.kind == ForumBodyTextPageFragmentKind.inline &&
        input.nativeCostsInRange == null) {
      throw ArgumentError(
        'Bounded inline composition requires native input costs',
      );
    }
    _active = _ActiveParagraph(
      input,
      paragraphIndex,
      left,
      spaceBefore,
      spaceAtPageStart,
      range.startLine,
      range.endLine,
    );
  }

  /// Admit physical padding independently of paragraph spacing. It can occupy
  /// an otherwise empty page and does not imply source/semantic coverage. Each
  /// advance handles at most one page; huge values still obey maxPages. Caller
  /// supplies already resolved padding, not a collapsible margin.
  void appendPadding(
    double extent, {
    double spaceBefore = 0,
    double spaceAtPageStart = 0,
  }) {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    if (!extent.isFinite ||
        extent < 0 ||
        !spaceBefore.isFinite ||
        !spaceAtPageStart.isFinite ||
        spaceAtPageStart < 0) {
      throw ArgumentError.value(extent, 'extent');
    }
    _padding = _ActivePadding(extent, spaceBefore, spaceAtPageStart);
  }

  ({double extentConsumed, int pagesPublished, bool isComplete})
  advancePadding() {
    _ensureOpen();
    final active = _padding;
    if (active == null) throw StateError('No padding is pending');
    final pagesBefore = _pages.length;
    try {
      if (active.remaining == 0) {
        _padding = null;
        return (extentConsumed: 0.0, pagesPublished: 0, isComplete: true);
      }
      if (!active.started) {
        final atPageStart = _draft.isEmpty && _usedHeight == 0;
        final gap = atPageStart ? active.spaceAtPageStart : active.spaceBefore;
        final top = math.max(0.0, _flowHeight + gap);
        if (!top.isFinite) _fail(ForumBodyTextPageFailure.invalidGeometry);
        if (top >= height) {
          if (atPageStart) _fail(ForumBodyTextPageFailure.oversizedGroup);
          _seal();
          return (extentConsumed: 0.0, pagesPublished: 1, isComplete: false);
        }
        _flowHeight = top;
        active.started = true;
      }
      final consumed = math.min(active.remaining, height - _flowHeight);
      _flowHeight += consumed;
      _usedHeight = math.max(_usedHeight, _flowHeight);
      final after = active.remaining - consumed;
      // Subtracting a page remainder must not create a subpixel-only new page
      // for values such as 0.1 + 0.2. Padding carries no source text coverage.
      active.remaining = after;
      if (after <= precisionErrorTolerance) _padding = null;
      if (_usedHeight == height) _seal();
      return (
        extentConsumed: consumed,
        pagesPublished: _pages.length - pagesBefore,
        isComplete: _padding == null,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }

  /// Budget counts inspected physical rows, including rows inside a protected
  /// grapheme. Such a group can span several calls before it can be placed.
  /// A call that publishes a page may inspect zero new rows: its known pending
  /// group remains for the next page. This is publication progress, not a stall.
  ({int linesInspected, int pagesPublished, bool paragraphCompleted}) advance({
    required int maxLines,
  }) {
    _ensureOpen();
    if (maxLines <= 0) throw ArgumentError.value(maxLines, 'maxLines');
    if (_active == null) throw StateError('No paragraph is pending');
    final pagesBefore = _pages.length;
    var inspected = 0;
    try {
      final active = _active!;
      final layout = active.input;
      layout.ensureActive();
      _ensureOpen();
      while (true) {
        if (layout.lines.isEmpty && active.groupEnd == null) {
          active.groupEnd = 0;
        }
        while (active.groupEnd == null && inspected < maxLines) {
          if (active.scanLine >= active.endLine) {
            _fail(ForumBodyTextPageFailure.invalidGeometry);
          }
          final line = layout.lines[active.scanLine++];
          inspected++;
          if (line.canBreakAfter) active.groupEnd = active.scanLine;
        }
        final end = active.groupEnd;
        if (end == null) return _result(inspected, pagesBefore, false);
        final continuation =
            _draft.isNotEmpty && _draft.last.paragraphIndex == active.index;
        final firstLine = continuation
            ? _draft.last.startLine
            : active.nextLine;
        final atPageStart = _draft.isEmpty && _usedHeight == 0;
        final gap = active.nextLine == active.firstLine
            ? (atPageStart ? active.spaceAtPageStart : active.spaceBefore)
            : 0.0;
        final top = continuation
            ? _draft.last.top
            : math.max(0.0, _flowHeight + gap);
        final view = layout.lines.isEmpty
            ? null
            : layout.fragment(firstLine, end);
        final fragmentHeight = view?.height ?? layout.height;
        final bottom = top + fragmentHeight;
        if (!fragmentHeight.isFinite ||
            fragmentHeight < 0 ||
            !bottom.isFinite ||
            bottom < top) {
          _fail(ForumBodyTextPageFailure.invalidGeometry);
        }
        if (bottom > height) {
          if (_draft.isEmpty && _usedHeight == 0) {
            _fail(ForumBodyTextPageFailure.oversizedGroup);
          }
          _seal();
          return _result(inspected, pagesBefore, false);
        }
        if (!continuation && _fragmentCount >= maxFragments) {
          _fail(ForumBodyTextPageFailure.fragmentLimit);
        }
        final emphasis = layout._emphasisEntries;
        _EmphasisSceneReservation? scene;
        _EmphasisSceneAddition? sceneAddition;
        if (emphasis != null) {
          scene = continuation
              ? _lastSceneReservation!
              : _EmphasisSceneReservation(
                  emphasis.inLines(firstLine, end).first.group.top,
                );
          sceneAddition = scene.propose(emphasis.inLines(active.nextLine, end));
          if (!sceneAddition.withinLimits ||
              fragmentHeight >
                  ForumBodyEmphasisFragmentInputPreparation.defaultMaxHeight) {
            if (_draft.isEmpty && _usedHeight == 0) {
              _fail(ForumBodyTextPageFailure.sceneLimit);
            }
            _seal();
            return _result(inspected, pagesBefore, false);
          }
        }
        final replacedSceneBytes = continuation
            ? (_lastSceneReservation?.estimatedBytes ?? 0)
            : 0;
        final proposedSceneEntries =
            _sceneEntries +
            (scene == null ? 0 : 1) -
            (continuation && _lastSceneReservation != null ? 1 : 0);
        final proposedSceneBytes =
            _sceneBytes -
            replacedSceneBytes +
            (sceneAddition?.estimatedBytes ?? 0);
        final limit = maxNativeHandlesPerPage;
        final handles = limit == null
            ? 0
            : emphasis != null
            ? 2
            : layout.nativeHandleCountInRange?.call(
                    view?.coverageStartUtf16 ?? 0,
                    view?.coverageEndUtf16 ?? 0,
                  ) ??
                  1;
        if (limit != null && handles <= 0) {
          _fail(ForumBodyTextPageFailure.invalidGeometry);
        }
        final replaced = continuation ? _lastFragmentNativeHandles : 0;
        final proposed = _usedNativeHandles - replaced + handles;
        if (limit != null && proposed > limit) {
          if (_draft.isEmpty && _usedHeight == 0) {
            _fail(ForumBodyTextPageFailure.nativeHandleLimit);
          }
          _seal();
          return _result(inspected, pagesBefore, false);
        }
        Map<Object, int>? addedEntries;
        final entryLimit = maxNativeEntriesPerPage;
        final byteLimit = maxNativeEstimatedBytesPerPage;
        var addedBytes = 0;
        if (entryLimit != null || byteLimit != null) {
          final from = layout.lines.isEmpty
              ? 0
              : layout.lines[active.nextLine].coverageStartUtf16;
          addedEntries = <Object, int>{};
          if (byteLimit != null) {
            final costs =
                emphasis?.fontCostsInLines(active.nextLine, end) ??
                layout.nativeCostsInRange?.call(
                  from,
                  view?.coverageEndUtf16 ?? 0,
                ) ??
                [
                  (
                    identity: layout.lease!.nativeInputIdentity,
                    estimatedBytes: layout.lease!.nativeLayoutEstimatedBytes,
                  ),
                ];
            for (final cost in costs) {
              if (cost.estimatedBytes <= 0) {
                _fail(ForumBodyTextPageFailure.invalidGeometry);
              }
              addedEntries[cost.identity] = math.max(
                addedEntries[cost.identity] ?? 0,
                cost.estimatedBytes,
              );
            }
          } else {
            for (final entry
                in emphasis
                        ?.fontCostsInLines(active.nextLine, end)
                        .map((cost) => cost.identity) ??
                    layout.nativeEntriesInRange?.call(
                      from,
                      view?.coverageEndUtf16 ?? 0,
                    ) ??
                    layout.nativeCostsInRange
                        ?.call(from, view?.coverageEndUtf16 ?? 0)
                        .map((cost) => cost.identity) ??
                    [layout.lease!.nativeInputIdentity]) {
              addedEntries[entry] = 0;
            }
          }
          _ensureOpen();
          layout.ensureActive();
          if (addedEntries.isEmpty) {
            _fail(ForumBodyTextPageFailure.invalidGeometry);
          }
          final proposedEntries =
              _nativeEntries.length +
              proposedSceneEntries +
              addedEntries.keys
                  .where((entry) => !_nativeEntries.containsKey(entry))
                  .length;
          if (entryLimit != null && proposedEntries > entryLimit) {
            if (_draft.isEmpty && _usedHeight == 0) {
              _fail(ForumBodyTextPageFailure.nativeEntryLimit);
            }
            _seal();
            return _result(inspected, pagesBefore, false);
          }
          for (final entry in addedEntries.entries) {
            final old = _nativeEntries[entry.key] ?? 0;
            addedBytes += math.max(0, entry.value - old);
            addedEntries[entry.key] = math.max(old, entry.value);
          }
          if (byteLimit != null &&
              _nativeBytes + addedBytes + proposedSceneBytes > byteLimit) {
            if (_draft.isEmpty && _usedHeight == 0) {
              _fail(ForumBodyTextPageFailure.nativeByteLimit);
            }
            _seal();
            return _result(inspected, pagesBefore, false);
          }
        }
        // Only inspect newly consumed display text. Reordered source windows
        // need actual range envelopes; rescanning a growing fragment for every
        // appended row would make continuation composition quadratic.
        final addedHint = forumBodySourceHint(
          layout.projection,
          layout.lines.isEmpty
              ? 0
              : layout.lines[active.nextLine].coverageStartUtf16,
          view?.coverageEndUtf16 ?? 0,
        );
        final previousHint = continuation ? _draft.last.sourceHint : null;
        final sourceHint = previousHint == null
            ? addedHint
            : addedHint == null
            ? previousHint
            : (
                runeStart: math.min(
                  previousHint.runeStart,
                  addedHint.runeStart,
                ),
                runeEnd: math.max(previousHint.runeEnd, addedHint.runeEnd),
              );
        final fragment = ForumBodyTextPageFragment._(
          paragraphIndex: active.index,
          path: layout.path,
          fontRevision: layout.fontRevision,
          styleRevision: layout.styleRevision,
          startLine: firstLine,
          endLine: end,
          coverageStartUtf16: view?.coverageStartUtf16 ?? 0,
          coverageEndUtf16: view?.coverageEndUtf16 ?? 0,
          sourceHint: sourceHint,
          left: active.left,
          top: top,
          width: layout.width,
          height: fragmentHeight,
          kind: layout.kind,
        );
        if (continuation) {
          _draft[_draft.length - 1] = fragment;
        } else {
          _draft.add(fragment);
          _fragmentCount++;
        }
        _usedNativeHandles = proposed;
        if (addedEntries != null) _nativeEntries.addAll(addedEntries);
        _nativeBytes += addedBytes;
        if (scene != null) scene.apply(sceneAddition!);
        _lastSceneReservation = scene;
        _sceneEntries = proposedSceneEntries;
        _sceneBytes = proposedSceneBytes;
        _lastFragmentNativeHandles = handles;
        _flowHeight = bottom;
        _usedHeight = math.max(_usedHeight, bottom);
        active.nextLine = end;
        active.scanLine = end;
        active.groupEnd = null;
        final paragraphComplete = end == active.endLine;
        if (paragraphComplete) {
          active.input.lease?.release();
          _active = null;
          _nextParagraphIndex++;
        }
        if (_usedHeight == height) _seal();
        if (paragraphComplete ||
            inspected >= maxLines ||
            _pages.length != pagesBefore) {
          return _result(inspected, pagesBefore, paragraphComplete);
        }
      }
    } catch (_) {
      close();
      rethrow;
    }
  }

  ({int linesInspected, int pagesPublished, bool paragraphCompleted}) _result(
    int inspected,
    int pagesBefore,
    bool complete,
  ) => (
    linesInspected: inspected,
    pagesPublished: _pages.length - pagesBefore,
    paragraphCompleted: complete,
  );

  /// Called only after the upstream block stream reaches EOF. Completion does
  /// not independently prove that the caller consumed all original IR nodes.
  void finish() {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    try {
      if (_draft.isNotEmpty || _usedHeight > 0) _seal();
      _complete = true;
      _snapshot = null;
    } catch (_) {
      close();
      rethrow;
    }
  }

  void _seal() {
    if (_pages.length >= maxPages) _fail(ForumBodyTextPageFailure.pageLimit);
    _pages.add(ForumBodyTextPage._(_pages.length, _draft, _usedHeight));
    _draft.clear();
    _usedNativeHandles = 0;
    _nativeEntries.clear();
    _nativeBytes = 0;
    _lastFragmentNativeHandles = 0;
    _sceneEntries = 0;
    _sceneBytes = 0;
    _lastSceneReservation = null;
    _usedHeight = 0;
    _flowHeight = 0;
    _snapshot = null;
  }

  Never _fail(ForumBodyTextPageFailure failure) =>
      throw ForumBodyTextPageException(failure);
  void _ensureOpen() {
    if (_closed || _complete) throw StateError('Page composition is closed');
  }

  /// Retire only unpublished work. Existing snapshots keep their fixed prefix.
  void close() {
    if (_closed) return;
    _closed = true;
    _active?.input.lease?.release();
    _active = null;
    _padding = null;
    _fragmentCount -= _draft.length;
    _draft.clear();
    _usedNativeHandles = 0;
    _nativeEntries.clear();
    _nativeBytes = 0;
    _lastFragmentNativeHandles = 0;
    _sceneEntries = 0;
    _sceneBytes = 0;
    _lastSceneReservation = null;
    _usedHeight = 0;
    _flowHeight = 0;
  }
}

/// One private typed adapter for the sole active input. Only numeric fragment
/// records reach snapshots; no native layout, callback or child lease is stored
/// in a published page. Keep both public lease APIs concrete.
final class _CompositionParagraph {
  _CompositionParagraph.paragraph(ForumBodyParagraphLease current)
    : lease = current,
      nativeHandleCountInRange = null,
      nativeEntriesInRange = null,
      nativeCostsInRange = null,
      _text = current.layout,
      _inline = null,
      _emphasisEntries = null,
      _emphasisGuard = null,
      identity = current.content.identity,
      path = current.content.path,
      fontRevision = current.content.fontRevision,
      styleRevision = current.content.styleRevision,
      projection = current.content.projection,
      kind = ForumBodyTextPageFragmentKind.paragraph {
    if (current.content.isSourceFree) {
      throw ArgumentError('Anonymous font struts are not document paragraphs');
    }
  }
  _CompositionParagraph.inline(
    ForumBodyInlineParagraphLease current,
    this.nativeHandleCountInRange,
    this.nativeEntriesInRange,
    this.nativeCostsInRange,
  ) : lease = current,
      _text = null,
      _inline = current.layout,
      _emphasisEntries = null,
      _emphasisGuard = null,
      identity = current.content.identity,
      path = current.content.path,
      fontRevision = current.content.fontRevision,
      styleRevision = current.content.styleRevision,
      projection = current.content.projection.display,
      kind = ForumBodyTextPageFragmentKind.inline;
  _CompositionParagraph.emphasis(
    ForumBodyEmphasisParagraphNativeEntries entries,
    void Function() ensureOwner,
  ) : lease = null,
      _text = null,
      _inline = null,
      _emphasisEntries = entries,
      _emphasisGuard = ensureOwner,
      nativeHandleCountInRange = null,
      nativeEntriesInRange = null,
      nativeCostsInRange = null,
      identity = entries.paragraph.content.identity,
      path = entries.paragraph.content.path,
      fontRevision = entries.paragraph.content.fontRevision,
      styleRevision = entries.paragraph.content.styleRevision,
      projection = entries.paragraph.content.projection,
      kind = ForumBodyTextPageFragmentKind.emphasis {
    if (entries.groups.isEmpty) {
      throw ArgumentError('Empty struts require an actual paragraph input');
    }
  }
  final ForumBodyNativeParagraphLease? lease;
  final ForumBodyEmphasisParagraphNativeEntries? _emphasisEntries;
  final void Function()? _emphasisGuard;
  final int Function(int startUtf16, int endUtf16)? nativeHandleCountInRange;
  final Iterable<Object> Function(int startUtf16, int endUtf16)?
  nativeEntriesInRange;
  final Iterable<ForumBodyNativeInputCost> Function(
    int startUtf16,
    int endUtf16,
  )?
  nativeCostsInRange;
  final ForumBodyParagraphLayout? _text;
  final ForumBodyInlineParagraphLayout? _inline;
  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final HtmlDisplayTextProjection projection;
  final ForumBodyTextPageFragmentKind kind;
  double get width =>
      _emphasisEntries?.paragraph.width ?? _text?.width ?? _inline!.width;
  double get height =>
      _emphasisEntries?.paragraph.height ?? _text?.height ?? _inline!.height;
  List<ForumBodyParagraphLine> get lines =>
      _emphasisEntries?.paragraph.lines ?? _text?.lines ?? _inline!.lines;
  void ensureActive() {
    if (_emphasisEntries != null) {
      _emphasisGuard!();
      return;
    }
    if (!lease!.isActive || (_text?.isDisposed ?? _inline!.isDisposed)) {
      throw StateError('Composition paragraph lease is retired');
    }
  }

  ({int startLine, int endLine}) lineWindow(ForumBodyParagraphWindow window) =>
      _emphasisEntries?.paragraph.lineWindow(window) ??
      _text?.lineWindow(window) ??
      _inline!.lineWindow(window);
  ({double height, int coverageStartUtf16, int coverageEndUtf16}) fragment(
    int start,
    int end,
  ) {
    final emphasis = _emphasisEntries;
    if (emphasis != null) {
      final view = emphasis.paragraph.fragment(start, end);
      return (
        height: view.height,
        coverageStartUtf16: view.coverageStartUtf16,
        coverageEndUtf16: view.coverageEndUtf16,
      );
    }
    final text = _text;
    if (text != null) {
      final view = text.fragment(start, end);
      return (
        height: view.height,
        coverageStartUtf16: view.coverageStartUtf16,
        coverageEndUtf16: view.coverageEndUtf16,
      );
    }
    final view = _inline!.fragment(start, end);
    return (
      height: view.height,
      coverageStartUtf16: view.coverageStartUtf16,
      coverageEndUtf16: view.coverageEndUtf16,
    );
  }
}

final class _ActivePadding {
  _ActivePadding(this.remaining, this.spaceBefore, this.spaceAtPageStart);
  double remaining;
  final double spaceBefore;
  final double spaceAtPageStart;
  bool started = false;
}

final class _ActiveParagraph {
  _ActiveParagraph(
    this.input,
    this.index,
    this.left,
    this.spaceBefore,
    this.spaceAtPageStart,
    this.firstLine,
    this.endLine,
  ) : nextLine = firstLine,
      scanLine = firstLine;
  final _CompositionParagraph input;
  final int index;
  final double left;
  final double spaceBefore;
  final double spaceAtPageStart;
  final int firstLine;
  final int endLine;
  int nextLine;
  int scanLine;
  int? groupEnd;
}

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;

import '../document/forum_body_document.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import 'forum_body_source_hint.dart';

enum ForumBodyTextPageFailure {
  oversizedGroup,
  invalidGeometry,
  pageLimit,
  fragmentLimit,
}

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

/// Low-level ordinary-text composition over actual native line geometry.
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
  }) {
    if (layoutId.isEmpty ||
        !width.isFinite ||
        width <= 0 ||
        !height.isFinite ||
        height <= 0 ||
        maxPages <= 0 ||
        maxFragments <= 0) {
      throw ArgumentError('Invalid page composition inputs');
    }
  }
  static const revision = 5;
  final ForumBodyIdentity identity;
  final String layoutId;
  final double width;
  final double height;

  /// Explicit metadata budgets, not measured native/GPU memory.
  final int maxPages;
  final int maxFragments;
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
  }) {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    final layout = lease.layout;
    if (paragraphIndex != _nextParagraphIndex ||
        lease.content.identity != identity ||
        !left.isFinite ||
        left < 0 ||
        left + layout.width > width ||
        !spaceBefore.isFinite ||
        !spaceAtPageStart.isFinite ||
        spaceAtPageStart < 0) {
      throw ArgumentError('Invalid paragraph composition inputs');
    }
    final range = layout.lineWindow(window);
    _active = _ActiveParagraph(
      lease,
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
      final layout = active.lease.layout;
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
        final fragment = ForumBodyTextPageFragment._(
          paragraphIndex: active.index,
          path: active.lease.content.path,
          fontRevision: active.lease.content.fontRevision,
          styleRevision: active.lease.content.styleRevision,
          startLine: firstLine,
          endLine: end,
          coverageStartUtf16: view?.coverageStartUtf16 ?? 0,
          coverageEndUtf16: view?.coverageEndUtf16 ?? 0,
          sourceHint: forumBodySourceHint(
            active.lease.content.projection,
            view?.coverageStartUtf16 ?? 0,
            view?.coverageEndUtf16 ?? 0,
          ),
          left: active.left,
          top: top,
          width: layout.width,
          height: fragmentHeight,
        );
        if (continuation) {
          _draft[_draft.length - 1] = fragment;
        } else {
          _draft.add(fragment);
          _fragmentCount++;
        }
        _flowHeight = bottom;
        _usedHeight = math.max(_usedHeight, bottom);
        active.nextLine = end;
        active.scanLine = end;
        active.groupEnd = null;
        final paragraphComplete = end == active.endLine;
        if (paragraphComplete) {
          active.lease.release();
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
    _active?.lease.release();
    _active = null;
    _padding = null;
    _fragmentCount -= _draft.length;
    _draft.clear();
    _usedHeight = 0;
    _flowHeight = 0;
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
    this.lease,
    this.index,
    this.left,
    this.spaceBefore,
    this.spaceAtPageStart,
    this.firstLine,
    this.endLine,
  ) : nextLine = firstLine,
      scanLine = firstLine;
  final ForumBodyParagraphLease lease;
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

import 'dart:async';

import 'package:flutter/painting.dart';

import '../block/forum_body_block_flow_cursor.dart';
import '../document/forum_body_document.dart';
import '../flow/forum_body_text_flow_cursor.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_preparation.dart';

enum ForumBodyTextPageSessionState { active, complete, failed, closed }

enum ForumBodyTextPageSessionFailure {
  paragraphLimit,
  textLimit,
  runLimit,
  leaseLimit,
  ownerRetired,
  decoration,
  preparationLimit,
  pageNotPrepared,
}

final class ForumBodyTextPageSessionException implements Exception {
  const ForumBodyTextPageSessionException(this.failure);
  final ForumBodyTextPageSessionFailure failure;
  @override
  String toString() => 'ForumBodyTextPageSessionException(${failure.name})';
}

/// Content counts are conservative retained-input budgets, not measured native
/// memory. The borrowed reading-owner cache supplies its own native estimates.
final class ForumBodyTextPageSessionLimits {
  const ForumBodyTextPageSessionLimits({
    required this.maxPages,
    required this.maxFragments,
    required this.maxParagraphs,
    required this.maxTextCodeUnits,
    required this.maxRuns,
    required this.maxIssuedLeases,
    this.maxStyleIssues = 128,
    this.maxPagePreparations = 3,
  });
  final int maxPages;
  final int maxFragments;
  final int maxParagraphs;
  final int maxTextCodeUnits;
  final int maxRuns;
  final int maxIssuedLeases;
  final int maxStyleIssues;
  final int maxPagePreparations;

  void _validate() {
    if (maxPages <= 0 ||
        maxFragments <= 0 ||
        maxParagraphs <= 0 ||
        maxTextCodeUnits < 0 ||
        maxRuns < 0 ||
        maxIssuedLeases <= 0 ||
        maxStyleIssues < 0 ||
        maxPagePreparations <= 0) {
      throw ArgumentError('Invalid text page session limits');
    }
  }
}

final class ForumBodyTextPageSessionStep {
  const ForumBodyTextPageSessionStep({
    required this.eventsRead,
    required this.unitsRead,
    required this.linesInspected,
    required this.paragraphsAdmitted,
    required this.paddingConsumed,
    required this.pagesPublished,
    required this.inputCompleted,
    required this.waitingForLayoutBudget,
    required this.isComplete,
  });
  final int eventsRead;
  final int unitsRead;
  final int linesInspected;
  final int paragraphsAdmitted;
  final double paddingConsumed;
  final int pagesPublished;
  final bool inputCompleted;
  final bool waitingForLayoutBudget;
  final bool isComplete;
  bool get madeProgress =>
      eventsRead > 0 ||
      unitsRead > 0 ||
      linesInspected > 0 ||
      paragraphsAdmitted > 0 ||
      paddingConsumed > 0 ||
      pagesPublished > 0 ||
      inputCompleted ||
      isComplete;
}

/// One ordinary-text layout generation. It owns traversal, retained content,
/// composition and issued view leases, but borrows the reading-owner native
/// cache. Keep an old session alive while a replacement is prepared. Close the
/// retired session after swapping views; owner retirement closes the cache too.
///
/// A failed generation keeps its published prefix and its content materializable.
/// Explicit close retires views and content. No Context, timer, mode preference,
/// demand scheduler or persisted semantic anchor is owned by this layer.
final class ForumBodyTextPageSession {
  factory ForumBodyTextPageSession({
    required ForumBodyDocument document,
    required ForumBodyReaderStyle reader,
    required ForumBodyParagraphCache cache,
    required ForumBodyTextPageSessionLimits limits,
    required String layoutId,
    required double width,
    required double height,
    TextScaler textScaler = TextScaler.noScaling,
    ForumBodyParagraphContentBuilder paragraphBuilder =
        const ForumBodyParagraphContentBuilder(),
  }) {
    limits._validate();
    if (cache.isClosed) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.ownerRetired,
      );
    }
    final composer = ForumBodyTextPageComposer(
      identity: document.identity,
      layoutId: layoutId,
      width: width,
      height: height,
      maxPages: limits.maxPages,
      maxFragments: limits.maxFragments,
    );
    try {
      return ForumBodyTextPageSession._(
        ForumBodyBlockFlowCursor(
          document: document,
          reader: reader,
          width: width,
          paragraphBuilder: paragraphBuilder,
        ),
        composer,
        cache,
        limits,
        textScaler,
      );
    } catch (_) {
      composer.close();
      rethrow;
    }
  }

  ForumBodyTextPageSession._(
    this._flow,
    this._composer,
    this._cache,
    this.limits,
    this._textScaler,
  ) : _content = _RetainedParagraphs(limits);
  final ForumBodyBlockFlowCursor _flow;
  final ForumBodyTextPageComposer _composer;
  final ForumBodyParagraphCache _cache;
  final TextScaler _textScaler;
  final ForumBodyTextPageSessionLimits limits;
  final _RetainedParagraphs _content;
  final _issued = <ForumBodyParagraphLease>{};
  final _preparations = <ForumBodyTextPagePreparation>{};
  int _reservedLeases = 0;
  StreamController<void>? _retirementEvents;
  final _issues = <ForumBodyStyleIssue>[];
  ForumBodyTextPageSessionState _state = ForumBodyTextPageSessionState.active;
  ForumBodyBlockFlowParagraph? _pendingParagraph;
  double _margin = 0;
  int _publishedPageCount = 0;
  int _publishedParagraphCount = 0;
  int _droppedIssues = 0;
  bool _waiting = false;

  ForumBodyTextPageSessionState get state => _state;
  bool get isComplete => _state == ForumBodyTextPageSessionState.complete;
  bool get isClosed => _state == ForumBodyTextPageSessionState.closed;
  bool get waitingForLayoutBudget => _waiting;
  ForumBodyTextPageSnapshot get snapshot => _composer.snapshot;
  int get resolvedNodeCount => _flow.resolvedNodeCount;
  int get retainedParagraphCount => _content.items.length;
  int get retainedTextCodeUnits => _content.textCodeUnits;
  int get retainedRuns => _content.runs;
  int get activeIssuedLeases => _issued.where((lease) => lease.isActive).length;
  int get pendingPreparationCount => _preparations.length;
  int get reservedViewLeases => _reservedLeases;
  int get layoutBudgetRevision => _cache.budgetRevision;
  Stream<int> get layoutBudgetChanges => _cache.budgetChanges;
  bool get isLayoutOwnerRetired => _cache.isClosed;

  /// Explicit retirement only. A failed source still owns usable published
  /// views; closing the generation ends their preparation and async waits.
  Stream<void> get retirement => isClosed
      ? const Stream<void>.empty()
      : (_retirementEvents ??= StreamController<void>.broadcast()).stream;
  int get droppedStyleIssueCount => _droppedIssues;

  /// Each call handles at most one paragraph/padding input and publishes at
  /// most one page. Pinned-cache pressure retains the exact pending input; retry
  /// after view leases change instead of spinning or restarting the traversal.
  ForumBodyTextPageSessionStep advance({
    required int maxEvents,
    required int maxLines,
  }) {
    _ensureUsable();
    if (_state != ForumBodyTextPageSessionState.active) {
      throw StateError('Page session is not active');
    }
    if (maxEvents <= 0 || maxLines <= 0) {
      throw ArgumentError('Invalid session work budget');
    }
    var events = 0;
    var units = 0;
    var admitted = 0;
    final before = snapshot.length;
    _waiting = false;
    ForumBodyTextPageSessionStep result({
      int lines = 0,
      double padding = 0,
      bool completed = false,
    }) {
      _recordPublished();
      return ForumBodyTextPageSessionStep(
        eventsRead: events,
        unitsRead: units,
        linesInspected: lines,
        paragraphsAdmitted: admitted,
        paddingConsumed: padding,
        pagesPublished: snapshot.length - before,
        inputCompleted: completed,
        waitingForLayoutBudget: _waiting,
        isComplete: isComplete,
      );
    }

    try {
      while (true) {
        final pending = _pendingParagraph;
        if (pending != null) {
          _content.check(pending.paragraph.content);
          final lease = _cache.acquire(
            content: pending.paragraph.content,
            width: pending.contentWidth,
            textScaler: _textScaler,
          );
          try {
            _composer.append(
              lease: lease,
              paragraphIndex: pending.paragraph.index,
              left: pending.contentLeft,
              spaceBefore: _margin,
              spaceAtPageStart: 0,
              window: pending.paragraph.window,
            );
          } catch (_) {
            lease.release();
            rethrow;
          }
          _content.add(pending.paragraph.content);
          _pendingParagraph = null;
          _margin = 0;
          admitted = 1;
        }
        if (_composer.hasPendingPadding) {
          final step = _composer.advancePadding();
          return result(
            padding: step.extentConsumed,
            completed: step.isComplete,
          );
        }
        if (!_composer.needsInput) {
          final step = _composer.advance(maxLines: maxLines);
          return result(
            lines: step.linesInspected,
            completed: step.paragraphCompleted,
          );
        }
        if (events >= maxEvents) return result();
        final step = _flow.advance(maxEvents: maxEvents - events);
        events += step.eventsRead;
        _collectIssues();
        final unit = _flow.current;
        if (unit == null) continue;
        units++;
        switch (unit) {
          case ForumBodyBlockFlowSpace():
            if (unit.kind == ForumBodyBlockSpaceKind.collapsedMargin) {
              _margin += unit.extent;
            } else {
              _composer.appendPadding(unit.extent, spaceBefore: _margin);
              _margin = 0;
            }
          case ForumBodyBlockFlowParagraph():
            if (unit.paragraph.index != _content.items.length) {
              throw StateError('Unordered paragraph input');
            }
            _pendingParagraph = unit;
          case ForumBodyBlockFlowBoundary():
            if (unit.boundary.kind ==
                ForumBodyTextFlowBoundaryKind.endDocument) {
              _composer.finish();
              _flow.close();
              _state = ForumBodyTextPageSessionState.complete;
              return result(completed: true);
            }
            if ((unit.boundary.event?.style.boxBackground?.a ?? 0) > 0) {
              throw const ForumBodyTextPageSessionException(
                ForumBodyTextPageSessionFailure.decoration,
              );
            }
        }
      }
    } on ForumBodyParagraphBudgetException catch (error) {
      if (error.failure == ForumBodyParagraphBudgetFailure.pinned &&
          _pendingParagraph != null) {
        _waiting = true;
        return result();
      }
      _fail();
      rethrow;
    } catch (_) {
      if (_cache.isClosed) {
        close();
        throw const ForumBodyTextPageSessionException(
          ForumBodyTextPageSessionFailure.ownerRetired,
        );
      }
      _fail();
      rethrow;
    }
  }

  /// Warm-only convenience. A miss never shapes and rolls back partial work;
  /// use openPagePreparation to prepare cold fragments outside Widget build.
  List<ForumBodyParagraphLease> preparePageLeases(int pageIndex) {
    final preparation = openPagePreparation(pageIndex);
    try {
      if (!preparation.tryPrepareCached()) {
        throw const ForumBodyTextPageSessionException(
          ForumBodyTextPageSessionFailure.pageNotPrepared,
        );
      }
      return preparation.takeLeases();
    } finally {
      preparation.close();
    }
  }

  /// Reserve the whole visible fragment budget before acquiring any lease.
  /// Concurrent/partial preparations count, including empty-page requests.
  ForumBodyTextPagePreparation openPagePreparation(int pageIndex) {
    _ensureUsable();
    final prefix = snapshot;
    final page = prefix[pageIndex];
    if (_preparations.length >= limits.maxPagePreparations) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.preparationLimit,
      );
    }
    _issued.removeWhere((lease) => !lease.isActive);
    if (page.fragments.length >
        limits.maxIssuedLeases - _issued.length - _reservedLeases) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.leaseLimit,
      );
    }
    final preparation = createForumBodyTextPagePreparation(
      cache: _cache,
      snapshot: prefix,
      pageIndex: pageIndex,
      contents: [
        for (final fragment in page.fragments)
          _content.items[fragment.paragraphIndex],
      ],
      textScaler: _textScaler,
      ensureOwner: _ensureUsable,
      onTransfer: _transferPreparation,
      onRetire: _retirePreparation,
    );
    _preparations.add(preparation);
    _reservedLeases += page.fragments.length;
    return preparation;
  }

  void _retirePreparation(ForumBodyTextPagePreparation preparation) {
    if (_preparations.remove(preparation)) {
      _reservedLeases -= preparation.expectedFragmentCount;
    }
  }

  void _transferPreparation(
    ForumBodyTextPagePreparation preparation,
    List<ForumBodyParagraphLease> leases,
  ) {
    _ensureUsable();
    if (!_preparations.contains(preparation)) {
      throw StateError('Unregistered page preparation');
    }
    _retirePreparation(preparation);
    _issued.addAll(leases);
  }

  void _recordPublished() {
    final pages = snapshot;
    while (_publishedPageCount < pages.length) {
      final fragments = pages[_publishedPageCount++].fragments;
      if (fragments.isNotEmpty) {
        _publishedParagraphCount = fragments.last.paragraphIndex + 1;
      }
    }
  }

  void _collectIssues() {
    for (final issue in _flow.takePendingIssues()) {
      if (_issues.length < limits.maxStyleIssues) {
        _issues.add(issue);
      } else {
        _droppedIssues++;
      }
    }
  }

  List<ForumBodyStyleIssue> takePendingIssues() {
    if (isClosed) throw StateError('Page session is closed');
    final result = List<ForumBodyStyleIssue>.unmodifiable(_issues);
    _issues.clear();
    return result;
  }

  void _ensureUsable() {
    if (_cache.isClosed) {
      close();
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.ownerRetired,
      );
    }
    if (isClosed) throw StateError('Page session is closed');
  }

  void _fail() {
    if (isClosed) return;
    _recordPublished();
    _flow.close();
    _composer.close();
    _pendingParagraph = null;
    _margin = 0;
    _waiting = false;
    _content.retain(_publishedParagraphCount);
    _state = ForumBodyTextPageSessionState.failed;
  }

  void close() {
    if (isClosed) return;
    _state = ForumBodyTextPageSessionState.closed;
    _flow.close();
    _composer.close();
    for (final preparation in _preparations.toList()) {
      preparation.close();
    }
    _preparations.clear();
    _reservedLeases = 0;
    for (final lease in _issued) {
      lease.release();
    }
    _issued.clear();
    _content.retain(0);
    _pendingParagraph = null;
    _margin = 0;
    _waiting = false;
    _issues.clear();
    final events = _retirementEvents;
    if (events != null) {
      events.add(null);
      unawaited(events.close());
    }
  }
}

final class _RetainedParagraphs {
  _RetainedParagraphs(this.limits);
  final ForumBodyTextPageSessionLimits limits;
  final items = <ForumBodyParagraphContent>[];
  int textCodeUnits = 0;
  int runs = 0;
  void check(ForumBodyParagraphContent content) {
    if (items.length >= limits.maxParagraphs) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.paragraphLimit,
      );
    }
    if (content.projection.text.length >
        limits.maxTextCodeUnits - textCodeUnits) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.textLimit,
      );
    }
    if (content.runs.length > limits.maxRuns - runs) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.runLimit,
      );
    }
  }

  void add(ForumBodyParagraphContent content) {
    items.add(content);
    textCodeUnits += content.projection.text.length;
    runs += content.runs.length;
  }

  void retain(int count) {
    while (items.length > count) {
      final removed = items.removeLast();
      textCodeUnits -= removed.projection.text.length;
      runs -= removed.runs.length;
    }
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../block/forum_body_block_flow_cursor.dart';
import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import '../flow/forum_body_text_flow_cursor.dart';
import '../inline/forum_body_inline_plan_input.dart';
import '../inline/forum_body_inline_image_input.dart';
import '../inline/forum_body_ruby_content.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import '../style/forum_body_length.dart';
import '../table/forum_body_table_preparation.dart';
import 'forum_body_flow_width_measure.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_preparation.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_text_page_content.dart';
import 'forum_body_inline_native_entries.dart';
import 'forum_body_inline_page_admission.dart';
import '../inline/forum_body_inline_font_frame_plan.dart';
import 'forum_body_emphasis_page_admission.dart';
import 'forum_body_list_marker_plan.dart';
import 'forum_body_image_frame.dart';

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
  imageResource,
  imageStructure,
  imageLimit,
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
    int? maxIssuedImages,
    this.maxStyleIssues = 128,
    this.maxPagePreparations = 3,
  }) : maxIssuedImages = maxIssuedImages ?? maxIssuedLeases;
  final int maxPages;
  final int maxFragments;
  final int maxParagraphs;
  final int maxTextCodeUnits;
  final int maxRuns;

  /// Bounds native handles and issued delivery objects independently. Images
  /// have zero paragraph handles but still consume one delivery object.
  final int maxIssuedLeases;

  /// Mounted and reserved image occurrences, independent of native handles
  /// and outer fragment delivery objects. Sharing a URL does not share a slot.
  final int maxIssuedImages;
  final int maxStyleIssues;
  final int maxPagePreparations;

  void _validate() {
    if (maxPages <= 0 ||
        maxFragments <= 0 ||
        maxParagraphs <= 0 ||
        maxTextCodeUnits < 0 ||
        maxRuns < 0 ||
        maxIssuedLeases <= 0 ||
        maxIssuedImages <= 0 ||
        maxStyleIssues < 0 ||
        maxPagePreparations <= 0) {
      throw ArgumentError('Invalid text page session limits');
    }
  }
}

final class ForumBodyTextPageSessionStep {
  const ForumBodyTextPageSessionStep({
    required this.eventsRead,
    int? flowWorkDone,
    this.formatUnitsPrepared = 0,
    this.layoutsBuilt = 0,
    this.rulesComposed = 0,
    required this.unitsRead,
    required this.linesInspected,
    required this.paragraphsAdmitted,
    required this.paddingConsumed,
    required this.pagesPublished,
    required this.inputCompleted,
    required this.waitingForLayoutBudget,
    required this.isComplete,
  }) : flowWorkDone = flowWorkDone ?? eventsRead;
  final int eventsRead;
  final int flowWorkDone;
  final int formatUnitsPrepared;
  final int layoutsBuilt;
  final int rulesComposed;
  final int unitsRead;
  final int linesInspected;
  final int paragraphsAdmitted;
  final double paddingConsumed;
  final int pagesPublished;
  final bool inputCompleted;
  final bool waitingForLayoutBudget;
  final bool isComplete;
  bool get madeProgress =>
      rulesComposed > 0 ||
      flowWorkDone > 0 ||
      formatUnitsPrepared > 0 ||
      layoutsBuilt > 0 ||
      eventsRead > 0 ||
      unitsRead > 0 ||
      linesInspected > 0 ||
      paragraphsAdmitted > 0 ||
      paddingConsumed > 0 ||
      pagesPublished > 0 ||
      inputCompleted ||
      isComplete;
}

/// A mounted or prepared outer table page keeps its cell sessions available
/// even before the viewport has acquired its first visible body slice.
final class ForumBodyTablePageLease {
  ForumBodyTablePageLease._(this.layout, this._owner, this.pageIndex);

  final ForumBodyTableLayout layout;
  final int pageIndex;
  ForumBodyTextPageSession? _owner;

  bool get isActive => _owner != null && !layout.isClosed;

  void close() {
    final owner = _owner;
    _owner = null;
    owner?._issuedTables.remove(this);
  }
}

/// One sequential text layout generation. It owns traversal, retained content,
/// composition and issued view leases, but borrows the reading-owner native
/// cache. Keep an old session alive while a replacement is prepared. Close the
/// retired session after swapping views; owner retirement closes the cache too.
///
/// A failed generation keeps its published prefix and its content materializable.
/// Explicit close retires views and content. No Context, timer, mode preference,
/// demand scheduler or persisted semantic anchor is owned by this layer.
final class ForumBodyTextPageSession {
  static const inlinePlanRevision = ForumBodyInlinePlanInput.revision;
  static const paragraphPlanRevision = 1;
  static const inlineFontFrameRevision = ForumBodyInlineFontFramePlan.revision;
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
    ForumBodyRubyContentLimits rubyLimits = const ForumBodyRubyContentLimits(),
    int? maxNativeHandlesPerPage,
    int? maxNativeEntriesPerPage,
    int? maxNativeEstimatedBytesPerPage,
    ForumBodyImageResolver? imageResolver,
    ForumBodyInlineImageResolver? inlineImageResolver,
    ForumBodyCollapseLayout? collapses,
    // Scope a cell or caption to its actual descendants, with inherited style.
    ForumBodyElement? contentRoot,
    double? intrinsicAvailableWidth,
    int? maxImagesPerPage,
    bool dedicatedTables = false,
  }) {
    limits._validate();
    if (intrinsicAvailableWidth != null &&
        (!intrinsicAvailableWidth.isFinite || intrinsicAvailableWidth <= 0)) {
      throw ArgumentError.value(
        intrinsicAvailableWidth,
        'intrinsicAvailableWidth',
      );
    }
    if (maxImagesPerPage != null && maxImagesPerPage > limits.maxIssuedImages) {
      throw ArgumentError('Page image limit exceeds session capacity');
    }
    if (maxNativeHandlesPerPage != null &&
        maxNativeHandlesPerPage > limits.maxIssuedLeases) {
      throw ArgumentError('Page handle limit exceeds session capacity');
    }
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
      maxNativeHandlesPerPage: maxNativeHandlesPerPage,
      maxNativeEntriesPerPage: maxNativeEntriesPerPage,
      maxNativeEstimatedBytesPerPage: maxNativeEstimatedBytesPerPage,
      // The Host's per-page slot allotment also bounds zero-native resources;
      // their actual native handle count remains zero.
      maxDeliveriesPerPage: maxNativeHandlesPerPage ?? limits.maxIssuedLeases,
      maxImagesPerPage: maxImagesPerPage ?? limits.maxIssuedImages,
    );
    try {
      return ForumBodyTextPageSession._(
        ForumBodyBlockFlowCursor(
          document: document,
          reader: reader,
          width: width,
          paragraphBuilder: paragraphBuilder,
          rubyLimits: rubyLimits,
          inlineImageResolver: inlineImageResolver,
          collapses: collapses,
          contentRoot: contentRoot,
          dedicatedTables: dedicatedTables,
        ),
        composer,
        cache,
        limits,
        textScaler,
        imageResolver,
        contentRoot?.kind == ForumBodyElementKind.tableCell ||
            contentRoot?.kind == ForumBodyElementKind.tableCaption,
        intrinsicAvailableWidth == null
            ? null
            : ForumBodyFlowWidthMeasure(intrinsicAvailableWidth),
        dedicatedTables
            ? (table, remaining) => ForumBodyTablePreparation(
                document: document,
                table: table.table.element,
                reader: reader,
                cache: cache,
                availableWidth: table.width,
                layoutId: '$layoutId/table/${table.table.element.path}',
                limits: remaining,
                textScaler: textScaler,
                collapses: collapses,
                imageResolver: imageResolver,
                inlineImageResolver: inlineImageResolver,
              )
            : null,
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
    this._imageResolver,
    this._tableBody,
    this._intrinsic,
    this._openTable,
  ) : _content = _RetainedParagraphs(limits);
  final ForumBodyBlockFlowCursor _flow;
  final ForumBodyTextPageComposer _composer;
  final ForumBodyParagraphCache _cache;
  final TextScaler _textScaler;
  final ForumBodyImageResolver? _imageResolver;
  final bool _tableBody;
  final ForumBodyFlowWidthMeasure? _intrinsic;
  final ForumBodyTablePreparation Function(
    ForumBodyBlockFlowTable table,
    ForumBodyTextPageSessionLimits remaining,
  )?
  _openTable;
  final ForumBodyTextPageSessionLimits limits;
  final _RetainedParagraphs _content;
  final _issued = <ForumBodyPreparedTextFragment>{};
  final _preparations = <ForumBodyTextPagePreparation>{};
  final _tables = <int, ForumBodyTableLayout>{};
  final _issuedTables = <ForumBodyTablePageLease>{};
  int _reservedLeases = 0;
  int _reservedFragments = 0;
  int _reservedImages = 0;
  StreamController<void>? _retirementEvents;
  final _issues = <ForumBodyStyleIssue>[];
  ForumBodyTextPageSessionState _state = ForumBodyTextPageSessionState.active;
  ForumBodyBlockFlowParagraph? _pendingParagraph;
  ForumBodyBlockFlowImage? _pendingImage;
  ForumBodyBlockFlowTable? _pendingTable;
  ForumBodyTablePreparation? _tablePreparation;
  ForumBodyListMarkerPlanPreparation? _listPreparation;
  ForumBodyListMarkerPlan? _listPlan;
  bool _markersReady = false;
  ForumBodyBlockFlowListItemStart? _pendingListItem;
  ForumBodyEmphasisPageAdmission? _paragraphAdmission;
  ForumBodyBlockFlowInline? _pendingInline;
  ForumBodyInlinePageAdmission? _inlinePreparation;
  ({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})?
  _readyInline;
  ForumBodyInlineNativeEntriesPreparation? _entryPreparation;
  double _margin = 0;
  int _publishedPageCount = 0;
  int _publishedParagraphCount = 0;
  int _droppedIssues = 0;
  bool _waiting = false;

  ForumBodyTextPageSessionState get state => _state;
  bool get isComplete => _state == ForumBodyTextPageSessionState.complete;
  ForumBodyResolvedStyle get contentRootStyle => _flow.rootStyle;
  ({double minimum, double preferred})? get intrinsicWidths =>
      isComplete ? _intrinsic?.result : null;
  bool get isClosed => _state == ForumBodyTextPageSessionState.closed;
  bool get waitingForLayoutBudget => _waiting;
  ForumBodyTextPageSnapshot get snapshot => _composer.snapshot;
  int get resolvedNodeCount => _flow.resolvedNodeCount;
  int get retainedParagraphCount => _content.paragraphCount;
  int get retainedTextCodeUnits => _content.textCodeUnits;
  int get retainedRuns => _content.runs;
  int get activeIssuedLeases => _issued
      .expand((fragment) => fragment.nativeLeases)
      .where((lease) => lease.isActive)
      .length;
  int get pendingPreparationCount => _preparations.length;
  int get reservedViewLeases => _reservedLeases;
  int get activeIssuedFragments => isClosed || _cache.isClosed
      ? 0
      : _issued.where((fragment) => fragment.isActive).length;
  int get reservedViewFragments => _reservedFragments;
  int get activeIssuedTablePages => _cache.isClosed ? 0 : _issuedTables.length;
  int get activeIssuedImages => _state == ForumBodyTextPageSessionState.closed
      ? 0
      : _issued
            .where((fragment) => fragment.isActive)
            .fold<int>(0, (sum, fragment) => sum + fragment.imageCount);
  int get reservedViewImages => _reservedImages;
  int get layoutBudgetRevision => _cache.budgetRevision;
  Stream<int> get layoutBudgetChanges => _cache.budgetChanges;
  bool get isLayoutOwnerRetired => _cache.isClosed;

  /// Explicit retirement only. A failed source still owns usable published
  /// views; closing the generation ends their preparation and async waits.
  Stream<void> get retirement => isClosed
      ? const Stream<void>.empty()
      : (_retirementEvents ??= StreamController<void>.broadcast()).stream;
  int get droppedStyleIssueCount => _droppedIssues;

  /// Borrow a published table while this session is alive. The session owns
  /// the table's cell bodies even when the published prefix survives a failure.
  ForumBodyTableLayout? tableLayoutForPage(int page) {
    _ensureUsable();
    RangeError.checkValidIndex(page, snapshot);
    return _tables[page];
  }

  ForumBodyTablePageLease? acquireTablePage(int page) {
    final layout = tableLayoutForPage(page);
    if (layout == null) return null;
    final lease = ForumBodyTablePageLease._(layout, this, page);
    _issuedTables.add(lease);
    return lease;
  }

  bool ownsTablePageLease(int page, ForumBodyTablePageLease lease) =>
      lease.pageIndex == page &&
      lease.isActive &&
      _issuedTables.contains(lease);

  /// Each call handles at most one paragraph/padding input and publishes at
  /// most one page. Pinned-cache pressure retains the exact pending input; retry
  /// after view leases change instead of spinning or restarting the traversal.
  /// Format inspection, emphasis measurement and native-index work share the
  /// explicit part budget; numeric preparation never records a visible scene.
  ForumBodyTextPageSessionStep advance({
    required int maxEvents,
    required int maxLines,
    int maxFormatParts = 32,
  }) {
    _ensureUsable();
    if (_state != ForumBodyTextPageSessionState.active) {
      throw StateError('Page session is not active');
    }
    if (maxEvents <= 0 || maxLines <= 0 || maxFormatParts <= 0) {
      throw ArgumentError('Invalid session work budget');
    }
    var events = 0;
    var work = 0;
    var units = 0;
    var admitted = 0;
    var formatUnits = 0;
    final buildsBefore = _cache.layoutBuildCount;
    final before = snapshot.length;
    _waiting = false;
    ForumBodyTextPageSessionStep result({
      int lines = 0,
      double padding = 0,
      bool completed = false,
      int rules = 0,
    }) {
      _recordPublished();
      return ForumBodyTextPageSessionStep(
        eventsRead: events,
        flowWorkDone: work,
        formatUnitsPrepared: formatUnits,
        layoutsBuilt: _cache.layoutBuildCount - buildsBefore,
        rulesComposed: rules,
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
        final item = _pendingListItem;
        if (item != null) {
          var gutter = 0.0;
          if (item.marker.text != null) {
            if (item.marker.style.listStyle.position !=
                ForumBodyListMarkerPosition.outside) {
              throw ForumBodyBlockFlowException(
                ForumBodyBlockFlowFailure.structure,
                item.marker.itemPath,
              );
            }
            final input = forumBodyListMarkerFontInput(
              item.marker,
              _flow.fontRevision,
              _flow.styleRevision,
            );
            final lease = _cache.acquireDecorationText(
              input: input,
              textScaler: _textScaler,
            );
            try {
              _ensureActivePlan();
              final bounds = forumBodyListMarkerFontBounds(input, lease);
              final gap = lease.layout.height * .25;
              gutter = item.marker.style.textDirection == TextDirection.ltr
                  ? gap + lease.layout.width - bounds.left
                  : gap + bounds.right;
            } finally {
              lease.release();
            }
          }
          _flow.resolveListItemGutter(item, gutter);
          _intrinsic?.addListGutter(
            math.max(0.0, gutter - item.availableGutter),
          );
          _pendingListItem = null;
          formatUnits++;
          return result();
        }
        final markers =
            _pendingParagraph?.listMarkers ??
            _pendingInline?.listMarkers ??
            _pendingImage?.listMarkers;
        if (markers != null && markers.isNotEmpty && !_markersReady) {
          final preparation = _listPreparation ??=
              ForumBodyListMarkerPlanPreparation(
                identity: _flow.identity,
                markers: markers,
                left:
                    _pendingParagraph?.contentLeft ??
                    _pendingInline?.contentLeft ??
                    _pendingImage!.contentLeft,
                fontRevision: _flow.fontRevision,
                styleRevision: _flow.styleRevision,
                cache: _cache,
                textScaler: _textScaler,
                ensureOwner: _ensureActivePlan,
              );
          formatUnits += preparation.advance();
          if (preparation.isReady) {
            _listPlan = preparation.take();
            _listPreparation = null;
            _markersReady = true;
          }
          return result();
        }
        final pending = _pendingParagraph;
        if (pending != null) {
          final admission = _paragraphAdmission ??= _openParagraphPlan(pending);
          if (!admission.isReady) {
            final step = admission.advance(maxParts: maxFormatParts);
            formatUnits += step.partsPrepared;
            _waiting = step.waitingForLayoutBudget;
            if (!admission.isReady) return result();
          }
          ForumBodyTextPageContent input;
          if (admission.isPlain) {
            input = _decorate(
              ForumBodyTextPageContent.paragraph(admission.plainContent),
            );
            final lease = admission.takePlainLease();
            try {
              if (_intrinsic != null) {
                final widths = lease.layout.intrinsicWidths;
                _intrinsic.add(widths.minimum, widths.preferred);
              }
              _composer.append(
                lease: lease,
                paragraphIndex: pending.paragraph.index,
                left: pending.contentLeft,
                spaceBefore: _margin,
                spaceAtPageStart: 0,
                window: pending.paragraph.window,
                listMarkers: _listPlan,
              );
            } catch (_) {
              lease.release();
              rethrow;
            }
            admission.close();
          } else if (admission.isFitted) {
            final fitted = admission.takeFitted();
            input = _decorate(fitted);
            if (_intrinsic != null) {
              final width = fitted.plan.metrics.fontBounds.width;
              _intrinsic.add(width, width);
            }
            _composer.appendFittedEmphasis(
              plan: fitted.plan,
              ensureOwner: _ensureActivePlan,
              paragraphIndex: pending.paragraph.index,
              left: pending.contentLeft,
              spaceBefore: _margin,
              spaceAtPageStart: 0,
              window: pending.paragraph.window,
              listMarkers: _listPlan,
            );
          } else {
            final ready = admission.take();
            input = _decorate(ready.content);
            if (_intrinsic != null) {
              final widths = ready.content.paragraph.intrinsicWidths!;
              _intrinsic.add(widths.minimum, widths.preferred);
            }
            _composer.appendEmphasis(
              entries: ready.entries,
              ensureOwner: _ensureActivePlan,
              paragraphIndex: pending.paragraph.index,
              left: pending.contentLeft,
              spaceBefore: _margin,
              spaceAtPageStart: 0,
              window: pending.paragraph.window,
              listMarkers: _listPlan,
            );
          }
          _paragraphAdmission = null;
          _content.add(input);
          _pendingParagraph = null;
          _listPlan = null;
          _markersReady = false;
          _margin = 0;
          admitted = 1;
        }
        final mixed = _pendingInline;
        if (mixed != null) {
          if (_readyInline == null) {
            final prepare = _inlinePreparation ??= _openInlinePlan(mixed);
            final step = prepare.advance(maxParts: maxFormatParts);
            formatUnits += step.partsPrepared;
            _waiting = step.waitingForLayoutBudget;
            if (!step.isReady) return result();
            final ready = _readyInline = prepare.take();
            prepare.close();
            _inlinePreparation = null;
            if (_composer.maxNativeEntriesPerPage != null ||
                _composer.maxNativeEstimatedBytesPerPage != null) {
              _entryPreparation = ForumBodyInlineNativeEntriesPreparation(
                input: ready.content,
                parent: ready.lease,
                cache: _cache,
                textScaler: _textScaler,
                ensureOwner: _ensureActivePlan,
              );
              return result();
            }
          }
          ForumBodyInlineNativeEntries? entries;
          final entryJob = _entryPreparation;
          if (entryJob != null) {
            formatUnits += entryJob.advance(maxParts: maxFormatParts);
            if (!entryJob.isReady) return result();
            entries = entryJob.take();
            _entryPreparation = null;
          }
          final ready = _readyInline!;
          final input = _decorate(ready.content);
          try {
            if (_intrinsic != null) {
              final widths = ready.lease.layout.intrinsicWidths;
              _intrinsic.add(widths.minimum, widths.preferred);
            }
            _composer.appendInline(
              lease: ready.lease,
              paragraphIndex: mixed.paragraph.index,
              left: mixed.contentLeft,
              spaceBefore: _margin,
              spaceAtPageStart: 0,
              window: mixed.paragraph.window,
              listMarkers: _listPlan,
              nativeHandleCountInRange:
                  ready.content.nativePreparationHandleCountInRange,
              fontFrames: ready.content.fontFrames,
              nativeEntriesInRange: entries?.inRange,
              nativeCostsInRange: entries?.costsInRange,
            );
          } catch (_) {
            ready.lease.release();
            rethrow;
          }
          _readyInline = null;
          _content.add(input);
          _pendingInline = null;
          _listPlan = null;
          _markersReady = false;
          _margin = 0;
          admitted = 1;
        }
        final image = _pendingImage;
        if (image != null) {
          _admitImage(image);
          _pendingImage = null;
          _listPlan = null;
          _markersReady = false;
          _margin = 0;
          admitted = 1;
        }
        if (_composer.hasPendingRule) {
          final step = _composer.advanceRule();
          return result(
            rules: step.isComplete ? 1 : 0,
            completed: step.isComplete,
          );
        }
        if (_composer.hasPendingImage) {
          final step = _composer.advanceImage();
          return result(completed: step.isComplete);
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
        if (_pendingTable case final table?) {
          if (_composer.sealBeforeTable()) return result();
          final preparation = _tablePreparation ??= _openTable!(
            table,
            _remainingTableLimits(),
          );
          final step = preparation.advance(
            maxEvents: maxEvents,
            maxLines: maxLines,
            maxFormatParts: maxFormatParts,
          );
          _waiting = step.waitingForLayoutBudget;
          if (!_waiting) formatUnits++;
          if (!step.isReady) return result();
          final layout = preparation.takeLayout();
          _tablePreparation = null;
          _publishTable(table, layout);
          _pendingTable = null;
          _margin = 0;
          return result(completed: true);
        }
        if (work >= maxEvents) return result();
        final step = _flow.advance(maxEvents: maxEvents - work);
        events += step.eventsRead;
        work += step.workDone;
        _collectIssues();
        final unit = _flow.current;
        if (unit == null) continue;
        units++;
        switch (unit) {
          case ForumBodyBlockFlowTable():
            _pendingTable = unit;
          case ForumBodyBlockFlowImage():
            if (unit.image.index != _content.items.length) {
              throw StateError('Unordered image input');
            }
            _pendingImage = unit;
          case ForumBodyBlockFlowListItemStart():
            _pendingListItem = unit;
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
          case ForumBodyBlockFlowInline():
            if (unit.paragraph.index != _content.items.length) {
              throw StateError('Unordered inline input');
            }
            _pendingInline = unit;
          case ForumBodyBlockFlowRule():
            _composer.appendRule(
              path: unit.path,
              left: unit.left,
              width: unit.width,
              thickness: unit.thickness,
              color: unit.color,
              spaceBefore: _margin,
            );
            _margin = 0;
          case ForumBodyBlockFlowBoundary():
            if (unit.boundary.kind ==
                ForumBodyTextFlowBoundaryKind.endDocument) {
              _composer.finish();
              _flow.close();
              _state = ForumBodyTextPageSessionState.complete;
              return result(completed: true);
            }
            final event = unit.boundary.event!;
            final opens =
                unit.boundary.kind == ForumBodyTextFlowBoundaryKind.openBlock;
            if (opens) {
              _intrinsic?.open(unit);
            } else {
              _intrinsic?.close(event.node.path);
            }
            if (unit.collapseTitle case final section?) {
              if (opens) {
                final box = unit.box!;
                _composer.openCollapseTitle(
                  id: section.id,
                  titlePath: section.title.path,
                  expanded: section.expanded,
                  direction: event.style.textDirection,
                  left: unit.contentLeft - box.padding.left - box.leftBorder,
                  width: box.borderBoxWidth,
                );
              } else {
                _composer.closeCollapseTitle(section.title.path);
              }
            }
            final background = event.style.visibilityHidden
                ? null
                : event.style.boxBackground;
            final quote = event.style.visibilityHidden
                ? null
                : event.style.quoteDecoration;
            if ((background?.a ?? 0) > 0 || quote != null) {
              if (opens) {
                _composer.openBackground(
                  path: event.node.path,
                  left:
                      unit.contentLeft -
                      unit.box!.padding.left -
                      unit.box!.leftBorder,
                  width: unit.box!.borderBoxWidth,
                  color: background ?? const Color(0x00000000),
                  quoteDecoration: quote,
                );
              } else {
                _composer.closeBackground(event.node.path);
                if (snapshot.length != before) return result();
              }
            }
        }
      }
    } on ForumBodyParagraphBudgetException catch (error) {
      if (error.failure == ForumBodyParagraphBudgetFailure.pinned &&
          (_pendingParagraph != null ||
              _pendingImage != null ||
              _pendingInline != null ||
              _pendingListItem != null)) {
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
    _ensureUsable();
    if (snapshot[pageIndex].fragments.any(
      (fragment) =>
          fragment.kind != ForumBodyTextPageFragmentKind.paragraph ||
          fragment.listMarker != null,
    )) {
      throw StateError('Mixed pages require typed fragment delivery');
    }
    final preparation = openPagePreparation(pageIndex);
    try {
      _completeWarmPreparation(preparation);
      return preparation.takeLeases();
    } finally {
      preparation.close();
    }
  }

  /// Synchronous warm-only delivery drives the same bounded numeric worker.
  /// Only an actual glyph/picture miss retires this convenience request;
  /// cooperative UI work uses openPagePreparation/advance between quanta.
  List<ForumBodyPreparedTextFragment> preparePageFragments(int pageIndex) {
    final preparation = openPagePreparation(pageIndex);
    try {
      _completeWarmPreparation(preparation);
      return preparation.takeFragments();
    } finally {
      preparation.close();
    }
  }

  void _completeWarmPreparation(ForumBodyTextPagePreparation preparation) {
    while (!preparation.tryPrepareCached()) {
      if (preparation.cacheMiss || preparation.waitingForLayoutBudget) {
        throw const ForumBodyTextPageSessionException(
          ForumBodyTextPageSessionFailure.pageNotPrepared,
        );
      }
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
    // A compound fragment can lose one child while retaining another handle.
    // Retire the whole failed delivery before dropping it from the ledger.
    for (final fragment
        in _issued.where((fragment) => !fragment.isActive).toList()) {
      fragment.close();
      _issued.remove(fragment);
    }
    final inputs = <ForumBodyTextPageContent>[];
    // Images own no paragraph handles. Bound their issued delivery objects by
    // the same capacity so repeated unmounted preparations cannot grow forever.
    if (page.fragments.length >
        limits.maxIssuedLeases - _issued.length - _reservedFragments) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.leaseLimit,
      );
    }
    var requested = 0;
    var requestedImages = 0;
    final availableImages =
        limits.maxIssuedImages - activeIssuedImages - _reservedImages;
    final available =
        limits.maxIssuedLeases - activeIssuedLeases - _reservedLeases;
    for (final fragment in page.fragments) {
      final input = _content.items[fragment.paragraphIndex];
      requested += input.nativePreparationHandleCountFor(fragment);
      requestedImages += input.imageCountFor(fragment);
      if (requestedImages > availableImages) {
        throw const ForumBodyTextPageSessionException(
          ForumBodyTextPageSessionFailure.imageLimit,
        );
      }
      if (requested > available) {
        throw const ForumBodyTextPageSessionException(
          ForumBodyTextPageSessionFailure.leaseLimit,
        );
      }
      inputs.add(input);
    }
    final preparation = createForumBodyTextPagePreparation(
      cache: _cache,
      snapshot: prefix,
      pageIndex: pageIndex,
      inputs: inputs,
      textScaler: _textScaler,
      ensureOwner: _ensureUsable,
      onTransfer: _transferPreparation,
      onRetire: _retirePreparation,
    );
    _preparations.add(preparation);
    _reservedLeases += preparation.expectedNativeLeaseCount;
    _reservedFragments += preparation.expectedFragmentCount;
    _reservedImages += preparation.expectedImageCount;
    return preparation;
  }

  void _retirePreparation(ForumBodyTextPagePreparation preparation) {
    if (_preparations.remove(preparation)) {
      _reservedLeases -= preparation.expectedNativeLeaseCount;
      _reservedFragments -= preparation.expectedFragmentCount;
      _reservedImages -= preparation.expectedImageCount;
    }
  }

  void _transferPreparation(
    ForumBodyTextPagePreparation preparation,
    List<ForumBodyPreparedTextFragment> fragments,
  ) {
    _ensureUsable();
    if (!_preparations.contains(preparation)) {
      throw StateError('Unregistered page preparation');
    }
    _retirePreparation(preparation);
    _issued.addAll(fragments);
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

  void _ensureActivePlan() {
    _ensureUsable();
    if (_state != ForumBodyTextPageSessionState.active) {
      throw StateError('Inline plan generation is retired');
    }
  }

  ForumBodyInlinePageAdmission _openInlinePlan(ForumBodyBlockFlowInline mixed) {
    return ForumBodyInlinePageAdmission(
      input: mixed.paragraph.content,
      width: mixed.contentWidth,
      cache: _cache,
      textScaler: _textScaler,
      ensureOwner: _ensureActivePlan,
      validateCounts: _content.checkCounts,
    );
  }

  ForumBodyEmphasisPageAdmission _openParagraphPlan(
    ForumBodyBlockFlowParagraph paragraph,
  ) {
    final content = paragraph.paragraph.content;
    _content.check(_decorate(ForumBodyTextPageContent.paragraph(content)));
    return ForumBodyEmphasisPageAdmission(
      content: content,
      width: paragraph.contentWidth,
      cache: _cache,
      textScaler: _textScaler,
      ensureOwner: _ensureActivePlan,
      validateCounts: _content.checkCounts,
      captureIntrinsicWidths: _intrinsic != null,
    );
  }

  void _admitImage(ForumBodyBlockFlowImage unit) {
    final style = unit.image.event.style;
    if (style.visibilityHidden) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.imageStructure,
      );
    }
    final node = unit.image.event.node as ForumBodyElement;
    final input = _imageResolver?.call(unit.identity, node);
    _ensureActivePlan();
    if (input == null ||
        input.identity != unit.identity ||
        !identical(input.element, node)) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.imageResource,
      );
    }
    if (input.isSticker) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.imageStructure,
      );
    }
    final htmlWidth = input.entry.htmlWidth ?? node.resource?.width;
    final naturalWidth = htmlWidth ?? input.layout.displaySize?.width;
    final cssWidth = style.box.width;
    final usesNaturalWidth =
        cssWidth == null || cssWidth.unit == ForumBodyLengthUnit.auto;
    final imageWidth = usesNaturalWidth
        ? naturalWidth ?? _intrinsic?.availableWidth
        : null;
    final frame = ForumBodyImageFrame.resolve(
      input: input,
      width: unit.contentWidth,
      maxHeight: _composer.height,
      maxImageWidth: _tableBody ? imageWidth : null,
      align: style.textAlign,
      direction: style.textDirection,
    );
    if (_intrinsic != null) {
      final preferred = imageWidth ?? _intrinsic.availableWidth;
      final minimum = usesNaturalWidth && htmlWidth != null ? htmlWidth : 0.0;
      _intrinsic.add(minimum, preferred);
    }
    final content = _decorate(
      ForumBodyImagePageContent(
        input: input,
        frame: frame,
        fontRevision: _flow.fontRevision,
        styleRevision: _flow.styleRevision,
      ),
    );
    _composer.appendImage(
      input: input,
      frame: frame,
      inputIndex: unit.image.index,
      fontRevision: _flow.fontRevision,
      styleRevision: _flow.styleRevision,
      left: unit.contentLeft,
      spaceBefore: _margin,
      listMarkers: _listPlan,
    );
    _content.add(content);
  }

  ForumBodyTextPageContent _decorate(ForumBodyTextPageContent body) {
    final result = _listPlan == null
        ? body
        : ForumBodyListItemPageContent(body, _listPlan!);
    _content.check(result);
    return result;
  }

  void _closeInlineAdmission() {
    _entryPreparation?.close();
    _entryPreparation = null;
    _readyInline?.lease.release();
    _readyInline = null;
  }

  ForumBodyTextPageSessionLimits _remainingTableLimits() {
    if (snapshot.length >= limits.maxPages) {
      throw const ForumBodyTextPageException(
        ForumBodyTextPageFailure.pageLimit,
      );
    }
    final items = limits.maxFragments - _composer.retainedFragmentCount - 1;
    return ForumBodyTextPageSessionLimits(
      maxPages: math.max(1, items),
      maxFragments: math.max(1, items),
      maxParagraphs: math.max(1, limits.maxParagraphs - retainedParagraphCount),
      maxTextCodeUnits: limits.maxTextCodeUnits - retainedTextCodeUnits,
      maxRuns: limits.maxRuns - retainedRuns,
      maxIssuedLeases: limits.maxIssuedLeases,
      maxIssuedImages: limits.maxIssuedImages,
      maxPagePreparations: limits.maxPagePreparations,
      maxStyleIssues: limits.maxStyleIssues,
    );
  }

  void _publishTable(
    ForumBodyBlockFlowTable table,
    ForumBodyTableLayout layout,
  ) {
    try {
      final usage = layout.usage;
      _content.checkCounts(
        usage.textCodeUnits,
        usage.runs,
        paragraphs: usage.paragraphs,
      );
      final index = snapshot.length;
      final left = math.max(0.0, table.left);
      final right = math.min(snapshot.width, table.left + table.width);
      final source = table.table.element.source;
      _composer.publishTable((
        path: table.table.element.path,
        sourceRange: (runeStart: source.runeStart, runeEnd: source.runeEnd),
        bounds: Rect.fromLTRB(left, 0, right, snapshot.height),
        contentSize: layout.size,
        fingerprint: layout.fingerprint,
      ), retainedItems: usage.items + usage.pages);
      _tables[index] = layout;
      _content.addTable(usage.paragraphs, usage.textCodeUnits, usage.runs);
    } catch (_) {
      layout.close();
      rethrow;
    }
  }

  void _closePendingTable() {
    _pendingTable = null;
    _tablePreparation?.close();
    _tablePreparation = null;
  }

  void _fail() {
    if (isClosed) return;
    _recordPublished();
    _flow.close();
    _pendingListItem = null;
    _pendingImage = null;
    _closePendingTable();
    _listPreparation?.close();
    _listPreparation = null;
    _listPlan = null;
    _markersReady = false;
    _composer.close();
    _pendingParagraph = null;
    _paragraphAdmission?.close();
    _paragraphAdmission = null;
    _closeInlineAdmission();
    _inlinePreparation?.close();
    _inlinePreparation = null;
    _pendingInline = null;
    _margin = 0;
    _waiting = false;
    _content.retain(_publishedParagraphCount);
    _state = ForumBodyTextPageSessionState.failed;
  }

  void close() {
    if (isClosed) return;
    _state = ForumBodyTextPageSessionState.closed;
    _flow.close();
    _pendingListItem = null;
    _pendingImage = null;
    _closePendingTable();
    for (final lease in _issuedTables.toList()) {
      lease.close();
    }
    for (final table in _tables.values) {
      table.close();
    }
    _tables.clear();
    _content.clearTables();
    _listPreparation?.close();
    _listPreparation = null;
    _listPlan = null;
    _markersReady = false;
    _composer.close();
    for (final preparation in _preparations.toList()) {
      preparation.close();
    }
    _preparations.clear();
    _reservedLeases = 0;
    _reservedFragments = 0;
    _reservedImages = 0;
    for (final fragment in _issued) {
      fragment.close();
    }
    _issued.clear();
    _content.retain(0);
    _pendingParagraph = null;
    _paragraphAdmission?.close();
    _paragraphAdmission = null;
    _closeInlineAdmission();
    _inlinePreparation?.close();
    _inlinePreparation = null;
    _pendingInline = null;
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
  final items = <ForumBodyTextPageContent>[];
  int _tableParagraphs = 0, _tableText = 0, _tableRuns = 0;
  int get paragraphCount => items.length + _tableParagraphs;
  int textCodeUnits = 0;
  int runs = 0;
  void check(ForumBodyTextPageContent content) =>
      checkCounts(content.retainedTextCodeUnits, content.retainedRuns);
  void checkCounts(int text, int runCount, {int paragraphs = 1}) {
    if (paragraphs > limits.maxParagraphs - paragraphCount) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.paragraphLimit,
      );
    }
    if (text > limits.maxTextCodeUnits - textCodeUnits) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.textLimit,
      );
    }
    if (runCount > limits.maxRuns - runs) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.runLimit,
      );
    }
  }

  void add(ForumBodyTextPageContent content) {
    items.add(content);
    textCodeUnits += content.retainedTextCodeUnits;
    runs += content.retainedRuns;
  }

  void addTable(int paragraphs, int text, int runCount) {
    _tableParagraphs += paragraphs;
    _tableText += text;
    _tableRuns += runCount;
    textCodeUnits += text;
    runs += runCount;
  }

  void clearTables() {
    textCodeUnits -= _tableText;
    runs -= _tableRuns;
    _tableParagraphs = _tableText = _tableRuns = 0;
  }

  void retain(int count) {
    while (items.length > count) {
      final removed = items.removeLast();
      textCodeUnits -= removed.retainedTextCodeUnits;
      runs -= removed.retainedRuns;
    }
  }
}

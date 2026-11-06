import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../block/forum_body_block_flow_cursor.dart';
import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import '../flow/forum_body_inline_flow_content.dart';
import '../flow/forum_body_text_flow_cursor.dart';
import '../inline/forum_body_inline_plan_input.dart';
import '../inline/forum_body_inline_image_input.dart';
import '../inline/forum_body_inline_text_window.dart';
import '../inline/forum_body_ruby_content.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
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
import 'forum_body_float_body_preparation.dart';
import 'forum_body_selectable_text.dart';
import 'forum_body_text_highlight.dart';

part 'forum_body_float_session.dart';
part 'forum_body_float_text.dart';
part 'forum_body_float_inline.dart';
part 'forum_body_selection_copy.dart';
part 'forum_body_heading_keep.dart';

typedef _TableAdmission = ({
  ForumBodyElement element,
  double left,
  double width,
});

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
  floatLineLayout,
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
    this.columnsSealed = 0,
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
  final int columnsSealed;
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
      columnsSealed > 0 ||
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
  // Same numeric ceiling as an individual natural table extent. The native
  // text slice height is a work boundary, not a block image fitting limit.
  static const _maxFlowImageHeight = 1048576.0;
  factory ForumBodyTextPageSession({
    required ForumBodyDocument document,
    required ForumBodyReaderStyle reader,
    required ForumBodyParagraphCache cache,
    required ForumBodyTextPageSessionLimits limits,
    required String layoutId,
    required double width,
    required double height,
    ForumBodyPageColumns columns = const ForumBodyPageColumns(),
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
    // Scope a measured body to its actual descendants, with inherited style.
    ForumBodyElement? contentRoot,
    // A replaced root has no descendants for the flow cursor to emit.
    ({ForumBodyImageInput input, ForumBodyImageFrame frame})? scopedImage,
    double? intrinsicAvailableWidth,
    int? maxImagesPerPage,
    bool dedicatedTables = false,
    bool captureFloats = false,
    bool captureNativeUsage = false,
    bool avoidIsolatedLines = false,
    bool keepHeadingWithNext = false,
    // A flowing host consumes a table's actual occupied height as one slice.
    ForumBodyTableExtent tableExtent = ForumBodyTableExtent.bookPage,
  }) {
    limits._validate();
    if (columns.count != 1 &&
        (contentRoot != null ||
            scopedImage != null ||
            intrinsicAvailableWidth != null)) {
      throw ArgumentError('Columns require a full document viewport');
    }
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
      columns: columns,
      maxPages: limits.maxPages,
      maxFragments: limits.maxFragments,
      flowing: tableExtent == ForumBodyTableExtent.natural,
      avoidIsolatedLines: avoidIsolatedLines,
      captureNativeUsage: captureNativeUsage,
      maxNativeHandlesPerPage: maxNativeHandlesPerPage,
      maxNativeEntriesPerPage: maxNativeEntriesPerPage,
      maxNativeEstimatedBytesPerPage: maxNativeEstimatedBytesPerPage,
      // The Host's per-page slot allotment also bounds zero-native resources;
      // their actual native handle count remains zero.
      maxDeliveriesPerPage: maxNativeHandlesPerPage ?? limits.maxIssuedLeases,
      maxImagesPerPage: maxImagesPerPage ?? limits.maxIssuedImages,
    );
    final composeTables =
        dedicatedTables || tableExtent == ForumBodyTableExtent.natural;
    try {
      final session = ForumBodyTextPageSession._(
        ForumBodyBlockFlowCursor(
          document: document,
          reader: reader,
          width: composer.width,
          paragraphBuilder: paragraphBuilder,
          rubyLimits: rubyLimits,
          inlineImageResolver: inlineImageResolver,
          collapses: collapses,
          contentRoot: contentRoot,
          dedicatedTables: composeTables,
          captureFloats: captureFloats,
          dedicateFloatedTables: tableExtent == ForumBodyTableExtent.bookPage,
        ),
        composer,
        cache,
        limits,
        textScaler,
        imageResolver,
        contentRoot != null,
        intrinsicAvailableWidth == null
            ? null
            : ForumBodyFlowWidthMeasure(intrinsicAvailableWidth),
        tableExtent,
        composeTables
            ? (table, remaining) => ForumBodyTablePreparation(
                document: document,
                table: table.element,
                reader: reader,
                cache: cache,
                availableWidth: table.width,
                layoutId: '$layoutId/table/${table.element.path}',
                limits: remaining,
                textScaler: textScaler,
                collapses: collapses,
                imageResolver: imageResolver,
                inlineImageResolver: inlineImageResolver,
              )
            : null,
        captureFloats
            ? (
                source,
                containingWidth,
                remaining,
              ) => ForumBodyFloatBodyPreparation(
                document: document,
                source: source,
                reader: reader,
                cache: cache,
                containingWidth: containingWidth,
                layoutId: '$layoutId/float',
                limits: remaining,
                textScaler: textScaler,
                collapses: collapses,
                imageResolver: imageResolver,
                inlineImageResolver: inlineImageResolver,
                paragraphBuilder: paragraphBuilder,
                rubyLimits: rubyLimits,
                maxNativeHandlesPerPage: maxNativeHandlesPerPage,
                maxNativeEntriesPerPage: maxNativeEntriesPerPage,
                maxNativeEstimatedBytesPerPage: maxNativeEstimatedBytesPerPage,
                maxImagesPerPage: maxImagesPerPage,
                rootImageMaxHeight: tableExtent == ForumBodyTableExtent.natural
                    ? null
                    : height,
              )
            : null,
        contentRoot?.kind == ForumBodyElementKind.table,
        keepHeadingWithNext &&
            contentRoot == null &&
            tableExtent == ForumBodyTableExtent.bookPage,
      );
      if (scopedImage != null) {
        try {
          if (!identical(scopedImage.input.element, contentRoot) ||
              scopedImage.input.identity != document.identity ||
              scopedImage.frame.width != width ||
              scopedImage.input.isSticker ||
              intrinsicAvailableWidth != null ||
              session.contentRootStyle.hidden ||
              session.contentRootStyle.visibilityHidden ||
              collapses?.hidesPath(contentRoot!.path) == true) {
            throw ArgumentError('Scoped image does not match its content root');
          }
          session._appendImage(scopedImage.input, scopedImage.frame, left: 0);
        } catch (_) {
          session.close();
          rethrow;
        }
      }
      if (session._scopedTable) {
        if (!composeTables ||
            session.contentRootStyle.hidden ||
            collapses?.hidesPath(contentRoot!.path) == true) {
          session.close();
          throw ArgumentError('Invalid scoped table');
        }
        session._pendingTable = (element: contentRoot!, left: 0, width: width);
      }
      return session;
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
    this._scopedBody,
    this._intrinsic,
    this._tableExtent,
    this._openTable,
    this._openFloat,
    this._scopedTable,
    this._keepHeadingWithNext,
  ) : _content = _RetainedParagraphs(limits);
  final ForumBodyBlockFlowCursor _flow;
  final ForumBodyTextPageComposer _composer;
  final ForumBodyParagraphCache _cache;
  final TextScaler _textScaler;
  final ForumBodyImageResolver? _imageResolver;
  final bool _scopedBody;
  final bool _scopedTable;
  final bool _keepHeadingWithNext;
  final ForumBodyTableExtent _tableExtent;
  final ForumBodyFlowWidthMeasure? _intrinsic;
  final ForumBodyTablePreparation Function(
    _TableAdmission table,
    ForumBodyTextPageSessionLimits remaining,
  )?
  _openTable;
  final ForumBodyFloatBodyPreparation Function(
    ForumBodyInlineFlowFloat source,
    double containingWidth,
    ForumBodyTextPageSessionLimits remaining,
  )?
  _openFloat;
  final ForumBodyTextPageSessionLimits limits;
  final _RetainedParagraphs _content;
  final _issued = <ForumBodyPreparedTextFragment>{};
  final _preparations = <ForumBodyTextPagePreparation>{};
  final _tables = <(int, String), ForumBodyTableLayout>{};
  final _flowTableOffsets = <(int, String), double>{};
  final _issuedTables = <ForumBodyTablePageLease>{};
  int _reservedLeases = 0;
  int _reservedFragments = 0;
  int _reservedImages = 0;
  StreamController<void>? _retirementEvents;
  final _issues = <ForumBodyStyleIssue>[];
  ForumBodyTextPageSessionState _state = ForumBodyTextPageSessionState.active;
  ForumBodyBlockFlowParagraph? _pendingParagraph;
  ForumBodyBlockFlowImage? _pendingImage;
  _TableAdmission? _pendingTable;
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
  _FloatFlowAdmission? _floatFlow;
  _FloatTextAdmission? _floatText;
  _FloatInlineAdmission? _floatInline;
  int _nextFlowIndex = 0;
  double _margin = 0;
  int _publishedPageCount = 0;
  int _publishedParagraphCount = 0;
  int _droppedIssues = 0;
  bool _waiting = false;
  _HeadingKeepProbe? _headingKeepProbe;

  ForumBodyTextPageSessionState get state => _state;
  bool get isComplete => _state == ForumBodyTextPageSessionState.complete;
  ForumBodyResolvedStyle get contentRootStyle => _flow.rootStyle;
  ({double minimum, double preferred})? get intrinsicWidths =>
      isComplete ? _intrinsic?.result : null;
  bool get isClosed => _state == ForumBodyTextPageSessionState.closed;
  bool get waitingForLayoutBudget => _waiting;
  ForumBodyTextPageSnapshot get snapshot => _composer.snapshot;
  ForumBodyTableExtent get tableExtent => _tableExtent;
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
  int get pendingStyleIssueCount => _issues.length;

  /// Borrow a published table while this session is alive. The session owns
  /// the table's cell bodies even when the published prefix survives a failure.
  ForumBodyTableLayout? tableLayoutForPage(int page, {String? path}) {
    _ensureUsable();
    final frame = snapshot[page];
    final source = path ?? frame.table?.path;
    return source == null ? null : _tables[(page, source)];
  }

  ForumBodyTablePageLease? acquireTablePage(int page, {String? path}) {
    final layout = tableLayoutForPage(page, path: path);
    if (layout == null) return null;
    final lease = ForumBodyTablePageLease._(layout, this, page);
    _issuedTables.add(lease);
    return lease;
  }

  /// Flow widgets can be evicted by the outer list while their layout survives.
  double? flowTableOffset(int page, String path) =>
      _flowTableOffsets[(page, path)];

  void setFlowTableOffset(int page, String path, double? offset) {
    _ensureUsable();
    final key = (page, path);
    if (offset == null) {
      _flowTableOffsets.remove(key);
    } else {
      if (!_tables.containsKey(key) || !offset.isFinite || offset < 0) {
        throw ArgumentError('Offset does not match a flowing table');
      }
      _flowTableOffsets[key] = offset;
    }
  }

  bool ownsTablePageLease(int page, ForumBodyTablePageLease lease) =>
      lease.pageIndex == page &&
      lease.isActive &&
      _issuedTables.contains(lease);

  bool ownsPreparedFragments(List<ForumBodyPreparedTextFragment> fragments) =>
      !isClosed &&
      !isLayoutOwnerRetired &&
      fragments.every((item) => _issued.contains(item) && item.isActive);

  /// Reads a logical text range from the currently published prefix. The
  /// caller advances the copy in work slices and closes it on cancellation.
  /// No page preparation, native lease or mounted widget is required.
  ForumBodySelectionCopyCursor openSelectionCopy(
    ForumBodySourceRange range, {
    int maxCodeUnits = 65536,
    int maxWork = 32768,
  }) {
    _ensureUsable();
    final prefix = snapshot;
    if (range.identity != prefix.identity ||
        range.startRune < 0 ||
        range.endRune <= range.startRune ||
        maxCodeUnits <= 0 ||
        maxWork <= 0) {
      throw ArgumentError('Invalid selection range or copy budget');
    }
    return ForumBodySelectionCopyCursor._(
      this,
      range,
      selectionChunks(prefix, range).iterator,
      maxCodeUnits,
      maxWork,
    );
  }

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
    final columnsBefore = _composer.sealedColumnCount;
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
        columnsSealed: _composer.sealedColumnCount - columnsBefore,
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
        if (_floatInline case final admission?) {
          final step = admission.advance(
            maxLines: maxLines,
            maxFormatParts: maxFormatParts,
          );
          _waiting = step.waiting;
          if (!_waiting) formatUnits++;
          if (admission.isComplete) {
            if (admission.held case final held?) _floatFlow!.hold(held);
            admission.close();
            _floatInline = null;
          }
          return result(lines: step.lines, completed: admission.isComplete);
        }
        if (_floatText case final admission?) {
          final step = admission.advance(
            maxLines: maxLines,
            maxFormatParts: maxFormatParts,
          );
          _waiting = step.waiting;
          if (!_waiting) formatUnits++;
          if (admission.isComplete) {
            if (admission.held case final held?) _floatFlow!.hold(held);
            admission.close();
            _floatText = null;
          }
          return result(lines: step.lines, completed: admission.isComplete);
        }
        if (_floatFlow case final admission?) {
          _waiting = admission.advance(
            maxEvents: maxEvents,
            maxLines: maxLines,
            maxFormatParts: maxFormatParts,
          );
          if (!_waiting) formatUnits++;
          if (admission.isComplete) {
            admission.close();
            _floatFlow = null;
          }
          return result();
        }
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
          final admission = _paragraphAdmission ??= _openParagraphPlan(
            pending.paragraph.content,
            pending.contentWidth,
          );
          if (!admission.isReady) {
            final step = admission.advance(maxParts: maxFormatParts);
            formatUnits += step.partsPrepared;
            _waiting = step.waitingForLayoutBudget;
            if (!admission.isReady) return result();
          }
          _appendParagraphPlan(
            admission,
            left: pending.contentLeft,
            spaceBefore: _margin,
            window: pending.paragraph.window,
          );
          _paragraphAdmission = null;
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
          _readyInline = null;
          _appendInlinePlan(
            ready,
            entries,
            left: mixed.contentLeft,
            spaceBefore: _margin,
            window: mixed.paragraph.window,
          );
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
            _remainingSubtreeLimits(),
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
          if (_scopedTable) _finishSource();
          return result(completed: true);
        }
        final heading = _headingKeepProbe;
        if (heading != null && heading.isMeasuring) {
          formatUnits += heading.measure(this, maxParts: maxFormatParts);
          return result();
        }
        final ForumBodyBlockFlowUnit unit;
        if (heading != null && heading.isReplaying) {
          unit = heading.take();
          if (heading.isDrained) _headingKeepProbe = null;
        } else {
          if (work >= maxEvents) return result();
          final step = _flow.advance(
            maxEvents: math.min(
              maxEvents - work,
              heading?.sourceWorkLeft ?? maxEvents,
            ),
          );
          events += step.eventsRead;
          work += step.workDone;
          _collectIssues();
          final current = _flow.current;
          if (heading != null) {
            heading.observe(current, step.workDone);
            if (current != null) units++;
            continue;
          }
          if (current == null) continue;
          unit = current;
        }
        units++;
        if (_keepHeadingWithNext &&
            _headingKeepProbe == null &&
            !identical(unit, heading?.opening) &&
            _composer.canProbeHeading &&
            unit is ForumBodyBlockFlowBoundary &&
            _isHeadingOpening(unit) &&
            _margin >= 0) {
          _headingKeepProbe = _HeadingKeepProbe(unit, _margin);
          continue;
        }
        switch (unit) {
          case ForumBodyBlockFlowTable():
            // A book table owns a whole viewport, even between text columns.
            final spansColumns = _composer.columns.count > 1;
            _pendingTable = (
              element: unit.table.element,
              left: spansColumns ? 0 : unit.left,
              width: spansColumns
                  ? _composer.screenWidth
                  : math.min(
                      unit.width,
                      _intrinsic?.availableWidth ?? unit.width,
                    ),
            );
          case ForumBodyBlockFlowImage():
            _consumeFlowIndex(unit.image.index);
            _margin = _composer.clearForFullWidthBlock(_margin);
            _pendingImage = unit;
          case ForumBodyBlockFlowListItemStart():
            _pendingListItem = unit;
          case ForumBodyBlockFlowSpace():
            if (unit.kind == ForumBodyBlockSpaceKind.collapsedMargin) {
              if (_tableExtent == ForumBodyTableExtent.natural &&
                  unit.extent > 0) {
                // A slice boundary is invisible in a scrolling document.
                // Keep the gap even if it consumes the rest of this slice.
                _composer.appendPadding(unit.extent, opensBackgrounds: false);
              } else {
                _margin += unit.extent;
              }
            } else {
              _composer.appendPadding(unit.extent, spaceBefore: _margin);
              _margin = 0;
            }
          case ForumBodyBlockFlowParagraph():
            _consumeFlowIndex(unit.paragraph.index);
            if (_openFloat != null && _composer.hasFloatExclusion(_margin)) {
              if (unit.listMarkers.isNotEmpty) _requiresFloatLineLayout();
              _floatText = _FloatTextAdmission(
                this,
                unit.paragraph.content,
                unit.paragraph.window,
                left: unit.contentLeft,
                width: unit.contentWidth,
              );
              return result();
            }
            _pendingParagraph = unit;
          case ForumBodyBlockFlowInline():
            _consumeFlowIndex(unit.paragraph.index);
            if (_openFloat != null &&
                unit.paragraph.content.parts.any(
                  (part) => part is ForumBodyInlineFlowExclusion,
                )) {
              _floatFlow = _FloatFlowAdmission(this, unit);
              return result();
            } else {
              if (_openFloat != null && _composer.hasFloatExclusion(_margin)) {
                if (unit.listMarkers.isNotEmpty) _requiresFloatLineLayout();
                _floatInline = _FloatInlineAdmission(
                  this,
                  unit.paragraph.content,
                  unit.paragraph.window,
                  left: unit.contentLeft,
                  width: unit.contentWidth,
                );
                return result();
              }
              _pendingInline = unit;
            }
          case ForumBodyBlockFlowRule():
            _margin = _composer.clearForFullWidthBlock(_margin);
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
              _finishSource();
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

  void _appendInlinePlan(
    ({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})
    ready,
    ForumBodyInlineNativeEntries? entries, {
    required double left,
    required double spaceBefore,
    required ForumBodyParagraphWindow window,
  }) {
    try {
      final input = _decorate(ready.content);
      if (_intrinsic != null) {
        final widths = ready.lease.layout.intrinsicWidths;
        _intrinsic.add(widths.minimum, widths.preferred);
      }
      _composer.appendInline(
        lease: ready.lease,
        paragraphIndex: _content.items.length,
        left: left,
        spaceBefore: spaceBefore,
        spaceAtPageStart: 0,
        window: window,
        listMarkers: _listPlan,
        nativeHandleCountInRange:
            ready.content.nativePreparationHandleCountInRange,
        fontFrames: ready.content.fontFrames,
        nativeEntriesInRange: entries?.inRange,
        nativeCostsInRange: entries?.costsInRange,
      );
      _content.add(input);
    } catch (_) {
      ready.lease.release();
      rethrow;
    }
  }

  ForumBodyEmphasisPageAdmission _openParagraphPlan(
    ForumBodyParagraphContent content,
    double width,
  ) {
    _content.check(_decorate(ForumBodyTextPageContent.paragraph(content)));
    return ForumBodyEmphasisPageAdmission(
      content: content,
      width: width,
      cache: _cache,
      textScaler: _textScaler,
      ensureOwner: _ensureActivePlan,
      validateCounts: _content.checkCounts,
      captureIntrinsicWidths: _intrinsic != null,
    );
  }

  void _appendParagraphPlan(
    ForumBodyEmphasisPageAdmission admission, {
    required double left,
    required double spaceBefore,
    required ForumBodyParagraphWindow window,
  }) {
    ForumBodyTextPageContent input;
    final index = _content.items.length;
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
          paragraphIndex: index,
          left: left,
          spaceBefore: spaceBefore,
          spaceAtPageStart: 0,
          window: window,
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
        paragraphIndex: index,
        left: left,
        spaceBefore: spaceBefore,
        spaceAtPageStart: 0,
        window: window,
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
        paragraphIndex: index,
        left: left,
        spaceBefore: spaceBefore,
        spaceAtPageStart: 0,
        window: window,
        listMarkers: _listPlan,
      );
    }
    _content.add(input);
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
      maxHeight: _tableExtent == ForumBodyTableExtent.natural
          ? _maxFlowImageHeight
          : _composer.height,
      maxImageWidth: _scopedBody ? imageWidth : null,
      align: style.textAlign,
      direction: style.textDirection,
    );
    if (_intrinsic != null) {
      final preferred = imageWidth ?? _intrinsic.availableWidth;
      final minimum = usesNaturalWidth && htmlWidth != null ? htmlWidth : 0.0;
      _intrinsic.add(minimum, preferred);
    }
    _appendImage(input, frame, left: unit.contentLeft);
  }

  void _appendImage(
    ForumBodyImageInput input,
    ForumBodyImageFrame frame, {
    required double left,
  }) {
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
      inputIndex: _content.items.length,
      fontRevision: _flow.fontRevision,
      styleRevision: _flow.styleRevision,
      left: left,
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

  ForumBodyTextPageSessionLimits _remainingSubtreeLimits() {
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

  void _finishSource() {
    _composer.finish();
    _flow.close();
    _state = ForumBodyTextPageSessionState.complete;
  }

  void _publishTable(_TableAdmission table, ForumBodyTableLayout layout) {
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
      final source = table.element.source;
      final natural = _tableExtent == ForumBodyTableExtent.natural;
      final height = natural ? layout.size.height : snapshot.height;
      final preferred = math.max(
        1.0,
        math.min(right - left, layout.size.width),
      );
      _intrinsic?.add(preferred, preferred);
      _composer.publishTable(
        (
          path: table.element.path,
          sourceRange: (runeStart: source.runeStart, runeEnd: source.runeEnd),
          bounds: Rect.fromLTWH(
            left,
            0,
            _scopedTable ? preferred : right - left,
            height,
          ),
          contentSize: layout.size,
          fingerprint: layout.fingerprint,
        ),
        retainedItems: usage.items + usage.pages,
        extent: _tableExtent,
      );
      _tables[(index, table.element.path)] = layout;
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

  void _consumeFlowIndex(int index) {
    if (index != _nextFlowIndex) throw StateError('Unordered body flow input');
    _nextFlowIndex++;
  }

  Never _requiresFloatLineLayout() =>
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.floatLineLayout,
      );

  void _fail() {
    if (isClosed) return;
    _recordPublished();
    _flow.close();
    _headingKeepProbe?.close();
    _headingKeepProbe = null;
    _pendingListItem = null;
    _pendingImage = null;
    _closePendingTable();
    _floatFlow?.close();
    _floatFlow = null;
    _floatText?.close();
    _floatText = null;
    _floatInline?.close();
    _floatInline = null;
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
    _tables.removeWhere((key, layout) {
      if (key.$1 < _publishedPageCount) return false;
      layout.close();
      final usage = layout.usage;
      _content.addTable(-usage.paragraphs, -usage.textCodeUnits, -usage.runs);
      return true;
    });
    _state = ForumBodyTextPageSessionState.failed;
  }

  void close() {
    if (isClosed) return;
    _state = ForumBodyTextPageSessionState.closed;
    _flow.close();
    _headingKeepProbe?.close();
    _headingKeepProbe = null;
    _pendingListItem = null;
    _pendingImage = null;
    _closePendingTable();
    _floatFlow?.close();
    _floatFlow = null;
    _floatText?.close();
    _floatText = null;
    _floatInline?.close();
    _floatInline = null;
    for (final lease in _issuedTables.toList()) {
      lease.close();
    }
    for (final table in _tables.values) {
      table.close();
    }
    _tables.clear();
    _flowTableOffsets.clear();
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

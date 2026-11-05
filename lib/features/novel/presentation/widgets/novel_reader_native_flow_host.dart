import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart' show ResolvedFont;
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_document.dart';
import '../../domain/models/novel_reader_marks.dart';
import '../../domain/models/novel_reader_preferences.dart';
import '../models/novel_reader_native_image_tap.dart';
import '../models/novel_reader_native_link_handler.dart';
import '../models/novel_reader_native_prepared_chapter.dart';
import '../models/novel_reader_native_source_location.dart';
import '../models/novel_reader_native_text_selection.dart';
import '../services/novel_reader_native_image_resources.dart';
import '../services/novel_reader_native_flow_position.dart';
import '../services/novel_reader_native_layout_scope.dart';
import '../services/novel_reader_native_owner.dart';
import '../services/novel_reader_native_preparation_service.dart';
import '../services/novel_reader_native_render_environment.dart';
import '../services/novel_reader_native_source_run.dart';
import '../services/novel_reader_native_table_anchor_probe.dart';
import '../services/novel_reader_native_table_window_proof.dart';
import '../services/novel_reader_native_work_scheduler.dart';
import '../services/novel_reader_pagination_cancellation.dart';
import '../services/novel_reader_pagination_demand.dart';
import '../services/novel_reading_image_host.dart';

typedef NovelReaderFlowOffsetRestore = Future<bool> Function(
  double? Function() resolveOffset,
  bool Function() isCurrent,
);

/// Owns a native scrolling layout. Restoration, chapter navigation and
/// progress still belong to the outer reader.
final class NovelReaderNativeFlowHost extends StatefulWidget {
  const NovelReaderNativeFlowHost({
    super.key,
    required this.owner,
    required this.readingAuthority,
    required this.sourceId,
    required this.rawHtml,
    required this.document,
    required this.preferences,
    required this.resolvedFont,
    required this.converter,
    required this.preparationService,
    required this.width,
    required this.scrollController,
    required this.imageHost,
    required this.imagePolicy,
    required this.threadId,
    required this.onContentReady,
    required this.onContentTerminal,
    required this.onImagesReadyChanged,
    required this.onInteraction,
    required this.onImageTap,
    required this.onTextSelection,
    this.onLinkTap,
    this.idleScheduler,
    this.viewportInsets = EdgeInsets.zero,
    this.initialSource,
    this.restoreReflowOffset,
    this.onReflowRestored,
  });

  final NovelReaderNativeOwner owner;
  final Object readingAuthority;
  final String sourceId;
  final String rawHtml;
  final NovelReaderDocument document;
  final NovelReaderPreferences preferences;
  final ResolvedFont resolvedFont;
  final TextConverter converter;
  final NovelReaderNativePreparationService preparationService;
  final double width;
  final ScrollController scrollController;
  final ForumHtmlImageHost imageHost;
  final ForumHtmlPreparationImagePolicy imagePolicy;
  final String? threadId;
  final VoidCallback onContentReady;
  final VoidCallback onContentTerminal;
  final ValueChanged<bool> onImagesReadyChanged;
  final VoidCallback onInteraction;
  final ValueChanged<NovelReaderNativeImageTap> onImageTap;
  final ValueChanged<NovelReaderNativeTextSelection> onTextSelection;
  final NovelReaderNativeLinkHandler? onLinkTap;
  final NovelReaderPaginationIdleScheduler? idleScheduler;
  final EdgeInsets viewportInsets;
  final NovelReaderNativeSourceLocation? initialSource;
  final NovelReaderFlowOffsetRestore? restoreReflowOffset;
  final ValueChanged<NovelReaderTextAnchor>? onReflowRestored;

  @override
  NovelReaderNativeFlowHostState createState() =>
      NovelReaderNativeFlowHostState();
}

final class NovelReaderNativeFlowHostState
    extends State<NovelReaderNativeFlowHost> {
  static const _sliceHeight = 1024.0;
  static const _limits = ForumBodyTextPageSessionLimits(
    maxPages: 10000,
    maxFragments: 100000,
    maxParagraphs: 16384,
    maxTextCodeUnits: 1024 * 1024,
    maxRuns: 100000,
    maxIssuedLeases: 512,
  );

  final _expansion = <String, bool>{};
  final _imageLayouts = <String, ForumHtmlImageLayout>{};
  final _inlineSizes = <String, Size>{};
  Object? _documentKey;
  Object? _layoutKey;
  _FlowRun? _request;
  _FlowRun? _displayed;
  final _retiring = <_FlowRun>{};
  Object? _error;
  bool _emptyBody = false;
  bool _initialSourceTaken = false;
  int _revision = 0;
  double? _lastScrollOffset;

  @override
  void initState() {
    super.initState();
    widget.owner.addListener(_ownerChanged);
    widget.scrollController.addListener(_outerMoved);
  }

  @override
  void didUpdateWidget(covariant NovelReaderNativeFlowHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.owner, widget.owner)) {
      oldWidget.owner.removeListener(_ownerChanged);
      widget.owner.addListener(_ownerChanged);
    }
    if (!identical(oldWidget.scrollController, widget.scrollController)) {
      oldWidget.scrollController.removeListener(_outerMoved);
      widget.scrollController.addListener(_outerMoved);
      _lastScrollOffset = null;
      _cancelReflow();
    }
  }

  void _ownerChanged() {
    if (mounted) setState(() => _revision++);
  }

  bool _current(_FlowRun run) =>
      mounted &&
      identical(_request, run) &&
      !run.token.isCancelled &&
      !widget.owner.isClosed &&
      run.handle?.isCurrent != false;

  bool _interactive(_FlowRun run) =>
      _current(run) && identical(_displayed, run) && run.ready;

  @override
  Widget build(BuildContext context) {
    final documentKey = (
      widget.owner,
      widget.readingAuthority,
      widget.sourceId,
      widget.rawHtml,
      widget.document.textConversionIdentity,
    );
    final key = (
      documentKey,
      widget.preferences,
      widget.resolvedFont.cacheKey,
      widget.owner.fontGeneration,
      widget.width,
      widget.preparationService,
      widget.imageHost,
      widget.imagePolicy,
      Theme.of(context),
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
      Localizations.maybeLocaleOf(context),
      _revision,
    );
    if (_layoutKey != key && widget.width > 0 && !widget.owner.isClosed) {
      _layoutKey = key;
      final sameDocument = _documentKey == documentKey;
      final position = sameDocument ? _positionForReflow() : null;
      if (!sameDocument) {
        _documentKey = documentKey;
        _expansion.clear();
        _imageLayouts.clear();
        _inlineSizes.clear();
        _retire(_displayed);
        _displayed = null;
      }
      _request?.stop();
      if (!identical(_request, _displayed)) _retire(_request);
      final run = _request = _FlowRun(widget.idleScheduler);
      if (position != null) run.reflow = _FlowReflow(position);
      _error = null;
      _emptyBody = false;
      final config = widget;
      NovelReaderNativeRenderEnvironment? environment;
      Object? captureError;
      try {
        environment = NovelReaderNativeRenderEnvironment.capture(
          context,
          preferences: config.preferences,
          resolvedFont: config.resolvedFont,
        );
      } on Object catch (error) {
        captureError = error;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_current(run)) return;
        widget.onImagesReadyChanged(false);
        if (captureError != null) {
          _fail(run, captureError);
        } else {
          _takeInitialSource(run);
          unawaited(_prepare(config, environment!, run));
        }
      });
    }

    final run = _displayed;
    final session = run?.session;
    final prefix = run?.prefix;
    final error = _error;
    if (run == null || session == null || prefix == null) {
      return SliverLayoutBuilder(
        builder: (context, _) => SliverToBoxAdapter(
          child: error != null
              ? _failure(error)
              : SizedBox(height: _emptyBody ? 0 : 96),
        ),
      );
    }
    final body = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.horizontal &&
            ((notification is ScrollStartNotification &&
                    notification.dragDetails != null) ||
                (notification is UserScrollNotification &&
                    notification.direction != ScrollDirection.idle))) {
          _cancelReflow();
        }
        return false;
      },
      child: ForumBodyFlowSliver(
        key: run.bodyKey,
        session: session,
        prefix: prefix,
        initialTableOffset: run.initialTableOffset,
        isCurrentLayout: _current(run) && error == null,
        onReadyChanged: (ready) => _ready(run, ready),
        onTableWindowChanged: widget.restoreReflowOffset == null
            ? null
            : (index, window) =>
                  _tableWindowChanged(run, index, prefix[index].table!, window),
        onFloatedTableWindowChanged: widget.restoreReflowOffset == null
            ? null
            : (index, frame, window) =>
                  _tableWindowChanged(run, index, frame, window),
        onFailure: (error, _) => _fail(run, error),
        buildSlice: (context, snapshot, index, fragments) =>
            _slice(context, run, snapshot, index, fragments),
      ),
    );
    return SliverMainAxisGroup(
      slivers: [
        body,
        if (error != null) SliverToBoxAdapter(child: _failure(error)),
      ],
    );
  }

  Future<void> _prepare(
    NovelReaderNativeFlowHost config,
    NovelReaderNativeRenderEnvironment environment,
    _FlowRun run,
  ) async {
    try {
      final prepared = await config.owner.preparationCache.resolve(
        service: config.preparationService,
        episodeId: config.document.episodeId,
        sourceId: config.sourceId,
        rawHtml: config.rawHtml,
        semanticDocument: config.document,
        converter: config.converter,
        cancellation: run.token,
      );
      if (!_current(run)) return;
      if (prepared is NovelReaderNativeEmptyChapter) {
        _empty(run);
        return;
      }
      final chapter = prepared as NovelReaderNativePreparedChapter;
      final collapses = chapter.document.collapseElements.isEmpty
          ? null
          : ForumBodyCollapseLayout(
              chapter.document,
              expansionOverrides: _expansion,
            );
      final images =
          await NovelReaderNativeImageResources(
            chapter: chapter,
            host: config.imageHost,
            policy: config.imagePolicy,
            threadId: config.threadId,
            cacheOwnerId: config.threadId,
          ).capture(
            cancellation: run.token,
            maxCodeUnits: _limits.maxTextCodeUnits,
            collapses: collapses,
            resolvedLayouts: _imageLayouts,
            resolvedInlineSizes: _inlineSizes,
          );
      if (!_current(run)) return;
      final scope = await NovelReaderNativeLayoutScope.prepare(
        chapter: chapter,
        environment: environment,
        width: config.width,
        height: _sliceHeight,
        cancellation: run.token,
        images: images,
        collapses: collapses,
        fontCollectionGeneration: config.owner.fontGeneration,
        maxIssuedLeases: _limits.maxIssuedLeases,
        maxParagraphCacheEntries: config.owner.maxParagraphEntries,
        maxParagraphCacheEstimatedBytes:
            config.owner.maxParagraphEstimatedBytes,
      );
      if (!_current(run)) return;
      final layoutId = '${scope.paginationKey}/flow';
      final handle = run.handle = config.owner.acquireCache(
        layoutKey: '$layoutId/${identityHashCode(run)}',
      );
      run.scope = scope;
      final session = run.session = scope.openSession(
        cache: handle.cache,
        layoutId: layoutId,
        limits: _limits,
        tableExtent: ForumBodyTableExtent.natural,
      );
      run.imageTracker = NovelReadingImageTracker((_) {
        if (_current(run)) _reportImages(run);
      });
      run.imageHost = config.imageHost;
      final source = run.source = NovelReaderNativeSourceRun(
        session: session,
        demand: run.demand,
        parent: run.token,
        onPublication: (prefix, _) async {
          if (!_current(run)) return;
          final start = run.prefix?.length ?? 0;
          run.updatePrefix(prefix);
          if (prefix.isEmpty) {
            if (prefix.isComplete) _empty(run);
            return;
          }
          final reflow = run.reflow;
          if (reflow != null && !identical(_displayed, run)) {
            if (await _publishAtSource(run, reflow, start)) return;
            if (!_current(run)) return;
          }
          final scroll = config.scrollController;
          // The reader can move within the retained prefix while a replacement
          // is being measured. Use the live window at publication time.
          final retainedEnd = _displayed != null && scroll.hasClients
              ? scroll.offset + scroll.position.viewportDimension
              : 0.0;
          if (identical(_displayed, run) ||
              run.extent >= retainedEnd ||
              prefix.isComplete) {
            setState(() {
              if (!identical(_displayed, run)) _retire(_displayed);
              _displayed = run;
            });
          }
        },
      );
      await source.run();
    } on Object catch (error) {
      if (_current(run)) _fail(run, error);
    }
  }

  void _ready(_FlowRun run, bool ready) {
    if (!_current(run) || !identical(_displayed, run)) return;
    run.ready = ready;
    run.demand.update(targetPending: !ready, pageIndex: 0);
    _reportReady(run);
  }

  void _reportReady(_FlowRun run) {
    if (!_current(run) || !identical(_displayed, run)) return;
    _reportImages(run);
    _proveNextTable(run);
    final reflow = run.reflow;
    if (run.ready &&
        reflow != null &&
        reflow.source.tablePath == null &&
        reflow.offsetApplied &&
        !reflow.verifying) {
      reflow.verifying = true;
      unawaited(_verifyFlowReflow(run, reflow));
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    if (run.ready && run.reflow == null && !run.reportedReady) {
      run.reportedReady = true;
      widget.onContentReady();
    }
  }

  void _reportImages(_FlowRun run) => widget.onImagesReadyChanged(
    run.ready && run.reflow == null && run.imageTracker!.isReady,
  );

  void _outerMoved() {
    final scroll = widget.scrollController;
    if (!scroll.hasClients) return;
    final offset = scroll.offset;
    if (_lastScrollOffset == offset) return;
    _lastScrollOffset = offset;
    _displayed?.clearTableWindows();
    _displayed?.textPosition = null;
    _displayed?.imageSample?.cancel();
    _cancelReflow();
  }

  _FlowSourcePosition? _positionForReflow() {
    final scroll = widget.scrollController;
    if (widget.restoreReflowOffset == null ||
        !scroll.hasClients ||
        scroll.position.isScrollingNotifier.value) {
      return null;
    }
    _FlowSourcePosition? position;
    for (final candidate in [
      _displayed?.leadingTablePosition,
      _displayed?.textPosition,
      _request?.reflow?.source,
    ]) {
      if (candidate != null &&
          identical(candidate.scroll, scroll.position) &&
          candidate.pixels == scroll.offset &&
          (position == null || candidate.inset.dy < position.inset.dy)) {
        position = candidate;
      }
    }
    return position;
  }

  RenderForumBodyFlowBoundary? _bodyBoundary(_FlowRun run) {
    final render = run.bodyKey.currentContext?.findRenderObject();
    return render is RenderForumBodyFlowBoundary && render.attached
        ? render
        : null;
  }

  double? _bodyTop(_FlowRun run) =>
      _bodyBoundary(run)?.constraints.precedingScrollExtent;

  double _readableHeight(ScrollPosition position) =>
      position.viewportDimension - widget.viewportInsets.vertical;

  void _takeInitialSource(_FlowRun run) {
    final source = widget.initialSource;
    final scroll = widget.scrollController;
    if (_initialSourceTaken || source == null) return;
    _initialSourceTaken = true;
    if (widget.restoreReflowOffset == null ||
        !scroll.hasClients ||
        scroll.position.isScrollingNotifier.value) {
      return;
    }
    final position = scroll.position;
    _lastScrollOffset = position.pixels;
    run.reflow = _FlowReflow((
      identity: source.identity,
      tablePath: source.tablePath,
      anchor: source.anchor,
      imageProgress: source.imageProgress,
      inset: Offset.zero,
      scroll: position,
      pixels: position.pixels,
    ));
  }

  void cancelSourceRestore() {
    _initialSourceTaken = true;
    _cancelReflow();
  }

  /// Capture the settled source before replacing the scrolling surface.
  Future<NovelReaderNativeSourceLocation?> captureVisibleSource(
    NovelReaderPaginationCancellationToken token,
  ) async {
    final run = _displayed;
    final scroll = widget.scrollController;
    if (run == null || !_interactive(run) || !scroll.hasClients) return null;
    final position = scroll.position;
    final pixels = position.pixels;
    if (position.isScrollingNotifier.value) return null;
    final table = run.leadingTablePosition;
    final top = _bodyTop(run);
    final point = await _sampleSource(
      run,
      position,
      token,
      includeRenderedImages: true,
    );
    if (token.isCancelled ||
        !_interactive(run) ||
        !scroll.hasClients ||
        !identical(scroll.position, position) ||
        position.pixels != pixels ||
        position.isScrollingNotifier.value) {
      return null;
    }
    if (table != null &&
        identical(run.leadingTablePosition, table) &&
        identical(table.scroll, position) &&
        table.pixels == pixels &&
        (point == null ||
            (top != null &&
                table.inset.dy <=
                    top +
                        run.extentBefore(point.slice) +
                        point.bounds.top -
                        pixels -
                        widget.viewportInsets.top))) {
      return (
        identity: table.identity,
        anchor: table.anchor,
        tablePath: table.tablePath,
        imageProgress: 0.0,
      );
    }
    if (point == null || top == null) return null;
    final imageTop = top + run.extentBefore(point.slice) + point.bounds.top;
    return (
      identity: run.scope!.chapter.identity,
      anchor: point.anchor,
      tablePath: null,
      imageProgress: point.isImage
          ? ((pixels + widget.viewportInsets.top - imageTop) /
                    point.bounds.height)
                .clamp(0.0, 1.0)
          : 0.0,
    );
  }

  void _tableWindowChanged(
    _FlowRun run,
    int index,
    ForumBodyTextPageTable frame,
    ForumBodyTableVisibleWindow? window,
  ) {
    if (!_current(run) || widget.restoreReflowOffset == null) return;
    final key = (slice: index, path: frame.path);
    run.tablePositions.remove(key);
    if (run.tableProofKey == key) run.cancelTableProof();
    if (window != null &&
        window.layout.geometry.grid.table.path == frame.path) {
      run.pendingTables[key] = (frame: frame, window: window);
    } else {
      run.pendingTables.remove(key);
    }
    _proveNextTable(run);
  }

  void _proveNextTable(_FlowRun run) {
    if (!_current(run) || run.tableProof != null) return;
    final reflow = run.reflow;
    final target = reflow?.target;
    final path = reflow?.source.tablePath;
    if (reflow != null &&
        (!reflow.offsetApplied || target == null || path == null)) {
      return;
    }
    final scroll = widget.scrollController;
    final top = _bodyTop(run);
    if (!scroll.hasClients || top == null) return;
    // The viewport can expose several floats in one slice. Keep at most one
    // coverage worker active and prefer the exact target during a restore.
    while (run.pendingTables.isNotEmpty) {
      final key = reflow == null
          ? run.pendingTables.keys.first
          : (slice: target!.slice, path: path!);
      final candidate = run.pendingTables.remove(key);
      if (candidate == null) return;
      if (!candidate.window.isCurrent) continue;
      _proveTable(run, key, candidate, top, scroll, reflow);
      if (run.tableProof != null) return;
    }
  }

  void _proveTable(
    _FlowRun run,
    _FlowTableKey key,
    _FlowTableWindow candidate,
    double bodyTop,
    ScrollController scroll,
    _FlowReflow? reflow,
  ) {
    final (:frame, :window) = candidate;
    final tableTop = bodyTop + run.extentBefore(key.slice) + frame.bounds.top;
    final readableTop = scroll.offset + widget.viewportInsets.top - tableTop;
    final readable = Rect.fromLTWH(
      window.bounds.left,
      readableTop,
      window.bounds.width,
      _readableHeight(scroll.position),
    );
    if (readable.isEmpty) return;
    final token = run.tableProof = NovelReaderPaginationCancellationToken();
    run.tableProofKey = key;
    final position = scroll.position;
    final pixels = scroll.offset;
    _lastScrollOffset = pixels;
    unawaited(() async {
      try {
        final proof = await NovelReaderNativeTableWindowProof.prepare(
          window: window,
          anchors: run.scope!.chapter.anchors,
          scheduler: const NovelReaderNativeWorkScheduler(),
          token: token,
          preferred: reflow?.source.anchor,
          viewportClip: readable,
        );
        if (!_current(run) ||
            token.isCancelled ||
            !identical(run.reflow, reflow) ||
            proof?.isCurrent != true ||
            !scroll.hasClients ||
            !identical(scroll.position, position) ||
            scroll.offset != pixels) {
          return;
        }
        final anchor = proof!.anchor;
        final bounds = proof.bounds;
        if (anchor != null && bounds != null) {
          final positionInBody = (
            identity: run.scope!.chapter.identity,
            tablePath: frame.path,
            anchor: anchor,
            imageProgress: 0.0,
            inset:
                bounds.topLeft +
                Offset(frame.bounds.left - window.bounds.left, -readableTop),
            scroll: position,
            pixels: pixels,
          );
          run.tablePositions[key] = (position: positionInBody, window: window);
        }
        if (reflow != null) {
          _finishReflow(run, reflow, proof.matchesPreferred ? anchor : null);
        }
      } on Object {
        if (!token.isCancelled && reflow != null) _finishReflow(run, reflow);
      } finally {
        if (identical(run.tableProof, token)) {
          run.cancelTableProof();
          _proveNextTable(run);
        }
      }
    }());
    // A settled table reports after paint. Its proof still needs another frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Retain the old view until the new source and its following viewport have
  /// been measured. The mounted result must then prove the actual coverage.
  Future<bool> _publishAtSource(
    _FlowRun run,
    _FlowReflow reflow,
    int start,
  ) async {
    final prefix = run.prefix!;
    final scope = run.scope!;
    final scroll = widget.scrollController;
    final source = reflow.source;
    bool current() =>
        _current(run) &&
        identical(run.reflow, reflow) &&
        scroll.hasClients &&
        identical(scroll.position, source.scroll);
    if (!current() || scope.chapter.identity != source.identity) {
      _finishReflow(run, reflow);
      return false;
    }
    if (reflow.target == null) {
      final NovelReaderNativeFlowPoint? candidate;
      try {
        candidate = await _probeReflow(run, reflow, start);
      } on Object {
        if (current()) _finishReflow(run, reflow);
        return false;
      }
      if (!current()) return false;
      if (candidate != null) {
        final index = candidate.slice;
        final table = prefix[index].tableFrames
            .where((frame) => frame.path == source.tablePath)
            .firstOrNull;
        final bounds = candidate.bounds;
        final height = _readableHeight(scroll.position);
        if (height <= 0 || (!candidate.isImage && bounds.height > height)) {
          _finishReflow(run, reflow);
          return false;
        }
        final Rect focus;
        if (candidate.isImage) {
          // Reveal a point within the original image. A natural flowing image
          // can be taller than both its book page and the readable viewport.
          final band = math.min(1.0, math.min(bounds.height, height));
          final y = (bounds.height * source.imageProgress).clamp(
            0.0,
            bounds.height - band,
          );
          focus = Rect.fromLTWH(
            bounds.left,
            bounds.top + y,
            bounds.width,
            band,
          );
        } else {
          focus = table == null ? bounds : bounds.shift(table.bounds.topLeft);
        }
        final y = focus.top - source.inset.dy.clamp(0.0, height - focus.height);
        reflow.target = (
          slice: index,
          bodyOffset: run.extentBefore(index) + y - widget.viewportInsets.top,
          horizontal: table == null
              ? null
              : (bounds.left -
                        (source.inset.dx - table.bounds.left).clamp(
                          0.0,
                          table.bounds.width - bounds.width,
                        ))
                    .clamp(
                      0.0,
                      math.max(
                        0.0,
                        table.contentSize.width - table.bounds.width,
                      ),
                    ),
          focus: focus,
        );
      }
    }
    final target = reflow.target;
    if (target == null) {
      if (!prefix.isComplete) return true;
      _finishReflow(run, reflow);
      return false;
    }
    if (scroll.position.isScrollingNotifier.value) {
      _finishReflow(run, reflow);
      return false;
    }
    if (!prefix.isComplete &&
        run.extent < target.bodyOffset + scroll.position.viewportDimension) {
      return true;
    }
    setState(() {
      _retire(_displayed);
      _displayed = run;
      if (target.horizontal case final offset?) {
        final path = source.tablePath!;
        if (prefix[target.slice].table?.path == path) {
          run.initialTableOffset = (slice: target.slice, offset: offset);
        } else {
          run.session!.setFlowTableOffset(target.slice, path, offset);
        }
      }
    });
    final bool applied;
    try {
      applied = await reflow.token.waitFor(
        widget.restoreReflowOffset!(() {
          final top = _bodyTop(run);
          return top == null ? null : top + target.bodyOffset;
        }, current),
      );
    } on Object {
      if (current()) _finishReflow(run, reflow);
      return true;
    }
    if (!current()) return true;
    _lastScrollOffset = scroll.offset;
    final bodyTop = _bodyTop(run);
    final y = bodyTop == null
        ? null
        : bodyTop + run.extentBefore(target.slice) + target.focus.top;
    final readableTop = scroll.offset + widget.viewportInsets.top;
    final readableBottom = readableTop + _readableHeight(scroll.position);
    if (!applied ||
        y == null ||
        y < readableTop - .5 ||
        y + target.focus.height > readableBottom + .5) {
      _finishReflow(run, reflow);
    } else {
      reflow.offsetApplied = true;
      _reportReady(run);
    }
    return true;
  }

  Future<NovelReaderNativeFlowPoint?> _probeReflow(
    _FlowRun run,
    _FlowReflow reflow,
    int start,
  ) async {
    final prefix = run.prefix!;
    final session = run.session!;
    final anchors = run.scope!.chapter.anchors;
    final source = reflow.source;
    final path = source.tablePath;
    if (path == null) {
      return probeNovelReaderFlowSource(
        session: session,
        prefix: prefix,
        anchors: anchors,
        target: source.anchor,
        start: start,
        token: reflow.token,
      );
    }
    for (var index = start; index < prefix.length; index++) {
      if (!prefix[index].tableFrames.any((frame) => frame.path == path)) {
        continue;
      }
      final candidate = await probeNovelReaderNativeTableAnchor(
        session: session,
        anchors: anchors,
        pageIndex: index,
        tablePath: path,
        target: source.anchor,
        allowNodeCompatibility: false,
        scheduler: const NovelReaderNativeWorkScheduler(),
        token: reflow.token,
      );
      if (candidate != null) {
        return (
          slice: index,
          anchor: candidate.anchor,
          bounds: candidate.bounds,
          isImage: false,
        );
      }
    }
    return null;
  }

  Future<void> _verifyFlowReflow(_FlowRun run, _FlowReflow reflow) async {
    final scroll = widget.scrollController;
    if (!scroll.hasClients) {
      _finishReflow(run, reflow);
      return;
    }
    final position = scroll.position;
    final pixels = position.pixels;
    NovelReaderNativeFlowPoint? point;
    try {
      // The destination verifies mounted geometry here. Its accepted image
      // frame remains a separate readiness check.
      point = await _sampleSource(
        run,
        position,
        reflow.token,
        preferred: reflow.source.anchor,
        slice: reflow.target!.slice,
      );
    } on Object {
      // An unreadable or retired window cannot confirm a source restore.
    }
    if (_current(run) && identical(run.reflow, reflow)) {
      final stillThere =
          scroll.hasClients &&
          identical(scroll.position, position) &&
          position.pixels == pixels;
      _finishReflow(run, reflow, stillThere ? point?.anchor : null);
    }
  }

  Future<NovelReaderNativeFlowPoint?> _sampleSource(
    _FlowRun run,
    ScrollPosition position,
    NovelReaderPaginationCancellationToken token, {
    NovelReaderTextAnchor? preferred,
    int? slice,
    bool includeRenderedImages = false,
  }) async {
    final boundary = _bodyBoundary(run);
    final window = boundary?.borrowTextWindow();
    if (window == null) return null;
    final top = boundary!.constraints.precedingScrollExtent;
    return sampleNovelReaderFlowSource(
      window: window,
      anchors: run.scope!.chapter.anchors,
      readable: Rect.fromLTWH(
        0,
        position.pixels + widget.viewportInsets.top - top,
        window.bounds.width,
        _readableHeight(position),
      ),
      token: token,
      preferred: preferred,
      targetSlice: slice,
      includeRenderedImages: includeRenderedImages,
    );
  }

  void _cancelReflow() {
    final run = _request;
    if (run?.reflow case final reflow?) _finishReflow(run!, reflow);
  }

  void _finishReflow(
    _FlowRun run,
    _FlowReflow reflow, [
    NovelReaderTextAnchor? restored,
  ]) {
    if (!identical(run.reflow, reflow)) return;
    run.reflow = null;
    reflow.token.cancel();
    if (restored != null && _current(run)) {
      widget.onReflowRestored?.call(restored);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportReady(run));
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _empty(_FlowRun run) {
    setState(() {
      _retire(_displayed);
      _displayed = null;
      _emptyBody = true;
    });
    _retire(run);
    widget.onContentTerminal();
  }

  void _fail(_FlowRun run, Object error) {
    if (!_current(run) || _error != null) return;
    setState(() => _error = error);
    run.stop();
    if (!identical(_displayed, run)) _retire(run);
    widget.onContentTerminal();
    widget.onImagesReadyChanged(false);
  }

  Widget _failure(Object error) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.novelReaderLoadFailed(
              LibraryErrorSummary.resolve(l10n, error),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _revision++),
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }

  Widget _slice(
    BuildContext context,
    _FlowRun run,
    ForumBodyTextPageSnapshot snapshot,
    int index,
    List<ForumBodyPreparedTextFragment> fragments,
  ) {
    final images = fragments
        .where((fragment) => fragment.imageCount > 0)
        .toList();
    Widget build(VoidCallback? onFrameChanged) =>
        _pageSurface(context, run, snapshot, index, fragments, onFrameChanged);
    return images.isEmpty
        ? build(null)
        : _FlowImageReadiness(
            tracker: run.imageTracker!,
            fragments: images,
            buildSurface: build,
          );
  }

  Widget _pageSurface(
    BuildContext context,
    _FlowRun run,
    ForumBodyTextPageSnapshot snapshot,
    int index,
    List<ForumBodyPreparedTextFragment> fragments,
    VoidCallback? onFrameChanged,
  ) {
    final l10n = AppLocalizations.of(context);
    final catalog = run.scope!.images!;
    bool current() =>
        _interactive(run) && fragments.every((fragment) => fragment.isActive);
    void openImage(ForumHtmlReadableImageEntry entry) {
      if (current()) {
        widget.onImageTap(
          NovelReaderNativeImageTap(entry, catalog.sequence, current),
        );
      }
    }

    return ForumBodyTextPageSurface.prepared(
      snapshot: snapshot,
      pageIndex: index,
      layoutId: snapshot.layoutId,
      fragments: fragments,
      compactHeight: true,
      imageHost: run.imageHost,
      collapseLabels: ForumHtmlCollapseLabels(
        fallbackTitle: l10n.threadHtmlCollapseContent,
        expandedSemanticsLabel: l10n.threadHtmlCollapseExpanded,
        collapsedSemanticsLabel: l10n.threadHtmlCollapseCollapsed,
      ),
      onCollapseToggle: (fragment) {
        final header = fragment.collapseHeader;
        if (!current() || header == null) return;
        widget.onInteraction();
        setState(() {
          _expansion[header.id] = !header.expanded;
          _revision++;
        });
      },
      onImageTap: (fragment) => openImage(fragment.content.input.entry),
      onInlineImageTap: (_, binding) {
        if (binding.input.entry case final entry?) openImage(entry);
      },
      onImageDisplayChanged: onFrameChanged == null
          ? null
          : (_, _) => onFrameChanged(),
      onInlineImageDisplayChanged: onFrameChanged == null
          ? null
          : (_, _, _) => onFrameChanged(),
      onImageLayoutResolved: (fragment, layout) {
        final input = fragment.content.input;
        if (!_current(run) || !fragment.isActive || !catalog.owns(input)) {
          return;
        }
        final path = input.element.path;
        final updated = updatedNovelReaderBlockImageLayout(
          input: input,
          resolved: layout,
          previous: _imageLayouts[path],
          isFloated: snapshot[index].fragments.any(
            (item) => item.isFloated && item.path == path,
          ),
        );
        if (updated == null) return;
        _imageLayouts[path] = updated;
        _scheduleReflow(run);
      },
      onInlineImageLayoutResolved: (fragment, binding, layout) {
        final input = binding.input;
        final key = input.image.cacheKey;
        final size = layout.displaySize;
        if (!_current(run) ||
            !fragment.isActive ||
            !identical(fragment.view.images[binding.atomIndex], binding) ||
            !catalog.ownsInline(input) ||
            !input.usesIntrinsicSize ||
            (input.image.isSticker && input.image.htmlSize != null) ||
            size == null ||
            !size.isFinite ||
            size.isEmpty ||
            size ==
                (_inlineSizes[key] ??
                    catalog
                        .layoutFor(input.identity, input.element)
                        ?.displaySize)) {
          return;
        }
        _inlineSizes[key] = size;
        _scheduleReflow(run);
      },
      onLinkTap: widget.onLinkTap == null
          ? null
          : (url) {
              // Other visible slices can still be preparing. The hit belongs
              // to this mounted delivery under the current source request.
              bool linkCurrent() =>
                  _current(run) &&
                  identical(_displayed, run) &&
                  fragments.every((fragment) => fragment.isActive);
              if (linkCurrent()) widget.onLinkTap?.call(url, linkCurrent);
            },
      onSourceLongPress: (_, selection) {
        if (current()) {
          widget.onTextSelection(
            NovelReaderNativeTextSelection(selection, current),
          );
        }
      },
    );
  }

  void _scheduleReflow(_FlowRun run) {
    if (run.imageSample != null) return;
    final token = run.imageSample = NovelReaderPaginationCancellationToken();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reflowAfterImage(run, token));
      WidgetsBinding.instance.ensureVisualUpdate();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _reflowAfterImage(
    _FlowRun run,
    NovelReaderPaginationCancellationToken token,
  ) async {
    try {
      if (!_current(run)) return;
      final scroll = widget.scrollController;
      final top = _bodyTop(run);
      if (widget.restoreReflowOffset != null &&
          run.reportedReady &&
          top != null &&
          scroll.hasClients &&
          scroll.offset > .5 &&
          !scroll.position.isScrollingNotifier.value &&
          !token.isCancelled) {
        final position = scroll.position;
        final pixels = position.pixels;
        final point = await _sampleSource(run, position, token);
        if (_current(run) &&
            !token.isCancelled &&
            scroll.hasClients &&
            identical(scroll.position, position) &&
            position.pixels == pixels &&
            point != null) {
          run.textPosition = (
            identity: run.scope!.chapter.identity,
            tablePath: null,
            anchor: point.anchor,
            imageProgress: 0.0,
            inset: Offset(
              0,
              top +
                  run.extentBefore(point.slice) +
                  point.bounds.top -
                  pixels -
                  widget.viewportInsets.top,
            ),
            scroll: position,
            pixels: pixels,
          );
        }
      }
    } on Object {
      // Apply accepted dimensions even when reading moved during sampling.
    } finally {
      if (identical(run.imageSample, token)) run.imageSample = null;
      token.cancel();
      if (_current(run)) setState(() => _revision++);
    }
  }

  void _retire(_FlowRun? run) {
    if (run == null || !_retiring.add(run)) return;
    run.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retiring.remove(run);
      run.close();
    });
  }

  @override
  void dispose() {
    widget.owner.removeListener(_ownerChanged);
    widget.scrollController.removeListener(_outerMoved);
    _request?.close();
    _displayed?.close();
    for (final run in _retiring) {
      run.close();
    }
    _retiring.clear();
    super.dispose();
  }
}

typedef _FlowSourcePosition = ({
  ForumBodyIdentity identity,
  String? tablePath,
  NovelReaderTextAnchor anchor,
  double imageProgress,
  Offset inset,
  ScrollPosition scroll,
  double pixels,
});

typedef _FlowTableKey = ({int slice, String path});

typedef _FlowTableWindow = ({
  ForumBodyTextPageTable frame,
  ForumBodyTableVisibleWindow window,
});

final class _FlowReflow {
  _FlowReflow(this.source);

  final _FlowSourcePosition source;
  final token = NovelReaderPaginationCancellationToken();
  ({int slice, double bodyOffset, double? horizontal, Rect focus})? target;
  bool offsetApplied = false;
  bool verifying = false;
}

/// The shared surface has already validated the display binding before it
/// reports a frame. Register only its actual mounted resource deliveries.
final class _FlowImageReadiness extends StatefulWidget {
  const _FlowImageReadiness({
    required this.tracker,
    required this.fragments,
    required this.buildSurface,
  });

  final NovelReadingImageTracker tracker;
  final List<ForumBodyPreparedTextFragment> fragments;
  final Widget Function(VoidCallback) buildSurface;

  @override
  State<_FlowImageReadiness> createState() => _FlowImageReadinessState();
}

final class _FlowImageReadinessState extends State<_FlowImageReadiness> {
  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(covariant _FlowImageReadiness oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tracker, widget.tracker)) {
      oldWidget.tracker.remove(this);
    }
    _report();
  }

  void _report() {
    if (mounted) {
      widget.tracker.update(
        this,
        widget.fragments.every((fragment) => fragment.hasRenderedImages),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.buildSurface(_report);

  @override
  void dispose() {
    widget.tracker.remove(this);
    super.dispose();
  }
}

final class _FlowRun {
  _FlowRun(NovelReaderPaginationIdleScheduler? idleScheduler)
    : demand = NovelReaderPaginationDemand(idleScheduler: idleScheduler);

  final token = NovelReaderPaginationCancellationToken();
  final NovelReaderPaginationDemand demand;
  final bodyKey = GlobalKey();
  NovelReaderNativeCacheHandle? handle;
  NovelReaderNativeLayoutScope? scope;
  ForumBodyTextPageSession? session;
  NovelReaderNativeSourceRun? source;
  ForumBodyTextPageSnapshot? prefix;
  NovelReadingImageTracker? imageTracker;
  ForumHtmlImageHost? imageHost;
  final _ends = <double>[];
  final pendingTables = <_FlowTableKey, _FlowTableWindow>{};
  final tablePositions =
      <
        _FlowTableKey,
        ({_FlowSourcePosition position, ForumBodyTableVisibleWindow window})
      >{};
  _FlowSourcePosition? textPosition;
  _FlowReflow? reflow;
  NovelReaderPaginationCancellationToken? imageSample;
  NovelReaderPaginationCancellationToken? tableProof;
  _FlowTableKey? tableProofKey;
  ({int slice, double offset})? initialTableOffset;
  bool ready = false;
  bool reportedReady = false;
  bool _closed = false;

  double get extent => _ends.lastOrNull ?? 0;
  double extentBefore(int slice) => slice == 0 ? 0 : _ends[slice - 1];

  _FlowSourcePosition? get leadingTablePosition {
    _FlowSourcePosition? leading;
    for (final item in tablePositions.values) {
      if (item.window.isCurrent &&
          (leading == null || item.position.inset.dy < leading.inset.dy)) {
        leading = item.position;
      }
    }
    return leading;
  }

  void updatePrefix(ForumBodyTextPageSnapshot next) {
    for (var i = prefix?.length ?? 0; i < next.length; i++) {
      _ends.add(extent + next[i].usedHeight);
    }
    prefix = next;
  }

  void cancelTableProof() {
    tableProof?.cancel();
    tableProof = null;
    tableProofKey = null;
  }

  void clearTableWindows() {
    cancelTableProof();
    pendingTables.clear();
    tablePositions.clear();
  }

  void stop() {
    clearTableWindows();
    imageSample?.cancel();
    reflow?.token.cancel();
    token.cancel();
    source?.close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    stop();
    demand.dispose();
    imageTracker?.dispose();
    session?.close();
    handle?.release();
  }
}

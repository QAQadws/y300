import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart' show ResolvedFont;
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_document.dart';
import '../../domain/models/novel_reader_preferences.dart';
import '../models/novel_reader_native_image_tap.dart';
import '../models/novel_reader_native_prepared_chapter.dart';
import '../models/novel_reader_native_text_selection.dart';
import '../services/novel_reader_native_image_resources.dart';
import '../services/novel_reader_native_layout_scope.dart';
import '../services/novel_reader_native_owner.dart';
import '../services/novel_reader_native_preparation_service.dart';
import '../services/novel_reader_native_render_environment.dart';
import '../services/novel_reader_native_source_run.dart';
import '../services/novel_reader_pagination_cancellation.dart';
import '../services/novel_reader_pagination_demand.dart';
import '../services/novel_reading_image_host.dart';

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
    this.idleScheduler,
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
  final NovelReaderPaginationIdleScheduler? idleScheduler;

  @override
  State<NovelReaderNativeFlowHost> createState() =>
      _NovelReaderNativeFlowHostState();
}

final class _NovelReaderNativeFlowHostState
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
  int _revision = 0;
  bool _reflowScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.owner.addListener(_ownerChanged);
  }

  @override
  void didUpdateWidget(covariant NovelReaderNativeFlowHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.owner, widget.owner)) {
      oldWidget.owner.removeListener(_ownerChanged);
      widget.owner.addListener(_ownerChanged);
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
      if (_documentKey != documentKey) {
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
    final body = ForumBodyFlowSliver(
      key: ObjectKey(run),
      session: session,
      prefix: prefix,
      isCurrentLayout: _current(run) && error == null,
      onReadyChanged: (ready) => _ready(run, ready),
      onFailure: (error, _) => _fail(run, error),
      buildSlice: (context, snapshot, index, fragments) =>
          _slice(context, run, snapshot, index, fragments),
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
        onPublication: (prefix, _) {
          if (!_current(run)) return;
          run.updatePrefix(prefix);
          if (prefix.isEmpty) {
            if (prefix.isComplete) _empty(run);
            return;
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
    _reportImages(run);
    if (ready && !run.reportedReady) {
      run.reportedReady = true;
      widget.onContentReady();
    }
  }

  void _reportImages(_FlowRun run) =>
      widget.onImagesReadyChanged(run.ready && run.imageTracker!.isReady);

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
        final ratio = layout.aspectRatio ?? layout.displaySize?.aspectRatio;
        if (!_current(run) ||
            !fragment.isActive ||
            !catalog.owns(input) ||
            ratio == null ||
            !ratio.isFinite ||
            ratio <= 0 ||
            ratio ==
                (_imageLayouts[input.element.path]?.aspectRatio ??
                    input.aspectRatio)) {
          return;
        }
        _imageLayouts[input.element.path] = ForumHtmlImageLayout(
          aspectRatio: ratio,
        );
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
    if (_reflowScheduled) return;
    _reflowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reflowScheduled = false;
      if (_current(run)) setState(() => _revision++);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
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
    _request?.close();
    _displayed?.close();
    for (final run in _retiring) {
      run.close();
    }
    _retiring.clear();
    super.dispose();
  }
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
  NovelReaderNativeCacheHandle? handle;
  NovelReaderNativeLayoutScope? scope;
  ForumBodyTextPageSession? session;
  NovelReaderNativeSourceRun? source;
  ForumBodyTextPageSnapshot? prefix;
  NovelReadingImageTracker? imageTracker;
  ForumHtmlImageHost? imageHost;
  double extent = 0;
  bool ready = false;
  bool reportedReady = false;
  bool _closed = false;

  void updatePrefix(ForumBodyTextPageSnapshot next) {
    for (var i = prefix?.length ?? 0; i < next.length; i++) {
      extent += next[i].usedHeight;
    }
    prefix = next;
  }

  void stop() {
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

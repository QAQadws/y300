import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/rendering.dart'
    show GrowthDirection, RenderAbstractViewport, RenderSliver;
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_layout_scroll_controller.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';

import '../../application/forum_body_preparation_controller.dart';
import '../../application/forum_body_preparation_executor.dart';
import '../../application/forum_native_body_cache.dart';
import '../../domain/models/forum_html_reader_preferences.dart';
import 'forum_html_preparation_placeholder.dart';
import 'forum_native_body_images.dart';

part 'forum_native_block_reflow.dart';
part 'forum_native_source_reflow.dart';

/// Natural document flow for readers whose outer surface owns scrolling.
final class ForumNativeBodyFlow extends StatefulWidget {
  const ForumNativeBodyFlow({
    super.key,
    required this.prepared,
    required this.preferences,
    required this.theme,
    required this.textStyle,
    required this.fontRevision,
    required this.imageHost,
    required this.expansion,
    required this.callbacks,
    this.onOpenImage,
    required this.clipboardTextWriter,
    this.onOpenSelectedLink,
    this.selectionEnabled = true,
    this.selectEntireBody = false,
    this.isSelectionCurrent,
    this.onGeometry,
    this.onLayoutPhase,
    required this.errorBuilder,
    this.imageAnchorController,
    this.bodyPresentation,
    this.contentLayout = ForumHtmlContentLayout.document,
    this.cache,
  });

  final ForumHtmlPreparedRenderDocument prepared;
  final ForumHtmlReaderPreferences preferences;
  final ForumHtmlThemeContext theme;
  final TextStyle textStyle;
  final String fontRevision;
  final ForumHtmlImageHost? imageHost;
  final Map<String, bool> expansion;
  final ForumHtmlRenderCallbacks callbacks;
  final void Function(
    ForumHtmlReadableImageSequence gallery,
    ForumHtmlImageRequest image,
  )?
  onOpenImage;
  final ClipboardTextWriter clipboardTextWriter;
  final ForumSelectionLinkOpener? onOpenSelectedLink;
  final bool selectionEnabled;
  final bool selectEntireBody;
  final bool Function()? isSelectionCurrent;
  final void Function(bool ready, bool complete)? onGeometry;
  final ValueChanged<ForumHtmlBodyLayoutPhase>? onLayoutPhase;
  final WidgetBuilder errorBuilder;
  final ForumHtmlImageAnchorController? imageAnchorController;
  final ForumHtmlBodyPresentation? bodyPresentation;
  final ForumHtmlContentLayout contentLayout;
  final ForumNativeBodyCache? cache;

  @override
  State<ForumNativeBodyFlow> createState() => _ForumNativeBodyFlowState();
}

class _ForumNativeBodyFlowState extends State<ForumNativeBodyFlow> {
  static const _sliceHeight = 768.0;
  static const _limits = ForumBodyTextPageSessionLimits(
    maxPages: 10000,
    maxFragments: 100000,
    maxParagraphs: 16384,
    maxTextCodeUnits: 1024 * 1024,
    maxRuns: 100000,
    maxIssuedLeases: 256,
  );

  ForumBodyParagraphCache? _localCache;
  ForumBodyParagraphCache get _cache =>
      widget.cache?.paragraphs ??
      (_localCache ??= ForumBodyParagraphCache(
        maxEntries: 128,
        maxEstimatedBytes: 8 << 20,
      ));
  final _preparation = ForumBodyPreparationController();
  final _resolvedImages = <String, ForumNativeBodyImageLayoutHint>{};
  final _changedImages = <String, _ImageChange>{};
  ForumBodyDocument? _document;
  _FlowRun? _pending, _shown;
  Object? _layoutKey;
  Object? _error;
  var _revision = 0;
  var _foldRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.imageAnchorController?.bindSequence(widget.prepared.sequence);
    _preparation.addListener(_prepare);
    _prepare();
  }

  @override
  void didUpdateWidget(covariant ForumNativeBodyFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageAnchorController != widget.imageAnchorController ||
        !identical(oldWidget.prepared, widget.prepared)) {
      widget.imageAnchorController?.bindSequence(widget.prepared.sequence);
    }
    if (identical(oldWidget.prepared, widget.prepared) &&
        identical(oldWidget.bodyPresentation, widget.bodyPresentation) &&
        identical(oldWidget.cache, widget.cache)) {
      return;
    }
    _preparation.reset();
    _document = null;
    _resolvedImages.clear();
    _changedImages.clear();
    _retireLayouts();
    _error = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  void _prepare() {
    if (!mounted || _document != null || _error != null) {
      return;
    }
    final prepared = widget.prepared;
    try {
      final document = _preparation.resolve(
        ForumBodyPreparationInput(
          html: prepared.preparedHtml,
          sourceId: prepared.sequence.sourceId,
          conversionIdentity: 'prepared-forum-body',
        ),
        owner: this,
        cache: widget.cache,
      );
      if (document != null) setState(() => _document = document);
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  bool _current(_FlowRun run) => mounted && identical(_pending, run);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final document = _document;
      final width = constraints.maxWidth;
      final compact = widget.contentLayout == ForumHtmlContentLayout.compact;
      final compactMinWidth = compact && constraints.minWidth < width
          ? constraints.minWidth
          : null;
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final style = widget.textStyle.copyWith(
        locale: Localizations.maybeLocaleOf(context),
      );
      final inputs = (
        document,
        width,
        compactMinWidth,
        scaler,
        direction,
        style,
        widget.fontRevision,
        widget.preferences.typography.paragraphSpacing,
        widget.theme.signature,
        widget.imageHost,
        _foldRevision,
      );
      final key = (inputs, _revision);
      if (document != null &&
          width.isFinite &&
          width > 0 &&
          key != _layoutKey &&
          _error == null) {
        _layoutKey = key;
        if (!identical(_pending, _shown)) _pending?.close();
        final changes = _shown?.inputs == inputs
            ? Map<String, _ImageChange>.of(_changedImages)
            : const <String, _ImageChange>{};
        _changedImages.clear();
        final run = _pending = _FlowRun(inputs, _foldRevision, changes);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_current(run)) return;
          widget.onGeometry?.call(false, false);
          unawaited(
            _start(
              run,
              document,
              width,
              scaler,
              direction,
              style,
              compactMinWidth,
            ),
          );
        });
      }
      final run = _shown;
      final table = run?.initialTable;
      final error = _error;
      final complete =
          _pending?.prefix?.isComplete == true &&
          (identical(run, _pending) || _pending!.prefix!.isEmpty);
      // Report the phase during layout so the outer floor records the extent
      // of this prefix, even when only the inner LayoutBuilder rebuilt.
      widget.onLayoutPhase?.call(
        error != null
            ? ForumHtmlBodyLayoutPhase.failed
            : complete
            ? ForumHtmlBodyLayoutPhase.built
            : ForumHtmlBodyLayoutPhase.preparing,
      );
      final body = Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (run != null)
            _withSelection(
              run,
              ForumBodyFlowBox(
                key: run.boundsKey,
                session: run.session!,
                preloadExtentFactor: widget.cache == null ? 0 : 1,
                preloadScope: widget.cache?.preloadScope,
                prefix: run.prefix!,
                isCurrentLayout: identical(run, _pending),
                imageAnchorController: widget.imageAnchorController,
                imagePathForIndex: run.images!.pathForIndex,
                initialSlice: run.initialSlice,
                initialTableSlice: table == null
                    ? null
                    : (index: table.index, slice: table.slice),
                onTableWindowChanged: (index, window) {
                  run.recordTableWindow(
                    index,
                    run.prefix![index].table!,
                    window,
                  );
                },
                onFloatedTableWindowChanged: run.recordTableWindow,
                onReadyChanged: (ready) {
                  if (!_current(run)) return;
                  run.ready = ready;
                  widget.onGeometry?.call(
                    ready && _error == null,
                    run.prefix!.isComplete && _error == null,
                  );
                },
                onFailure: (error, stack) {
                  if (_current(run)) _fail(error, stack);
                },
                buildSlice: (context, snapshot, index, fragments) =>
                    _buildSlice(context, run, snapshot, index, fragments),
              ),
            )
          else if (error == null && !complete)
            const ForumHtmlPreparationPlaceholder(),
          if (error != null) ...[
            widget.errorBuilder(context),
            Center(
              child: TextButton(
                onPressed: _retry,
                child: Text(AppLocalizations.of(context).commonRetry),
              ),
            ),
          ],
        ],
      );
      return compact
          ? SizedBox(
              width:
                  run?.prefix?.width ??
                  (error == null ? math.min(width, 48) : width),
              child: body,
            )
          : body;
    },
  );

  Widget _withSelection(_FlowRun run, Widget body) {
    if (!widget.selectionEnabled) return body;
    return ForumContentSelectionRegion(
      nativeFlow: true,
      clipboardTextWriter: widget.clipboardTextWriter,
      onOpenForumLink: widget.onOpenSelectedLink,
      selectionIdentity: _pending,
      isCurrent: () =>
          _current(run) &&
          _error == null &&
          (widget.isSelectionCurrent?.call() ?? true),
      wholeBodySelection: widget.selectEntireBody
          ? (session: run.session!, complete: run.prefix!.isComplete)
          : null,
      onSelectionStarted: widget.callbacks.onInteraction,
      child: body,
    );
  }

  Future<void> _start(
    _FlowRun run,
    ForumBodyDocument document,
    double width,
    TextScaler scaler,
    TextDirection direction,
    TextStyle style,
    double? compactMinWidth,
  ) async {
    try {
      final config = widget;
      final collapses = ForumBodyCollapseLayout(
        document,
        expansionOverrides: config.expansion,
      );
      final learned = Map<String, ForumNativeBodyImageLayoutHint>.of(
        _resolvedImages,
      );
      final previousImages = _shown?.host == config.imageHost
          ? _shown?.images
          : null;
      final host = config.imageHost;
      final images = ForumNativeBodyImages(
        document,
        presentation: config.bodyPresentation,
      );
      final reader = ForumBodyReaderStyle(
        textStyle: style,
        fontRevision: config.fontRevision,
        linkColor: config.theme.link,
        textDirection: direction,
        paragraphAfter: config.preferences.typography.paragraphSpacing,
        theme: config.theme,
      );
      final clock = Stopwatch()..start();
      for (final (index, element) in document.imageElements.indexed) {
        if (host == null) break;
        if (index != 0 &&
            (index % 48 == 0 || clock.elapsedMicroseconds >= 3000)) {
          final binding = WidgetsBinding.instance;
          // Reflow starts after a frame; endOfFrame alone does not schedule
          // the next frame when called from that phase.
          binding.ensureVisualUpdate();
          await binding.endOfFrame;
          if (!_current(run)) return;
          clock.reset();
        }
        if (!const ForumBodyStyleResolver().isVisibleAt(
          document,
          reader,
          element,
          collapses: collapses,
        )) {
          continue;
        }
        images.add(
          element: element,
          sequence: config.prepared.sequence,
          host: host,
          // Host estimates can learn from other images in the thread. Keep
          // already laid-out occurrences stable until their own size arrives.
          learnedLayout:
              learned[element.path] ?? previousImages?.layoutHintFor(element),
        );
      }
      run.images = images;
      run.host = config.imageHost;
      ForumBodyTextPageSession openSession(
        double bodyWidth, {
        bool probe = false,
      }) => ForumBodyTextPageSession(
        document: document,
        width: bodyWidth,
        height: _sliceHeight,
        layoutId: 'forum-flow-${identityHashCode(run)}',
        reader: reader,
        textScaler: scaler,
        cache: _cache,
        limits: _limits,
        collapses: collapses,
        tableExtent: ForumBodyTableExtent.natural,
        intrinsicAvailableWidth: probe ? width : null,
        captureFloats: true,
        imageResolver: images.block,
        inlineImageResolver: (identity, element, style) =>
            images.inline(identity, element, style, scaler, _sliceHeight),
      );
      if (compactMinWidth != null) {
        run.compactProbe = (
          min: compactMinWidth,
          max: width,
          open: openSession,
        );
      }
      run.step = () => _advance(run);
      _useSession(run, openSession(width, probe: compactMinWidth != null));
    } catch (error, stack) {
      if (_current(run)) _fail(error, stack);
    }
  }

  void _useSession(_FlowRun run, ForumBodyTextPageSession session) {
    unawaited(run.budget?.cancel());
    run.session?.close();
    run.session = session;
    run.waiting = false;
    run.budget = session.layoutBudgetChanges.listen((_) {
      if (_current(run) && run.waiting) {
        run.waiting = false;
        _FlowQueue.add(run.step!);
      }
    });
    _FlowQueue.add(run.step!);
  }

  void _advance(_FlowRun run) {
    if (!_current(run) || _error != null) return;
    final session = run.session!;
    try {
      final step = session.advance(maxEvents: 16, maxLines: 4);
      run.waiting = step.waitingForLayoutBudget;
      if (run.compactProbe case final probe?) {
        // Measure with the same formatting and resource inputs as the visible
        // body. Probe slices must never appear at a provisional width.
        if (!step.isComplete) {
          if (!run.waiting) _FlowQueue.add(run.step!);
          return;
        }
        run.compactProbe = null;
        final preferred = session.intrinsicWidths!.preferred;
        final width = preferred.isFinite && preferred > 0
            ? preferred.ceilToDouble().clamp(probe.min, probe.max).toDouble()
            : probe.max;
        if (width < probe.max) {
          _useSession(run, probe.open(width));
          return;
        }
      }
      final snapshot = session.snapshot;
      if (snapshot.length != run.prefix?.length ||
          snapshot.isComplete != run.prefix?.isComplete) {
        for (var i = run.prefix?.length ?? 0; i < snapshot.length; i++) {
          run.append(snapshot[i]);
        }
        run.prefix = snapshot;
        _present(run);
      }
      if (!step.isComplete && !run.waiting) _FlowQueue.add(run.step!);
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _present(_FlowRun run) {
    if (!_current(run) || _error != null) return;
    final snapshot = run.prefix!;
    if (snapshot.isEmpty) {
      if (snapshot.isComplete) {
        setState(() {
          _shown?.close();
          _shown = null;
        });
        widget.onGeometry?.call(false, true);
      }
      return;
    }
    final previous = _shown;
    if (!snapshot.isComplete &&
        (run.height < (previous?.height ?? 0) ||
            !run.blockChanges.every(run.blockImages.containsKey))) {
      return;
    }
    if (previous != null &&
        !identical(previous, run) &&
        (run.blockChanges.isNotEmpty || run.preserveSource) &&
        !_preserveImageReflow(previous, run)) {
      return;
    }
    // A live replacement keeps its existing image/source anchor handoff.
    if (previous == null || identical(previous, run)) _seedCachedSlice(run);
    setState(() {
      if (!identical(_shown, run)) _shown?.close();
      _shown = run;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(run) && identical(run.prefix, snapshot) && _error == null) {
        widget.onGeometry?.call(run.ready, snapshot.isComplete);
      }
    });
  }

  void _seedCachedSlice(_FlowRun run) {
    if (widget.cache == null ||
        run.initialSlice != null ||
        run.seedAttempted ||
        run.boundsKey.currentContext != null) {
      return;
    }
    final box = context.findRenderObject();
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    if (box is! RenderBox || !box.attached || viewport == null) return;
    final clip = MatrixUtils.transformRect(
      viewport.getTransformTo(box),
      viewport.paintBounds,
    );
    final prefix = run.prefix!;
    // The old placeholder's height is not the new body's occupied height.
    // Project the viewport into this origin and use the published prefix.
    if (!clip.isFinite ||
        clip.right <= 0 ||
        clip.left >= prefix.width ||
        clip.bottom <= 0 ||
        clip.top >= run.height) {
      return;
    }
    var first = 0, end = prefix.length;
    while (first < end) {
      final mid = (first + end) ~/ 2;
      if (run.pageTops[mid] + prefix[mid].usedHeight <= clip.top) {
        first = mid + 1;
      } else {
        end = mid;
      }
    }
    if (first >= prefix.length) return;
    run.seedAttempted = true;
    if (prefix[first].tableFrames.isNotEmpty) return;
    final job = run.session!.openPagePreparation(first);
    try {
      if (_FlowQueue.prepareCached(job) && _current(run)) {
        run.initialSlice = ForumBodyFlowPreparedSlice(
          session: run.session!,
          index: first,
          fragments: job.takeFragments(),
        );
      }
    } on ForumBodyTextPagePreparationException {
      // Optional cached delivery yields to the ordinary pressure/error path.
    } on ForumBodyTextPageSessionException {
      // A retired owner cannot transfer a display to a later mount.
    } on ForumBodyParagraphBudgetException {
      // The visible window owns admission and retries after pins are released.
    } finally {
      job.close();
    }
  }

  Widget _buildSlice(
    BuildContext context,
    _FlowRun run,
    ForumBodyTextPageSnapshot snapshot,
    int index,
    List<ForumBodyPreparedTextFragment> fragments,
  ) {
    final l10n = AppLocalizations.of(context);
    return ForumBodyTextPageSurface.prepared(
      snapshot: snapshot,
      pageIndex: index,
      layoutId: snapshot.layoutId,
      fragments: fragments,
      compactHeight: true,
      selectionEnabled:
          widget.selectionEnabled && _current(run) && _error == null,
      imageHost: run.host,
      imageAnchorController: widget.imageAnchorController,
      collapseLabels: ForumHtmlCollapseLabels(
        fallbackTitle: l10n.threadHtmlCollapseContent,
        expandedSemanticsLabel: l10n.threadHtmlCollapseExpanded,
        collapsedSemanticsLabel: l10n.threadHtmlCollapseCollapsed,
      ),
      onCollapseToggle: (fragment) {
        final header = fragment.collapseHeader;
        if (!_current(run) || header == null) return;
        widget.callbacks.onInteraction?.call();
        setState(() {
          widget.expansion[header.id] = !header.expanded;
          _foldRevision++;
          _revision++;
        });
      },
      onImageTap: (fragment) => _imageTap(run, fragment.content.input.entry),
      onInlineImageTap: (_, binding) {
        if (binding.input.entry case final entry?) _imageTap(run, entry);
      },
      onImageLayoutResolved: (fragment, layout) {
        final input = fragment.content.input;
        if (snapshot.layoutId != run.prefix!.layoutId) {
          _imageResolved(run, input.element, layout, _ImageChange.table);
          return;
        }
        if (run.floatedImages.contains(input.element.path)) {
          _imageResolved(run, input.element, layout, _ImageChange.source);
          return;
        }
        final ratio = layout.aspectRatio ?? layout.displaySize?.aspectRatio;
        if ((input.entry.htmlWidth != null && input.entry.htmlHeight != null) ||
            ratio == null ||
            !ratio.isFinite ||
            ratio <= 0) {
          return;
        }
        _imageResolved(
          run,
          input.element,
          ForumHtmlImageLayout(aspectRatio: ratio),
          _ImageChange.block,
        );
      },
      onInlineImageLayoutResolved: (_, binding, layout) {
        if (binding.input.usesIntrinsicSize) {
          _imageResolved(
            run,
            binding.input.element,
            layout,
            snapshot.layoutId == run.prefix!.layoutId
                ? _ImageChange.source
                : _ImageChange.table,
          );
        }
      },
      onLinkTap: widget.callbacks.onTapUrl == null
          ? null
          : (url) {
              if (_current(run)) widget.callbacks.onTapUrl?.call(url);
            },
    );
  }

  void _imageTap(_FlowRun run, ForumHtmlReadableImageEntry entry) {
    final open = widget.onOpenImage;
    final images = run.images;
    if (open == null ||
        !_current(run) ||
        _error != null ||
        run.foldRevision != _foldRevision ||
        images == null ||
        images.pathForIndex(entry.index) == null) {
      return;
    }
    open(
      images.galleryFor(widget.prepared.sequence),
      ForumHtmlImageRequest(
        url: entry.url,
        readableIndex: entry.index,
        cacheKey: entry.cacheKey,
        attachmentId: entry.attachmentId,
        alt: entry.alt,
        title: entry.title,
        width: entry.htmlWidth,
        height: entry.htmlHeight,
      ),
    );
  }

  void _imageResolved(
    _FlowRun run,
    ForumBodyElement element,
    ForumHtmlImageLayout layout,
    _ImageChange change,
  ) {
    if (!_current(run) || _error != null) return;
    final binding = run.images?.layoutHintFor(element);
    if (binding == null) return;
    final learned = _resolvedImages[element.path];
    final original = learned?.displayIdentity == binding.displayIdentity
        ? learned!.layout
        : binding.layout;
    // A confirmed size can match today's fallback without needing a reflow.
    run.images!.rememberLayout(element, layout);
    if (layout.displaySize == original.displaySize &&
        layout.aspectRatio == original.aspectRatio) {
      return;
    }
    _resolvedImages[element.path] = (
      displayIdentity: binding.displayIdentity,
      layout: layout,
    );
    _changedImages[element.path] = change;
    if (run.reflowScheduled) return;
    run.reflowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      run.reflowScheduled = false;
      if (_current(run) && _error == null) setState(() => _revision++);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _fail(Object error, StackTrace stack) {
    debugPrint('[ForumBody][flow] ${error.runtimeType}');
    setState(() => _error = error);
    widget.onGeometry?.call(false, false);
  }

  void _retry() {
    if (_document == null) _preparation.reset();
    setState(() {
      _error = null;
      _layoutKey = null;
    });
    _prepare();
  }

  void _retireLayouts() {
    _pending?.close();
    if (!identical(_shown, _pending)) _shown?.close();
    _pending = _shown = null;
    _layoutKey = null;
  }

  @override
  void dispose() {
    _preparation.dispose();
    _retireLayouts();
    _localCache?.close();
    super.dispose();
  }
}

enum _ImageChange { block, source, table }

final class _FlowRun {
  _FlowRun(this.inputs, this.foldRevision, Map<String, _ImageChange> changes)
    : blockChanges =
          changes.values.every((change) => change == _ImageChange.block)
          ? changes.keys.toSet()
          : const {},
      preserveSource =
          changes.containsValue(_ImageChange.source) ||
          changes.containsValue(_ImageChange.table),
      preserveTable = changes.containsValue(_ImageChange.table);

  final Object inputs;
  final int foldRevision;
  final Set<String> blockChanges;
  final bool preserveSource, preserveTable;
  final boundsKey = GlobalKey();
  final blockImages = <String, ({double top, double height})>{};
  final floatedImages = <String>{};
  final pageTops = <double>[];
  final tableWindows = <(int, String), _TableWindow>{};
  _SourceReflowProbe? sourceProbe;
  ForumBodyFlowPreparedSlice? initialSlice;
  _TableResult? initialTable;

  ForumBodyTextPageSession? session;
  ({
    double min,
    double max,
    ForumBodyTextPageSession Function(double width) open,
  })?
  compactProbe;
  ForumBodyTextPageSnapshot? prefix;
  ForumHtmlImageHost? host;
  ForumNativeBodyImages? images;
  StreamSubscription<int>? budget;
  VoidCallback? step;
  double height = 0;
  bool ready = false, waiting = false;
  bool reflowScheduled = false;
  bool seedAttempted = false;

  void append(ForumBodyTextPage page) {
    pageTops.add(height);
    for (final fragment in page.fragments) {
      if (fragment.imageFrame case final frame?) {
        final path = fragment.path!;
        if (fragment.isFloated) {
          floatedImages.add(path);
          continue;
        }
        blockImages[path] = (
          top: height + fragment.top + frame.imageRect.top,
          height: frame.imageRect.height,
        );
      }
    }
    height += page.usedHeight;
  }

  void recordTableWindow(
    int index,
    ForumBodyTextPageTable frame,
    ForumBodyTableVisibleWindow? window,
  ) {
    final key = (index, frame.path);
    if (window?.isCurrent == true &&
        window!.layout.geometry.grid.table.path == frame.path) {
      tableWindows[key] = (frame: frame, window: window);
    } else {
      tableWindows.remove(key);
    }
  }

  void close() {
    _FlowQueue.remove(step);
    unawaited(budget?.cancel());
    compactProbe = null;
    cancelSourceProbe();
    initialSlice?.close();
    initialTable?.slice.close();
    tableWindows.clear();
    session?.close();
  }

  void cancelSourceProbe() {
    sourceProbe?.close();
    sourceProbe = null;
  }
}

/// Fair across the floors that are currently mounted by the lazy list.
abstract final class _FlowQueue {
  static final _pending = <VoidCallback>{};
  static final _clock = Stopwatch();
  static int _steps = 0;
  static bool _initialized = false;
  static bool _scheduled = false;
  static bool _draining = false;

  static void add(VoidCallback work) {
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPersistentFrameCallback((_) {
        _clock.reset();
        _steps = 0;
      });
    }
    _pending.add(work);
    if (_draining) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.postFrameCallbacks) {
      _drain();
    } else {
      _schedule();
    }
  }

  static void remove(VoidCallback? work) => _pending.remove(work);

  static bool prepareCached(ForumBodyTextPagePreparation job) {
    // Share the source frame's remaining budget. A warm delivery must not
    // introduce another independent slice or perform shaping/picture work.
    while (_draining && _steps < 64 && _clock.elapsedMicroseconds < 3000) {
      _steps++;
      if (job.tryPrepareCached(maxParts: 32)) return true;
      if (job.cacheMiss || job.waitingForLayoutBudget) return false;
    }
    return false;
  }

  static void _schedule() {
    if (_scheduled || _pending.isEmpty) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _drain();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  static void _drain() {
    if (_draining || _pending.isEmpty) return;
    _draining = true;
    _clock.start();
    try {
      // Starts already arrive after layout. Use this frame's remaining shared
      // slice instead of imposing another vsync; no floor gets a fresh budget.
      while (_steps < 64 &&
          _pending.isNotEmpty &&
          _clock.elapsedMicroseconds < 3000) {
        _steps++;
        final step = _pending.first;
        _pending.remove(step);
        step();
      }
    } finally {
      _clock.stop();
      _draining = false;
      _schedule();
    }
  }
}

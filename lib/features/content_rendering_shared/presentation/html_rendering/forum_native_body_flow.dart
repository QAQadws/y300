import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show GrowthDirection, RenderAbstractViewport, RenderSliver;
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_layout_scroll_controller.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';

import '../../application/forum_body_preparation_controller.dart';
import '../../application/forum_body_preparation_executor.dart';
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
    required this.clipboardTextWriter,
    this.onOpenSelectedLink,
    this.selectEntireBody = false,
    this.isSelectionCurrent,
    required this.onGeometry,
    this.onLayoutPhase,
    required this.errorBuilder,
    this.imageAnchorController,
  });

  final ForumHtmlPreparedRenderDocument prepared;
  final ForumHtmlReaderPreferences preferences;
  final ForumHtmlThemeContext theme;
  final TextStyle textStyle;
  final String fontRevision;
  final ForumHtmlImageHost? imageHost;
  final Map<String, bool> expansion;
  final ForumHtmlRenderCallbacks callbacks;
  final ClipboardTextWriter clipboardTextWriter;
  final ForumSelectionLinkOpener? onOpenSelectedLink;
  final bool selectEntireBody;
  final bool Function()? isSelectionCurrent;
  final void Function(bool ready, bool complete) onGeometry;
  final ValueChanged<ForumHtmlBodyLayoutPhase>? onLayoutPhase;
  final WidgetBuilder errorBuilder;
  final ForumHtmlImageAnchorController? imageAnchorController;

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

  final _cache = ForumBodyParagraphCache(
    maxEntries: 128,
    maxEstimatedBytes: 8 << 20,
  );
  final _preparation = ForumBodyPreparationController();
  final _resolvedImages = <String, ForumHtmlImageLayout>{};
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void didUpdateWidget(covariant ForumNativeBodyFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageAnchorController != widget.imageAnchorController ||
        !identical(oldWidget.prepared, widget.prepared)) {
      widget.imageAnchorController?.bindSequence(widget.prepared.sequence);
    }
    if (identical(oldWidget.prepared, widget.prepared)) return;
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
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final style = widget.textStyle.copyWith(
        locale: Localizations.maybeLocaleOf(context),
      );
      final inputs = (
        document,
        width,
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
        final run = _pending = _FlowRun(inputs, changes);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_current(run)) return;
          widget.onGeometry(false, false);
          unawaited(_start(run, document, width, scaler, direction, style));
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (run != null)
            ForumContentSelectionRegion(
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
              child: ForumBodyFlowBox(
                key: run.boundsKey,
                session: run.session!,
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
                  widget.onGeometry(
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
    },
  );

  Future<void> _start(
    _FlowRun run,
    ForumBodyDocument document,
    double width,
    TextScaler scaler,
    TextDirection direction,
    TextStyle style,
  ) async {
    try {
      final config = widget;
      final collapses = ForumBodyCollapseLayout(
        document,
        expansionOverrides: config.expansion,
      );
      final learned = Map<String, ForumHtmlImageLayout>.of(_resolvedImages);
      final previousImages = _shown?.host == config.imageHost
          ? _shown?.images
          : null;
      final host = config.imageHost;
      final images = ForumNativeBodyImages(document);
      final clock = Stopwatch()..start();
      for (final (index, element) in document.imageElements.indexed) {
        if (host == null) break;
        if (index != 0 &&
            (index % 48 == 0 || clock.elapsedMicroseconds >= 3000)) {
          await WidgetsBinding.instance.endOfFrame;
          if (!_current(run)) return;
          clock.reset();
        }
        if (collapses.hidesPath(element.path)) continue;
        images.add(
          element: element,
          sequence: config.prepared.sequence,
          host: host,
          // Host estimates can learn from other images in the thread. Keep
          // already laid-out occurrences stable until their own size arrives.
          learnedLayout:
              learned[element.path] ?? previousImages?.layoutFor(element),
        );
      }
      run.images = images;
      run.host = config.imageHost;
      final session = run.session = ForumBodyTextPageSession(
        document: document,
        width: width,
        height: _sliceHeight,
        layoutId: 'forum-flow-${identityHashCode(run)}',
        reader: ForumBodyReaderStyle(
          textStyle: style,
          fontRevision: config.fontRevision,
          linkColor: config.theme.link,
          textDirection: direction,
          paragraphAfter: config.preferences.typography.paragraphSpacing,
          theme: config.theme,
        ),
        textScaler: scaler,
        cache: _cache,
        limits: _limits,
        collapses: collapses,
        tableExtent: ForumBodyTableExtent.natural,
        captureFloats: true,
        imageResolver: images.block,
        inlineImageResolver: (identity, element, style) =>
            images.inline(identity, element, style, scaler, _sliceHeight),
      );
      run.step = () => _advance(run);
      run.budget = session.layoutBudgetChanges.listen((_) {
        if (_current(run) && run.waiting) {
          run.waiting = false;
          _FlowQueue.add(run.step!);
        }
      });
      _FlowQueue.add(run.step!);
    } catch (error, stack) {
      if (_current(run)) _fail(error, stack);
    }
  }

  void _advance(_FlowRun run) {
    if (!_current(run) || _error != null) return;
    final session = run.session!;
    try {
      final step = session.advance(maxEvents: 16, maxLines: 4);
      final snapshot = session.snapshot;
      if (snapshot.length != run.prefix?.length ||
          snapshot.isComplete != run.prefix?.isComplete) {
        for (var i = run.prefix?.length ?? 0; i < snapshot.length; i++) {
          run.append(snapshot[i]);
        }
        run.prefix = snapshot;
        _present(run);
      }
      run.waiting = step.waitingForLayoutBudget;
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
        widget.onGeometry(false, true);
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
    setState(() {
      if (!identical(_shown, run)) _shown?.close();
      _shown = run;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(run) && identical(run.prefix, snapshot) && _error == null) {
        widget.onGeometry(run.ready, snapshot.isComplete);
      }
    });
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
      selectionEnabled: _current(run) && _error == null,
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
            ratio <= 0 ||
            ratio ==
                (_resolvedImages[input.element.path]?.aspectRatio ??
                    input.aspectRatio)) {
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
    if (!_current(run)) return;
    widget.callbacks.onTapImage?.call(
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
    final original =
        _resolvedImages[element.path] ?? run.images!.layoutFor(element);
    if (layout.displaySize == original?.displaySize &&
        layout.aspectRatio == original?.aspectRatio) {
      return;
    }
    _resolvedImages[element.path] = layout;
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
    widget.onGeometry(false, false);
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
    _cache.close();
    super.dispose();
  }
}

enum _ImageChange { block, source, table }

final class _FlowRun {
  _FlowRun(this.inputs, Map<String, _ImageChange> changes)
    : blockChanges =
          changes.values.every((change) => change == _ImageChange.block)
          ? changes.keys.toSet()
          : const {},
      preserveSource =
          changes.containsValue(_ImageChange.source) ||
          changes.containsValue(_ImageChange.table),
      preserveTable = changes.containsValue(_ImageChange.table);

  final Object inputs;
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
  ForumBodyTextPageSnapshot? prefix;
  ForumHtmlImageHost? host;
  ForumNativeBodyImages? images;
  StreamSubscription<int>? budget;
  VoidCallback? step;
  double height = 0;
  bool ready = false, waiting = false;
  bool reflowScheduled = false;

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
  static bool _scheduled = false;

  static void add(VoidCallback work) {
    _pending.add(work);
    _schedule();
  }

  static void remove(VoidCallback? work) => _pending.remove(work);

  static void _schedule() {
    if (_scheduled || _pending.isEmpty) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final clock = Stopwatch()..start();
      for (
        var i = 0;
        i < 24 && _pending.isNotEmpty && clock.elapsedMicroseconds < 3000;
        i++
      ) {
        final step = _pending.first;
        _pending.remove(step);
        step();
      }
      _scheduled = false;
      _schedule();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

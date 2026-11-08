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
import '../../application/forum_native_body_cache.dart';
import '../../domain/models/forum_html_reader_preferences.dart';
import 'forum_html_preparation_placeholder.dart';
import 'forum_native_body_images.dart';
import 'forum_native_body_flow_input.dart';
import 'forum_native_body_flow_preloads.dart';

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
    this.preparationIdentity,
    this.resourceIdentity,
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
  final Object? preparationIdentity, resourceIdentity;

  @override
  State<ForumNativeBodyFlow> createState() => _ForumNativeBodyFlowState();
}

class _ForumNativeBodyFlowState extends State<ForumNativeBodyFlow> {
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
  ForumNativeBodyFlowPreloads? _preloads;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preloads = ForumNativeBodyFlowPreloadScope.maybeOf(context);
    _prepare();
  }

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
      final staged = _preloads?.peek(widget.preparationIdentity ?? this);
      final document =
          staged?.input.resourceIdentity == widget.resourceIdentity &&
              staged?.input.prepared.preparedHtml == prepared.preparedHtml
          ? staged!.input.document
          : _preparation.resolve(
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
      final input = document == null
          ? null
          : ForumNativeBodyFlowInput(
              document: document,
              prepared: widget.prepared,
              width: width,
              compactMinWidth: compactMinWidth,
              textStyle: style,
              fontRevision: widget.fontRevision,
              textScaler: scaler,
              direction: direction,
              paragraphAfter: widget.preferences.typography.paragraphSpacing,
              theme: widget.theme,
              cache: _cache,
              host: widget.imageHost,
              expansion: widget.expansion,
              presentation: widget.bodyPresentation,
              preparationIdentity: widget.preparationIdentity,
              resourceIdentity: widget.resourceIdentity,
            );
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
        final seed = input == null || _shown != null
            ? null
            : _preloads?.take(input);
        if (seed != null) {
          _bindSource(run, seed.body);
          run.initialSlices = seed.slices;
          final prefix = seed.body.source.prefix!;
          for (final page in prefix) {
            run.append(page);
          }
          run.prefix = prefix;
          _shown?.close();
          _shown = run;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_current(run)) return;
          if (seed != null) {
            run.source!.resume();
            widget.onGeometry?.call(false, run.prefix!.isComplete);
            return;
          }
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
      final pending = _pending;
      if (pending != null && pending.source != null && input != null) {
        final seed = _preloads?.take(input, mountedSource: pending.source);
        if (seed != null) {
          if (identical(seed.body.source, pending.source)) {
            for (final slice in pending.initialSlices) {
              slice.close();
            }
            pending.initialSlices = seed.slices;
          } else {
            for (final slice in seed.slices) {
              slice.close();
            }
            seed.body.close();
          }
        }
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
                initialSlices: run.initialSlices,
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
      final input = ForumNativeBodyFlowInput(
        document: document,
        prepared: config.prepared,
        width: width,
        compactMinWidth: compactMinWidth,
        textStyle: style,
        fontRevision: config.fontRevision,
        textScaler: scaler,
        direction: direction,
        paragraphAfter: config.preferences.typography.paragraphSpacing,
        theme: config.theme,
        cache: _cache,
        host: config.imageHost,
        expansion: config.expansion,
        presentation: config.bodyPresentation,
        preparationIdentity: config.preparationIdentity,
        resourceIdentity: config.resourceIdentity,
      );
      final opening = input.open(
        isCurrent: () => _current(run),
        learned: Map.of(_resolvedImages),
        previousImages: _shown?.host == config.imageHost
            ? _shown?.images
            : null,
      );
      final prepared = opening is ForumNativeBodyPreparedSource
          ? opening
          : await opening;
      if (!_current(run)) {
        prepared.close();
        return;
      }
      _bindSource(run, prepared);
      prepared.source.start();
    } catch (error, stack) {
      if (_current(run)) _fail(error, stack);
    }
  }

  void _bindSource(_FlowRun run, ForumNativeBodyPreparedSource prepared) {
    run.preparedSource = prepared;
    run.images = prepared.images;
    run.host = prepared.input.host;
    final source = run.source = prepared.source;
    run.sourceListener = () => _sourceChanged(run);
    source.addListener(run.sourceListener!);
    final preloads = _preloads;
    preloads?.bind(run, prepared);
    run.releaseSource = () => preloads?.release(run, prepared) ?? false;
  }

  void _sourceChanged(_FlowRun run) {
    if (!_current(run) || _error != null) return;
    final source = run.source!;
    if (source.error case final error?) {
      _fail(error, source.errorStack!);
      return;
    }
    try {
      final snapshot = source.prefix;
      if (snapshot == null) return;
      if (snapshot.length != run.prefix?.length ||
          snapshot.isComplete != run.prefix?.isComplete) {
        for (var i = run.prefix?.length ?? 0; i < snapshot.length; i++) {
          run.append(snapshot[i]);
        }
        run.prefix = snapshot;
        _present(run);
      }
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
      if (ForumBodyFlowSource.tryPrepareCached(job) && _current(run)) {
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
    _pending?.source?.stop();
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
  List<ForumBodyFlowPreparedSlice> initialSlices = [];
  bool Function()? releaseSource;
  VoidCallback? sourceListener;
  _TableResult? initialTable;

  ForumBodyFlowSource? source;
  ForumNativeBodyPreparedSource? preparedSource;
  ForumBodyTextPageSession? get session => source?.session;
  ForumBodyTextPageSnapshot? prefix;
  ForumHtmlImageHost? host;
  ForumNativeBodyImages? images;
  double height = 0;
  bool ready = false;
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
    final retained = releaseSource?.call() ?? false;
    releaseSource = null;
    if (sourceListener case final listener?) source?.removeListener(listener);
    sourceListener = null;
    cancelSourceProbe();
    initialSlice?.close();
    for (final slice in initialSlices) {
      slice.close();
    }
    initialTable?.slice.close();
    tableWindows.clear();
    if (!retained) source?.close();
  }

  void cancelSourceProbe() {
    sourceProbe?.close();
    sourceProbe = null;
  }
}

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show GrowthDirection, RenderAbstractViewport, RenderSliver;
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_layout_scroll_controller.dart';
import 'package:y300/l10n/app_localizations.dart';

import 'thread_native_body_images.dart';

part 'thread_native_block_reflow.dart';
part 'thread_native_inline_reflow.dart';

/// Thread adapter for the same natural flow used by the novel reader. The
/// outer floor list owns scroll and reading authority.
final class ThreadPostNativeFlow extends StatefulWidget {
  const ThreadPostNativeFlow({
    super.key,
    required this.prepared,
    required this.preferences,
    required this.theme,
    required this.textStyle,
    required this.fontRevision,
    required this.imageHost,
    required this.expansion,
    required this.callbacks,
    required this.onGeometry,
    required this.errorBuilder,
    this.imageAnchorController,
  });

  final ForumHtmlPreparedRenderDocument prepared;
  final ForumHtmlReaderPreferences preferences;
  final ForumHtmlThemeContext theme;
  final TextStyle textStyle;
  final String fontRevision;
  final ForumHtmlImageHost imageHost;
  final Map<String, bool> expansion;
  final ForumHtmlRenderCallbacks callbacks;
  final void Function(bool ready, bool complete) onGeometry;
  final WidgetBuilder errorBuilder;
  final ForumHtmlImageAnchorController? imageAnchorController;

  @override
  State<ThreadPostNativeFlow> createState() => _ThreadPostNativeFlowState();
}

class _ThreadPostNativeFlowState extends State<ThreadPostNativeFlow> {
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
  final _preparation = ForumPreparationScheduler.shared.createScope();
  final _resolvedImages = <String, ForumHtmlImageLayout>{};
  final _changedImages = <String, _ThreadImageChange>{};
  ForumPreparationLease<ForumBodyDocument>? _work;
  ForumBodyDocument? _document;
  _ThreadFlowRun? _pending, _shown;
  Object? _layoutKey;
  Object? _error;
  var _revision = 0;
  var _foldRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.imageAnchorController?.bindSequence(widget.prepared.sequence);
    ForumPreparationScheduler.shared.addListener(_prepare);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void didUpdateWidget(covariant ThreadPostNativeFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageAnchorController != widget.imageAnchorController ||
        !identical(oldWidget.prepared, widget.prepared)) {
      widget.imageAnchorController?.bindSequence(widget.prepared.sequence);
    }
    if (identical(oldWidget.prepared, widget.prepared)) return;
    _work?.release();
    _work = null;
    _document = null;
    _resolvedImages.clear();
    _changedImages.clear();
    _retireLayouts();
    _error = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  void _prepare() {
    if (!mounted || _document != null || _work != null || _error != null) {
      return;
    }
    final prepared = widget.prepared;
    final html = prepared.preparedHtml, source = prepared.sequence.sourceId;
    final work = _preparation.tryAcquire(
      identity: (source, html),
      codeUnits: html.length,
      work: () => _parseThreadNativeBody(source, html),
    );
    if (work == null) return;
    _work = work;
    unawaited(
      work.future
          .then<void>(
            (value) {
              if (mounted && identical(_work, work) && value != null) {
                setState(() => _document = value);
              }
            },
            onError: (Object error, StackTrace stack) {
              if (mounted && identical(_work, work)) _fail(error, stack);
            },
          )
          .whenComplete(() {
            work.release();
            if (identical(_work, work)) _work = null;
          }),
    );
  }

  bool _current(_ThreadFlowRun run) => mounted && identical(_pending, run);

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
            ? Map<String, _ThreadImageChange>.of(_changedImages)
            : const <String, _ThreadImageChange>{};
        _changedImages.clear();
        final run = _pending = _ThreadFlowRun(inputs, changes);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_current(run)) return;
          widget.onGeometry(false, false);
          unawaited(_start(run, document, width, scaler, direction, style));
        });
      }
      final run = _shown;
      final error = _error;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (run != null)
            ForumBodyFlowBox(
              key: run.boundsKey,
              session: run.session!,
              prefix: run.prefix!,
              isCurrentLayout: identical(run, _pending),
              imageAnchorController: widget.imageAnchorController,
              imagePathForIndex: run.images!.pathForIndex,
              initialSlice: run.initialSlice,
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
            )
          else if (error == null)
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
    _ThreadFlowRun run,
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
      final images = ThreadNativeBodyImages(document);
      final clock = Stopwatch()..start();
      for (final (index, element) in document.imageElements.indexed) {
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
          host: config.imageHost,
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
        layoutId: 'thread-flow-${identityHashCode(run)}',
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
        imageResolver: images.block,
        inlineImageResolver: (identity, element, style) =>
            images.inline(identity, element, style, scaler, _sliceHeight),
      );
      run.step = () => _advance(run);
      run.budget = session.layoutBudgetChanges.listen((_) {
        if (_current(run) && run.waiting) {
          run.waiting = false;
          _ThreadFlowQueue.add(run.step!);
        }
      });
      _ThreadFlowQueue.add(run.step!);
    } catch (error, stack) {
      if (_current(run)) _fail(error, stack);
    }
  }

  void _advance(_ThreadFlowRun run) {
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
      if (!step.isComplete && !run.waiting) _ThreadFlowQueue.add(run.step!);
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _present(_ThreadFlowRun run) {
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
        (run.blockChanges.isNotEmpty || run.preserveInline) &&
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
    _ThreadFlowRun run,
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
          _imageResolved(run, input.element, layout, _ThreadImageChange.table);
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
          _ThreadImageChange.block,
        );
      },
      onInlineImageLayoutResolved: (_, binding, layout) {
        if (binding.input.usesIntrinsicSize) {
          _imageResolved(
            run,
            binding.input.element,
            layout,
            snapshot.layoutId == run.prefix!.layoutId
                ? _ThreadImageChange.inline
                : _ThreadImageChange.table,
          );
        }
      },
      onSourceTap: (fragment, position) {
        if (!_current(run) || !position.isExact) return;
        final binding = fragments[snapshot[index].fragments.indexOf(fragment)];
        for (final part in binding.projection.parts) {
          if (part.utf16Start > position.displayUtf16) return;
          if (position.displayUtf16 >= part.utf16Start + part.text.length) {
            continue;
          }
          final url = binding.runs[part.runIndex].style.linkTarget;
          if (url != null && url.isNotEmpty) {
            widget.callbacks.onTapUrl?.call(url);
          }
          return;
        }
      },
    );
  }

  void _imageTap(_ThreadFlowRun run, ForumHtmlReadableImageEntry entry) {
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
    _ThreadFlowRun run,
    ForumBodyElement element,
    ForumHtmlImageLayout layout,
    _ThreadImageChange change,
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
    debugPrint('[ThreadDetail][body-flow] ${error.runtimeType}');
    setState(() => _error = error);
    widget.onGeometry(false, false);
  }

  void _retry() {
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
    ForumPreparationScheduler.shared.removeListener(_prepare);
    _preparation.close();
    _work?.release();
    _work = null;
    _retireLayouts();
    _cache.close();
    super.dispose();
  }
}

Future<ForumBodyDocument> _parseThreadNativeBody(String source, String html) =>
    Isolate.run(
      () => const ForumBodyParser().parse(
        html: html,
        sourceId: source,
        conversionIdentity: 'prepared-thread',
      ),
      debugName: 'thread-native-body',
    );

enum _ThreadImageChange { block, inline, table }

final class _ThreadFlowRun {
  _ThreadFlowRun(this.inputs, Map<String, _ThreadImageChange> changes)
    : blockChanges =
          changes.values.every((change) => change == _ThreadImageChange.block)
          ? changes.keys.toSet()
          : const {},
      preserveInline =
          changes.containsValue(_ThreadImageChange.inline) &&
          !changes.containsValue(_ThreadImageChange.table);

  final Object inputs;
  final Set<String> blockChanges;
  final bool preserveInline;
  final boundsKey = GlobalKey();
  final blockImages = <String, ({double top, double height})>{};
  final pageTops = <double>[];
  _ThreadInlineProbe? inlineProbe;
  ForumBodyFlowPreparedSlice? initialSlice;

  ForumBodyTextPageSession? session;
  ForumBodyTextPageSnapshot? prefix;
  ForumHtmlImageHost? host;
  ThreadNativeBodyImages? images;
  StreamSubscription<int>? budget;
  VoidCallback? step;
  double height = 0;
  bool ready = false, waiting = false;
  bool reflowScheduled = false;

  void append(ForumBodyTextPage page) {
    pageTops.add(height);
    for (final fragment in page.fragments) {
      if (fragment.imageFrame case final frame?) {
        blockImages[fragment.path!] = (
          top: height + fragment.top + frame.imageRect.top,
          height: frame.imageRect.height,
        );
      }
    }
    height += page.usedHeight;
  }

  void close() {
    _ThreadFlowQueue.remove(step);
    unawaited(budget?.cancel());
    cancelInlineProbe();
    initialSlice?.close();
    session?.close();
  }

  void cancelInlineProbe() {
    inlineProbe?.close();
    inlineProbe = null;
  }
}

/// Fair across the floors that are currently mounted by the lazy list.
abstract final class _ThreadFlowQueue {
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

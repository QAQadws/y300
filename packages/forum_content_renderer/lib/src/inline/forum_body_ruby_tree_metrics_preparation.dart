import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_text_request_preparation.dart';
import '../paragraph/forum_body_native_request.dart';
import '../pagination/forum_body_text_page_content.dart';
import '../pagination/forum_body_text_page_composer.dart';
import 'forum_body_inline_plan_preparation.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_root_box.dart';
import 'forum_body_ruby_tree_input.dart';
import 'forum_body_text_band_content.dart';
import 'forum_body_text_band_layout.dart';

part 'forum_body_ruby_tree_segment_metrics.dart';

/// Pure postorder plan. Intrinsic children retain their actual source-bound
/// page input; no native handle or owner is retained. Visible binding must
/// qualify every actual leaf AND inner parent before claiming coverage.
final class ForumBodyRubyTreeMetrics {
  ForumBodyRubyTreeMetrics._(
    this.input,
    List<ForumBodyRubyTreeNodeMetrics> nodes,
    Map<double, double> scales,
    this.nativeHandleCount,
  )
    // The worker seals before transferring this append-only list.
    : nodes = UnmodifiableListView(nodes),
      textScaler = _TreeNativeTextScaler(
        UnmodifiableMapView(scales),
        (input.nodes.last as ForumBodyRubyTreeContainer)
            .font
            .fontStrut
            .style
            .textStyle
            .fontSize!,
      );
  final ForumBodyRubyTreeInput input;
  final List<ForumBodyRubyTreeNodeMetrics> nodes;
  final int nativeHandleCount;
  Iterable<ForumBodyNativeRequestSlot> get nativeFootprint sync* {
    for (final slot in nativeBudgetFootprint) {
      final request = slot.request;
      if (request is ForumBodyNativeRequest) {
        yield (
          request: request,
          width: slot.width,
          minimumLineCount: slot.minimumLineCount,
        );
      }
    }
  }

  Iterable<ForumBodyNativeBudgetSlot> get nativeBudgetFootprint sync* {
    for (var i = 0; i < input.nodes.length; i++) {
      final node = input.nodes[i];
      if (node is ForumBodyRubyTreeText && node.needsNative) {
        yield (
          request: node.request,
          width: input.maxWidth,
          minimumLineCount: 1,
        );
      } else if (node is ForumBodyRubyTreeInline) {
        final child = (nodes[i] as ForumBodyRubyTreeContainerMetrics).inline!;
        yield* child.input.nativeBudgetFootprintFor(child.fragment);
      }
    }
  }

  /// Exact per-font inputs used for native planning, including root/background
  /// fonts and the complete native band when a leaf borrows a shared band key.
  final TextScaler textScaler;
  Map<double, double> get effectiveScales =>
      (textScaler as _TreeNativeTextScaler).samples;
  ForumBodyRubyChildMetrics get box => nodes.last.box!;
  ForumBodyRubyTreeContainerMetrics get root =>
      nodes.last as ForumBodyRubyTreeContainerMetrics;
  ForumBodyRubyAtomMetrics get rootAtom => root.segment == null
      ? ForumBodyRubyAtomMetrics.column(root.group!)
      : ForumBodyRubyAtomMetrics.segment(root.segment!);
  ForumBodyRubyTreeMetrics._copy(
    this.input,
    this.nodes,
    this.textScaler,
    this.nativeHandleCount,
  );

  /// A band isolation retry can rebind native requests while retaining exactly
  /// the original immutable structural graph and source/style objects.
  ForumBodyRubyTreeMetrics rebindInput(ForumBodyRubyTreeInput current) {
    if (!input.hasSameStructure(current)) {
      throw ArgumentError('Foreign ruby tree structure');
    }
    return identical(input, current)
        ? this
        : ForumBodyRubyTreeMetrics._copy(
            current,
            nodes,
            textScaler,
            nativeHandleCount,
          );
  }

  /// Only the existing row alignment may reposition the outer stack. Require
  /// the same actual child extents; inner nodes never move relative to each other.
  ForumBodyRubyTreeMetrics withRootGroup(ForumBodyRubyGroupMetrics value) {
    final old = root.group;
    if (old == null ||
        old.size.width != value.size.width ||
        old.baseFontBounds != value.baseFontBounds ||
        old.baseFontBaseline != value.baseFontBaseline ||
        old.baseAscent != value.baseAscent ||
        old.baseDescent != value.baseDescent ||
        old.baseOffset.dx != value.baseOffset.dx ||
        old.alignmentSignature != value.alignmentSignature ||
        old.annotations.length != value.annotations.length) {
      throw ArgumentError('Ruby row target changed native child geometry');
    }
    for (final (rank, a) in old.annotations.indexed) {
      final b = value.annotations[rank];
      if (a.bounds != b.bounds ||
          a.fontBaseline != b.fontBaseline ||
          a.side != b.side ||
          a.gap != b.gap ||
          a.hasAnnotation != b.hasAnnotation) {
        throw ArgumentError(
          'Ruby row target changed native annotation geometry',
        );
      }
    }
    if (identical(old, value)) return this;
    final replacement = ForumBodyRubyTreeContainerMetrics(
      font: root.font,
      backgroundFont: root.backgroundFont,
      group: value,
      frame: root.font.enclose(
        childSize: value.size,
        childBaseline: value.baseline,
      ),
    );
    return ForumBodyRubyTreeMetrics._copy(
      input,
      UnmodifiableListView(_TreeRootMetricsView(nodes, replacement)),
      textScaler,
      nativeHandleCount,
    );
  }

  ForumBodyRubyTreeMetrics withRootSegment(ForumBodyRubySegmentMetrics value) {
    final old = root.segment;
    if (old == null || !old.hasSameMeasuredInput(value)) {
      throw ArgumentError('Ruby tree segment changed measured members');
    }
    if (identical(old, value)) return this;
    final replacement = ForumBodyRubyTreeContainerMetrics(
      font: root.font,
      backgroundFont: root.backgroundFont,
      segment: value,
      frame: root.font.enclose(
        childSize: value.size,
        childBaseline: value.baseline,
      ),
    );
    return ForumBodyRubyTreeMetrics._copy(
      input,
      UnmodifiableListView(_TreeRootMetricsView(nodes, replacement)),
      textScaler,
      nativeHandleCount,
    );
  }
}

final class _TreeRootMetricsView
    extends ListBase<ForumBodyRubyTreeNodeMetrics> {
  _TreeRootMetricsView(this.prefix, this.root);
  final List<ForumBodyRubyTreeNodeMetrics> prefix;
  final ForumBodyRubyTreeNodeMetrics root;
  @override
  int get length => prefix.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only ruby metrics');
  @override
  ForumBodyRubyTreeNodeMetrics operator [](int index) {
    RangeError.checkValidIndex(index, prefix);
    return index == length - 1 ? root : prefix[index];
  }

  @override
  void operator []=(int index, ForumBodyRubyTreeNodeMetrics value) =>
      throw UnsupportedError('Read-only ruby metrics');
}

sealed class ForumBodyRubyTreeNodeMetrics {
  const ForumBodyRubyTreeNodeMetrics();
  ForumBodyRubyChildMetrics? get box;
}

final class ForumBodyRubyTreeTextMetrics extends ForumBodyRubyTreeNodeMetrics {
  const ForumBodyRubyTreeTextMetrics(this.box);
  @override
  final ForumBodyRubyChildMetrics? box;
}

final class ForumBodyRubyTreeContainerMetrics
    extends ForumBodyRubyTreeNodeMetrics {
  ForumBodyRubyTreeContainerMetrics({
    required this.font,
    required this.backgroundFont,
    required this.frame,
    this.group,
    this.inline,
    this.segment,
  }) : box = ForumBodyRubyChildMetrics(
         bounds: Offset.zero & frame.size,
         alphabeticBaseline: frame.baseline,
       );
  final ForumBodyRubyRootFontBox font;
  final ForumBodyRubyContainerFontBox? backgroundFont;
  final ForumBodyRubyAtomFrame frame;
  final ForumBodyRubyGroupMetrics? group;
  final ForumBodyRubyInlineChildMetrics? inline;
  final ForumBodyRubySegmentMetrics? segment;
  @override
  final ForumBodyRubyChildMetrics box;
}

final class ForumBodyRubyInlineChildMetrics {
  const ForumBodyRubyInlineChildMetrics(
    this.input,
    this.fragment,
    this.baseline,
  );
  final ForumBodyInlinePageContent input;
  final ForumBodyTextPageFragment fragment;
  final double baseline;
  Size get size => Size(fragment.width, fragment.height);
  int get nativeHandleCount => input.nativeHandleCountFor(fragment);
}

enum _State { active, ready, transferred, failed, closed }

/// Original nested IR -> native leaf/font geometry -> the one shared numeric
/// stack. Temporary leases are released before the next child is acquired.
/// This is metric planning, not the visible tree's aggregate pin admission.
final class ForumBodyRubyTreeMetricsPreparation {
  ForumBodyRubyTreeMetricsPreparation({
    required ForumBodyRubyTreeInput input,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _input = input,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _scaler = textScaler,
       _additionalOwned = additionalOwnedLeases;
  ForumBodyRubyTreeInput? _input;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _scaler;
  Map<double, double> _scales = {};
  Map<ForumBodyTextBandContent, TextScaler> _bandScalers = Map.identity();
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyTextRequestPreparation? _member;
  ForumBodyTextRequest? _currentRequest;
  ForumBodyTextRequest? _failedRequest;
  ForumBodyTextRequest? get failedRequest => _failedRequest;
  ForumBodyRubyGroupGeometry? _geometry;
  _TreeSegmentMetricsWork? _segment;
  ForumBodyInlinePlanPreparation? _inline;
  Iterator<double>? _inlineFonts;
  Map<double, double> _inlineScales = {};
  bool _inlineFontsComplete = false;
  int _nativeCount = 0;
  ForumBodyRubyRootFontBox? _font;
  ForumBodyRubyContainerFontBox? _backgroundFont;
  List<ForumBodyRubyTreeNodeMetrics> _nodes = [];
  ForumBodyRubyTreeMetrics? _result;
  var _state = _State.active;
  bool _operating = false;
  bool _waiting = false;
  bool _cacheMiss = false;
  int _rank = -1;
  bool get isReady => _state == _State.ready;
  bool get cacheMiss => _cacheMiss;
  int get measuredNodeCount => _nodes.length;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    if (_member != null) ..._member!.nativeLeases,
    if (_inline != null) ..._inline!.nativeLeases,
  ];
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _member?.lastBudgetRejection;

  ForumBodyRubyGroupPreparationStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      final cache = _cache!;
      final builds = cache.layoutBuildCount;
      final pictures = cache.pictureBuildCount;
      var units = 0;
      var captured = 0;
      _waiting = false;
      _cacheMiss = false;
      while (!isReady && units < maxParts) {
        final beforeNodes = _nodes.length;
        final used = _advanceNode(cachedOnly);
        units += used;
        captured += _nodes.length - beforeNodes;
        _guard();
        if (_waiting ||
            _cacheMiss ||
            used == 0 ||
            cache.layoutBuildCount != builds ||
            cache.pictureBuildCount != pictures) {
          break;
        }
      }
      return ForumBodyRubyGroupPreparationStep(
        partsPrepared: captured,
        layoutsBuilt: cache.layoutBuildCount - builds,
        picturesBuilt: cache.pictureBuildCount - pictures,
        partsInspected: 0,
        formatUnitsPrepared: units,
        isReady: isReady,
        waitingForLayoutBudget: _waiting,
      );
    });
  }

  int _advanceNode(bool cachedOnly) {
    if (_nodes.length == _input!.nodes.length) {
      _result = ForumBodyRubyTreeMetrics._(
        _input!,
        _nodes,
        _scales,
        _nativeCount,
      );
      _state = _State.ready;
      return 1;
    }
    final node = _input!.nodes[_nodes.length];
    if (node is ForumBodyRubyTreeText) {
      if (!node.needsNative) {
        _nodes.add(const ForumBodyRubyTreeTextMetrics(null));
        return 1;
      }
      return _read(node.request, cachedOnly, (lease) {
        _nodes.add(
          ForumBodyRubyTreeTextMetrics(
            ForumBodyRubyChildMetrics.measure(
              cache: _cache!,
              lease: lease,
              content: node.content,
            ),
          ),
        );
        _nativeCount++;
      });
    }
    final container = node as ForumBodyRubyTreeContainer;
    if (_font == null) {
      return _read(
        ForumBodyTextRequest.paragraph(container.font.fontStrut),
        cachedOnly,
        (lease) {
          _font = ForumBodyRubyRootFontBox(
            input: container.font,
            height: lease.layout.height,
            alphabeticBaseline: lease.layout.alphabeticBaseline,
          );
        },
      );
    }
    final background = container.background;
    if (background != null && _backgroundFont == null) {
      return _read(
        ForumBodyTextRequest.paragraph(background.fontStrut),
        cachedOnly,
        (lease) {
          _backgroundFont = ForumBodyRubyContainerFontBox(
            background: background,
            height: lease.layout.height,
            alphabeticBaseline: lease.layout.alphabeticBaseline,
          );
        },
      );
    }
    switch (container) {
      case ForumBodyRubyTreeSegment():
        final work = _segment ??= _TreeSegmentMetricsWork(
          container,
          _nodes,
          _input!.maxWidth,
        );
        work.advance();
        if (work.isReady) {
          final value = work.result!;
          _seal(
            _font!.enclose(
              childSize: value.size,
              childBaseline: value.baseline,
            ),
            segment: value,
          );
        }
        return 1;
      case ForumBodyRubyTreeInline():
        return _advanceInline(container, cachedOnly);
      case ForumBodyRubyTreeFrame(:final child):
        final box = _nodes[child].box!;
        _seal(
          _font!.enclose(
            childSize: box.bounds.size,
            childBaseline: box.alphabeticBaseline,
          ),
        );
      case ForumBodyRubyTreeGroup(:final base, :final annotations):
        if (_geometry == null) {
          _geometry = ForumBodyRubyGroupGeometry(
            annotations: [
              for (final annotation in annotations)
                (
                  hasAnnotation:
                      annotation.child != null &&
                      _nodes[annotation.child!].box != null,
                  gap: 0.0,
                  side: annotation.side,
                ),
            ],
            maxWidth: _input!.maxWidth,
          );
          return 1;
        }
        if (_rank == -1) {
          _geometry!.addBase(_nodes[base].box!);
          _rank = 0;
          return 1;
        }
        if (_rank < annotations.length) {
          final child = annotations[_rank++].child;
          _geometry!.addAnnotation(child == null ? null : _nodes[child].box);
          return 1;
        }
        if (!_geometry!.isReady) {
          return _geometry!.advance(maxParts: 1);
        }
        final measured = _geometry!.takeMetrics();
        _seal(
          _font!.enclose(
            childSize: measured.size,
            childBaseline: measured.baseline,
          ),
          group: measured,
        );
    }
    return 1;
  }

  void _seal(
    ForumBodyRubyAtomFrame frame, {
    ForumBodyRubyGroupMetrics? group,
    ForumBodyRubyInlineChildMetrics? inline,
    ForumBodyRubySegmentMetrics? segment,
  }) {
    _nodes.add(
      ForumBodyRubyTreeContainerMetrics(
        font: _font!,
        backgroundFont: _backgroundFont,
        frame: frame,
        group: group,
        inline: inline,
        segment: segment,
      ),
    );
    _geometry?.close();
    _geometry = null;
    _segment?.close();
    _segment = null;
    _font = null;
    _backgroundFont = null;
    _rank = -1;
  }

  int _advanceInline(ForumBodyRubyTreeInline node, bool cachedOnly) {
    if (!_inlineFontsComplete) {
      final fonts = _inlineFonts ??= node.input.nativeFontSizes.iterator;
      if (fonts.moveNext()) {
        final size = fonts.current;
        var scaled = _scales[size];
        if (scaled == null) {
          scaled = _scaler!.scale(size);
          _guard();
          _scales[size] = scaled;
        }
        _inlineScales[size] = scaled;
      } else {
        _inlineFonts = null;
        _inlineFontsComplete = true;
      }
      return 1;
    }
    final work = _inline ??= ForumBodyInlinePlanPreparation(
      input: node.input,
      cache: _cache!,
      ensureOwner: _guard,
      textScaler: _TreeNativeTextScaler(
        Map.unmodifiable(_inlineScales),
        node.input.content.style.textStyle.fontSize!,
      ),
    );
    final step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
    _guard();
    _waiting = step.waitingForLayoutBudget;
    _cacheMiss = work.cacheMiss;
    if (!work.isReady) return step.partsPrepared;
    final ready = work.take();
    _inline = null;
    work.close();
    final lease = ready.lease;
    try {
      _guard();
      final layout = lease.layout;
      if (layout.lines.length != 1) {
        throw StateError('Intrinsic ruby child is not one native row');
      }
      final baseline = layout.lines.single.baseline;
      final composer = ForumBodyTextPageComposer(
        identity: ready.content.identity,
        layoutId: 'intrinsic-ruby-child',
        // Capacity must be positive even for a zero physical native frame;
        // the composed fragment retains the actual zero width/height.
        width: layout.width == 0 ? 1 : layout.width,
        height: layout.height == 0 ? 1 : layout.height,
        maxPages: 1,
        maxFragments: 1,
      );
      late ForumBodyTextPageFragment fragment;
      try {
        composer.appendInline(
          lease: lease,
          paragraphIndex: 0,
          left: 0,
          spaceBefore: 0,
          spaceAtPageStart: 0,
          nativeHandleCountInRange: ready.content.nativeHandleCountInRange,
        );
        composer.advance(maxLines: 1);
        if (!composer.needsInput) {
          throw StateError('Intrinsic ruby child exceeded one native row');
        }
        composer.finish();
        fragment = composer.snapshot[0].fragments.single;
      } finally {
        composer.close();
      }
      final child = ForumBodyRubyInlineChildMetrics(
        ready.content,
        fragment,
        baseline,
      );
      _nativeCount += child.nativeHandleCount;
      _seal(
        _font!.enclose(childSize: child.size, childBaseline: child.baseline),
        inline: child,
      );
      _inlineScales = {};
      _inlineFontsComplete = false;
      return step.partsPrepared;
    } finally {
      lease.release();
    }
  }

  int _read(
    ForumBodyTextRequest request,
    bool cachedOnly,
    void Function(ForumBodyTextLease) capture,
  ) {
    _currentRequest = request;
    final member = _member ??= ForumBodyTextRequestPreparation(
      cache: _cache!,
      request: request,
      ensureOwner: _guard,
      preparePaint: false,
      textScaler: _captureScaler(request),
      width: _input!.maxWidth,
      additionalOwnedLeases: _additionalOwned,
    );
    final step = member.advance(cachedOnly: cachedOnly);
    _waiting = step.waiting;
    _cacheMiss = step.cacheMiss;
    _guard();
    if (member.isReady) {
      final lease = member.takeLease();
      member.close();
      _member = null;
      try {
        _guard();
        capture(lease);
      } finally {
        lease.release();
      }
      _currentRequest = null;
    }
    return step.units;
  }

  TextScaler _captureScaler(ForumBodyTextRequest request) {
    final band = request is ForumBodyTextBandChildRequest ? request.band : null;
    final captured = _bandScalers[band];
    if (captured != null) return captured;
    final sampler = _TreeScaleCapture((size) {
      final old = _scales[size];
      if (old != null) return old;
      final actual = _scaler!.scale(size);
      _guard();
      _scales[size] = actual;
      return actual;
    });
    final contexts = switch (request) {
      ForumBodyParagraphTextRequest() => [request.content],
      ForumBodyTextBandChildRequest() => request.band.contexts,
    };
    final scratch = <double, double>{};
    final requestSamples = <double, double>{};
    for (final context in contexts) {
      context.layoutInput.resolveScalesInto(scratch, textScaler: sampler);
      _guard();
      requestSamples.addAll(scratch);
    }
    // A cached native painter may retain this scaler. It must never retain the
    // owner callback/raw scaler or observe later additions to the sampled map.
    final result = _TreeNativeTextScaler(
      Map.unmodifiable(requestSamples),
      (band?.contexts.first ?? request.content).style.textStyle.fontSize!,
    );
    // A band is one native key. Its later children do not scan/copy all sibling
    // font inputs again; the frozen sample never retains this preparation.
    if (band != null) _bandScalers[band] = result;
    return result;
  }

  ForumBodyRubyTreeMetrics takeMetrics() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby tree metrics are incomplete');
    final result = _result!;
    _state = _State.transferred;
    _dropOwner();
    return result;
  });
  void _guard() {
    if (_state != _State.active && !isReady) {
      throw StateError('Ruby tree metrics are retired');
    }
    _ensureOwner!();
    if ((_state != _State.active && !isReady) || _cache!.isClosed) {
      throw StateError('Ruby tree owner is retired');
    }
  }

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Ruby tree preparation is reentrant');
    _operating = true;
    try {
      return action();
    } catch (error) {
      final failed = error is ForumBodyTextBandLayoutException
          ? _currentRequest
          : null;
      _retire(_State.failed);
      _failedRequest = failed;
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _dropOwner() {
    _segment?.close();
    _segment = null;
    _member?.close();
    _member = null;
    _inline?.close();
    _inline = null;
    _inlineFonts = null;
    _inlineScales = {};
    _inlineFontsComplete = false;
    _currentRequest = null;
    _geometry?.close();
    _geometry = null;
    _font = null;
    _backgroundFont = null;
    _result = null;
    _nodes = [];
    _input = null;
    _cache = null;
    _scaler = null;
    _scales = {};
    _bandScalers = Map.identity();
    _ensureOwner = null;
    _additionalOwned = null;
  }

  void _retire(_State state) {
    if (_state != _State.active && !isReady) return;
    _state = state;
    _dropOwner();
  }

  void close() => _retire(_State.closed);
}

final class _TreeNativeTextScaler extends TextScaler {
  const _TreeNativeTextScaler(this.samples, this.rootSize);
  final Map<double, double> samples;
  final double rootSize;
  @override
  double scale(double fontSize) =>
      samples[fontSize] ??
      (throw StateError('Ruby native font input was not captured'));
  @override
  double get textScaleFactor => scale(rootSize) / rootSize;
}

final class _TreeScaleCapture extends TextScaler {
  const _TreeScaleCapture(this.sample);
  final double Function(double) sample;
  @override
  double scale(double fontSize) => sample(fontSize);
  @override
  double get textScaleFactor => throw StateError('Use per-font ruby scaling');
}

import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../block/forum_body_block_flow_cursor.dart';
import '../decoration/forum_body_decoration_text_request.dart';
import '../document/forum_body_document.dart';
import '../inline/forum_body_emphasis_mark.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_native_request.dart';
import '../style/forum_body_style_options.dart';

ForumBodyDecorationTextInput forumBodyListMarkerFontInput(
  ForumBodyListItemMarker marker,
  String fontRevision,
  int styleRevision,
) => ForumBodyDecorationTextInput.label(
  text: marker.text!,
  style: marker.style,
  fontRevision: fontRevision,
  styleRevision: styleRevision,
);

Rect forumBodyListMarkerFontBounds(
  ForumBodyDecorationTextInput input,
  ForumBodyDecorationTextLease lease,
) {
  var bounds = lease.layout.fontBounds;
  for (final shadow in input.textStyle.shadows ?? const <Shadow>[]) {
    bounds = bounds.expandToInclude(
      lease.layout.fontBounds
          .shift(shadow.offset)
          .inflate(shadow.blurRadius * 3),
    );
  }
  return bounds;
}

/// Source-free labels in paragraph-local X and alphabetic-baseline-local Y.
/// It retains pure inputs/metrics only; the reading owner still owns fonts.
final class ForumBodyListMarkerPlan {
  ForumBodyListMarkerPlan._(
    this.identity,
    List<_MarkerFont> fonts,
    this.picture,
    this.bounds,
    List<ForumBodyNativeInputCost> costs,
  ) : _fonts = List.unmodifiable(fonts),
      costs = List.unmodifiable(costs);
  final ForumBodyIdentity identity;
  final List<_MarkerFont> _fonts;
  int get fontCount => _fonts.length;
  int get preparationHandleCount => 1 + 2 * fontCount;

  /// A block resource has no text baseline. Align the marker ink to its top.
  double get blockTopBaseline => -bounds.top;
  final ForumBodyTextPictureInput picture;
  final Rect bounds;
  final List<ForumBodyNativeInputCost> costs;
  int get retainedCodeUnits => (picture.estimatedInputBytes + 1) ~/ 2;
  Iterable<ForumBodyNativeBudgetSlot> get footprint sync* {
    for (final font in _fonts) {
      yield (request: font.request, width: 0, minimumLineCount: 1);
    }
    yield (
      request: ForumBodyTextPictureBudgetInput(picture),
      width: 0,
      minimumLineCount: 0,
    );
  }
}

final class _MarkerFont {
  const _MarkerFont(
    this.request,
    this.identity,
    this.width,
    this.height,
    this.baseline,
    this.fontBounds,
    this.offset,
  );
  final ForumBodyDecorationTextRequest request;
  final Object identity;
  final double width, height, baseline;
  final Rect fontBounds;
  final Offset offset;
  bool matches(ForumBodyDecorationTextLease lease) =>
      lease.nativeInputIdentity == identity &&
      lease.layout.width == width &&
      lease.layout.height == height &&
      lease.layout.alphabeticBaseline == baseline &&
      lease.layout.fontBounds == fontBounds;
}

/// One font at a time, without a second cache or retained measurement lease.
final class ForumBodyListMarkerPlanPreparation {
  ForumBodyListMarkerPlanPreparation({
    required this.identity,
    required List<ForumBodyListItemMarker> markers,
    required this.left,
    required this.fontRevision,
    required this.styleRevision,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
  }) : _markers = markers,
       _cache = cache,
       _scaler = textScaler,
       _ensureOwner = ensureOwner;
  final ForumBodyIdentity identity;
  final double left;
  final String fontRevision;
  final int styleRevision;
  List<ForumBodyListItemMarker> _markers;
  ForumBodyParagraphCache? _cache;
  TextScaler? _scaler;
  void Function()? _ensureOwner;
  final _fonts = <_MarkerFont>[];
  final _costs = <ForumBodyNativeInputCost>[];
  Rect? _bounds;
  var _index = 0;
  bool _ready = false;
  ForumBodyListMarkerPlan? _result;
  bool get isReady => _ready;
  int advance() {
    _guard();
    if (_ready) return 0;
    if (_index < _markers.length) {
      final marker = _markers[_index];
      if (marker.text == null) {
        _index++;
        return 1;
      }
      if (marker.style.listStyle.position !=
          ForumBodyListMarkerPosition.outside) {
        throw ForumBodyBlockFlowException(
          ForumBodyBlockFlowFailure.structure,
          marker.itemPath,
        );
      }
      final input = forumBodyListMarkerFontInput(
        marker,
        fontRevision,
        styleRevision,
      );
      final lease = _cache!.acquireDecorationText(
        input: input,
        textScaler: _scaler!,
      );
      try {
        _guard();
        final layout = lease.layout;
        final gap = layout.height * .25;
        final x = marker.style.textDirection == TextDirection.ltr
            ? marker.contentLeft - gap - layout.width
            : marker.contentLeft + marker.contentWidth + gap;
        final offset = Offset(x - left, -layout.alphabeticBaseline);
        final bounds = forumBodyListMarkerFontBounds(
          input,
          lease,
        ).shift(offset);
        _bounds = _bounds?.expandToInclude(bounds) ?? bounds;
        _fonts.add(
          _MarkerFont(
            ForumBodyDecorationTextRequest(input),
            lease.nativeInputIdentity,
            layout.width,
            layout.height,
            layout.alphabeticBaseline,
            layout.fontBounds,
            offset,
          ),
        );
        _costs.add((
          identity: lease.nativeInputIdentity,
          estimatedBytes: lease.nativeLayoutEstimatedBytes,
        ));
        _index++;
      } finally {
        lease.release();
      }
      return 1;
    }
    if (_fonts.isNotEmpty) {
      final picture = ForumBodyTextPictureInput(
        commands: [
          for (final font in _fonts)
            ForumBodyTextPictureCommand(
              nativeInputIdentity: font.identity,
              offset: font.offset,
            ),
        ],
      );
      final probe = _cache!.createBudgetProbe(captureInputEstimates: true);
      try {
        probe.includeTextPicture(picture);
        _costs.addAll(probe.snapshotNativeEstimates());
      } finally {
        probe.close();
      }
      _guard();
      _result = ForumBodyListMarkerPlan._(
        identity,
        _fonts,
        picture,
        _bounds!,
        _costs,
      );
    }
    _ready = true;
    return 1;
  }

  ForumBodyListMarkerPlan? take() {
    _guard();
    if (!_ready) throw StateError('List marker plan is incomplete');
    final result = _result;
    close();
    return result;
  }

  void _guard() {
    if (_cache == null) throw StateError('List marker plan is retired');
    _ensureOwner!();
    if (_cache == null || _cache!.isClosed) {
      throw StateError('List marker owner retired');
    }
  }

  void close() {
    _cache = null;
    _scaler = null;
    _ensureOwner = null;
    _markers = const [];
    _fonts.clear();
    _costs.clear();
    _result = null;
  }
}

/// Prepares the one visible marker picture in the page's existing transaction.
final class ForumBodyListMarkerPicturePreparation {
  ForumBodyListMarkerPicturePreparation({
    required this.plan,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    required Iterable<ForumBodyNativeParagraphLease> Function() ownedLeases,
  }) : _cache = cache,
       _scaler = textScaler,
       _ensureOwner = ensureOwner,
       _ownedLeases = ownedLeases;
  final ForumBodyListMarkerPlan plan;
  ForumBodyParagraphCache? _cache;
  TextScaler? _scaler;
  void Function()? _ensureOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _ownedLeases;
  final _fonts = <ForumBodyDecorationTextLease>[];
  ForumBodyTextPicturePreparation? _picture;
  ForumBodyTextPictureLease? _result;
  int workCount = 0;
  bool get isReady => _result != null;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ..._fonts,
    ...?_picture?.nativeLeases,
    ?_result,
  ];
  ({bool cacheMiss, bool waiting}) advance({required bool cachedOnly}) {
    _guard();
    if (isReady) return (cacheMiss: false, waiting: false);
    if (_fonts.length < plan._fonts.length) {
      final font = plan._fonts[_fonts.length];
      final lease = font.request.acquire(
        _cache!,
        width: 0,
        textScaler: _scaler!,
        cachedOnly: cachedOnly,
      );
      if (lease == null) return (cacheMiss: true, waiting: false);
      try {
        _guard();
        if (!font.matches(lease)) throw StateError('List marker font changed');
        _fonts.add(lease);
      } catch (_) {
        lease.release();
        rethrow;
      }
      workCount++;
      return (cacheMiss: false, waiting: false);
    }
    final picture = _picture ??= ForumBodyTextPicturePreparation.cooperative(
      cache: _cache!,
      input: plan.picture,
      text: const [],
      marks: _fonts,
      ensureOwner: _guard,
      additionalOwnedLeases: _ownedLeases,
    );
    late final ({
      int partsPrepared,
      int picturesRecorded,
      bool waitingForLayoutBudget,
    })
    step;
    try {
      step = picture.advance(maxParts: 1, cachedOnly: cachedOnly);
    } on ForumBodyParagraphBudgetException {
      picture.close();
      _picture = null;
      rethrow;
    }
    workCount += math.max(1, step.partsPrepared);
    if (picture.isReady) {
      _result = picture.takeLease();
      _picture = null;
      for (final font in _fonts) {
        font.release();
      }
      _fonts.clear();
    }
    return (cacheMiss: picture.cacheMiss, waiting: step.waitingForLayoutBudget);
  }

  ForumBodyTextPictureLease take() {
    _guard();
    final result =
        _result ?? (throw StateError('List marker picture incomplete'));
    _result = null;
    close();
    return result;
  }

  void _guard() {
    if (_cache == null) throw StateError('List marker picture retired');
    _ensureOwner!();
    if (_cache == null || _cache!.isClosed) {
      throw StateError('List marker owner retired');
    }
  }

  void close() {
    _picture?.close();
    _picture = null;
    for (final font in _fonts) {
      font.release();
    }
    _fonts.clear();
    _result?.release();
    _result = null;
    _cache = null;
    _scaler = null;
    _ensureOwner = null;
    _ownedLeases = null;
  }
}

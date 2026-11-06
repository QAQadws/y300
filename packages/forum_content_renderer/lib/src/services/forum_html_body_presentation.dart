import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Small session-owned values, never a retained HTML/widget tree. Each body
/// (including nested folds) keeps only its latest completed layout.
class ForumHtmlBodyPresentation {
  final collapseExpansion = <String, bool>{};
  final _layouts = <String, ({Object revision, double height})>{};
  final _inlineImageSizes = <Object, Size>{};
  static const _maxInlineImageSizes = 128;
  bool _active = true;

  bool get isActive => _active;

  /// Natural sizes survive virtualized body remounts, without retaining pixels,
  /// widgets or cache services. Each owner disposes this bounded layout memory.
  Size? inlineImageSizeFor(Object identity) {
    if (!_active) return null;
    final size = _inlineImageSizes.remove(identity);
    if (size != null) _inlineImageSizes[identity] = size;
    return size;
  }

  void recordInlineImageSize(Object identity, Size size) {
    if (!_active ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    _inlineImageSizes.remove(identity);
    _inlineImageSizes[identity] = size;
    while (_inlineImageSizes.length > _maxInlineImageSizes) {
      _inlineImageSizes.remove(_inlineImageSizes.keys.first);
    }
  }

  Object get expansionRevision => Object.hashAll(
    (collapseExpansion.keys.toList()..sort()).map(
      (key) => (key, collapseExpansion[key]),
    ),
  );

  double? heightFor(String sourceId, Object revision) {
    final layout = _layouts[sourceId];
    return _active && layout?.revision == revision ? layout?.height : null;
  }

  void recordLayout(String sourceId, Object revision, double height) {
    if (_active && height.isFinite && height >= 0) {
      _layouts[sourceId] = (revision: revision, height: height);
    }
  }

  void dispose() {
    _active = false;
    _layouts.clear();
    _inlineImageSizes.clear();
    collapseExpansion.clear();
  }
}

enum ForumHtmlBodyLayoutPhase { preparing, built, failed }

/// Restores a measured height while the renderer is preparing its body.
/// The real child still lays out, then takes over without a scroll command or
/// a permanent height constraint. This also wraps async nested fold bodies.
class ForumHtmlBodyLayout extends StatefulWidget {
  const ForumHtmlBodyLayout({
    super.key,
    required this.presentation,
    required this.sourceId,
    required this.revision,
    required Widget Function(VoidCallback onBodyBuilt) builder,
  }) : _builder = builder,
       _child = null,
       _phase = null;

  /// [phase] is read after the child has laid out its current prefix.
  const ForumHtmlBodyLayout.observed({
    super.key,
    required this.presentation,
    required this.sourceId,
    required this.revision,
    required Widget child,
    required ForumHtmlBodyLayoutPhase Function() phase,
  }) : _child = child,
       _phase = phase,
       _builder = null;

  final ForumHtmlBodyPresentation presentation;
  final String sourceId;
  final Object revision;
  final Widget Function(VoidCallback onBodyBuilt)? _builder;
  final Widget? _child;
  final ForumHtmlBodyLayoutPhase Function()? _phase;

  @override
  State<ForumHtmlBodyLayout> createState() => _ForumHtmlBodyLayoutState();
}

class _ForumHtmlBodyLayoutState extends State<ForumHtmlBodyLayout> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) => _BodyMeasurement(
    presentation: widget.presentation,
    sourceId: widget.sourceId,
    revision: widget.revision,
    phase:
        widget._phase ??
        () => _ready
            ? ForumHtmlBodyLayoutPhase.built
            : ForumHtmlBodyLayoutPhase.preparing,
    child:
        widget._child ??
        widget._builder!(() {
          if (mounted && widget.presentation.isActive) _ready = true;
        }),
  );
}

class _BodyMeasurement extends SingleChildRenderObjectWidget {
  const _BodyMeasurement({
    required this.presentation,
    required this.sourceId,
    required this.revision,
    required this.phase,
    required super.child,
  });

  final ForumHtmlBodyPresentation presentation;
  final String sourceId;
  final Object revision;
  final ForumHtmlBodyLayoutPhase Function() phase;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BodyMeasurementBox(presentation, sourceId, revision, phase);

  @override
  void updateRenderObject(BuildContext context, _BodyMeasurementBox box) {
    box
      ..presentation = presentation
      ..sourceId = sourceId
      ..revision = revision
      ..phase = phase
      ..markNeedsLayout();
  }
}

class _BodyMeasurementBox extends RenderProxyBox {
  _BodyMeasurementBox(
    this.presentation,
    this.sourceId,
    this.revision,
    this.phase,
  );

  ForumHtmlBodyPresentation presentation;
  String sourceId;
  Object revision;
  ForumHtmlBodyLayoutPhase Function() phase;

  @override
  void performLayout() {
    super.performLayout();
    final layoutRevision = (
      revision,
      constraints.maxWidth,
      presentation.expansionRevision,
    );
    switch (phase()) {
      case ForumHtmlBodyLayoutPhase.built:
        presentation.recordLayout(sourceId, layoutRevision, size.height);
      case ForumHtmlBodyLayoutPhase.preparing:
        final height = presentation.heightFor(sourceId, layoutRevision);
        if (height != null && height > size.height) {
          size = constraints.constrain(Size(size.width, height));
        }
      case ForumHtmlBodyLayoutPhase.failed:
        break;
    }
  }
}

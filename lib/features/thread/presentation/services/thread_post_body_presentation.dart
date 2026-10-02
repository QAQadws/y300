import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Small session-owned values, never a retained HTML/widget tree. Each body
/// (including nested folds) keeps only its latest completed layout.
class ThreadPostBodyPresentation {
  final collapseExpansion = <String, bool>{};
  final _layouts = <String, ({Object revision, double height})>{};
  bool _active = true;

  bool get isActive => _active;

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
    collapseExpansion.clear();
  }
}

/// Restores a measured height only while HtmlWidget is preparing its body.
/// The real child still lays out, then takes over without a scroll command or
/// a permanent height constraint. This also wraps async nested fold bodies.
class ThreadPostBodyLayout extends StatefulWidget {
  const ThreadPostBodyLayout({
    super.key,
    required this.presentation,
    required this.sourceId,
    required this.revision,
    required this.builder,
  });

  final ThreadPostBodyPresentation presentation;
  final String sourceId;
  final Object revision;
  final Widget Function(VoidCallback onBodyBuilt) builder;

  @override
  State<ThreadPostBodyLayout> createState() => _ThreadPostBodyLayoutState();
}

class _ThreadPostBodyLayoutState extends State<ThreadPostBodyLayout> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) => _BodyMeasurement(
    presentation: widget.presentation,
    sourceId: widget.sourceId,
    revision: widget.revision,
    isReady: () => _ready,
    child: widget.builder(() {
      if (mounted && widget.presentation.isActive) _ready = true;
    }),
  );
}

class _BodyMeasurement extends SingleChildRenderObjectWidget {
  const _BodyMeasurement({
    required this.presentation,
    required this.sourceId,
    required this.revision,
    required this.isReady,
    required super.child,
  });

  final ThreadPostBodyPresentation presentation;
  final String sourceId;
  final Object revision;
  final bool Function() isReady;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BodyMeasurementBox(presentation, sourceId, revision, isReady);

  @override
  void updateRenderObject(BuildContext context, _BodyMeasurementBox box) {
    box
      ..presentation = presentation
      ..sourceId = sourceId
      ..revision = revision
      ..isReady = isReady
      ..markNeedsLayout();
  }
}

class _BodyMeasurementBox extends RenderProxyBox {
  _BodyMeasurementBox(
    this.presentation,
    this.sourceId,
    this.revision,
    this.isReady,
  );

  ThreadPostBodyPresentation presentation;
  String sourceId;
  Object revision;
  bool Function() isReady;

  @override
  void performLayout() {
    super.performLayout();
    final layoutRevision = (
      revision,
      constraints.maxWidth,
      presentation.expansionRevision,
    );
    if (isReady()) {
      presentation.recordLayout(sourceId, layoutRevision, size.height);
    } else {
      final height = presentation.heightFor(sourceId, layoutRevision);
      if (height != null) {
        size = constraints.constrain(Size(size.width, height));
      }
    }
  }
}
